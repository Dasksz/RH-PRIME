ALTER TABLE public.rh_asset_events ADD COLUMN comprovante text NOT NULL DEFAULT ''
  CHECK (length(comprovante) <= 2000 AND (comprovante='' OR comprovante ~* '^https?://[^[:space:]]+$'));

CREATE OR REPLACE FUNCTION rh_internal.asset_event(p_id uuid, p jsonb) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE
  action text := p->>'acao';
  movement_date date := (p->>'data')::date;
  qty integer := (p->>'quantidade')::integer;
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

  IF movement_date IS NULL OR movement_date > timezone('America/Sao_Paulo', now())::date
     OR qty IS NULL OR qty NOT BETWEEN 1 AND 10000 OR length(note)>1000 THEN
    RAISE EXCEPTION 'Confira a data, a quantidade e a observação.';
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
    delta := -qty;
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
    (id,estoque_id,funcionario_id,entrega_id,acao,quantidade,saldo_estoque,data,destino,observacao,ficha,comprovante)
  VALUES (p_id,stock.id,employee.id,delivery.id,action,qty,stock.quantidade,movement_date,target,note,doc,proof);
  RETURN p_id;
END $$;

CREATE FUNCTION rh_internal.asset_proof(p_event uuid, p_previous text, p_link text) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE
  proof text := btrim(coalesce(p_link,''));
  movement public.rh_asset_events%ROWTYPE;
BEGIN
  IF auth.uid() IS NULL OR NOT rh_internal.can_write() THEN RAISE EXCEPTION 'Sem permissão para editar comprovantes.'; END IF;
  IF length(proof)>2000 OR (proof<>'' AND proof !~* '^https?://[^[:space:]]+$') THEN
    RAISE EXCEPTION 'Informe um link de comprovante válido, começando com http:// ou https://.';
  END IF;
  SELECT * INTO movement FROM public.rh_asset_events WHERE id=p_event AND acao='entrega' FOR UPDATE;
  IF movement.id IS NULL OR NOT rh_internal.can_read_employee(movement.funcionario_id) THEN
    RAISE EXCEPTION 'Sem permissão para editar este comprovante.';
  END IF;
  IF movement.comprovante=proof THEN RETURN p_event; END IF;
  IF movement.comprovante IS DISTINCT FROM p_previous THEN RAISE EXCEPTION 'O comprovante mudou. Atualize o histórico e tente novamente.'; END IF;
  UPDATE public.rh_asset_events SET comprovante=proof WHERE id=p_event;
  RETURN p_event;
END $$;
CREATE FUNCTION public.rh_asset_proof(p_event uuid, p_previous text, p_link text) RETURNS uuid
LANGUAGE sql SECURITY INVOKER SET search_path = '' AS $$
  SELECT rh_internal.asset_proof(p_event,p_previous,p_link)
$$;
REVOKE ALL ON FUNCTION rh_internal.asset_proof(uuid,text,text), public.rh_asset_proof(uuid,text,text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION rh_internal.asset_proof(uuid,text,text), public.rh_asset_proof(uuid,text,text) TO authenticated;

CREATE INDEX rh_asset_employee_deliveries ON public.rh_asset_events (funcionario_id) WHERE acao='entrega';
CREATE FUNCTION public.rh_asset_delivered_employees() RETURNS uuid[]
LANGUAGE sql STABLE SECURITY INVOKER SET search_path = '' AS $$
  SELECT coalesce(array_agg(DISTINCT funcionario_id), '{}'::uuid[])
  FROM public.rh_asset_events WHERE acao='entrega' AND funcionario_id IS NOT NULL
$$;
REVOKE ALL ON FUNCTION public.rh_asset_delivered_employees() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.rh_asset_delivered_employees() TO authenticated;
