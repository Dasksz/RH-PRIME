-- Executar com postgres no MCP. Tudo, inclusive as entregas e gatilhos HTTP, é revertido.
BEGIN;
SELECT set_config('request.jwt.claim.sub',(SELECT id::text FROM public.profiles WHERE status='admin' ORDER BY created_at LIMIT 1),true);
CREATE TRIGGER zz_stock_equipment AFTER INSERT OR UPDATE ON public.rh_equipment_movements FOR EACH ROW EXECUTE FUNCTION rh_internal.stock_equipment();
SET LOCAL ROLE authenticated;
DO $$
DECLARE product jsonb; target jsonb; stock jsonb; payload jsonb; op uuid:=gen_random_uuid(); op8 uuid:=gen_random_uuid(); e5 uuid; e8 uuid; doc jsonb; olddoc jsonb; movement uuid; today date:=(now() AT TIME ZONE 'America/Sao_Paulo')::date; n integer;
BEGIN
 SELECT id INTO e5 FROM public.funcionarios_epi WHERE unidade='FILIAL 5' AND data_desligamento IS NULL LIMIT 1;
 SELECT id INTO e8 FROM public.funcionarios_epi WHERE unidade='FILIAL 8' AND data_desligamento IS NULL LIMIT 1;
 product:=public.rh_save_product(jsonb_build_object('nome','TESTE ESTOQUE TRANSACAO','categoria','epi','grupo','equipamento','tamanhos',jsonb_build_array('M','G'),'funcoes','[]'::jsonb,'todas_funcoes',true));
 payload:=jsonb_build_object('operacao_id',gen_random_uuid(),'produto_id',product->>'id','filial','FILIAL 5','tamanho','M','quantidade',10,'motivo','Teste revertido','versao',0);
 stock:=public.rh_set_stock(payload);
 PERFORM public.rh_set_stock(payload); -- repetição não adiciona mais estoque
 PERFORM public.rh_set_stock(jsonb_build_object('operacao_id',gen_random_uuid(),'produto_id',product->>'id','filial','FILIAL 8','tamanho','M','quantidade',7,'motivo','Teste revertido','versao',0));
 doc:=public.rh_registrar_equipamentos(e5,'epi',op,jsonb_build_array(jsonb_build_object('equipamento',product->>'nome','tamanho','M','quantidade',2,'data',today)));
 olddoc:=doc;
 PERFORM public.rh_registrar_equipamentos(e5,'epi',op,jsonb_build_array(jsonb_build_object('equipamento',product->>'nome','tamanho','M','quantidade',2,'data',today)));
 ASSERT (SELECT quantidade FROM public.rh_stock WHERE produto_id=(product->>'id')::uuid AND filial='FILIAL 5' AND tamanho='M')=8,'Entrega/repetição filial 5';
 ASSERT (SELECT quantidade FROM public.rh_stock WHERE produto_id=(product->>'id')::uuid AND filial='FILIAL 8' AND tamanho='M')=7,'Isolamento filial 8';
 PERFORM public.rh_registrar_equipamentos(e8,'epi',op8,jsonb_build_array(jsonb_build_object('equipamento',product->>'nome','tamanho','M','quantidade',2,'data',today)));
 ASSERT (SELECT quantidade FROM public.rh_stock WHERE produto_id=(product->>'id')::uuid AND filial='FILIAL 8' AND tamanho='M')=5,'Entrega filial 8';
 BEGIN
  PERFORM public.rh_registrar_equipamentos(e5,'epi',gen_random_uuid(),jsonb_build_array(jsonb_build_object('equipamento',product->>'nome','tamanho','M','quantidade',100,'data',today)));
  RAISE EXCEPTION 'ERRO: aceitou estoque insuficiente';
 EXCEPTION WHEN OTHERS THEN IF SQLERRM NOT LIKE 'Estoque insuficiente%' THEN RAISE; END IF; END;
 ASSERT (SELECT quantidade FROM public.rh_stock WHERE produto_id=(product->>'id')::uuid AND filial='FILIAL 5' AND tamanho='M')=8,'Rollback de entrega inválida';
 ASSERT (SELECT count(*) FROM public.rh_equipment_current WHERE produto_id=(product->>'id')::uuid)=2,'Sem entrega parcial';
 BEGIN
  PERFORM public.rh_registrar_equipamentos(e5,'epi',gen_random_uuid(),jsonb_build_array(jsonb_build_object('equipamento',product->>'nome','tamanho','XX','quantidade',1,'data',today)));
  RAISE EXCEPTION 'ERRO: aceitou tamanho inválido';
 EXCEPTION WHEN OTHERS THEN IF SQLERRM NOT LIKE 'Selecione um tamanho%' THEN RAISE; END IF; END;
 movement:=(SELECT id FROM public.rh_equipment_current WHERE operacao_id=op);
 product:=public.rh_save_product(product||jsonb_build_object('nome','TESTE NOME PADRONIZADO'));
 ASSERT (SELECT equipamento FROM public.rh_equipment_current WHERE id=movement)='TESTE NOME PADRONIZADO','Renomeação do histórico';
 ASSERT (SELECT epi_itens FROM public.funcionarios_epi WHERE id=e5) LIKE '%TESTE NOME PADRONIZADO%','Resumo padronizado';
 doc:=public.rh_registrar_equipamentos(e5,'epi',gen_random_uuid(),'[]');
 ASSERT EXISTS(SELECT 1 FROM jsonb_array_elements(doc->'snapshot'->'movimentos')m WHERE m->>'id'=movement::text AND m->>'equipamento'='TESTE NOME PADRONIZADO'),'Ficha nova padronizada';
 ASSERT (SELECT snapshot FROM public.rh_equipment_receipts WHERE id=op)=olddoc->'snapshot','Documento emitido preservado';
 -- Alias antigo continua reconhecido após renomear.
 PERFORM public.rh_registrar_equipamentos(e5,'epi',gen_random_uuid(),jsonb_build_array(jsonb_build_object('equipamento','TESTE ESTOQUE TRANSACAO','tamanho','M','quantidade',1,'data',today)));
 PERFORM public.rh_registrar_equipamentos(e5,'epi',gen_random_uuid(),jsonb_build_array(jsonb_build_object('acao','corrigir','origem',movement,'nome','TESTE NOME PADRONIZADO','tamanho','M','quantidade',3,'data',today,'verificacao',today)));
 ASSERT (SELECT quantidade FROM public.rh_stock WHERE produto_id=(product->>'id')::uuid AND filial='FILIAL 5' AND tamanho='M')=6,'Correção ajusta apenas diferença';
 product:=public.rh_save_product(product||jsonb_build_object('todas_funcoes',false,'funcoes','[]'::jsonb));
 BEGIN
  PERFORM public.rh_registrar_equipamentos(e5,'epi',gen_random_uuid(),jsonb_build_array(jsonb_build_object('equipamento',product->>'nome','tamanho','M','quantidade',1,'data',today)));
  RAISE EXCEPTION 'ERRO: aceitou função não autorizada';
 EXCEPTION WHEN OTHERS THEN IF SQLERRM NOT LIKE 'Item indisponível para a função%' THEN RAISE; END IF; END;
 target:=public.rh_save_product(jsonb_build_object('nome','TESTE DESTINO UNIFICADO','categoria','epi','grupo','equipamento','tamanhos',jsonb_build_array('M'),'funcoes','[]'::jsonb,'todas_funcoes',true));
 PERFORM public.rh_set_stock(jsonb_build_object('operacao_id',gen_random_uuid(),'produto_id',target->>'id','filial','FILIAL 5','tamanho','M','quantidade',3,'motivo','Teste revertido','versao',0));
 PERFORM public.rh_merge_products((product->>'id')::uuid,(target->>'id')::uuid);
 ASSERT (SELECT quantidade FROM public.rh_stock WHERE produto_id=(target->>'id')::uuid AND filial='FILIAL 5' AND tamanho='M')=9,'Unificação soma estoques';
 ASSERT (SELECT equipamento FROM public.rh_equipment_current WHERE id=movement)='TESTE DESTINO UNIFICADO','Unificação do histórico';
 PERFORM public.rh_merge_products((product->>'id')::uuid,(target->>'id')::uuid);
 ASSERT (SELECT quantidade FROM public.rh_stock WHERE produto_id=(target->>'id')::uuid AND filial='FILIAL 5' AND tamanho='M')=9,'Unificação repetida não duplica estoque';
 RAISE NOTICE 'OK: filiais, tamanhos, estoque insuficiente, idempotência, correções, funções, renomeação, unificação e documentos.';
END $$;
ROLLBACK;
