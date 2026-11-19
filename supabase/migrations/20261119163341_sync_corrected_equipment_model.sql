CREATE OR REPLACE FUNCTION rh_internal.asset_correct_delivery(p_operation uuid, p jsonb) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE
  original public.rh_asset_events%ROWTYPE;
  revised public.rh_asset_events%ROWTYPE;
  former public.rh_asset_stock%ROWTYPE;
  target public.rh_asset_stock%ROWTYPE;
  kind public.rh_asset_types%ROWTYPE;
  target_id uuid := (p->>'estoque_id')::uuid;
  qty integer := (p->>'quantidade')::integer;
  delivery_date date := (p->>'data')::date;
  note text := btrim(coalesce(p->>'observacao',''));
  reason text := btrim(coalesce(p->>'motivo',''));
  returned integer;
  first_return date;
  doc jsonb;
  final_balance integer;
BEGIN
  IF auth.uid() IS NULL OR NOT rh_internal.can_write() THEN
    RAISE EXCEPTION 'Sem permissão para editar entregas.';
  END IF;
  SELECT * INTO original FROM public.rh_asset_events
    WHERE id=(p->>'entrega_id')::uuid AND acao='entrega' FOR UPDATE;
  IF NOT FOUND OR NOT rh_internal.can_read_employee(original.funcionario_id) THEN
    RAISE EXCEPTION 'Sem permissão para editar esta entrega.';
  END IF;
  IF EXISTS (SELECT 1 FROM rh_internal.asset_delivery_corrections
      WHERE id=p_operation AND entrega_id=original.id AND responsavel=auth.uid()) THEN
    RETURN original.id;
  END IF;
  IF original.corrigido_em IS DISTINCT FROM (p->>'corrigido_em')::timestamptz THEN
    RAISE EXCEPTION 'Esta entrega foi alterada. Atualize o histórico antes de editar.';
  END IF;
  IF p_operation IS NULL OR target_id IS NULL OR qty IS NULL OR qty NOT BETWEEN 1 AND 10000
     OR delivery_date IS NULL OR delivery_date>timezone('America/Sao_Paulo',now())::date
     OR length(note)>1000 OR length(reason) NOT BETWEEN 1 AND 300 THEN
    RAISE EXCEPTION 'Confira o item, a data, a quantidade e o motivo da correção.';
  END IF;

  SELECT coalesce(sum(quantidade),0),min(data) INTO returned,first_return
    FROM public.rh_asset_events WHERE entrega_id=original.id;
  IF qty<returned OR delivery_date>first_return OR (returned>0 AND original.estoque_id<>target_id) THEN
    RAISE EXCEPTION 'Confira as devoluções ou baixas já registradas. Elas limitam a data, a quantidade e a troca do item.';
  END IF;

  PERFORM id FROM public.rh_asset_stock WHERE id IN (original.estoque_id,target_id) ORDER BY id FOR UPDATE;
  SELECT * INTO former FROM public.rh_asset_stock WHERE id=original.estoque_id;
  SELECT * INTO target FROM public.rh_asset_stock WHERE id=target_id;
  IF target.id IS NULL OR target.filial<>former.filial THEN
    RAISE EXCEPTION 'Selecione um item da filial da entrega original.';
  END IF;
  IF target.quantidade + (CASE WHEN target.id=former.id THEN original.quantidade ELSE 0 END) < qty THEN
    RAISE EXCEPTION 'Saldo insuficiente para corrigir esta entrega.';
  END IF;

  doc := original.ficha || jsonb_build_object('variante',target.variante);
  IF former.id<>target.id THEN
    SELECT * INTO kind FROM public.rh_asset_types WHERE id=target.tipo_id;
    doc := doc || jsonb_build_object('item',kind.nome,'detalhe',kind.detalhe);
    UPDATE public.rh_asset_stock SET quantidade=quantidade+original.quantidade WHERE id=former.id;
  END IF;
  IF former.id<>target.id OR original.quantidade<>qty THEN
    UPDATE public.rh_asset_stock
      SET quantidade=quantidade-qty+CASE WHEN id=former.id THEN original.quantidade ELSE 0 END
      WHERE id=target.id RETURNING quantidade INTO final_balance;
  END IF;
  UPDATE public.rh_asset_events SET estoque_id=target.id, quantidade=qty, data=delivery_date,
    observacao=note, ficha=doc, saldo_estoque=coalesce(final_balance,original.saldo_estoque), corrigido_em=clock_timestamp()
    WHERE id=original.id RETURNING * INTO revised;

  INSERT INTO rh_internal.asset_delivery_corrections VALUES
    (p_operation,original.id,auth.uid(),revised.corrigido_em,reason,to_jsonb(original),to_jsonb(revised));
  RETURN revised.id;
END $$;
