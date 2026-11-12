BEGIN;
DO $$
DECLARE
  admin_id uuid;
  test_profiles uuid[];
  employee public.funcionarios_epi;
  scope jsonb;
  admission date := (now() AT TIME ZONE 'America/Sao_Paulo')::date - 38;
  phone text := '5511999991111';
  other_phone text := '5511999992222';
  first_profile uuid;
  event_id uuid := gen_random_uuid();
BEGIN
  SELECT id INTO STRICT admin_id FROM public.profiles WHERE status='admin' LIMIT 1;
  SELECT array_agg(id) INTO test_profiles FROM (
    SELECT id FROM public.profiles WHERE status='aprovado' ORDER BY id LIMIT 3
  ) candidates;
  ASSERT cardinality(test_profiles)=3;
  SELECT * INTO STRICT employee FROM public.funcionarios_epi
  WHERE data_desligamento IS NULL AND manager_profile_id IS NULL AND unidade IS NOT NULL AND setor IS NOT NULL LIMIT 1;
  scope:=jsonb_build_array(jsonb_build_object('unidade',employee.unidade,'setor',employee.setor));

  PERFORM set_config('request.jwt.claim.sub',admin_id::text,true);
  UPDATE public.profiles SET access_mode='areas',access_scopes=scope,experience_notifications=true,
    whatsapp=CASE WHEN id=test_profiles[3] THEN other_phone ELSE phone END WHERE id=ANY(test_profiles);
  UPDATE public.funcionarios_epi SET admissao=to_char(admission,'DD/MM/YYYY') WHERE id=employee.id;

  PERFORM rh_internal.experience_queue();
  PERFORM rh_internal.experience_queue();
  SELECT recipient_profile_id INTO STRICT first_profile FROM public.rh_admin_notifications
  WHERE employee_id=employee.id AND experience_admission=admission AND experience_period=1
    AND recipient_phone=phone AND whatsapp_status='experiencia_pendente';
  ASSERT first_profile=ANY(test_profiles[1:2]);
  ASSERT (SELECT count(*) FROM public.rh_admin_notifications WHERE employee_id=employee.id
    AND experience_admission=admission AND experience_period=1 AND recipient_phone=other_phone)=1;

  -- Se o primeiro perfil perder a autorização antes do envio, outro perfil elegível pode assumir.
  UPDATE public.profiles SET experience_notifications=false WHERE id=first_profile;
  PERFORM rh_internal.experience_queue();
  ASSERT (SELECT count(*) FROM public.rh_admin_notifications WHERE employee_id=employee.id
    AND experience_admission=admission AND experience_period=1 AND recipient_phone=phone
    AND whatsapp_status='experiencia_pendente' AND recipient_profile_id<>first_profile)=1;
  UPDATE public.rh_admin_notifications SET whatsapp_status='aceito',attempts=1
  WHERE employee_id=employee.id AND experience_admission=admission AND experience_period=1
    AND recipient_phone=phone AND whatsapp_status='experiencia_pendente';

  UPDATE public.profiles SET experience_notifications=true WHERE id=first_profile;
  PERFORM rh_internal.experience_queue();
  ASSERT (SELECT count(*) FROM public.rh_admin_notifications WHERE employee_id=employee.id
    AND experience_admission=admission AND experience_period=1 AND recipient_phone=phone
    AND whatsapp_status<>'cancelado')=1;

  INSERT INTO public.rh_admin_notifications(id,employee_id,employee_name,source_table,operation,title,message_text)
  VALUES(event_id,employee.id,employee.nome,'rh_absenteismo','INSERT','Evento teste','Teste revertido');
  ASSERT (SELECT count(*) FROM public.rh_admin_notifications WHERE details->>'evento_origem'=event_id::text
    AND recipient_phone=phone)=1;
  ASSERT (SELECT count(*) FROM public.rh_admin_notifications WHERE details->>'evento_origem'=event_id::text
    AND recipient_phone=other_phone)=1;
END $$;
ROLLBACK;
