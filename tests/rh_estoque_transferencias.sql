-- Testa a função publicada com dados fictícios; tudo é revertido ao terminar.
BEGIN;
SELECT set_config('request.jwt.claim.sub',(SELECT id::text FROM public.profiles WHERE status='admin' ORDER BY created_at LIMIT 1),true);
SET LOCAL ROLE authenticated;
DO $$
DECLARE p jsonb; pid uuid; payload jsonb; r jsonb; branch text; dest text; q jsonb;
 before_events bigint; after_events bigint; before_sum bigint; version integer; origin_qty integer;
BEGIN
 ASSERT NOT has_function_privilege('anon','public.rh_transfer_stock(jsonb)','execute'),'Sem acesso anônimo';
 p:=public.rh_save_product(jsonb_build_object('nome','TESTE TRANSFERENCIA '||gen_random_uuid(),'categoria','epi','grupo','equipamento','tamanhos',jsonb_build_array('M','G'),'funcoes','[]'::jsonb,'todas_funcoes',true));
 pid:=(p->>'id')::uuid;
 -- Observação vazia, ausente e curta são aceitas na contagem física.
 FOREACH branch IN ARRAY ARRAY['FILIAL 5'] LOOP
  PERFORM public.rh_set_stock(jsonb_build_object('operacao_id',gen_random_uuid(),'produto_id',pid,'filial',branch,'tamanho','M','quantidade',10,'motivo','','versao',0));
 END LOOP;
 ASSERT (SELECT motivo FROM public.rh_stock_events WHERE produto_id=pid ORDER BY created_at LIMIT 1)='Atualização de estoque';
 payload:=jsonb_build_object('operacao_id',gen_random_uuid(),'produto_id',pid,'origem','FILIAL 5','destino','FILIAL 8','tamanho','M','quantidade',3,'versao_origem',2);
 r:=public.rh_transfer_stock(payload);
 ASSERT (r->>'saldo_origem')::int=7 AND (r->>'saldo_destino')::int=3,'Entrada e saída, inclusive destino sem linha anterior';
 ASSERT public.rh_transfer_stock(payload)=r,'Repetição devolve o mesmo resultado';
 ASSERT (SELECT count(*) FROM public.rh_stock_events WHERE operacao_id=(payload->>'operacao_id')::uuid)=2,'Exatamente dois eventos';
 ASSERT (SELECT sum(diferenca) FROM public.rh_stock_events WHERE operacao_id=(payload->>'operacao_id')::uuid)=0,'Saldo total conservado';
 BEGIN
  PERFORM public.rh_transfer_stock(payload||jsonb_build_object('quantidade',1));
  RAISE EXCEPTION 'Teste falhou: operação reutilizada';
 EXCEPTION WHEN OTHERS THEN IF SQLERRM NOT LIKE 'Operação já utilizada%' THEN RAISE; END IF; END;
 -- Os dois sentidos são permitidas; nunca mistura o tamanho G.
 FOREACH branch IN ARRAY ARRAY['FILIAL 5','FILIAL 8'] LOOP
  FOREACH dest IN ARRAY ARRAY['FILIAL 5','FILIAL 8'] LOOP
   IF branch=dest THEN CONTINUE; END IF;
   SELECT versao INTO version FROM public.rh_stock WHERE produto_id=pid AND filial=branch AND tamanho='M';
   PERFORM public.rh_transfer_stock(jsonb_build_object('operacao_id',gen_random_uuid(),'produto_id',pid,'origem',branch,'destino',dest,'tamanho','M','quantidade',1,'motivo','x','versao_origem',version));
  END LOOP;
 END LOOP;
 ASSERT (SELECT sum(quantidade) FROM public.rh_stock WHERE produto_id=pid)=10,'Todas as direções conservam o total';
 ASSERT NOT EXISTS(SELECT FROM public.rh_stock WHERE produto_id=pid AND tamanho='G'),'Tamanho isolado';
 SELECT count(*) INTO before_events FROM public.rh_stock_events WHERE produto_id=pid;
 SELECT quantidade,versao INTO origin_qty,version FROM public.rh_stock WHERE produto_id=pid AND filial='FILIAL 5' AND tamanho='M';
 payload:=jsonb_build_object('operacao_id',gen_random_uuid(),'produto_id',pid,'origem','FILIAL 5','destino','FILIAL 8','tamanho','M','quantidade',1,'versao_origem',version);
 FOR q IN SELECT value FROM jsonb_array_elements(jsonb_build_array(
  jsonb_build_object('quantidade',0),jsonb_build_object('quantidade',-1),jsonb_build_object('quantidade',1.5),jsonb_build_object('quantidade',null),
  jsonb_build_object('quantidade',1000001),jsonb_build_object('quantidade',origin_qty+1),jsonb_build_object('destino','FILIAL 5'),
  jsonb_build_object('destino','FILIAL 9'),jsonb_build_object('destino','FILIAL 6'),jsonb_build_object('origem','FILIAL 6'),jsonb_build_object('origem',null),jsonb_build_object('tamanho','XX'),
  jsonb_build_object('versao_origem',version-1),jsonb_build_object('versao_origem',null),jsonb_build_object('operacao_id',null),
  jsonb_build_object('motivo',repeat('x',501)))) LOOP
  BEGIN
   PERFORM public.rh_transfer_stock(payload||q);
   RAISE EXCEPTION 'Teste falhou: aceitou dados inválidos %',q;
  EXCEPTION WHEN OTHERS THEN IF SQLERRM LIKE 'Teste falhou:%' THEN RAISE; END IF; END;
 END LOOP;
 ASSERT (SELECT count(*) FROM public.rh_stock_events WHERE produto_id=pid)=before_events,'Erros não deixam eventos parciais';
 ASSERT (SELECT quantidade FROM public.rh_stock WHERE produto_id=pid AND filial='FILIAL 5' AND tamanho='M')=origin_qty,'Erros não debitam origem';
 -- Não basta ter sessão: sem identidade administrativa a função rejeita.
 PERFORM set_config('request.jwt.claim.sub','',true);
 BEGIN
  PERFORM public.rh_transfer_stock(payload);
  RAISE EXCEPTION 'Teste falhou: aceitou sem administrador';
 EXCEPTION WHEN OTHERS THEN IF SQLERRM NOT LIKE 'Somente administradores%' THEN RAISE; END IF; END;
END $$;
RESET ROLE;
-- Força erro no crédito do destino após o débito, provando rollback das duas pernas.
SELECT set_config('request.jwt.claim.sub',(SELECT id::text FROM public.profiles WHERE status='admin' ORDER BY created_at LIMIT 1),true);
DO $$
DECLARE pid uuid; op uuid:=gen_random_uuid(); count_before bigint;
BEGIN
 INSERT INTO public.rh_products(nome,categoria,tamanhos,todas_funcoes)
 VALUES('TESTE ROLLBACK TRANSFERENCIA '||gen_random_uuid(),'epi',ARRAY['M'],true) RETURNING id INTO pid;
 INSERT INTO public.rh_stock(produto_id,filial,tamanho,quantidade) VALUES(pid,'FILIAL 5','M',10),(pid,'FILIAL 8','M',2147483647);
 SELECT count(*) INTO count_before FROM public.rh_stock_events WHERE produto_id=pid;
 BEGIN
  PERFORM public.rh_transfer_stock(jsonb_build_object('operacao_id',op,'produto_id',pid,'origem','FILIAL 5','destino','FILIAL 8','tamanho','M','quantidade',1,'versao_origem',1));
  RAISE EXCEPTION 'Teste falhou: deveria rejeitar overflow no destino';
 EXCEPTION WHEN numeric_value_out_of_range THEN NULL; END;
 ASSERT (SELECT quantidade FROM public.rh_stock WHERE produto_id=pid AND filial='FILIAL 5')=10,'Erro no destino reverte débito';
 ASSERT (SELECT quantidade FROM public.rh_stock WHERE produto_id=pid AND filial='FILIAL 8')=2147483647,'Erro no destino conserva saldo';
 ASSERT (SELECT count(*) FROM public.rh_stock_events WHERE produto_id=pid)=count_before,'Erro na segunda perna não deixa eventos';
 ASSERT NOT EXISTS(SELECT FROM rh_internal.stock_operations WHERE id=op),'Erro não marca operação como concluída';
END $$;
SELECT 'OK: dois sentidos entre filiais 5 e 8, observação opcional, idempotência, validações, permissões e conservação de saldo' AS resultado;
ROLLBACK;
