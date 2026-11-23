ALTER TABLE public.rh_asset_events ADD COLUMN sem_desconto_estoque boolean NOT NULL DEFAULT false
  CHECK (NOT sem_desconto_estoque OR acao='entrega');

CREATE OR REPLACE FUNCTION rh_internal.asset_event(p_id uuid, p jsonb) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE
  action text := p->>'acao';
  movement_date date := (p->>'data')::date;
  qty integer := (p->>'quantidade')::integer;
  no_debit boolean := coalesce((p->>'sem_desconto_estoque')::boolean,false);
  note text := btrim(coalesce(p->>'observacao',''));
  proof text := btrim(coalesce(p->>'comprovante',''));
  target text;
  employee public.funcionarios_epi%ROWTYPE;
  stock public.rh_asset_stock%ROWTYPE;
  asset_type public.rh_asset_types%ROWTYPE;
  delivery public.rh_asset_events%ROWTYPE;
  existing public.rh_asset_events%ROWTYPE;
  company public.empresas%ROWTYPE;
  variant text;
  branch text;
  delta integer;
  doc jsonb;
  remaining integer;
BEGIN
  IF auth.uid() IS NULL OR p_id IS NULL OR action IS NULL OR action NOT IN ('entrada','ajuste','entrega','devolucao','baixa') THEN
    RAISE EXCEPTION 'Operação inválida.';
  END IF;
  IF action IN ('entrada','ajuste') THEN
    IF NOT rh_internal.can_manage_stock() THEN RAISE EXCEPTION 'Sem permissão para administrar estoque.'; END IF;
  ELSE
    SELECT * INTO employee FROM public.funcionarios_epi WHERE id = (p->>'funcionario_id')::uuid FOR SHARE;
    IF employee.id IS NULL OR NOT rh_internal.can_write() OR NOT rh_internal.can_read_employee(employee.id) THEN
      RAISE EXCEPTION 'Sem permissão para movimentar equipamentos deste colaborador.';
    END IF;
  END IF;

  PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_id::text, 0));
  SELECT * INTO existing FROM public.rh_asset_events WHERE id = p_id;
  IF FOUND THEN
    IF existing.created_by = auth.uid() AND existing.acao = action
       AND existing.funcionario_id IS NOT DISTINCT FROM employee.id THEN RETURN p_id; END IF;
    RAISE EXCEPTION 'Identificador de operação já utilizado.';
  END IF;

  IF movement_date IS NULL OR (action<>'entrega' AND movement_date > timezone('America/Sao_Paulo', now())::date)
     OR qty IS NULL OR qty NOT BETWEEN 1 AND 10000 OR length(note)>1000 THEN
    RAISE EXCEPTION 'Confira a data, a quantidade e a observação.';
  END IF;
  IF no_debit AND (action<>'entrega' OR movement_date>=timezone('America/Sao_Paulo',now())::date) THEN
    RAISE EXCEPTION 'A opção sem desconto é reservada a entregas retroativas.';
  END IF;
  IF length(proof)>2000 OR (proof<>'' AND proof !~* '^https?://[^[:space:]]+$') THEN
    RAISE EXCEPTION 'Informe um link de comprovante válido, começando com http:// ou https://.';
  END IF;
  IF action IN ('ajuste','devolucao','baixa') AND note = '' THEN
    RAISE EXCEPTION 'Informe o motivo ou a condição do equipamento.';
  END IF;

  IF action IN ('entrada','ajuste') THEN
    SELECT * INTO asset_type FROM public.rh_asset_types WHERE id = (p->>'tipo_id')::uuid;
    branch := p->>'filial';
    variant := regexp_replace(btrim(coalesce(p->>'variante','')), '[[:space:]]+', ' ', 'g');
    IF asset_type.id IS NULL OR branch IS NULL OR branch NOT IN ('FILIAL 5','FILIAL 8')
       OR length(variant)>120
       OR (asset_type.detalhe = 'ano' AND variant !~ '^[1-9][0-9]{3}$')
       OR (asset_type.detalhe IN ('modelo','descricao') AND variant='')
       OR (asset_type.detalhe = 'nenhum' AND variant<>'') THEN
      RAISE EXCEPTION 'Confira o tipo, a filial e o ano, modelo ou descrição do item.';
    END IF;
    variant := upper(variant);
    INSERT INTO public.rh_asset_stock (tipo_id, variante, filial)
      VALUES (asset_type.id, variant, branch) ON CONFLICT DO NOTHING;
    SELECT * INTO stock FROM public.rh_asset_stock
      WHERE tipo_id=asset_type.id AND variante=variant AND filial=branch FOR UPDATE;
    delta := CASE WHEN action='entrada' THEN qty ELSE -qty END;
  ELSIF action='entrega' THEN
    SELECT * INTO stock FROM public.rh_asset_stock WHERE id=(p->>'estoque_id')::uuid FOR UPDATE;
    IF stock.id IS NULL OR stock.filial IS DISTINCT FROM employee.unidade THEN
      RAISE EXCEPTION 'Selecione um equipamento disponível na filial do colaborador.';
    END IF;
    SELECT * INTO asset_type FROM public.rh_asset_types WHERE id=stock.tipo_id;
    SELECT * INTO company FROM public.empresas
      WHERE id=employee.empresa_id OR (nullif(regexp_replace(employee.local_registro, '[^0-9]', '', 'g'), '') IS NOT NULL
        AND regexp_replace(cnpj, '[^0-9]', '', 'g')=regexp_replace(employee.local_registro, '[^0-9]', '', 'g'))
      ORDER BY (id=employee.empresa_id) DESC NULLS LAST, id LIMIT 1;
    IF company.id IS NULL THEN RAISE EXCEPTION 'Confira a empresa no cadastro do colaborador antes da entrega.'; END IF;
    doc := jsonb_build_object('versao',1,'item',asset_type.nome,'detalhe',asset_type.detalhe,'variante',stock.variante,
      'empresa',jsonb_build_object('nome',company.nome,'cnpj',company.cnpj,'endereco',company.endereco),
      'colaborador',jsonb_build_object('nome',employee.nome,'cpf',employee.cpf,'cargo',employee.funcao,
        'unidade',employee.unidade,'setor',employee.setor,'admissao',employee.admissao));
    delta := CASE WHEN no_debit THEN 0 ELSE -qty END;
  ELSE
    SELECT * INTO delivery FROM public.rh_asset_events
      WHERE id=(p->>'entrega_id')::uuid AND acao='entrega' AND funcionario_id=employee.id FOR UPDATE;
    IF delivery.id IS NULL OR movement_date < delivery.data THEN
      RAISE EXCEPTION 'Escolha uma entrega válida e confira a data.';
    END IF;
    SELECT delivery.quantidade - coalesce(sum(quantidade),0) INTO remaining
      FROM public.rh_asset_events WHERE entrega_id=delivery.id;
    IF qty > remaining THEN RAISE EXCEPTION 'A quantidade supera o saldo em posse.'; END IF;
    IF action='devolucao' THEN
      target := p->>'destino';
      IF target IS NULL OR target NOT IN ('disponivel','avariado') THEN RAISE EXCEPTION 'Informe o destino da devolução.'; END IF;
    END IF;
    SELECT * INTO stock FROM public.rh_asset_stock WHERE id=delivery.estoque_id FOR UPDATE;
    delta := CASE WHEN target='disponivel' THEN qty ELSE 0 END;
  END IF;

  UPDATE public.rh_asset_stock SET quantidade=quantidade+delta
    WHERE id=stock.id AND quantidade+delta>=0 RETURNING * INTO stock;
  IF NOT FOUND THEN RAISE EXCEPTION 'Saldo insuficiente no estoque desta filial.'; END IF;

  INSERT INTO public.rh_asset_events
    (id,estoque_id,funcionario_id,entrega_id,acao,quantidade,saldo_estoque,data,destino,observacao,ficha,comprovante,sem_desconto_estoque)
  VALUES (p_id,stock.id,employee.id,delivery.id,action,qty,stock.quantidade,movement_date,target,note,doc,proof,no_debit);
  RETURN p_id;
END $$;

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
     OR delivery_date IS NULL
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
  IF original.sem_desconto_estoque AND delivery_date>=timezone('America/Sao_Paulo',now())::date THEN
    RAISE EXCEPTION 'A entrega sem desconto deve manter uma data retroativa.';
  END IF;
  IF NOT original.sem_desconto_estoque AND target.quantidade + (CASE WHEN target.id=former.id THEN original.quantidade ELSE 0 END) < qty THEN
    RAISE EXCEPTION 'Saldo insuficiente para corrigir esta entrega.';
  END IF;

  doc := original.ficha || jsonb_build_object('variante',target.variante);
  IF former.id<>target.id THEN
    SELECT * INTO kind FROM public.rh_asset_types WHERE id=target.tipo_id;
    doc := doc || jsonb_build_object('item',kind.nome,'detalhe',kind.detalhe);
    IF NOT original.sem_desconto_estoque THEN
      UPDATE public.rh_asset_stock SET quantidade=quantidade+original.quantidade WHERE id=former.id;
    END IF;
  END IF;
  IF NOT original.sem_desconto_estoque AND (former.id<>target.id OR original.quantidade<>qty) THEN
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

CREATE OR REPLACE FUNCTION rh_internal.asset_stock_history() RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $$
  SELECT CASE WHEN auth.uid() IS NOT NULL AND rh_internal.can_manage_stock() THEN (
    SELECT coalesce(jsonb_agg(to_jsonb(m) ORDER BY m.data DESC, m.created_at DESC, m.id DESC), '[]'::jsonb)
    FROM (
      SELECT id, estoque_id, acao, quantidade, saldo_estoque, data, destino, created_at, sem_desconto_estoque
      FROM public.rh_asset_events
      ORDER BY data DESC, created_at DESC, id DESC LIMIT 100
    ) m
  ) ELSE '[]'::jsonb END
$$;
