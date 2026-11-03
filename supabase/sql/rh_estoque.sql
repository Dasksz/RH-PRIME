-- Catálogo permanente. O histórico original e os documentos emitidos são preservados.
CREATE TABLE public.rh_products (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(), nome text NOT NULL CHECK(length(trim(nome)) BETWEEN 1 AND 200),
 categoria text NOT NULL CHECK(categoria IN ('epi','fardamento')),
 grupo text NOT NULL DEFAULT 'equipamento' CHECK(grupo IN ('produto','equipamento','fardamento')),
 tamanhos text[] NOT NULL DEFAULT ARRAY['ÚNICO'], funcoes text[] NOT NULL DEFAULT '{}',
 todas_funcoes boolean NOT NULL DEFAULT false, ativo boolean NOT NULL DEFAULT true,
 versao integer NOT NULL DEFAULT 1, updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE public.rh_product_aliases (
 categoria text NOT NULL, nome text NOT NULL, produto_id uuid NOT NULL REFERENCES public.rh_products,
 PRIMARY KEY(categoria,nome)
);
CREATE INDEX rh_product_alias_product ON public.rh_product_aliases(produto_id);
CREATE TABLE public.rh_stock (
 produto_id uuid NOT NULL REFERENCES public.rh_products, filial text NOT NULL CHECK(filial IN ('FILIAL 5','FILIAL 8')),
 tamanho text NOT NULL CHECK(length(tamanho) BETWEEN 1 AND 40), quantidade integer NOT NULL DEFAULT 0 CHECK(quantidade>=0),
 versao integer NOT NULL DEFAULT 1, PRIMARY KEY(produto_id,filial,tamanho)
);
CREATE TABLE public.rh_stock_events (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(), operacao_id uuid NOT NULL,
 produto_id uuid NOT NULL REFERENCES public.rh_products, filial text NOT NULL, tamanho text NOT NULL,
 diferenca integer NOT NULL, saldo integer NOT NULL CHECK(saldo>=0), motivo text NOT NULL,
 movimento_id uuid REFERENCES public.rh_equipment_movements, created_by uuid, created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX rh_stock_events_product ON public.rh_stock_events(produto_id,created_at DESC);
CREATE TABLE public.rh_equipment_products (
 movimento_id uuid PRIMARY KEY REFERENCES public.rh_equipment_movements,
 produto_id uuid NOT NULL REFERENCES public.rh_products, filial text NOT NULL, tamanho text NOT NULL,
 descontado boolean NOT NULL DEFAULT false
);
CREATE INDEX rh_equipment_products_product ON public.rh_equipment_products(produto_id);
CREATE TABLE public.rh_product_events (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(), produto_id uuid NOT NULL REFERENCES public.rh_products,
 antes jsonb, depois jsonb NOT NULL, created_by uuid NOT NULL, created_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE rh_internal.stock_operations (id uuid PRIMARY KEY, payload jsonb NOT NULL, result jsonb NOT NULL);
ALTER TABLE rh_internal.stock_operations ENABLE ROW LEVEL SECURITY;

CREATE FUNCTION rh_internal.product_key(v text) RETURNS text LANGUAGE sql IMMUTABLE SET search_path='' AS $$
 SELECT upper(trim(regexp_replace(v,'\s+',' ','g')))
$$;
REVOKE ALL ON FUNCTION rh_internal.product_key(text) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION rh_internal.product_key(text) TO authenticated,service_role;

-- Apenas diferenças de caixa/espaços são agrupadas automaticamente. Outros nomes continuam separados.
INSERT INTO public.rh_products(nome,categoria,grupo,tamanhos,todas_funcoes)
SELECT rh_internal.product_key(equipamento),categoria,CASE WHEN categoria='fardamento' THEN 'fardamento' ELSE 'equipamento' END,
 CASE WHEN rh_internal.product_key(equipamento) ~ '(BOTA|CALÇADO)' THEN ARRAY['35','36','37','38','39','40','41','42','43','44','45','46']
 WHEN rh_internal.product_key(equipamento) ~ '(CAMISA|REGATA|BLUSA|COLETE|CAL[CÇ]A|PROTETOR DORSAL)' THEN ARRAY['PP','P','M','G','GG','EXG'] ELSE ARRAY['ÚNICO'] END,false
FROM public.rh_equipment_movements GROUP BY 1,2,3,4;
INSERT INTO public.rh_product_aliases SELECT categoria,rh_internal.product_key(nome),id FROM public.rh_products;
INSERT INTO public.rh_equipment_products(movimento_id,produto_id,filial,tamanho)
SELECT m.id,a.produto_id,e.unidade,coalesce(nullif(m.tamanho,''),'ÚNICO')
FROM public.rh_equipment_movements m JOIN public.funcionarios_epi e ON e.id=m.funcionario_id
JOIN public.rh_product_aliases a ON a.categoria=m.categoria AND a.nome=rh_internal.product_key(m.equipamento);
-- Preservar as regras conhecidas; itens sem regra ficam disponíveis para configuração pelo RH.
UPDATE public.rh_products p SET funcoes=coalesce((SELECT array_agg(r.funcao ORDER BY r.funcao) FROM public.epi_funcao r
 WHERE coalesce((to_jsonb(r)->>CASE p.nome WHEN 'CAPACETE' THEN 'capacete' WHEN 'PROTETOR AURICULAR' THEN 'protetor_auricular'
 WHEN 'COLETE REFLETIVO' THEN 'colete_refletivo' WHEN 'PROTETOR DORSAL' THEN 'protetor_dorsal'
 WHEN 'CALÇA C/ FAIXA REFLETIVA' THEN 'calca_faixa_refletiva' WHEN 'BOTA MARLUVAS' THEN 'bota_marluvas' WHEN 'BOTA' THEN 'bota_marluvas'
 WHEN 'CAMISA ELMA' THEN 'camisa_elma' WHEN 'REGATA ELMA' THEN 'regata_elma' WHEN 'CAMISA COPA' THEN 'camisa_copa'
 WHEN 'OCULOS DE POLICARBONATO' THEN 'oculos_policarbonato' END)::boolean,false)),'{}');

ALTER TABLE public.rh_products ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.rh_product_aliases ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.rh_stock ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.rh_stock_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.rh_equipment_products ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.rh_product_events ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.rh_products,public.rh_product_aliases,public.rh_stock,public.rh_stock_events,public.rh_equipment_products,public.rh_product_events FROM PUBLIC,anon,authenticated;
GRANT SELECT ON public.rh_products,public.rh_product_aliases,public.rh_stock,public.rh_stock_events,public.rh_equipment_products,public.rh_product_events TO authenticated;
GRANT ALL ON public.rh_products,public.rh_product_aliases,public.rh_stock,public.rh_stock_events,public.rh_equipment_products,public.rh_product_events TO service_role;
CREATE POLICY products_read ON public.rh_products FOR SELECT TO authenticated USING(EXISTS(SELECT 1 FROM public.profiles WHERE id=(SELECT auth.uid()) AND status IN ('admin','aprovado')));
CREATE POLICY aliases_read ON public.rh_product_aliases FOR SELECT TO authenticated USING(EXISTS(SELECT 1 FROM public.rh_products p WHERE p.id=produto_id));
CREATE POLICY stock_read ON public.rh_stock FOR SELECT TO authenticated USING((SELECT rh_internal.is_admin()) OR EXISTS(SELECT 1 FROM public.funcionarios_epi e WHERE e.unidade=filial));
CREATE POLICY stock_events_read ON public.rh_stock_events FOR SELECT TO authenticated USING((SELECT rh_internal.is_admin()));
CREATE POLICY equipment_products_read ON public.rh_equipment_products FOR SELECT TO authenticated USING(EXISTS(SELECT 1 FROM public.rh_equipment_movements m WHERE m.id=movimento_id));
CREATE POLICY product_events_read ON public.rh_product_events FOR SELECT TO authenticated USING((SELECT rh_internal.is_admin()));

CREATE VIEW public.rh_equipment_current WITH(security_invoker=true) AS
SELECT m.id,m.funcionario_id,m.operacao_id,m.categoria,m.tipo,coalesce(p.nome,m.equipamento) equipamento,m.complemento,
 coalesce(p.nome||CASE WHEN m.complemento<>'' THEN ' - '||m.complemento ELSE '' END,m.descricao) descricao,
 m.ca,m.quantidade,m.data_movimento,m.entrega_origem_id,m.motivo,m.observacao,m.comprovante,m.legado,m.legado_chave,m.created_by,m.created_at,m.registrado_por,m.tamanho,
 b.produto_id,b.filial estoque_filial,b.descontado estoque_descontado
FROM public.rh_equipment_movements m LEFT JOIN public.rh_equipment_products b ON b.movimento_id=m.id LEFT JOIN public.rh_products p ON p.id=b.produto_id;
REVOKE ALL ON public.rh_equipment_current FROM PUBLIC,anon;
GRANT SELECT ON public.rh_equipment_current TO authenticated,service_role;

-- Somente rotinas internas alteram saldo. Autorização explícita antes de qualquer acesso privilegiado.
CREATE FUNCTION rh_internal.stock_delta(p uuid,f text,t text,d integer,op uuid,reason text,m uuid DEFAULT NULL) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE balance integer;
BEGIN
 IF auth.uid() IS NULL OR NOT rh_internal.can_write() THEN RAISE EXCEPTION 'Sem permissão para movimentar estoque.'; END IF;
 INSERT INTO public.rh_stock(produto_id,filial,tamanho) VALUES(p,f,t) ON CONFLICT DO NOTHING;
 UPDATE public.rh_stock SET quantidade=quantidade+d,versao=versao+1 WHERE produto_id=p AND filial=f AND tamanho=t AND quantidade+d>=0 RETURNING quantidade INTO balance;
 IF NOT FOUND THEN RAISE EXCEPTION 'Estoque insuficiente na % para tamanho %. Confira o saldo e registre a entrada.',f,t; END IF;
 INSERT INTO public.rh_stock_events(operacao_id,produto_id,filial,tamanho,diferenca,saldo,motivo,movimento_id,created_by) VALUES(op,p,f,t,d,balance,reason,m,auth.uid());
END $$;
REVOKE ALL ON FUNCTION rh_internal.stock_delta(uuid,text,text,integer,uuid,text,uuid) FROM PUBLIC,anon,authenticated;

CREATE FUNCTION rh_internal.stock_equipment() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE p public.rh_products; b public.rh_equipment_products; e public.funcionarios_epi; sz text;
BEGIN
 IF auth.uid() IS NULL OR NOT rh_internal.can_write() OR NOT rh_internal.can_read_employee(new.funcionario_id) THEN RAISE EXCEPTION 'Sem permissão para entrega.'; END IF;
 -- Uma trava única ordena catálogo, correções e saldos, evitando corrida entre entregas/renomeação.
 PERFORM pg_advisory_xact_lock(73411928);
 IF new.tipo<>'entrega' THEN
  INSERT INTO public.rh_equipment_products(movimento_id,produto_id,filial,tamanho,descontado)
  SELECT new.id,produto_id,filial,tamanho,false FROM public.rh_equipment_products WHERE movimento_id=new.entrega_origem_id ON CONFLICT DO NOTHING;
  RETURN new; -- Devolução avariada/perda não é entrada disponível; o RH confere e registra a entrada.
 END IF;
 SELECT * INTO p FROM public.rh_products WHERE id=(SELECT produto_id FROM public.rh_product_aliases WHERE categoria=new.categoria AND nome=rh_internal.product_key(new.equipamento));
 IF NOT FOUND THEN RAISE EXCEPTION 'Cadastre o item no Estoque antes de entregar.'; END IF;
 SELECT * INTO b FROM public.rh_equipment_products WHERE movimento_id=new.id;
 IF TG_OP='UPDATE' AND ROW(old.equipamento,old.tamanho,old.quantidade) IS NOT DISTINCT FROM ROW(new.equipamento,new.tamanho,new.quantidade) THEN RETURN new; END IF;
 SELECT * INTO e FROM public.funcionarios_epi WHERE id=new.funcionario_id;
 sz:=coalesce(nullif(trim(new.tamanho),''),'ÚNICO');
 IF TG_OP='INSERT' OR b.descontado THEN
  IF NOT p.ativo OR NOT (p.todas_funcoes OR e.funcao=ANY(p.funcoes)) THEN RAISE EXCEPTION 'Item indisponível para a função %.',e.funcao; END IF;
  IF NOT sz=ANY(p.tamanhos) THEN RAISE EXCEPTION 'Selecione um tamanho cadastrado para %.',p.nome; END IF;
  IF b.descontado THEN PERFORM rh_internal.stock_delta(b.produto_id,b.filial,b.tamanho,old.quantidade,new.operacao_id,'Estorno por correção',new.id); END IF;
  PERFORM rh_internal.stock_delta(p.id,CASE WHEN b.descontado THEN b.filial ELSE e.unidade END,sz,-new.quantidade,new.operacao_id,'Entrega',new.id);
 END IF;
 INSERT INTO public.rh_equipment_products(movimento_id,produto_id,filial,tamanho,descontado)
 VALUES(new.id,p.id,coalesce(b.filial,e.unidade),sz,TG_OP='INSERT' OR coalesce(b.descontado,false))
 ON CONFLICT(movimento_id) DO UPDATE SET produto_id=excluded.produto_id,tamanho=excluded.tamanho;
 RETURN new;
END $$;
REVOKE ALL ON FUNCTION rh_internal.stock_equipment() FROM PUBLIC,anon,authenticated;
-- Ativado após cadastro dos saldos; não infere estoque físico a partir das entregas antigas.

CREATE FUNCTION rh_internal.stock_refresh_employee(emp uuid) RETURNS void LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $$
DECLARE cat text; txt text;
BEGIN
 FOREACH cat IN ARRAY ARRAY['epi','fardamento'] LOOP
  SELECT string_agg(m.descricao||' ('||CASE WHEN m.ca<>'' THEN 'CA: '||m.ca||', ' ELSE '' END||CASE WHEN m.tamanho<>'' THEN 'Tamanho: '||m.tamanho||', ' ELSE '' END||'Qtd: '||s.saldo||CASE WHEN m.data_movimento IS NOT NULL THEN ' - '||coalesce((SELECT max(v.data_verificacao) FROM public.rh_equipment_checks v WHERE v.entrega_id=m.id),m.data_movimento)::text ELSE '' END||')','; ' ORDER BY m.data_movimento DESC NULLS LAST,m.id)
  INTO txt FROM public.rh_equipment_current m CROSS JOIN LATERAL(SELECT m.quantidade-coalesce(sum(r.quantidade),0) saldo FROM public.rh_equipment_movements r WHERE r.entrega_origem_id=m.id AND r.tipo IN ('devolucao','baixa'))s
  WHERE m.funcionario_id=emp AND m.categoria=cat AND m.tipo='entrega' AND s.saldo>0;
  IF cat='epi' THEN UPDATE public.funcionarios_epi SET epi_itens=coalesce(txt,'') WHERE id=emp AND epi_itens IS DISTINCT FROM coalesce(txt,'');
  ELSE UPDATE public.funcionarios_epi SET fardamento_itens=coalesce(txt,'') WHERE id=emp AND fardamento_itens IS DISTINCT FROM coalesce(txt,''); END IF;
 END LOOP;
END $$;
REVOKE ALL ON FUNCTION rh_internal.stock_refresh_employee(uuid) FROM PUBLIC,anon,authenticated;

CREATE FUNCTION rh_internal.product_save(payload jsonb) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE p public.rh_products; previous jsonb; key text; emp uuid;
BEGIN
 IF auth.uid() IS NULL OR NOT rh_internal.is_admin() THEN RAISE EXCEPTION 'Somente administradores podem cadastrar e padronizar itens.'; END IF;
 PERFORM pg_advisory_xact_lock(73411928);
 IF nullif(payload->>'id','') IS NOT NULL THEN
  SELECT * INTO p FROM public.rh_products WHERE id=(payload->>'id')::uuid FOR UPDATE;
  IF NOT FOUND OR p.versao IS DISTINCT FROM (payload->>'versao')::integer THEN RAISE EXCEPTION 'O cadastro mudou. Atualize a página antes de salvar.'; END IF;
  IF payload->>'categoria' IS DISTINCT FROM p.categoria THEN RAISE EXCEPTION 'A categoria de um item existente é permanente.'; END IF;
  previous:=to_jsonb(p);
 ELSE p.id:=gen_random_uuid(); END IF;
 key:=rh_internal.product_key(payload->>'nome');
 IF key IS NULL OR length(key) NOT BETWEEN 1 AND 200 OR key ~ '\s+-\s+' THEN RAISE EXCEPTION 'Informe um nome de até 200 caracteres; use o complemento na entrega.'; END IF;
 IF EXISTS(SELECT 1 FROM public.rh_product_aliases WHERE categoria=payload->>'categoria' AND nome=key AND produto_id<>p.id) THEN RAISE EXCEPTION 'Esse nome já pertence a outro item. Edite o cadastro existente.'; END IF;
 IF jsonb_typeof(payload->'tamanhos') IS DISTINCT FROM 'array' OR jsonb_array_length(payload->'tamanhos') NOT BETWEEN 1 AND 100 THEN RAISE EXCEPTION 'Informe ao menos um tamanho (ou ÚNICO).'; END IF;
 IF EXISTS(SELECT 1 FROM jsonb_array_elements_text(payload->'tamanhos') x WHERE length(trim(x)) NOT BETWEEN 1 AND 40) THEN RAISE EXCEPTION 'Tamanho inválido.'; END IF;
 IF jsonb_typeof(payload->'funcoes') IS DISTINCT FROM 'array' THEN RAISE EXCEPTION 'Lista de funções inválida.'; END IF;
 INSERT INTO public.rh_products(id,nome,categoria,grupo,tamanhos,funcoes,todas_funcoes,ativo)
 VALUES(p.id,key,payload->>'categoria',payload->>'grupo',ARRAY(SELECT DISTINCT trim(x) FROM jsonb_array_elements_text(payload->'tamanhos')x),ARRAY(SELECT DISTINCT trim(x) FROM jsonb_array_elements_text(payload->'funcoes')x),coalesce((payload->>'todas_funcoes')::boolean,false),coalesce((payload->>'ativo')::boolean,true))
 ON CONFLICT(id) DO UPDATE SET nome=excluded.nome,grupo=excluded.grupo,tamanhos=excluded.tamanhos,funcoes=excluded.funcoes,todas_funcoes=excluded.todas_funcoes,ativo=excluded.ativo,versao=public.rh_products.versao+1,updated_at=now() RETURNING * INTO p;
 INSERT INTO public.rh_product_aliases VALUES(p.categoria,key,p.id) ON CONFLICT DO NOTHING;
 INSERT INTO public.rh_product_events(produto_id,antes,depois,created_by) VALUES(p.id,previous,to_jsonb(p),auth.uid());
 IF previous->>'nome' IS DISTINCT FROM p.nome THEN
  FOR emp IN SELECT DISTINCT m.funcionario_id FROM public.rh_equipment_products b JOIN public.rh_equipment_movements m ON m.id=b.movimento_id WHERE b.produto_id=p.id ORDER BY m.funcionario_id LOOP
   PERFORM rh_internal.stock_refresh_employee(emp);
  END LOOP;
 END IF;
 RETURN to_jsonb(p);
END $$;
REVOKE ALL ON FUNCTION rh_internal.product_save(jsonb) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION rh_internal.product_save(jsonb) TO authenticated;
CREATE FUNCTION public.rh_save_product(payload jsonb) RETURNS jsonb LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$ SELECT rh_internal.product_save(payload) $$;
REVOKE ALL ON FUNCTION public.rh_save_product(jsonb) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.rh_save_product(jsonb) TO authenticated;

CREATE FUNCTION rh_internal.stock_set(payload jsonb) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE s public.rh_stock; p public.rh_products; previous rh_internal.stock_operations; op uuid; qty integer; result jsonb;
BEGIN
 IF auth.uid() IS NULL OR NOT rh_internal.is_admin() THEN RAISE EXCEPTION 'Somente administradores podem ajustar estoque.'; END IF;
 PERFORM pg_advisory_xact_lock(73411928);
 op:=(payload->>'operacao_id')::uuid;
 SELECT * INTO previous FROM rh_internal.stock_operations WHERE id=op;
 IF FOUND THEN
  IF previous.payload IS DISTINCT FROM payload THEN RAISE EXCEPTION 'Operação já utilizada para outro ajuste.'; END IF;
  RETURN previous.result;
 END IF;
 SELECT * INTO p FROM public.rh_products WHERE id=(payload->>'produto_id')::uuid;
 IF NOT FOUND THEN RAISE EXCEPTION 'Item inexistente.'; END IF;
 IF NOT (payload->>'tamanho')=ANY(p.tamanhos) OR payload->>'filial' NOT IN ('FILIAL 5','FILIAL 8') THEN RAISE EXCEPTION 'Filial ou tamanho inválido.'; END IF;
 qty:=(payload->>'quantidade')::integer;
 IF qty IS NULL OR qty<0 OR qty>1000000 OR length(trim(coalesce(payload->>'motivo',''))) NOT BETWEEN 3 AND 500 THEN RAISE EXCEPTION 'Informe quantidade de 0 a 1.000.000 e motivo do ajuste.'; END IF;
 SELECT * INTO s FROM public.rh_stock WHERE produto_id=p.id AND filial=payload->>'filial' AND tamanho=payload->>'tamanho' FOR UPDATE;
 IF coalesce(s.versao,0) IS DISTINCT FROM (payload->>'versao')::integer THEN RAISE EXCEPTION 'O saldo mudou. Atualize a página e confira novamente.'; END IF;
 PERFORM rh_internal.stock_delta(p.id,payload->>'filial',payload->>'tamanho',qty-coalesce(s.quantidade,0),op,payload->>'motivo');
 SELECT to_jsonb(x) INTO result FROM public.rh_stock x WHERE produto_id=p.id AND filial=payload->>'filial' AND tamanho=payload->>'tamanho';
 INSERT INTO rh_internal.stock_operations VALUES(op,payload,result);
 RETURN result;
END $$;
REVOKE ALL ON FUNCTION rh_internal.stock_set(jsonb) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION rh_internal.stock_set(jsonb) TO authenticated;
CREATE FUNCTION public.rh_set_stock(payload jsonb) RETURNS jsonb LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$ SELECT rh_internal.stock_set(payload) $$;
REVOKE ALL ON FUNCTION public.rh_set_stock(jsonb) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.rh_set_stock(jsonb) TO authenticated;

-- Novas fichas exibem a nomenclatura atual. Fotografias já emitidas continuam imutáveis.
DO $$ DECLARE definition text; BEGIN
 SELECT pg_get_functiondef('rh_internal.equipment_receipt_snapshot()'::regprocedure) INTO definition;
 definition:=replace(definition,'FROM public.rh_equipment_movements m','FROM public.rh_equipment_current m');
 definition:=replace(definition,'from public.rh_equipment_movements m','from public.rh_equipment_current m');
 EXECUTE definition;
END $$;
NOTIFY pgrst,'reload schema';
