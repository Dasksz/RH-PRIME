-- Exercita o fluxo com produtos de teste. O rollback descarta as movimentações e os webhooks.
BEGIN;
SET LOCAL plpgsql.check_asserts = on;
SELECT set_config('request.jwt.claim.sub',(
  SELECT id::text FROM public.profiles WHERE status='admin' ORDER BY created_at LIMIT 1
),true);
SET LOCAL ROLE authenticated;

DO $$
DECLARE
  today date := (now() AT TIME ZONE 'America/Sao_Paulo')::date;
  employee uuid;
  category text;
  product jsonb;
  payload jsonb;
  operation uuid;
  receipt jsonb;
  delivery public.rh_equipment_current;
  original jsonb;
  rejected boolean;
BEGIN
  SELECT id INTO employee FROM public.funcionarios_epi
   WHERE unidade='FILIAL 5' AND data_desligamento IS NULL LIMIT 1;
  ASSERT employee IS NOT NULL,'Colaborador para teste indisponível';
  FOREACH category IN ARRAY ARRAY['epi','fardamento'] LOOP
    operation := gen_random_uuid();
    product := public.rh_save_product(jsonb_build_object(
      'nome','TESTE ENTREGA FUTURA '||operation,'categoria',category,
      'grupo',CASE WHEN category='epi' THEN 'equipamento' ELSE 'fardamento' END,
      'tamanhos',jsonb_build_array('M'),'funcoes','[]'::jsonb,'todas_funcoes',true));
    PERFORM public.rh_set_stock(jsonb_build_object('operacao_id',gen_random_uuid(),
      'produto_id',product->>'id','filial','FILIAL 5','tamanho','M','quantidade',3,'versao',0));
    payload := jsonb_build_object('equipamento',product->>'nome','tamanho','M','quantidade',2,'data',today+1);
    receipt := public.rh_registrar_equipamentos(employee,category,operation,jsonb_build_array(payload));
    SELECT * INTO delivery FROM public.rh_equipment_current WHERE operacao_id=operation;
    ASSERT delivery.data_movimento=today+1 AND delivery.estoque_descontado,'Entrega futura não reservou estoque';
    ASSERT (SELECT quantidade FROM public.rh_stock
      WHERE produto_id=(product->>'id')::uuid AND filial='FILIAL 5' AND tamanho='M')=1,'Saldo reservado incorreto';
    ASSERT EXISTS(SELECT 1 FROM jsonb_array_elements(receipt->'snapshot'->'movimentos') m
      WHERE m->>'id'=delivery.id::text AND (m->>'data_movimento')::date=today+1),'Ficha sem a data futura';
    ASSERT public.rh_registrar_equipamentos(employee,category,operation,jsonb_build_array(payload))=receipt,
      'Repetir o salvamento deve retornar a mesma ficha';

    original := jsonb_build_object('produto_id',delivery.produto_id,'complemento',coalesce(delivery.complemento,''),
      'tamanho',coalesce(delivery.tamanho,''),'ca',coalesce(delivery.ca,''),'quantidade',delivery.quantidade,
      'data_movimento',delivery.data_movimento,'observacao',coalesce(delivery.observacao,''),
      'comprovante',coalesce(delivery.comprovante,''),'descontado',delivery.estoque_descontado);
    PERFORM public.rh_editar_entrega_historico(delivery.id,original,jsonb_build_object('data_movimento',today+2));
    ASSERT (SELECT data_movimento FROM public.rh_equipment_current WHERE id=delivery.id)=today+2,'Reagendamento falhou';
    ASSERT (SELECT quantidade FROM public.rh_stock
      WHERE produto_id=(product->>'id')::uuid AND filial='FILIAL 5' AND tamanho='M')=1,'Reagendamento alterou o saldo';

    rejected := false;
    BEGIN
      PERFORM public.rh_registrar_equipamentos(employee,category,gen_random_uuid(),
        jsonb_build_array(payload||jsonb_build_object('sem_desconto_estoque',true)));
    EXCEPTION WHEN OTHERS THEN
      IF SQLERRM NOT LIKE 'Registrar sem desconto%' THEN RAISE; END IF;
      rejected := true;
    END;
    ASSERT rejected,'Entrega futura aceitou isenção de estoque';

    rejected := false;
    BEGIN
      PERFORM public.rh_registrar_equipamentos(employee,category,gen_random_uuid(),'[]'::jsonb,
        jsonb_build_array(jsonb_build_object('origem',delivery.id,'tipo','devolucao','quantidade',1,'data',today+2,'motivo','Defeito')));
    EXCEPTION WHEN OTHERS THEN
      IF SQLERRM NOT LIKE 'Data da movimentação não pode estar no futuro%' THEN RAISE; END IF;
      rejected := true;
    END;
    ASSERT rejected,'Devolução futura indevidamente aceita';
  END LOOP;
END $$;
ROLLBACK;
