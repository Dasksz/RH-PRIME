CREATE TABLE public.rh_asset_types (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  nome text NOT NULL CHECK (length(btrim(nome)) BETWEEN 1 AND 80),
  detalhe text NOT NULL CHECK (detalhe IN ('ano','modelo','descricao','nenhum'))
);
CREATE UNIQUE INDEX rh_asset_type_name ON public.rh_asset_types (lower(btrim(nome)));
INSERT INTO public.rh_asset_types (nome, detalhe) VALUES ('Catálogo','ano'), ('Celular','modelo');

CREATE TABLE public.rh_asset_stock (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tipo_id uuid NOT NULL REFERENCES public.rh_asset_types,
  variante text NOT NULL CHECK (length(variante) <= 120),
  filial text NOT NULL CHECK (filial IN ('FILIAL 5','FILIAL 8')),
  quantidade integer NOT NULL DEFAULT 0 CHECK (quantidade >= 0),
  UNIQUE (tipo_id, variante, filial)
);

CREATE TABLE public.rh_asset_events (
  id uuid PRIMARY KEY,
  estoque_id uuid NOT NULL REFERENCES public.rh_asset_stock,
  funcionario_id uuid REFERENCES public.funcionarios_epi,
  entrega_id uuid REFERENCES public.rh_asset_events,
  acao text NOT NULL CHECK (acao IN ('entrada','ajuste','entrega','devolucao','baixa')),
  quantidade integer NOT NULL CHECK (quantidade BETWEEN 1 AND 10000),
  saldo_estoque integer NOT NULL CHECK (saldo_estoque >= 0),
  data date NOT NULL,
  destino text CHECK (destino IN ('disponivel','avariado')),
  observacao text NOT NULL CHECK (length(observacao) <= 1000),
  ficha jsonb,
  created_by uuid NOT NULL DEFAULT auth.uid(),
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX rh_asset_employee_events ON public.rh_asset_events (funcionario_id, data DESC);
CREATE INDEX rh_asset_delivery_returns ON public.rh_asset_events (entrega_id);

ALTER TABLE public.rh_asset_types ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.rh_asset_stock ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.rh_asset_events ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.rh_asset_types, public.rh_asset_stock, public.rh_asset_events FROM PUBLIC, anon, authenticated;
GRANT SELECT ON public.rh_asset_types, public.rh_asset_stock, public.rh_asset_events TO authenticated;
GRANT INSERT ON public.rh_asset_types TO authenticated;

CREATE POLICY asset_types_read ON public.rh_asset_types FOR SELECT TO authenticated USING (
  (SELECT rh_internal.can_manage_stock()) OR EXISTS (SELECT 1 FROM public.funcionarios_epi)
);
CREATE POLICY asset_types_insert ON public.rh_asset_types FOR INSERT TO authenticated
  WITH CHECK ((SELECT rh_internal.can_manage_stock()));
CREATE POLICY asset_stock_read ON public.rh_asset_stock FOR SELECT TO authenticated USING (
  (SELECT rh_internal.can_manage_stock()) OR EXISTS (SELECT 1 FROM public.funcionarios_epi e WHERE e.unidade = filial)
);
CREATE POLICY asset_events_read ON public.rh_asset_events FOR SELECT TO authenticated USING (
  (funcionario_id IS NULL AND (SELECT rh_internal.can_manage_stock()))
  OR (funcionario_id IS NOT NULL AND rh_internal.can_read_employee(funcionario_id))
);

CREATE FUNCTION rh_internal.asset_event(p_id uuid, p jsonb) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE
  action text := p->>'acao';
  movement_date date := (p->>'data')::date;
  qty integer := (p->>'quantidade')::integer;
  note text := btrim(coalesce(p->>'observacao',''));
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
    (id,estoque_id,funcionario_id,entrega_id,acao,quantidade,saldo_estoque,data,destino,observacao,ficha)
  VALUES (p_id,stock.id,employee.id,delivery.id,action,qty,stock.quantidade,movement_date,target,note,doc);
  RETURN p_id;
END $$;

CREATE FUNCTION public.rh_asset_event(p_id uuid, p jsonb) RETURNS uuid
LANGUAGE sql SECURITY INVOKER SET search_path = '' AS $$
  SELECT rh_internal.asset_event(p_id,p)
$$;

REVOKE ALL ON FUNCTION rh_internal.asset_event(uuid,jsonb), public.rh_asset_event(uuid,jsonb) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION rh_internal.asset_event(uuid,jsonb), public.rh_asset_event(uuid,jsonb) TO authenticated;

CREATE FUNCTION public.rh_asset_access() RETURNS jsonb
LANGUAGE sql STABLE SECURITY INVOKER SET search_path = '' AS $$
  SELECT jsonb_build_object('estoque',rh_internal.can_manage_stock(),'entrega',rh_internal.can_write())
$$;
REVOKE ALL ON FUNCTION public.rh_asset_access() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.rh_asset_access() TO authenticated;

CREATE FUNCTION rh_internal.asset_stock_history() RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $$
  SELECT CASE WHEN auth.uid() IS NOT NULL AND rh_internal.can_manage_stock() THEN (
    SELECT coalesce(jsonb_agg(to_jsonb(m) ORDER BY m.data DESC, m.created_at DESC, m.id DESC), '[]'::jsonb)
    FROM (
      SELECT id, estoque_id, acao, quantidade, saldo_estoque, data, destino, created_at
      FROM public.rh_asset_events
      ORDER BY data DESC, created_at DESC, id DESC LIMIT 100
    ) m
  ) ELSE '[]'::jsonb END
$$;
CREATE FUNCTION public.rh_asset_stock_history() RETURNS jsonb
LANGUAGE sql STABLE SECURITY INVOKER SET search_path = '' AS $$
  SELECT rh_internal.asset_stock_history()
$$;
REVOKE ALL ON FUNCTION rh_internal.asset_stock_history(), public.rh_asset_stock_history() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION rh_internal.asset_stock_history(), public.rh_asset_stock_history() TO authenticated;
