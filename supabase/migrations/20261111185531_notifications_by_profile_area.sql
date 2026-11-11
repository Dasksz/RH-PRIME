-- O perfil recebe avisos das combinações de filial e setor cadastradas no seu acesso.
CREATE FUNCTION rh_internal.profile_subscribed_to_area(profile public.profiles, unit text, sector text)
RETURNS boolean LANGUAGE sql STABLE SET search_path='' AS $$
  SELECT profile.status='aprovado' AND profile.access_mode='areas'
    AND profile.experience_notifications AND profile.whatsapp ~ '^55[1-9][0-9][0-9]{8,9}$'
    AND EXISTS(SELECT 1 FROM jsonb_array_elements(profile.access_scopes) scope
      WHERE (scope->>'unidade' IS NULL OR scope->>'unidade'=unit)
        AND (scope->>'setor' IS NULL OR scope->>'setor'=sector))
$$;
REVOKE ALL ON FUNCTION rh_internal.profile_subscribed_to_area(public.profiles,text,text) FROM PUBLIC,anon,authenticated;

CREATE FUNCTION rh_internal.experience_recipient(profile_id uuid, individual_id uuid, unit text, sector text)
RETURNS boolean LANGUAGE sql STABLE SET search_path='' AS $$
  SELECT EXISTS(
    SELECT 1 FROM public.profiles p WHERE p.id=profile_id
      AND p.experience_notifications AND p.whatsapp ~ '^55[1-9][0-9][0-9]{8,9}$'
      AND ((p.id=individual_id AND rh_internal.experience_manager_allowed(p.id,unit,sector))
        OR rh_internal.profile_subscribed_to_area(p,unit,sector))
  )
$$;
REVOKE ALL ON FUNCTION rh_internal.experience_recipient(uuid,uuid,text,text) FROM PUBLIC,anon,authenticated;

DROP INDEX public.experience_notice_contract_period;
CREATE UNIQUE INDEX experience_notice_contract_period
  ON public.rh_admin_notifications(employee_id,experience_admission,experience_period,recipient_profile_id)
  WHERE experience_admission IS NOT NULL;

CREATE OR REPLACE FUNCTION rh_internal.experience_queue()
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare today date=(now() at time zone 'America/Sao_Paulo')::date;total integer;begin
 insert into public.rh_admin_notifications(employee_id,employee_name,source_table,operation,title,message_text,
 recipient_profile_id,recipient_phone,experience_admission,experience_period,whatsapp_status,actor_name)
 select e.id,e.nome,'experiencia','ALERTA',
 'Experiência — '||stage.period::text||'º período próximo do fim: '||e.nome,
 '*PRIME RH | Contrato de experiência*'||E'\n\nOlá, '||coalesce(nullif(initcap(split_part(regexp_replace(btrim(p.name),'\s+',' ','g'),' ',1)),''),'gestor')||'!'
 ||E'\nO '||stage.period::text||'º período de experiência do colaborador abaixo está próximo do término.'
 ||E'\n\n*Colaborador:* '||e.nome||E'\n*Função:* '||coalesce(e.funcao,'Não informada')
 ||E'\n*Filial / setor:* '||coalesce(e.unidade,'—')||' / '||coalesce(e.setor,'—')
 ||E'\n*Admissão:* '||to_char(d.admission,'DD/MM/YYYY')
 ||E'\n*Período:* '||stage.period::text||'º de 45 dias (total: 90 dias)'
 ||E'\n*Término do '||stage.period::text||'º período:* '||to_char(d.admission+stage.deadline,'DD/MM/YYYY')
 ||E'\n*Dias restantes neste período:* '||(d.admission+stage.deadline-today)::text
 ||case when stage.period=1 then
 E'\n\nPor favor, avalie o colaborador e alinhe com o RH as providências para o término do primeiro período.'
 else E'\n\nPor favor, conclua a avaliação e alinhe com o RH as providências antes do término total da experiência.' end,
 p.id,p.whatsapp,d.admission,stage.period,'experiencia_pendente','Sistema'
 from public.funcionarios_epi e join public.profiles p on p.experience_notifications and p.whatsapp<>''
 cross join lateral (select rh_internal.experience_date(e.admissao) admission) d
 cross join (values(1::smallint,38,45),(2::smallint,83,90)) stage(period,alert_day,deadline)
 where e.data_desligamento is null and today>=d.admission+stage.alert_day and today<d.admission+stage.deadline
 and p.experience_notifications and p.whatsapp<>''
 and rh_internal.experience_recipient(p.id,e.manager_profile_id,e.unidade,e.setor)
 on conflict(employee_id,experience_admission,experience_period,recipient_profile_id) where experience_admission is not null do update
 set recipient_profile_id=excluded.recipient_profile_id,recipient_phone=excluded.recipient_phone,
 message_text=excluded.message_text,employee_name=excluded.employee_name,title=excluded.title
 where rh_admin_notifications.whatsapp_status='experiencia_pendente';
 get diagnostics total=row_count;return total;
end $function$;

CREATE OR REPLACE FUNCTION rh_internal.experience_event_valid(p_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
 select exists(select 1 from public.rh_admin_notifications n
 join public.funcionarios_epi e on e.id=n.employee_id join public.profiles p on p.id=n.recipient_profile_id
 where n.id=p_id and n.experience_admission is not null and n.experience_period in (1,2)
 and rh_internal.experience_date(e.admissao)=n.experience_admission
 and e.data_desligamento is null
 and (now() at time zone 'America/Sao_Paulo')::date>=n.experience_admission+
 case n.experience_period when 1 then 38 else 83 end
 and (now() at time zone 'America/Sao_Paulo')::date<n.experience_admission+
 case n.experience_period when 1 then 45 else 90 end
 and p.experience_notifications and p.whatsapp<>'' and p.whatsapp=n.recipient_phone
 and rh_internal.experience_recipient(p.id,e.manager_profile_id,e.unidade,e.setor))
 $function$;

-- Repasse os avisos de colaboradores já gerados pelo RH, com mensagem própria para a área.
CREATE FUNCTION rh_internal.enqueue_area_notices() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE
  employee public.funcionarios_epi;
  event_label text;
BEGIN
  event_label:=CASE
    WHEN NEW.source_table IN ('rh_ferias','rh_ferias_periodos','rh_ferias_lancamentos','rh_ferias_documentos') THEN 'Atualização de férias'
    WHEN NEW.source_table='rh_absenteismo' THEN 'Atualização de frequência'
    WHEN NEW.source_table='rh_desligados' THEN 'Atualização de desligamento'
    WHEN NEW.source_table='devolucoes_pendentes' THEN 'Atualização de devolução'
    WHEN NEW.source_table IN ('funcionarios_epi','rh_movimentacoes') THEN 'Atualização de colaborador'
  END;
  IF event_label IS NULL OR NEW.employee_id IS NULL THEN RETURN NEW; END IF;
  SELECT * INTO employee FROM public.funcionarios_epi WHERE id=NEW.employee_id;
  IF NOT FOUND THEN RETURN NEW; END IF;

  INSERT INTO public.rh_admin_notifications(
    employee_id,employee_name,source_table,operation,title,details,message_text,recipient_profile_id,recipient_phone
  )
  SELECT employee.id,employee.nome,'avisos_area',NEW.operation,event_label||' · '||employee.nome,
    jsonb_build_object('evento_origem',NEW.id,'unidade',employee.unidade,'setor',employee.setor),
    'RH PRIME · '||event_label||E'\nColaborador: '||employee.nome
      ||E'\nFilial / setor: '||coalesce(employee.unidade,'—')||' / '||coalesce(employee.setor,'—')
      ||E'\nConsulte o registro no RH PRIME.',
    p.id,p.whatsapp
  FROM public.profiles p WHERE rh_internal.profile_subscribed_to_area(p,employee.unidade,employee.setor);
  RETURN NEW;
END $$;
REVOKE ALL ON FUNCTION rh_internal.enqueue_area_notices() FROM PUBLIC,anon,authenticated;
CREATE TRIGGER rh_enqueue_area_notices AFTER INSERT ON public.rh_admin_notifications
  FOR EACH ROW WHEN (NEW.employee_id IS NOT NULL AND NEW.source_table IN
    ('funcionarios_epi','rh_movimentacoes','rh_absenteismo','rh_ferias','rh_ferias_periodos',
     'rh_ferias_lancamentos','rh_ferias_documentos','rh_desligados','devolucoes_pendentes'))
  EXECUTE FUNCTION rh_internal.enqueue_area_notices();

CREATE FUNCTION rh_internal.area_notice_valid(p_id uuid) RETURNS boolean
LANGUAGE sql STABLE SET search_path='' AS $$
  SELECT EXISTS(
    SELECT 1 FROM public.rh_admin_notifications n
    JOIN public.funcionarios_epi e ON e.id=n.employee_id
    JOIN public.profiles p ON p.id=n.recipient_profile_id
    WHERE n.id=p_id AND n.source_table='avisos_area' AND n.recipient_phone=p.whatsapp
      AND (n.details->>'unidade') IS NOT DISTINCT FROM e.unidade
      AND (n.details->>'setor') IS NOT DISTINCT FROM e.setor
      AND rh_internal.profile_subscribed_to_area(p,e.unidade,e.setor)
  )
$$;
REVOKE ALL ON FUNCTION rh_internal.area_notice_valid(uuid) FROM PUBLIC,anon,authenticated;

CREATE OR REPLACE FUNCTION rh_internal.dispatch_admin_notifications()
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare n record;s public.rh_notification_settings;url text;token text;admin_enabled boolean;begin
 select * into s from public.rh_notification_settings where id;select webhook_url into url from rh_internal.notification_runtime where id;
 if url is null then return;end if;
 admin_enabled:=coalesce(s.whatsapp_enabled,false) and exists(select 1 from public.profiles where id=s.recipient_profile_id and status='admin');
 update public.rh_admin_notifications set whatsapp_status='cancelado',error='O perfil ou a área deixou de receber este aviso.'
 where source_table='avisos_area' and whatsapp_status in ('aguardando_configuracao','aguardando') and not rh_internal.area_notice_valid(id);
 update public.rh_admin_notifications set whatsapp_status='falha',error='Não foi possível iniciar o envio após três tentativas.' where whatsapp_status='aguardando' and attempts>=3 and last_attempt_at<now()-interval '11 minutes';
 update public.rh_admin_notifications set whatsapp_status='incerto',error='Envio sem confirmação. Confira o n8n antes de reenviar.' where whatsapp_status='enviando' and last_attempt_at<now()-interval '15 minutes';
 for n in select id from public.rh_admin_notifications where source_table not in('ponto_fichas','ponto_fichas_autorizacao') and experience_admission is null and (source_table='avisos_area' or admin_enabled) and (whatsapp_status='aguardando_configuracao' or (whatsapp_status='aguardando' and last_attempt_at<now()-interval '11 minutes')) and attempts<3 order by created_at limit 10 for update skip locked loop
  token=encode(extensions.gen_random_bytes(32),'hex');
  insert into rh_internal.notification_dispatch(id,token,expires_at) values(n.id,token,now()+interval '10 minutes') on conflict(id) do update set token=excluded.token,expires_at=excluded.expires_at,claimed=false;
  perform net.http_post(url:=url,body:=jsonb_build_object('eventId',n.id,'eventToken',token),headers:='{"Content-Type":"application/json"}'::jsonb,timeout_milliseconds:=15000);
  update public.rh_admin_notifications set whatsapp_status='aguardando',last_attempt_at=now(),attempts=attempts+1 where id=n.id;
 end loop;
end $function$;

CREATE OR REPLACE FUNCTION rh_notifications_internal.notification_admin_claim(p_id uuid, p_token text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare n public.rh_admin_notifications;s public.rh_notification_settings;phone text;begin
 if p_token is null or length(p_token)<>64 then raise exception 'Evento inválido';end if;
 perform 1 from rh_internal.notification_dispatch where id=p_id and token=p_token and expires_at>now() and not claimed for update;
 if not found then raise exception 'Evento expirado ou já processado';end if;
 select * into n from public.rh_admin_notifications where id=p_id and whatsapp_status='aguardando' for update;
 if not found then raise exception 'Evento indisponível';end if;
 if n.source_table='avisos_area' then
  if not rh_internal.area_notice_valid(p_id) then raise exception 'O perfil ou a área deixou de receber este aviso.';end if;
  phone:=n.recipient_phone;
 else
 select * into s from public.rh_notification_settings where id;
 if not s.whatsapp_enabled or not exists(select 1 from public.profiles where id=s.recipient_profile_id and status='admin') then raise exception 'Notificações desativadas';end if;
 phone=s.recipient_whatsapp;if s.employee_id is not null then select whatsapp into phone from public.funcionarios_epi where id=s.employee_id;end if;
 phone=regexp_replace(coalesce(phone,''),'[^0-9]','','g');if length(phone) in(10,11) then phone='55'||phone;end if;
 if phone !~ '^55[1-9][0-9][0-9]{8,9}$' then raise exception 'Destinatário inválido';end if;
 end if;
 update rh_internal.notification_dispatch set claimed=true where id=p_id;
 update public.rh_admin_notifications set whatsapp_status='enviando' where id=p_id;
 return jsonb_build_object('eventId',p_id,'chatId',phone||'@c.us','message',n.message_text);
end $function$;
