-- Alertas individuais de experiência. Requer perfis e notificações administrativas existentes.
begin;
alter table public.profiles add column whatsapp text not null default '',
 add column experience_notifications boolean not null default false;
alter table public.profiles add constraint profile_whatsapp_valid check
 (whatsapp='' or whatsapp ~ '^55[1-9][0-9][0-9]{8,9}$');
alter table public.funcionarios_epi add column manager_profile_id uuid references public.profiles(id) on delete set null;
create index employees_manager on public.funcionarios_epi(manager_profile_id);
alter table public.rh_admin_notifications add column recipient_profile_id uuid references public.profiles(id),
 add column recipient_phone text, add column experience_admission date;
create unique index experience_notice_contract on public.rh_admin_notifications(employee_id,experience_admission)
 where experience_admission is not null;

create function rh_internal.experience_phone(p_phone text) returns text
 language plpgsql immutable set search_path='' as $$
declare phone text=regexp_replace(coalesce(p_phone,''),'[^0-9]','','g');begin
 if phone='' then return '';end if;
 if length(phone) in (10,11) then phone='55'||phone;end if;
 if phone !~ '^55[1-9][0-9][0-9]{8,9}$' then raise exception 'Informe WhatsApp válido com DDD';end if;
 return phone;
end $$;
create function rh_internal.experience_date(p_text text) returns date
 language plpgsql immutable set search_path='' as $$
declare d date;begin
 if p_text ~ '^\d{4}-\d{2}-\d{2}$' then d=p_text::date;
 elsif p_text ~ '^\d{2}/\d{2}/\d{4}$' then
  d=make_date(substring(p_text,7,4)::int,substring(p_text,4,2)::int,substring(p_text,1,2)::int);
 else return null;end if;
 return d;
 exception when datetime_field_overflow or invalid_datetime_format then return null;
end $$;
create function rh_internal.experience_profile_guard() returns trigger
 language plpgsql set search_path='' as $$begin
 new.whatsapp=rh_internal.experience_phone(new.whatsapp);
 if new.experience_notifications and new.whatsapp='' then raise exception 'Cadastre o WhatsApp antes de ativar os avisos';end if;
 return new;
end $$;
create trigger rh_experience_profile_guard before insert or update on public.profiles
 for each row execute function rh_internal.experience_profile_guard();

-- Telefone é apenas contato. Papel, aprovação e escopos continuam definidos pelo administrador.
create or replace function public.handle_new_user() returns trigger
 language plpgsql security definer set search_path='' as $$begin
 insert into public.profiles(id,name,email,status,whatsapp)
 values(new.id,coalesce(new.raw_user_meta_data->>'full_name',new.raw_user_meta_data->>'name','Usuário sem nome'),
 new.email,'pendente',rh_internal.experience_phone(new.raw_user_meta_data->>'whatsapp'));
 return new;
end $$;
revoke all on function public.handle_new_user() from public,anon,authenticated;

create function rh_internal.experience_manager_allowed(p_manager uuid,p_unit text,p_sector text) returns boolean
 language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.profiles p where p.id=p_manager
 and p.status in ('aprovado','admin') and p.role in ('supervisor','coordenador','gerente','administrador')
 and (p.status='admin' or p.access_mode='todos' or (p.access_mode='areas' and exists
 (select 1 from jsonb_array_elements(p.access_scopes) s
 where (s->>'unidade' is null or s->>'unidade'=p_unit) and (s->>'setor' is null or s->>'setor'=p_sector)))))
 $$;
create function rh_internal.experience_assignment_guard() returns trigger
 language plpgsql security definer set search_path='' as $$begin
 if tg_op='INSERT' then
  if new.manager_profile_id is null then return new;end if;
 elsif new.manager_profile_id is not distinct from old.manager_profile_id then return new;end if;
 if auth.uid() is not null and not rh_internal.is_admin() then raise exception 'Somente o administrador pode vincular o gestor';end if;
 if new.manager_profile_id is not null and not rh_internal.experience_manager_allowed(new.manager_profile_id,new.unidade,new.setor)
 then raise exception 'Selecione um gestor aprovado com acesso à área deste colaborador';end if;
 return new;
end $$;
create trigger rh_experience_assignment_guard before insert or update on public.funcionarios_epi
 for each row execute function rh_internal.experience_assignment_guard();

create function rh_internal.experience_queue() returns integer
 language plpgsql security definer set search_path='' as $$
declare today date=(now() at time zone 'America/Sao_Paulo')::date;total integer;begin
 insert into public.rh_admin_notifications(employee_id,employee_name,source_table,operation,title,message_text,
 recipient_profile_id,recipient_phone,experience_admission,whatsapp_status,actor_name)
 select e.id,e.nome,'experiencia','ALERTA','Experiência próxima do fim: '||e.nome,
 '*PRIME RH | Contrato de experiência*'||E'\n\nOlá, '||coalesce(p.name,'gestor')||'!'
 ||E'\nO contrato de experiência do colaborador abaixo está próximo do término.'
 ||E'\n\n*Colaborador:* '||e.nome||E'\n*Função:* '||coalesce(e.funcao,'Não informada')
 ||E'\n*Filial / setor:* '||coalesce(e.unidade,'—')||' / '||coalesce(e.setor,'—')
 ||E'\n*Admissão:* '||to_char(d.admission,'DD/MM/YYYY')
 ||E'\n*Término previsto (90 dias):* '||to_char(d.admission+90,'DD/MM/YYYY')
 ||E'\n*Dias restantes:* '||(d.admission+90-today)::text
 ||E'\n\nPor favor, avalie o colaborador e alinhe com o RH as providências antes do término.'
 ||E'\n\nAcesse: https://dasksz.github.io/RH-PRIME/colaboradores.html',
 p.id,p.whatsapp,d.admission,'experiencia_pendente','Sistema'
 from public.funcionarios_epi e join public.profiles p on p.id=e.manager_profile_id
 cross join lateral (select rh_internal.experience_date(e.admissao) admission) d
 where e.data_desligamento is null and today>=d.admission+80 and today<d.admission+90
 and p.experience_notifications and p.whatsapp<>''
 and rh_internal.experience_manager_allowed(p.id,e.unidade,e.setor)
 on conflict(employee_id,experience_admission) where experience_admission is not null do update
 set recipient_profile_id=excluded.recipient_profile_id,recipient_phone=excluded.recipient_phone,
 message_text=excluded.message_text,employee_name=excluded.employee_name
 where rh_admin_notifications.whatsapp_status='experiencia_pendente';
 get diagnostics total=row_count;return total;
end $$;

create function rh_internal.experience_event_valid(p_id uuid) returns boolean
 language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.rh_admin_notifications n
 join public.funcionarios_epi e on e.id=n.employee_id join public.profiles p on p.id=n.recipient_profile_id
 where n.id=p_id and n.experience_admission is not null and e.manager_profile_id=p.id
 and rh_internal.experience_date(e.admissao)=n.experience_admission and e.data_desligamento is null
 and (now() at time zone 'America/Sao_Paulo')::date>=n.experience_admission+80
 and (now() at time zone 'America/Sao_Paulo')::date<n.experience_admission+90
 and p.experience_notifications and p.whatsapp<>'' and p.whatsapp=n.recipient_phone
 and rh_internal.experience_manager_allowed(p.id,e.unidade,e.setor))
 $$;
create function rh_internal.dispatch_experience_notifications() returns void
 language plpgsql security definer set search_path='' as $$
declare n record;url text;token text;begin
 select webhook_url into url from rh_internal.notification_runtime where id;
 if url is null then return;end if;
 update public.rh_admin_notifications set whatsapp_status='incerto',error='Envio sem confirmação. Confira o n8n antes de reenviar.'
 where experience_admission is not null and whatsapp_status='enviando' and last_attempt_at<now()-interval '15 minutes';
 update public.rh_admin_notifications set whatsapp_status='falha',error='Não foi possível iniciar o envio após três tentativas.'
 where experience_admission is not null and whatsapp_status='aguardando' and attempts>=3 and last_attempt_at<now()-interval '11 minutes';
 for n in select id from public.rh_admin_notifications where experience_admission is not null
 and (whatsapp_status='experiencia_pendente' or (whatsapp_status='aguardando' and last_attempt_at<now()-interval '11 minutes'))
 and attempts<3 and rh_internal.experience_event_valid(id) order by created_at limit 10 for update skip locked loop
  token=encode(extensions.gen_random_bytes(32),'hex');
  insert into rh_internal.notification_dispatch(id,token,expires_at) values(n.id,token,now()+interval '10 minutes')
  on conflict(id) do update set token=excluded.token,expires_at=excluded.expires_at,claimed=false;
  perform net.http_post(url:=url,body:=jsonb_build_object('eventId',n.id,'eventToken',token),
  headers:='{"Content-Type":"application/json"}'::jsonb,timeout_milliseconds:=15000);
  update public.rh_admin_notifications set whatsapp_status='aguardando',last_attempt_at=now(),attempts=attempts+1 where id=n.id;
 end loop;
end $$;

-- O fluxo n8n existente continua atendendo os dois tipos de evento.
-- Impede que o disparador administrativo selecione um aviso destinado a um gestor.
do $$declare def text;begin
 select pg_get_functiondef('rh_internal.dispatch_admin_notifications()'::regprocedure) into def;
 if position('where (whatsapp_status=' in def)=0 then raise exception 'Revise o formato do disparador administrativo';end if;
 def=replace(def,'where (whatsapp_status=','where experience_admission is null and (whatsapp_status=');
 execute def;
end $$;
alter function rh_notifications_internal.notification_claim(uuid,text) rename to notification_admin_claim;
create function rh_notifications_internal.notification_claim(p_id uuid,p_token text) returns jsonb
 language plpgsql security definer set search_path='' as $$
declare n public.rh_admin_notifications;begin
 select * into n from public.rh_admin_notifications where id=p_id;
 if n.experience_admission is null then return rh_notifications_internal.notification_admin_claim(p_id,p_token);end if;
 if p_token is null or length(p_token)<>64 then raise exception 'Evento inválido';end if;
 perform 1 from rh_internal.notification_dispatch where id=p_id and token=p_token and expires_at>now() and not claimed for update;
 if not found then raise exception 'Evento expirado ou já processado';end if;
 select * into n from public.rh_admin_notifications where id=p_id and whatsapp_status='aguardando' for update;
 if not found or not rh_internal.experience_event_valid(p_id) then raise exception 'Contrato ou destinatário mudou; envio cancelado';end if;
 update rh_internal.notification_dispatch set claimed=true where id=p_id;
 update public.rh_admin_notifications set whatsapp_status='enviando' where id=p_id;
 return jsonb_build_object('eventId',p_id,'chatId',n.recipient_phone||'@c.us','message',n.message_text);
end $$;
-- Recriar o wrapper para apontar à nova função após o rename.
create or replace function public.rh_notification_claim(p_id uuid,p_token text) returns jsonb
 language sql security invoker set search_path='' as $$select rh_notifications_internal.notification_claim(p_id,p_token);$$;
revoke all on function rh_notifications_internal.notification_admin_claim(uuid,text) from public,anon,authenticated;
revoke all on function rh_notifications_internal.notification_claim(uuid,text) from public;
grant execute on function rh_notifications_internal.notification_claim(uuid,text) to anon,authenticated;
revoke all on function rh_internal.experience_phone(text),rh_internal.experience_date(text),
 rh_internal.experience_profile_guard(),rh_internal.experience_manager_allowed(uuid,text,text),
 rh_internal.experience_assignment_guard(),rh_internal.experience_queue(),rh_internal.experience_event_valid(uuid),
 rh_internal.dispatch_experience_notifications() from public,anon,authenticated;
-- Guards invoker precisam executar apenas normalização; não expõe dados nem autoridade.
grant usage on schema rh_internal to authenticated;
grant execute on function rh_internal.experience_phone(text) to authenticated;
select cron.schedule('rh_experience_daily','0 11 * * *','select rh_internal.experience_queue()');
select cron.schedule('rh_experience_dispatch','* * * * *','select rh_internal.dispatch_experience_notifications()');
notify pgrst,'reload schema';
commit;
