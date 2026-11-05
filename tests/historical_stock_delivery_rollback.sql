-- Executar como transação: nenhum dado de teste ou webhook é confirmado.
BEGIN;
SELECT set_config('request.jwt.claim.sub',(SELECT id::text FROM public.profiles WHERE status='admin' ORDER BY created_at LIMIT 1),true);
SET LOCAL ROLE authenticated;
DO $$
DECLARE product jsonb; doc jsonb; repeated jsonb; payload jsonb; op uuid; emp uuid; historical uuid;
 category text; today date:=(now() AT TIME ZONE 'America/Sao_Paulo')::date; ver integer; events integer; rejected boolean;
BEGIN
 SELECT id INTO emp FROM public.funcionarios_epi WHERE unidade='FILIAL 5' AND data_desligamento IS NULL LIMIT 1;
 ASSERT emp IS NOT NULL,'Colaborador para o teste indisponível';
 FOREACH category IN ARRAY ARRAY['epi','fardamento'] LOOP
  op:=gen_random_uuid();
  product:=public.rh_save_product(jsonb_build_object('nome','TESTE RETROATIVO '||op,'categoria',category,'grupo',CASE WHEN category='epi' THEN 'equipamento' ELSE 'fardamento' END,'tamanhos',jsonb_build_array('M'),'funcoes','[]'::jsonb,'todas_funcoes',true));
  PERFORM public.rh_set_stock(jsonb_build_object('operacao_id',gen_random_uuid(),'produto_id',product->>'id','filial','FILIAL 5','tamanho','M','quantidade',0,'versao',0));
  SELECT versao INTO ver FROM public.rh_stock WHERE produto_id=(product->>'id')::uuid AND filial='FILIAL 5' AND tamanho='M';
  SELECT count(*) INTO events FROM public.rh_stock_events WHERE produto_id=(product->>'id')::uuid;
  payload:=jsonb_build_object('equipamento',product->>'nome','tamanho','M','quantidade',3,'data',today-5,'sem_desconto_estoque',true);
  doc:=public.rh_registrar_equipamentos(emp,category,op,jsonb_build_array(payload));
  SELECT id INTO historical FROM public.rh_equipment_current WHERE operacao_id=op;
  ASSERT (SELECT sem_desconto_estoque AND NOT estoque_descontado AND quantidade=3 AND data_movimento=today-5 FROM public.rh_equipment_current WHERE id=historical),'Registro histórico incorreto';
  ASSERT (SELECT quantidade=0 AND versao=ver FROM public.rh_stock WHERE produto_id=(product->>'id')::uuid AND filial='FILIAL 5' AND tamanho='M'),'Histórico modificou saldo ou versão';
  ASSERT (SELECT count(*) FROM public.rh_stock_events WHERE produto_id=(product->>'id')::uuid)=events,'Histórico gerou movimentação de estoque';
  ASSERT EXISTS(SELECT 1 FROM jsonb_array_elements(doc->'snapshot'->'movimentos') m WHERE m->>'id'=historical::text AND (m->>'sem_desconto_estoque')::boolean),'Opção ausente da auditoria da ficha';
  repeated:=public.rh_registrar_equipamentos(emp,category,op,jsonb_build_array(payload));
  ASSERT repeated=doc,'Repetição não retornou a mesma ficha';
  ASSERT (SELECT count(*) FROM public.rh_equipment_movements WHERE operacao_id=op)=1,'Entrega duplicada';
  rejected:=false;
  BEGIN PERFORM public.rh_registrar_equipamentos(emp,category,gen_random_uuid(),jsonb_build_array(payload||jsonb_build_object('sem_desconto_estoque',false)));
  EXCEPTION WHEN OTHERS THEN IF SQLERRM NOT LIKE 'Estoque insuficiente%' THEN RAISE; END IF;rejected:=true;END;
  ASSERT rejected,'Entrega retroativa normal ignorou saldo zero';
  rejected:=false;
  BEGIN PERFORM public.rh_registrar_equipamentos(emp,category,gen_random_uuid(),jsonb_build_array(payload||jsonb_build_object('data',today)));
  EXCEPTION WHEN OTHERS THEN IF SQLERRM NOT LIKE 'Registrar sem desconto%' THEN RAISE; END IF;rejected:=true;END;
  ASSERT rejected,'Aceitou isenção para entrega de hoje';
  PERFORM public.rh_registrar_equipamentos(emp,category,gen_random_uuid(),jsonb_build_array(jsonb_build_object('acao','corrigir','origem',historical,'nome',product->>'nome','tamanho','M','quantidade',4,'data',today-4,'verificacao',today)));
  ASSERT (SELECT quantidade FROM public.rh_stock WHERE produto_id=(product->>'id')::uuid AND filial='FILIAL 5' AND tamanho='M')=0,'Correção do histórico alterou saldo';
  PERFORM public.rh_excluir_entrega(historical,'Exclusão de registro de teste revertida');
  ASSERT (SELECT quantidade FROM public.rh_stock WHERE produto_id=(product->>'id')::uuid AND filial='FILIAL 5' AND tamanho='M')=0,'Exclusão de histórico criou saldo';
  PERFORM public.rh_set_stock(jsonb_build_object('operacao_id',gen_random_uuid(),'produto_id',product->>'id','filial','FILIAL 5','tamanho','M','quantidade',2,'versao',ver));
  PERFORM public.rh_registrar_equipamentos(emp,category,gen_random_uuid(),jsonb_build_array(payload,jsonb_build_object('equipamento',product->>'nome','tamanho','M','quantidade',1,'data',today)));
  ASSERT (SELECT quantidade FROM public.rh_stock WHERE produto_id=(product->>'id')::uuid AND filial='FILIAL 5' AND tamanho='M')=1,'Lote misto descontou quantidade incorreta';
  ASSERT (SELECT snapshot FROM public.rh_equipment_receipts WHERE id=op)=doc->'snapshot','Ficha antiga alterada';
 END LOOP;
END $$;
ROLLBACK;
