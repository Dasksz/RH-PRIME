BEGIN;
DO $$
DECLARE
  admin_id uuid;
  employee_id uuid;
  delivery_id uuid;
  operation_id uuid := gen_random_uuid();
  product_id uuid;
  product_name text := 'TESTE CA '||operation_id;
  delivery_date date := (now() AT TIME ZONE 'America/Sao_Paulo')::date-1;
  original jsonb;
  receipt jsonb;
  response jsonb;
BEGIN
  SELECT id INTO admin_id FROM public.profiles WHERE status='admin' ORDER BY created_at LIMIT 1;
  PERFORM set_config('request.jwt.claim.sub',admin_id::text,true);
  SELECT id INTO employee_id FROM public.funcionarios_epi
    WHERE unidade='FILIAL 5' AND data_desligamento IS NULL LIMIT 1;
  SET LOCAL ROLE authenticated;
  product_id := (public.rh_save_product(jsonb_build_object(
    'nome',product_name,'categoria','epi','grupo','equipamento','tamanhos',jsonb_build_array('M'),
    'funcoes','[]'::jsonb,'todas_funcoes',true))->>'id')::uuid;
  PERFORM public.rh_set_stock(jsonb_build_object('operacao_id',gen_random_uuid(),'produto_id',product_id,
    'filial','FILIAL 5','tamanho','M','quantidade',10,'motivo','Teste revertido','versao',0));
  receipt := public.rh_registrar_equipamentos(employee_id,'epi',operation_id,jsonb_build_array(jsonb_build_object(
    'equipamento',product_name,'tamanho','M','quantidade',2,'data',delivery_date)));
  SELECT m.id,to_jsonb(m) INTO delivery_id,original FROM public.rh_equipment_movements m WHERE m.operacao_id=operation_id;
  ASSERT original IS NOT NULL AND original->>'ca'='', 'Entrega de teste ausente';
  response := public.rh_corrigir_ca_entrega(delivery_id,' 12345 ','');
  ASSERT response->>'ca'='12345' AND (response->>'data_movimento')::date=delivery_date;
  ASSERT (SELECT to_jsonb(m)-'ca' FROM public.rh_equipment_movements m WHERE m.id=delivery_id)=original-'ca',
    'Outro campo da entrega foi alterado';
  ASSERT (SELECT quantidade FROM public.rh_stock WHERE produto_id=product_id AND filial='FILIAL 5' AND tamanho='M')=8,
    'Saldo do estoque mudou';
  ASSERT NOT EXISTS(SELECT 1 FROM public.rh_equipment_checks WHERE entrega_id=delivery_id), 'Criou verificação';
  ASSERT (SELECT count(*) FROM public.rh_equipment_receipts WHERE funcionario_id=employee_id
    AND categoria='epi' AND created_at >= now())=1, 'Criou ficha extra';
  ASSERT (SELECT snapshot FROM public.rh_equipment_receipts WHERE id=operation_id)=receipt->'snapshot', 'Mudou a ficha emitida';
  PERFORM public.rh_corrigir_ca_entrega(delivery_id,'12345','');
  BEGIN
    PERFORM public.rh_corrigir_ca_entrega(delivery_id,'98765','');
    RAISE EXCEPTION 'Aceitou uma alteração concorrente';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM NOT LIKE 'O C.A. foi alterado%' THEN RAISE; END IF;
  END;
  RESET ROLE;
  ASSERT (SELECT count(*) FROM rh_internal.equipment_ca_edits WHERE entrega_id=delivery_id)=1, 'Auditoria duplicada';
  ASSERT (SELECT created_by FROM rh_internal.equipment_ca_edits WHERE entrega_id=delivery_id)=admin_id, 'Autor ausente';
END $$;
ROLLBACK;
