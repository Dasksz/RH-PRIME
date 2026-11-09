BEGIN;
DO $$
DECLARE
  admin_id uuid;
  employee_id uuid;
  delivery_id uuid;
  operation_id uuid := gen_random_uuid();
  first_product uuid;
  second_product uuid;
  first_name text := 'TESTE EDIÇÃO A '||operation_id;
  second_name text := 'TESTE EDIÇÃO B '||operation_id;
  target_date date := (now() AT TIME ZONE 'America/Sao_Paulo')::date-2;
  original jsonb;
  changes jsonb;
  receipt jsonb;
  response jsonb;
BEGIN
  SELECT id INTO admin_id FROM public.profiles WHERE status='admin' ORDER BY created_at LIMIT 1;
  SELECT id INTO employee_id FROM public.funcionarios_epi WHERE unidade='FILIAL 5' AND data_desligamento IS NULL LIMIT 1;
  PERFORM set_config('request.jwt.claim.sub',admin_id::text,true);
  SET LOCAL ROLE authenticated;
  first_product := (public.rh_save_product(jsonb_build_object(
    'nome',first_name,'categoria','epi','grupo','equipamento','tamanhos',jsonb_build_array('M'),
    'funcoes','[]'::jsonb,'todas_funcoes',true))->>'id')::uuid;
  second_product := (public.rh_save_product(jsonb_build_object(
    'nome',second_name,'categoria','epi','grupo','equipamento','tamanhos',jsonb_build_array('G'),
    'funcoes','[]'::jsonb,'todas_funcoes',true))->>'id')::uuid;
  PERFORM public.rh_set_stock(jsonb_build_object('operacao_id',gen_random_uuid(),'produto_id',first_product,
    'filial','FILIAL 5','tamanho','M','quantidade',10,'motivo','Teste revertido','versao',0));
  PERFORM public.rh_set_stock(jsonb_build_object('operacao_id',gen_random_uuid(),'produto_id',second_product,
    'filial','FILIAL 5','tamanho','G','quantidade',8,'motivo','Teste revertido','versao',0));
  receipt := public.rh_registrar_equipamentos(employee_id,'epi',operation_id,jsonb_build_array(
    jsonb_build_object('equipamento',first_name,'tamanho','M','quantidade',2,'data',target_date-1),
    jsonb_build_object('equipamento',second_name,'tamanho','G','quantidade',1,'data',target_date)));
  SELECT id INTO delivery_id FROM public.rh_equipment_current WHERE operacao_id=operation_id AND produto_id=first_product;
  original := jsonb_build_object('produto_id',first_product,'complemento','','tamanho','M','ca','',
    'quantidade',2,'data_movimento',target_date-1,'observacao','','comprovante','','descontado',true);
  changes := jsonb_build_object('produto_id',second_product,'complemento','CORRIGIDO','tamanho','G','ca','12345',
    'quantidade',3,'data_movimento',target_date,'observacao','Observação corrigida','comprovante','https://example.com/arquivo');

  BEGIN
    PERFORM public.rh_editar_entrega_historico(delivery_id,original,changes||'{"quantidade":9}');
    RAISE EXCEPTION 'Aceitou saldo insuficiente';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM NOT LIKE 'Estoque insuficiente%' THEN RAISE; END IF;
  END;
  ASSERT (SELECT quantidade FROM public.rh_stock WHERE produto_id=first_product AND filial='FILIAL 5' AND tamanho='M')=8,
    'Falha parcial estornou o estoque anterior';

  response := public.rh_editar_entrega_historico(delivery_id,original,changes);
  ASSERT response->>'id'=delivery_id::text AND response->>'operacao_id'=operation_id::text;
  ASSERT response->>'data_movimento'=target_date::text AND response->>'ca'='12345' AND response->>'complemento'='CORRIGIDO'
    AND response->>'tamanho'='G' AND response->>'quantidade'='3' AND response->>'observacao'='Observação corrigida'
    AND response->>'comprovante'='https://example.com/arquivo';
  ASSERT (SELECT count(*) FROM public.rh_equipment_current WHERE operacao_id=operation_id AND data_movimento=target_date)=2;
  ASSERT NOT EXISTS(SELECT 1 FROM public.rh_equipment_checks WHERE entrega_id=delivery_id), 'Criou verificação';
  ASSERT (SELECT count(*) FROM public.rh_equipment_receipts WHERE funcionario_id=employee_id AND categoria='epi' AND created_at>=now())=1;
  ASSERT (SELECT snapshot FROM public.rh_equipment_receipts WHERE id=operation_id)=receipt->'snapshot';
  ASSERT (SELECT quantidade FROM public.rh_stock WHERE produto_id=first_product AND filial='FILIAL 5' AND tamanho='M')=10;
  ASSERT (SELECT quantidade FROM public.rh_stock WHERE produto_id=second_product AND filial='FILIAL 5' AND tamanho='G')=4;

  PERFORM public.rh_editar_entrega_historico(delivery_id,original,changes);
  PERFORM public.rh_editar_entrega_historico(delivery_id,original||changes,'{"descontado":false}');
  ASSERT (SELECT quantidade FROM public.rh_stock WHERE produto_id=second_product AND filial='FILIAL 5' AND tamanho='G')=7;
  ASSERT (SELECT sem_desconto_estoque AND NOT estoque_descontado FROM public.rh_equipment_current WHERE id=delivery_id);
  PERFORM public.rh_editar_entrega_historico(delivery_id,original||changes||'{"descontado":false}','{"descontado":true}');
  ASSERT (SELECT quantidade FROM public.rh_stock WHERE produto_id=second_product AND filial='FILIAL 5' AND tamanho='G')=4;
  RESET ROLE;
  ASSERT (SELECT count(*) FROM rh_internal.equipment_history_edits WHERE entrega_id=delivery_id)=3;
END $$;
ROLLBACK;
