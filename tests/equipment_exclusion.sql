BEGIN;
SELECT set_config('request.jwt.claim.sub',(SELECT id::text FROM public.profiles WHERE status='admin' ORDER BY created_at LIMIT 1),true);
SET LOCAL ROLE authenticated;
DO $$
DECLARE product jsonb; doc jsonb; fresh jsonb; emp uuid; movement uuid; op uuid:=gen_random_uuid(); today date:=(now() AT TIME ZONE 'America/Sao_Paulo')::date;
BEGIN
 SELECT id INTO emp FROM public.funcionarios_epi WHERE unidade='FILIAL 5' AND data_desligamento IS NULL LIMIT 1;
 product:=public.rh_save_product(jsonb_build_object('nome','TESTE EXCLUSAO '||op,'categoria','epi','grupo','equipamento','tamanhos',jsonb_build_array('M'),'funcoes','[]'::jsonb,'todas_funcoes',true));
 PERFORM public.rh_set_stock(jsonb_build_object('operacao_id',gen_random_uuid(),'produto_id',product->>'id','filial','FILIAL 5','tamanho','M','quantidade',10,'motivo','Teste revertido','versao',0));
 doc:=public.rh_registrar_equipamentos(emp,'epi',op,jsonb_build_array(jsonb_build_object('equipamento',product->>'nome','tamanho','M','quantidade',2,'data',today)));
 SELECT id INTO movement FROM public.rh_equipment_current WHERE operacao_id=op;
 ASSERT (SELECT quantidade FROM public.rh_stock WHERE produto_id=(product->>'id')::uuid AND filial='FILIAL 5' AND tamanho='M')=8;
 PERFORM public.rh_excluir_entrega(movement,'Lançamento incorreto de teste');
 ASSERT NOT EXISTS(SELECT 1 FROM public.rh_equipment_current WHERE id=movement),'Exclusão não ocultou entrega';
 ASSERT (SELECT quantidade FROM public.rh_stock WHERE produto_id=(product->>'id')::uuid AND filial='FILIAL 5' AND tamanho='M')=10,'Estorno incorreto';
 PERFORM public.rh_excluir_entrega(movement,'Repetição');
 ASSERT (SELECT quantidade FROM public.rh_stock WHERE produto_id=(product->>'id')::uuid AND filial='FILIAL 5' AND tamanho='M')=10,'Estorno duplicado';
 ASSERT (SELECT epi_itens FROM public.funcionarios_epi WHERE id=emp) NOT LIKE '%'||(product->>'nome')||'%','Resumo incorreto';
 fresh:=public.rh_registrar_equipamentos(emp,'epi',gen_random_uuid(),'[]');
 ASSERT NOT EXISTS(SELECT 1 FROM jsonb_array_elements(fresh->'snapshot'->'movimentos')m WHERE m->>'id'=movement::text),'Nova ficha contém exclusão';
 ASSERT (SELECT snapshot FROM public.rh_equipment_receipts WHERE id=op)=doc->'snapshot','Ficha antiga alterada';
 BEGIN
  PERFORM public.rh_registrar_equipamentos(emp,'epi',gen_random_uuid(),jsonb_build_array(jsonb_build_object('acao','verificacao','origem',movement,'data',today)));
  RAISE EXCEPTION 'ERRO: aceitou conferência excluída';
 EXCEPTION WHEN OTHERS THEN IF SQLERRM NOT LIKE 'Entrega excluída%' THEN RAISE; END IF; END;
 PERFORM set_config('request.jwt.claim.sub','',true);
 BEGIN
  PERFORM public.rh_excluir_entrega(movement,'Sem autenticação');
  RAISE EXCEPTION 'ERRO: aceitou exclusão sem autenticação';
 EXCEPTION WHEN OTHERS THEN IF SQLERRM NOT LIKE 'Sem permissão%' THEN RAISE; END IF; END;
END $$;
ROLLBACK;
