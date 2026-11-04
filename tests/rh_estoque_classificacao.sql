-- Integração com dados fictícios e ROLLBACK: não publica entregas nem altera estoque real.
BEGIN;
SELECT set_config('request.jwt.claim.sub',(SELECT id::text FROM public.profiles WHERE status='admin' ORDER BY created_at LIMIT 1),true);
SET LOCAL ROLE authenticated;
DO $$
DECLARE p jsonb; target jsonb; payload jsonb; r jsonb; doc jsonb; olddoc jsonb; raw_before jsonb; checks_before jsonb;
 emp uuid; movement uuid; return_id uuid; pid uuid; tid uuid; version integer; total_before bigint; after_merge bigint; duplicate_a jsonb; duplicate_b jsonb;
 today date:=(now() AT TIME ZONE 'America/Sao_Paulo')::date; uniq text:=gen_random_uuid()::text;
BEGIN
 ASSERT NOT has_function_privilege('anon','public.rh_reclassify_product(jsonb)','execute');
 ASSERT NOT has_table_privilege('anon','public.rh_returned_items','select');
 duplicate_a:=public.rh_save_product(jsonb_build_object('nome','TESTE COLISAO '||uniq,'categoria','epi','grupo','equipamento','tamanhos',jsonb_build_array('M'),'funcoes','[]'::jsonb));
 duplicate_b:=public.rh_save_product(jsonb_build_object('nome','TESTE COLISAO '||uniq,'categoria','fardamento','grupo','fardamento','tamanhos',jsonb_build_array('M'),'funcoes','[]'::jsonb));
 BEGIN
  PERFORM public.rh_reclassify_product(jsonb_build_object('operacao_id',gen_random_uuid(),'id',duplicate_a->>'id','versao',1,'categoria','fardamento'));
  RAISE EXCEPTION 'Teste falhou: aceitou nome duplicado sem substituição';
 EXCEPTION WHEN OTHERS THEN IF SQLERRM NOT LIKE 'Já existe um item%' THEN RAISE; END IF; END;
 PERFORM public.rh_reclassify_product(jsonb_build_object('operacao_id',gen_random_uuid(),'id',duplicate_a->>'id','versao',1,'categoria','fardamento','substituto_id',duplicate_b->>'id','versao_substituto',1));
 SELECT id INTO emp FROM public.funcionarios_epi WHERE unidade='FILIAL 5' AND data_desligamento IS NULL ORDER BY id LIMIT 1;
 p:=public.rh_save_product(jsonb_build_object('nome','TESTE CLASSIFICACAO '||uniq,'categoria','epi','grupo','equipamento','tamanhos',jsonb_build_array('M'),'funcoes','[]'::jsonb,'todas_funcoes',true));
 pid:=(p->>'id')::uuid;
 target:=public.rh_save_product(jsonb_build_object('nome','TESTE DESTINO '||uniq,'categoria','fardamento','grupo','fardamento','tamanhos',jsonb_build_array('M','G'),'funcoes','[]'::jsonb,'todas_funcoes',true));
 tid:=(target->>'id')::uuid;
 PERFORM public.rh_set_stock(jsonb_build_object('operacao_id',gen_random_uuid(),'produto_id',pid,'filial','FILIAL 5','tamanho','M','quantidade',20,'versao',0));
 PERFORM public.rh_set_stock(jsonb_build_object('operacao_id',gen_random_uuid(),'produto_id',tid,'filial','FILIAL 5','tamanho','M','quantidade',5,'versao',0));
 doc:=public.rh_registrar_equipamentos(emp,'epi',gen_random_uuid(),jsonb_build_array(jsonb_build_object('equipamento',p->>'nome','tamanho','M','quantidade',3,'data',today,'ca','123','complemento','Detalhe preservado','comprovante','https://example.com/comprovante')));
 olddoc:=doc;
 -- Identidade da entrega pelo vínculo do catálogo.
 SELECT m.id INTO movement FROM public.rh_equipment_current m WHERE m.operacao_id=(doc->>'id')::uuid AND m.tipo='entrega' AND m.produto_id=pid;
 PERFORM public.rh_registrar_equipamentos(emp,'epi',gen_random_uuid(),jsonb_build_array(jsonb_build_object('acao','verificacao','origem',movement,'data',today)));
 doc:=public.rh_registrar_equipamentos(emp,'epi',gen_random_uuid(),'[]',jsonb_build_array(jsonb_build_object('origem',movement,'quantidade',1,'data',today,'tipo','devolucao','motivo','Desgaste','observacao','Costura desgastada; conferir antes de reutilizar.')));
 SELECT m.id INTO return_id FROM public.rh_equipment_current m WHERE m.operacao_id=(doc->>'id')::uuid AND m.tipo='devolucao';
 SELECT jsonb_agg(to_jsonb(m) ORDER BY m.id) INTO raw_before FROM public.rh_equipment_movements m JOIN public.rh_equipment_products b ON b.movimento_id=m.id WHERE b.produto_id=pid;
 SELECT jsonb_agg(to_jsonb(v) ORDER BY v.id) INTO checks_before FROM public.rh_equipment_checks v WHERE v.entrega_id=movement;
 SELECT sum(quantidade) INTO total_before FROM public.rh_stock WHERE produto_id IN(pid,tid);
 payload:=jsonb_build_object('operacao_id',gen_random_uuid(),'id',pid,'versao',1,'categoria','fardamento');
 r:=public.rh_reclassify_product(payload);
 ASSERT public.rh_reclassify_product(payload)=r,'Repetição não reaplica';
 ASSERT (SELECT categoria FROM public.rh_equipment_current WHERE id=movement)='fardamento','Entrega mudou de aba';
 ASSERT (SELECT categoria FROM public.rh_returned_items WHERE id=return_id)='fardamento','Devolução acompanha o tipo';
 ASSERT (SELECT observacao FROM public.rh_returned_items WHERE id=return_id)='Costura desgastada; conferir antes de reutilizar.','Observações preservadas';
 ASSERT (SELECT jsonb_agg(to_jsonb(m) ORDER BY m.id) FROM public.rh_equipment_movements m JOIN public.rh_equipment_products b ON b.movimento_id=m.id WHERE b.produto_id=pid)=raw_before,'Lançamentos originais integralmente preservados';
 ASSERT (SELECT jsonb_agg(to_jsonb(v) ORDER BY v.id) FROM public.rh_equipment_checks v WHERE v.entrega_id=movement)=checks_before,'Conferências originais preservadas';
 ASSERT (SELECT count(*) FROM public.rh_equipment_checks_current WHERE entrega_id=movement AND categoria='fardamento')=1,'Conferência acompanha o tipo';
 ASSERT (SELECT sum(quantidade) FROM public.rh_stock WHERE produto_id IN(pid,tid))=total_before,'Mudar tipo não muda estoque';
 ASSERT (SELECT snapshot FROM public.rh_equipment_receipts WHERE id=(olddoc->>'id')::uuid)=olddoc->'snapshot','PDF emitido preservado';
 doc:=public.rh_registrar_equipamentos(emp,'epi',gen_random_uuid(),'[]');
 ASSERT NOT EXISTS(SELECT FROM jsonb_array_elements(doc->'snapshot'->'movimentos')m WHERE m->>'id'=movement::text),'Ficha EPI nova não inclui item reclassificado';
 doc:=public.rh_registrar_equipamentos(emp,'fardamento',gen_random_uuid(),'[]');
 ASSERT EXISTS(SELECT FROM jsonb_array_elements(doc->'snapshot'->'movimentos')m WHERE m->>'id'=movement::text),'Ficha de fardamento inclui item';
 ASSERT EXISTS(SELECT FROM jsonb_array_elements(doc->'snapshot'->'verificacoes')v WHERE v->>'entrega_id'=movement::text),'Ficha inclui conferência antiga';
 -- Operações posteriores continuam válidas na categoria nova.
 PERFORM public.rh_registrar_equipamentos(emp,'fardamento',gen_random_uuid(),jsonb_build_array(jsonb_build_object('acao','verificacao','origem',movement,'data',today)));
 PERFORM public.rh_registrar_equipamentos(emp,'fardamento',gen_random_uuid(),'[]',jsonb_build_array(jsonb_build_object('origem',movement,'quantidade',1,'data',today,'tipo','devolucao','motivo','Rasgo','observacao','Pequeno rasgo na manga')));
 -- Volta sem substituição.
 r:=public.rh_reclassify_product(jsonb_build_object('operacao_id',gen_random_uuid(),'id',pid,'versao',2,'categoria','epi'));
 ASSERT (SELECT categoria FROM public.rh_equipment_current WHERE id=movement)='epi';
 -- Unificação com um cadastro da categoria de destino, incluindo estoque e tamanhos.
 payload:=jsonb_build_object('operacao_id',gen_random_uuid(),'id',pid,'versao',3,'categoria','fardamento','substituto_id',tid,'versao_substituto',1);
 r:=public.rh_reclassify_product(payload);PERFORM public.rh_reclassify_product(payload);
 ASSERT (SELECT produto_id FROM public.rh_equipment_current WHERE id=movement)=tid;
 ASSERT (SELECT categoria FROM public.rh_equipment_current WHERE id=movement)='fardamento';
 ASSERT (SELECT quantidade FROM public.rh_stock WHERE produto_id=pid AND filial='FILIAL 5' AND tamanho='M')=0;
 ASSERT (SELECT quantidade FROM public.rh_stock WHERE produto_id=tid AND filial='FILIAL 5' AND tamanho='M')=total_before;
 ASSERT (SELECT tamanhos @> ARRAY['M','G'] FROM public.rh_products WHERE id=tid),'Mantém tamanhos das entregas';
 ASSERT (SELECT todas_funcoes FROM public.rh_products WHERE id=tid),'Preserva regras do destino';
 ASSERT (SELECT count(*) FROM public.rh_returned_items WHERE funcionario_id=emp AND produto_id=tid AND motivo IN ('Desgaste','Rasgo'))=2;
 -- Corrigir uma entrega antiga após unificar também usa a categoria vigente e o nome do destino.
 PERFORM public.rh_registrar_equipamentos(emp,'fardamento',gen_random_uuid(),jsonb_build_array(jsonb_build_object('acao','corrigir','origem',movement,'nome',target->>'nome','tamanho','M','ca','123','quantidade',3,'data',today,'verificacao',today,'comprovante','https://example.com/comprovante')));
 ASSERT (SELECT count(*) FROM public.rh_equipment_item_corrections_current WHERE entrega_id=movement AND categoria='fardamento')=1;
 -- A categoria original não permite novas entregas pelo alias antigo.
 BEGIN
  PERFORM public.rh_registrar_equipamentos(emp,'epi',gen_random_uuid(),jsonb_build_array(jsonb_build_object('equipamento',p->>'nome','tamanho','M','quantidade',1,'data',today)));
  RAISE EXCEPTION 'Teste falhou: aceitou categoria antiga';
 EXCEPTION WHEN OTHERS THEN IF SQLERRM NOT LIKE 'O item pertence a outro tipo%' THEN RAISE; END IF; END;
 PERFORM set_config('request.jwt.claim.sub','',true);
 BEGIN
  PERFORM public.rh_reclassify_product(payload);
  RAISE EXCEPTION 'Teste falhou: aceitou usuário sem permissão';
 EXCEPTION WHEN OTHERS THEN IF SQLERRM NOT LIKE 'Somente administradores%' THEN RAISE; END IF; END;
END $$;
RESET ROLE;
SELECT 'OK: tipo nos dois sentidos, substituição, datas e dados originais, estoque, devoluções, conferências, correções e snapshots de PDFs' AS resultado;
ROLLBACK;
