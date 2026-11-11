ALTER TABLE public.profiles ADD COLUMN manage_stock boolean NOT NULL DEFAULT false;

-- A atualização continua protegida pela regra de perfis que reserva acessos aos administradores.
CREATE FUNCTION rh_internal.can_manage_stock() RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path='' AS $$
  SELECT EXISTS(
    SELECT 1 FROM public.profiles
    WHERE id=(SELECT auth.uid())
      AND (status='admin' OR (status='aprovado' AND manage_stock))
  )
$$;
REVOKE ALL ON FUNCTION rh_internal.can_manage_stock() FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION rh_internal.can_manage_stock() TO authenticated,service_role;

ALTER POLICY stock_read ON public.rh_stock TO authenticated USING(
  (SELECT rh_internal.can_manage_stock())
  OR EXISTS(SELECT 1 FROM public.funcionarios_epi e WHERE e.unidade=filial)
);
ALTER POLICY stock_events_read ON public.rh_stock_events TO authenticated
  USING((SELECT rh_internal.can_manage_stock()));
ALTER POLICY product_events_read ON public.rh_product_events TO authenticated
  USING((SELECT rh_internal.can_manage_stock()));

-- O catálogo precisa da lista completa de funções, sem ampliar o acesso aos registros de colaboradores.
CREATE FUNCTION rh_internal.stock_catalog_roles() RETURNS text[]
LANGUAGE sql STABLE SECURITY DEFINER SET search_path='' AS $$
  SELECT CASE WHEN rh_internal.can_manage_stock() THEN ARRAY(
    SELECT funcao FROM (
      SELECT funcao FROM public.funcionarios_epi
      UNION
      SELECT funcao FROM public.epi_funcao
    ) roles WHERE nullif(trim(funcao),'') IS NOT NULL ORDER BY funcao
  ) END
$$;
REVOKE ALL ON FUNCTION rh_internal.stock_catalog_roles() FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION rh_internal.stock_catalog_roles() TO authenticated;

CREATE FUNCTION public.rh_stock_catalog_roles() RETURNS text[]
LANGUAGE sql STABLE SECURITY INVOKER SET search_path='' AS $$
  SELECT rh_internal.stock_catalog_roles()
$$;
REVOKE ALL ON FUNCTION public.rh_stock_catalog_roles() FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.rh_stock_catalog_roles() TO authenticated;

CREATE OR REPLACE FUNCTION rh_internal.stock_delta(p uuid, f text, t text, d integer, op uuid, reason text, m uuid DEFAULT NULL::uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE balance integer;
BEGIN
 IF auth.uid() IS NULL OR NOT (rh_internal.can_write() OR rh_internal.can_manage_stock()) THEN RAISE EXCEPTION 'Sem permissão para movimentar estoque.'; END IF;
 INSERT INTO public.rh_stock(produto_id,filial,tamanho) VALUES(p,f,t) ON CONFLICT DO NOTHING;
 UPDATE public.rh_stock SET quantidade=quantidade+d,versao=versao+1 WHERE produto_id=p AND filial=f AND tamanho=t AND quantidade+d>=0 RETURNING quantidade INTO balance;
 IF NOT FOUND THEN RAISE EXCEPTION 'Estoque insuficiente na % para tamanho %. Confira o saldo e registre a entrada.',f,t; END IF;
 INSERT INTO public.rh_stock_events(operacao_id,produto_id,filial,tamanho,diferenca,saldo,motivo,movimento_id,created_by) VALUES(op,p,f,t,d,balance,reason,m,auth.uid());
END $function$;

CREATE OR REPLACE FUNCTION rh_internal.product_save(payload jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE p public.rh_products; previous jsonb; key text; emp uuid;
BEGIN
 IF auth.uid() IS NULL OR NOT rh_internal.can_manage_stock() THEN RAISE EXCEPTION 'Sem permissão para cadastrar e padronizar itens.'; END IF;
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
END $function$;

CREATE OR REPLACE FUNCTION rh_internal.product_merge(source_id uuid, target_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE source public.rh_products; target public.rh_products; s public.rh_stock; emp uuid; op uuid:=gen_random_uuid();
BEGIN
 IF auth.uid() IS NULL OR NOT rh_internal.can_manage_stock() THEN RAISE EXCEPTION 'Sem permissão para unificar cadastros.'; END IF;
 PERFORM pg_advisory_xact_lock(73411928);
 SELECT * INTO source FROM public.rh_products WHERE id=source_id;
 SELECT * INTO target FROM public.rh_products WHERE id=target_id;
 IF source_id=target_id OR source.id IS NULL OR target.id IS NULL OR source.categoria<>target.categoria OR NOT target.ativo THEN RAISE EXCEPTION 'Selecione dois cadastros distintos da mesma categoria, com destino ativo.'; END IF;
 IF NOT EXISTS(SELECT 1 FROM public.rh_product_aliases WHERE produto_id=source_id) THEN RETURN; END IF;
 UPDATE public.rh_products SET tamanhos=ARRAY(SELECT DISTINCT unnest(source.tamanhos||target.tamanhos)),versao=versao+1,updated_at=now() WHERE id=target_id;
 FOR s IN SELECT * FROM public.rh_stock WHERE produto_id=source_id AND quantidade>0 ORDER BY filial,tamanho LOOP
  PERFORM rh_internal.stock_delta(source_id,s.filial,s.tamanho,-s.quantidade,op,'Unificação em '||target.nome);
  PERFORM rh_internal.stock_delta(target_id,s.filial,s.tamanho,s.quantidade,op,'Unificação de '||source.nome);
 END LOOP;
 UPDATE public.rh_equipment_products SET produto_id=target_id WHERE produto_id=source_id;
 UPDATE public.rh_product_aliases SET produto_id=target_id WHERE produto_id=source_id;
 UPDATE public.rh_products SET ativo=false,versao=versao+1,updated_at=now() WHERE id=source_id;
 INSERT INTO public.rh_product_events(produto_id,antes,depois,created_by) VALUES(source_id,to_jsonb(source),jsonb_build_object('unificado_em',target_id,'nome',target.nome),auth.uid());
 FOR emp IN SELECT DISTINCT m.funcionario_id FROM public.rh_equipment_products b JOIN public.rh_equipment_movements m ON m.id=b.movimento_id WHERE b.produto_id=target_id ORDER BY m.funcionario_id LOOP
  PERFORM rh_internal.stock_refresh_employee(emp);
 END LOOP;
END $function$;

CREATE OR REPLACE FUNCTION rh_internal.product_reclassify(payload jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE source public.rh_products; target public.rh_products; s public.rh_stock;
 previous rh_internal.stock_operations; op uuid; destination text; target_id uuid; final_id uuid;
 request jsonb; result jsonb; emp uuid; affected integer; deliveries integer;
BEGIN
 IF auth.uid() IS NULL OR NOT rh_internal.can_manage_stock() THEN RAISE EXCEPTION 'Sem permissão para mudar o tipo dos itens.'; END IF;
 PERFORM pg_advisory_xact_lock(73411928);
 op:=(payload->>'operacao_id')::uuid;
 IF op IS NULL THEN RAISE EXCEPTION 'Identificador da alteração obrigatório.'; END IF;
 request:=payload||jsonb_build_object('tipo','reclassificacao','responsavel',auth.uid());
 SELECT * INTO previous FROM rh_internal.stock_operations WHERE id=op;
 IF FOUND THEN
  IF previous.payload IS DISTINCT FROM request THEN RAISE EXCEPTION 'Operação já utilizada para outra alteração.'; END IF;
  RETURN previous.result;
 END IF;
 SELECT * INTO source FROM public.rh_products WHERE id=(payload->>'id')::uuid FOR UPDATE;
 IF NOT FOUND OR source.versao IS DISTINCT FROM (payload->>'versao')::integer THEN RAISE EXCEPTION 'O cadastro mudou. Atualize e confira novamente.'; END IF;
 IF NOT EXISTS(SELECT 1 FROM public.rh_product_aliases WHERE produto_id=source.id) THEN RAISE EXCEPTION 'Este cadastro já foi unificado. Use o cadastro de destino.'; END IF;
 destination:=payload->>'categoria';
 IF destination IS NULL OR destination NOT IN ('epi','fardamento') OR destination=source.categoria THEN RAISE EXCEPTION 'Selecione um tipo de destino diferente do atual.'; END IF;
 target_id:=nullif(payload->>'substituto_id','')::uuid;
 SELECT count(DISTINCT m.funcionario_id),count(*) FILTER(WHERE m.tipo='entrega') INTO affected,deliveries
 FROM public.rh_equipment_products b JOIN public.rh_equipment_movements m ON m.id=b.movimento_id WHERE b.produto_id=source.id;
 IF target_id IS NULL THEN
  IF EXISTS(SELECT 1 FROM public.rh_product_aliases WHERE categoria=destination AND nome=rh_internal.product_key(source.nome) AND produto_id<>source.id) THEN
   RAISE EXCEPTION 'Já existe um item com este nome no tipo de destino. Escolha esse cadastro como substituto ou renomeie o item antes.';
  END IF;
  UPDATE public.rh_products SET categoria=destination,grupo=CASE WHEN destination='fardamento' THEN 'fardamento' ELSE 'equipamento' END,versao=versao+1,updated_at=now() WHERE id=source.id;
  INSERT INTO public.rh_product_aliases(categoria,nome,produto_id) VALUES(destination,rh_internal.product_key(source.nome),source.id) ON CONFLICT DO NOTHING;
  final_id:=source.id;
 ELSE
  SELECT * INTO target FROM public.rh_products WHERE id=target_id FOR UPDATE;
  IF NOT FOUND OR target.id=source.id OR NOT target.ativo OR target.categoria<>destination OR target.versao IS DISTINCT FROM (payload->>'versao_substituto')::integer THEN
   RAISE EXCEPTION 'Selecione um substituto ativo do tipo de destino e confira se o cadastro está atualizado.';
  END IF;
  UPDATE public.rh_products SET tamanhos=ARRAY(SELECT DISTINCT unnest(source.tamanhos||target.tamanhos) ORDER BY 1),versao=versao+1,updated_at=now() WHERE id=target.id;
  FOR s IN SELECT * FROM public.rh_stock WHERE produto_id=source.id AND quantidade>0 ORDER BY filial,tamanho LOOP
   PERFORM rh_internal.stock_delta(source.id,s.filial,s.tamanho,-s.quantidade,op,'Mudança de tipo e unificação em '||target.nome);
   PERFORM rh_internal.stock_delta(target.id,s.filial,s.tamanho,s.quantidade,op,'Mudança de tipo e unificação de '||source.nome);
  END LOOP;
  UPDATE public.rh_equipment_products SET produto_id=target.id WHERE produto_id=source.id;
  UPDATE public.rh_product_aliases SET produto_id=target.id WHERE produto_id=source.id;
  UPDATE public.rh_products SET ativo=false,versao=versao+1,updated_at=now() WHERE id=source.id;
  final_id:=target.id;
 END IF;
 INSERT INTO public.rh_product_events(produto_id,antes,depois,created_by)
 VALUES(source.id,to_jsonb(source),jsonb_build_object('acao','reclassificacao','operacao_id',op,'categoria',destination,'cadastro_destino',final_id,'substituido',target_id IS NOT NULL,'colaboradores',affected,'entregas',deliveries),auth.uid());
 FOR emp IN SELECT DISTINCT m.funcionario_id FROM public.rh_equipment_products b JOIN public.rh_equipment_movements m ON m.id=b.movimento_id WHERE b.produto_id=final_id ORDER BY m.funcionario_id LOOP
  PERFORM rh_internal.stock_refresh_employee(emp);
 END LOOP;
 result:=jsonb_build_object('operacao_id',op,'id',final_id,'categoria',destination,'substituido',target_id IS NOT NULL,'colaboradores',affected,'entregas',deliveries);
 INSERT INTO rh_internal.stock_operations(id,payload,result) VALUES(op,request,result);
 RETURN result;
END $function$;

CREATE OR REPLACE FUNCTION rh_internal.stock_set(payload jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE s public.rh_stock; p public.rh_products; previous rh_internal.stock_operations; op uuid; qty integer; result jsonb;
BEGIN
 IF auth.uid() IS NULL OR NOT rh_internal.can_manage_stock() THEN RAISE EXCEPTION 'Sem permissão para ajustar estoque.'; END IF;
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
 IF qty IS NULL OR qty<0 OR qty>1000000 OR length(trim(coalesce(payload->>'motivo','')))>500 THEN RAISE EXCEPTION 'Informe quantidade de 0 a 1.000.000 e observação de até 500 caracteres.'; END IF;
 SELECT * INTO s FROM public.rh_stock WHERE produto_id=p.id AND filial=payload->>'filial' AND tamanho=payload->>'tamanho' FOR UPDATE;
 IF coalesce(s.versao,0) IS DISTINCT FROM (payload->>'versao')::integer THEN RAISE EXCEPTION 'O saldo mudou. Atualize a página e confira novamente.'; END IF;
 PERFORM rh_internal.stock_delta(p.id,payload->>'filial',payload->>'tamanho',qty-coalesce(s.quantidade,0),op,coalesce(nullif(trim(payload->>'motivo'),''),'Atualização de estoque'));
 SELECT to_jsonb(x) INTO result FROM public.rh_stock x WHERE produto_id=p.id AND filial=payload->>'filial' AND tamanho=payload->>'tamanho';
 INSERT INTO rh_internal.stock_operations VALUES(op,payload,result);
 RETURN result;
END $function$;

CREATE OR REPLACE FUNCTION rh_internal.stock_transfer(payload jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
 p public.rh_products; source public.rh_stock; previous rh_internal.stock_operations;
 op uuid; qty integer; origin text; destination text; sz text; reason text;
 request jsonb; result jsonb;
BEGIN
 IF auth.uid() IS NULL OR NOT rh_internal.can_manage_stock() THEN
  RAISE EXCEPTION 'Sem permissão para transferir estoque.';
 END IF;
 IF payload IS NULL OR jsonb_typeof(payload)<>'object' THEN RAISE EXCEPTION 'Informe os dados da transferência.'; END IF;
 PERFORM pg_advisory_xact_lock(73411928);
 op:=(payload->>'operacao_id')::uuid;
 IF op IS NULL THEN RAISE EXCEPTION 'Identificador da transferência obrigatório.'; END IF;
 request:=payload||jsonb_build_object('tipo','transferencia','responsavel',auth.uid());
 SELECT * INTO previous FROM rh_internal.stock_operations WHERE id=op;
 IF FOUND THEN
  IF previous.payload IS DISTINCT FROM request THEN RAISE EXCEPTION 'Operação já utilizada para outra movimentação.'; END IF;
  RETURN previous.result;
 END IF;
 origin:=payload->>'origem'; destination:=payload->>'destino'; sz:=payload->>'tamanho';
 IF origin IS NULL OR destination IS NULL OR origin NOT IN ('FILIAL 5','FILIAL 8')
  OR destination NOT IN ('FILIAL 5','FILIAL 8') OR origin=destination THEN
  RAISE EXCEPTION 'Selecione filiais de origem e destino diferentes: 5 ou 8.';
 END IF;
 SELECT * INTO p FROM public.rh_products WHERE id=(payload->>'produto_id')::uuid;
 IF NOT FOUND OR NOT p.ativo THEN RAISE EXCEPTION 'Selecione um item ativo do estoque.'; END IF;
 IF sz IS NULL OR NOT sz=ANY(p.tamanhos) THEN RAISE EXCEPTION 'Selecione um tamanho cadastrado para o item.'; END IF;
 IF coalesce(payload->>'quantidade','') !~ '^[0-9]{1,7}$' THEN RAISE EXCEPTION 'Informe uma quantidade inteira de 1 a 1.000.000.'; END IF;
 qty:=(payload->>'quantidade')::integer;
 IF qty<1 OR qty>1000000 THEN RAISE EXCEPTION 'Informe uma quantidade inteira de 1 a 1.000.000.'; END IF;
 reason:=trim(coalesce(payload->>'motivo',''));
 IF length(reason)>500 THEN RAISE EXCEPTION 'A observação deve ter até 500 caracteres.'; END IF;
 SELECT * INTO source FROM public.rh_stock WHERE produto_id=p.id AND filial=origin AND tamanho=sz FOR UPDATE;
 IF coalesce(source.quantidade,0)<qty THEN RAISE EXCEPTION 'Estoque insuficiente na origem. Atualize o saldo e confira a quantidade.'; END IF;
 IF (payload->>'versao_origem')::integer IS DISTINCT FROM source.versao THEN
  RAISE EXCEPTION 'O saldo da origem mudou. Atualize e confira novamente antes de transferir.';
 END IF;
 PERFORM rh_internal.stock_delta(p.id,origin,sz,-qty,op,'Transferência para '||destination||CASE WHEN reason='' THEN '' ELSE ' · '||reason END);
 PERFORM rh_internal.stock_delta(p.id,destination,sz,qty,op,'Transferência de '||origin||CASE WHEN reason='' THEN '' ELSE ' · '||reason END);
 SELECT jsonb_build_object('operacao_id',op,'quantidade',qty,'origem',origin,'destino',destination,
  'saldo_origem',(SELECT quantidade FROM public.rh_stock WHERE produto_id=p.id AND filial=origin AND tamanho=sz),
  'saldo_destino',(SELECT quantidade FROM public.rh_stock WHERE produto_id=p.id AND filial=destination AND tamanho=sz)) INTO result;
 INSERT INTO rh_internal.stock_operations(id,payload,result) VALUES(op,request,result);
 RETURN result;
END $function$;

NOTIFY pgrst,'reload schema';
