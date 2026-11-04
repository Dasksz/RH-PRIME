-- Transferência atômica entre filiais; usa as mesmas travas das entregas e contagens.
ALTER TABLE public.rh_stock DROP CONSTRAINT rh_stock_filial_check;
ALTER TABLE public.rh_stock ADD CONSTRAINT rh_stock_filial_check
 CHECK (filial IN ('FILIAL 5','FILIAL 6','FILIAL 8'));

CREATE OR REPLACE FUNCTION rh_internal.stock_transfer(payload jsonb) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE
 p public.rh_products; source public.rh_stock; previous rh_internal.stock_operations;
 op uuid; qty integer; origin text; destination text; sz text; reason text;
 request jsonb; result jsonb;
BEGIN
 IF auth.uid() IS NULL OR NOT rh_internal.is_admin() THEN
  RAISE EXCEPTION 'Somente administradores podem transferir estoque.';
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
 IF origin IS NULL OR destination IS NULL OR origin NOT IN ('FILIAL 5','FILIAL 6','FILIAL 8')
  OR destination NOT IN ('FILIAL 5','FILIAL 6','FILIAL 8') OR origin=destination THEN
  RAISE EXCEPTION 'Selecione filiais de origem e destino diferentes: 5, 6 ou 8.';
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
END $$;
REVOKE ALL ON FUNCTION rh_internal.stock_transfer(jsonb) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION rh_internal.stock_transfer(jsonb) TO authenticated;
CREATE OR REPLACE FUNCTION public.rh_transfer_stock(payload jsonb) RETURNS jsonb
LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$ SELECT rh_internal.stock_transfer(payload) $$;
REVOKE ALL ON FUNCTION public.rh_transfer_stock(jsonb) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.rh_transfer_stock(jsonb) TO authenticated;

-- A filial 6 também recebe entradas e contagens físicas pelo formulário existente.
CREATE OR REPLACE FUNCTION rh_internal.stock_set(payload jsonb) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
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
 IF NOT (payload->>'tamanho')=ANY(p.tamanhos) OR payload->>'filial' NOT IN ('FILIAL 5','FILIAL 6','FILIAL 8') THEN RAISE EXCEPTION 'Filial ou tamanho inválido.'; END IF;
 qty:=(payload->>'quantidade')::integer;
 IF qty IS NULL OR qty<0 OR qty>1000000 OR length(trim(coalesce(payload->>'motivo','')))>500 THEN RAISE EXCEPTION 'Informe quantidade de 0 a 1.000.000 e observação de até 500 caracteres.'; END IF;
 SELECT * INTO s FROM public.rh_stock WHERE produto_id=p.id AND filial=payload->>'filial' AND tamanho=payload->>'tamanho' FOR UPDATE;
 IF coalesce(s.versao,0) IS DISTINCT FROM (payload->>'versao')::integer THEN RAISE EXCEPTION 'O saldo mudou. Atualize a página e confira novamente.'; END IF;
 PERFORM rh_internal.stock_delta(p.id,payload->>'filial',payload->>'tamanho',qty-coalesce(s.quantidade,0),op,coalesce(nullif(trim(payload->>'motivo'),''),'Atualização de estoque'));
 SELECT to_jsonb(x) INTO result FROM public.rh_stock x WHERE produto_id=p.id AND filial=payload->>'filial' AND tamanho=payload->>'tamanho';
 INSERT INTO rh_internal.stock_operations VALUES(op,payload,result);
 RETURN result;
END $$;
NOTIFY pgrst,'reload schema';
