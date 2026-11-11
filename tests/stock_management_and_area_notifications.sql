BEGIN;
DO $$
DECLARE
 admin_id uuid;
 delegate_id uuid;
 outside_id uuid;
 e public.funcionarios_epi;
 product uuid;
 notice_id uuid := gen_random_uuid();
 area_id uuid;
 exp_id uuid;
 token text := repeat('a',64);
 payload jsonb;
BEGIN
 SELECT id INTO STRICT admin_id FROM public.profiles WHERE status='admin' LIMIT 1;
 SELECT id INTO STRICT delegate_id FROM public.profiles WHERE status='aprovado' ORDER BY id LIMIT 1;
 SELECT id INTO STRICT outside_id FROM public.profiles WHERE status='aprovado' AND id<>delegate_id ORDER BY id LIMIT 1;
 SELECT * INTO STRICT e FROM public.funcionarios_epi WHERE data_desligamento IS NULL AND unidade='FILIAL 5' AND setor IS NOT NULL
 AND manager_profile_id IS NULL LIMIT 1;
 PERFORM set_config('request.jwt.claim.sub',admin_id::text,true);
 UPDATE public.profiles SET role='analista',access_mode='areas',access_level='consulta',
   access_scopes=jsonb_build_array(jsonb_build_object('unidade',e.unidade,'setor',e.setor)),
   whatsapp='5511999991111',experience_notifications=true,manage_stock=false WHERE id=delegate_id;
 UPDATE public.profiles SET role='analista',access_mode='areas',access_level='consulta',
   access_scopes=jsonb_build_array(jsonb_build_object('unidade','FILIAL 8','setor',e.setor)),
   whatsapp='5511999992222',experience_notifications=true,manage_stock=false WHERE id=outside_id;
 UPDATE public.funcionarios_epi SET admissao=to_char((now() at time zone 'America/Sao_Paulo')::date-38,'DD/MM/YYYY') WHERE id=e.id;

 PERFORM set_config('request.jwt.claim.sub',delegate_id::text,true);
 SET LOCAL ROLE authenticated;
 ASSERT public.rh_stock_catalog_roles() IS NULL;
 BEGIN
   UPDATE public.profiles SET manage_stock=true WHERE id=delegate_id;
   RAISE EXCEPTION 'Perfil alterou a própria permissão';
 EXCEPTION WHEN OTHERS THEN IF SQLERRM NOT LIKE 'Somente o administrador%' THEN RAISE; END IF; END;
 BEGIN
   PERFORM public.rh_set_stock('{}');
   RAISE EXCEPTION 'Perfil sem permissão alterou estoque';
 EXCEPTION WHEN OTHERS THEN IF SQLERRM NOT LIKE 'Sem permissão%' THEN RAISE; END IF; END;
 PERFORM set_config('request.jwt.claim.sub',admin_id::text,true);
 ASSERT cardinality(public.rh_stock_catalog_roles())>0;
 UPDATE public.profiles SET manage_stock=true WHERE id=delegate_id;
 PERFORM set_config('request.jwt.claim.sub',delegate_id::text,true);
 ASSERT cardinality(public.rh_stock_catalog_roles())>0;
 ASSERT NOT rh_internal.can_write() AND NOT rh_internal.is_admin();
 product:=(public.rh_save_product(jsonb_build_object('nome','TESTE ESTOQUE '||gen_random_uuid(),'categoria','epi',
  'grupo','equipamento','tamanhos',jsonb_build_array('M'),'funcoes','[]'::jsonb,'todas_funcoes',true))->>'id')::uuid;
 PERFORM public.rh_set_stock(jsonb_build_object('operacao_id',gen_random_uuid(),'produto_id',product,
  'filial','FILIAL 5','tamanho','M','quantidade',10,'motivo','Teste revertido','versao',0));
 PERFORM public.rh_transfer_stock(jsonb_build_object('operacao_id',gen_random_uuid(),'produto_id',product,
  'origem','FILIAL 5','destino','FILIAL 8','tamanho','M','quantidade',3,'versao_origem',(SELECT versao FROM public.rh_stock WHERE produto_id=product AND filial='FILIAL 5' AND tamanho='M'),'motivo','Teste revertido'));
 ASSERT (SELECT quantidade FROM public.rh_stock WHERE produto_id=product AND filial='FILIAL 8' AND tamanho='M')=3;
 ASSERT (SELECT count(*) FROM public.rh_stock_events WHERE produto_id=product)=3;
 RESET ROLE;

 PERFORM rh_internal.experience_queue();
 SELECT id INTO STRICT exp_id FROM public.rh_admin_notifications WHERE employee_id=e.id AND recipient_profile_id=delegate_id
   AND experience_admission=(now() at time zone 'America/Sao_Paulo')::date-38 AND experience_period=1;
 ASSERT rh_internal.experience_event_valid(exp_id);
 ASSERT NOT EXISTS(SELECT 1 FROM public.rh_admin_notifications WHERE employee_id=e.id AND recipient_profile_id=outside_id AND experience_admission IS NOT NULL);
 PERFORM rh_internal.experience_queue();
 ASSERT (SELECT count(*) FROM public.rh_admin_notifications WHERE employee_id=e.id AND recipient_profile_id=delegate_id
   AND experience_admission=(now() at time zone 'America/Sao_Paulo')::date-38 AND experience_period=1)=1;

 INSERT INTO public.rh_admin_notifications(id,employee_id,employee_name,source_table,operation,title,message_text)
 VALUES(notice_id,e.id,e.nome,'rh_absenteismo','INSERT','Evento teste','Detalhe reservado ao RH');
 SELECT id INTO STRICT area_id FROM public.rh_admin_notifications WHERE source_table='avisos_area'
   AND recipient_profile_id=delegate_id AND details->>'evento_origem'=notice_id::text;
 ASSERT NOT EXISTS(SELECT 1 FROM public.rh_admin_notifications WHERE recipient_profile_id=outside_id AND details->>'evento_origem'=notice_id::text);
 ASSERT rh_internal.area_notice_valid(area_id);
 UPDATE public.rh_admin_notifications SET whatsapp_status='aguardando' WHERE id=area_id;
 INSERT INTO rh_internal.notification_dispatch(id,token,expires_at) VALUES(area_id,token,now()+interval '5 minutes');
 payload:=public.rh_notification_claim(area_id,token);
 ASSERT payload->>'chatId'='5511999991111@c.us' AND payload->>'message' NOT LIKE '%Detalhe reservado%';
 PERFORM set_config('request.jwt.claim.sub',admin_id::text,true);
 UPDATE public.profiles SET manage_stock=false,experience_notifications=false WHERE id=delegate_id;
 ASSERT NOT rh_internal.area_notice_valid(area_id) AND NOT rh_internal.experience_event_valid(exp_id);
 PERFORM set_config('request.jwt.claim.sub',delegate_id::text,true);
 SET LOCAL ROLE authenticated;
 ASSERT public.rh_stock_catalog_roles() IS NULL;
END $$;
ROLLBACK;
