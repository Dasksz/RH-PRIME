create table public.rh_notification_settings(
 id boolean primary key default true check(id),
 recipient_profile_id uuid references public.profiles(id),employee_id uuid references public.funcionarios_epi(id),
 recipient_name text not null default '',recipient_whatsapp text not null default '',
 whatsapp_enabled boolean not null default false,
 notify_new_access boolean not null default true,notify_changes boolean not null default true,
 updated_at timestamptz not null default now());
alter table public.rh_notification_settings enable row level security;
revoke all on public.rh_notification_settings from anon,authenticated;
grant select,update on public.rh_notification_settings to authenticated;
create policy notification_settings_admin on public.rh_notification_settings for all to authenticated using((select rh_internal.is_admin())) with check((select rh_internal.is_admin()));
insert into public.rh_notification_settings(id,recipient_profile_id,recipient_name)
 select true,id,coalesce(name,'') from public.profiles where status='admin' order by created_at limit 1;
create function rh_internal.notification_settings_guard() returns trigger language plpgsql set search_path='' as $$begin
 if new.recipient_profile_id is not null and not exists(select 1 from public.profiles where id=new.recipient_profile_id and status='admin') then raise exception 'Selecione uma conta administradora';end if;
 if new.employee_id is not null then select nome,coalesce(whatsapp,'') into new.recipient_name,new.recipient_whatsapp from public.funcionarios_epi where id=new.employee_id;end if;
 if new.whatsapp_enabled and regexp_replace(new.recipient_whatsapp,'[^0-9]','','g') !~ '^(55)?[1-9][0-9][0-9]{8,9}$' then raise exception 'Informe WhatsApp válido com DDD';end if;
 if new.whatsapp_enabled and (new.recipient_profile_id is null or nullif(trim(new.recipient_name),'') is null) then raise exception 'Selecione o administrador e informe o nome do destinatário';end if;
 new.updated_at=now();return new;end $$;
create trigger notification_settings_guard before update on public.rh_notification_settings for each row execute function rh_internal.notification_settings_guard();

create table public.rh_admin_notifications(
 id uuid primary key default gen_random_uuid(),created_at timestamptz not null default now(),actor_id uuid,
 actor_name text,employee_id uuid,employee_name text,source_table text not null,operation text not null,
 title text not null,details jsonb not null default '{}',message_text text not null,
 whatsapp_status text not null default 'aguardando_configuracao',error text,
 sent_at timestamptz,last_attempt_at timestamptz,attempts integer not null default 0);
alter table public.rh_admin_notifications enable row level security;
revoke all on public.rh_admin_notifications from anon,authenticated;
grant select on public.rh_admin_notifications to authenticated;
create policy notifications_admin_read on public.rh_admin_notifications for select to authenticated using((select rh_internal.is_admin()));
create table rh_internal.notification_dispatch(id uuid primary key references public.rh_admin_notifications(id) on delete cascade,token text not null,expires_at timestamptz not null,claimed boolean not null default false);
revoke all on rh_internal.notification_dispatch from public,anon,authenticated;
create table rh_internal.notification_runtime(id boolean primary key default true,webhook_url text not null);
revoke all on rh_internal.notification_runtime from public,anon,authenticated;

create function rh_internal.notify_admin_event() returns trigger language plpgsql security definer set search_path='' as $$
declare before_row jsonb;after_row jsonb;record_row jsonb;diff jsonb='{}';k text;actor text;employee uuid;person text;title text;msg text;kind text;begin
 if tg_table_name<>'profiles' and auth.uid() is null then return coalesce(new,old);end if;
 if tg_op='UPDATE' and new is not distinct from old then return new;end if;
 before_row=case when tg_op<>'INSERT' then to_jsonb(old) else '{}' end;after_row=case when tg_op<>'DELETE' then to_jsonb(new) else '{}' end;record_row=coalesce(after_row,before_row);
 if tg_op='DELETE' then record_row=before_row;end if;
 if tg_table_name='profiles' and tg_op='UPDATE' and
 (before_row-array['access_version']) is not distinct from (after_row-array['access_version']) then return new;end if;
 if not coalesce((select case when tg_table_name='profiles' and tg_op='INSERT' then notify_new_access else notify_changes end from public.rh_notification_settings where id),false) then return coalesce(new,old);end if;
 select coalesce(name,email) into actor from public.profiles where id=auth.uid();actor=coalesce(actor,'Novo cadastro');
 employee=nullif(record_row->>'funcionario_id','')::uuid;
 if tg_table_name='funcionarios_epi' then employee=(record_row->>'id')::uuid;end if;
 if employee is not null then select nome into person from public.funcionarios_epi where id=employee;end if;
 person=coalesce(person,record_row->>'funcionario_nome',record_row->>'nome',record_row->>'name','');
 for k in select key from jsonb_object_keys(before_row||after_row) as key loop
  if before_row->k is distinct from after_row->k and k not in ('updated_at','created_at','access_version') then
   diff=diff||jsonb_build_object(k,jsonb_build_object('antes',before_row->k,'depois',after_row->k));end if;
 end loop;
 if diff='{}' then return coalesce(new,old);end if;
 title=case when tg_table_name='profiles' and tg_op='INSERT' then 'Novo cadastro: '||person
 when tg_table_name='rh_absenteismo' then 'Registro de falta/atestado: '||person
 when tg_table_name='profiles' then 'Perfil atualizado: '||person
 else 'Alteração em '||tg_table_name||': '||person end;
 msg='RH PRIME — '||title||E'\nResponsável: '||actor||E'\nOperação: '||tg_op;
 if tg_table_name='profiles' and tg_op='INSERT' then msg=msg||E'\nE-mail: '||coalesce(record_row->>'email','')||E'\nAguardando aprovação.';end if;
 -- Resumo externo limita-se aos campos operacionais; conteúdo completo fica no painel restrito.
 for k in select key from jsonb_object_keys(diff) as key loop
  if k in ('data_inicio','data_fim','mes_ref','horas_perdidas','status','unidade','setor','role','access_mode','access_level','data_desligamento') then
   msg=msg||E'\n'||k||': '||coalesce(diff->k->>'antes','—')||' → '||coalesce(diff->k->>'depois','—');end if;
 end loop;
 msg=left(msg,6000)||E'\nConfira no administrativo: https://dasksz.github.io/RH-PRIME/admin.html';
 insert into public.rh_admin_notifications(actor_id,actor_name,employee_id,employee_name,source_table,operation,title,details,message_text)
 values(auth.uid(),actor,employee,person,tg_table_name,tg_op,title,diff,msg);return coalesce(new,old);
end $$;
revoke all on function rh_internal.notify_admin_event() from public,anon,authenticated;
do $$declare t text;begin foreach t in array array['profiles','funcionarios_epi','rh_absenteismo','rh_movimentacoes','rh_ferias','rh_desligados','devolucoes_pendentes'] loop
 execute format('create trigger rh_notify_admin_event after insert or update or delete on public.%I for each row execute function rh_internal.notify_admin_event()',t);end loop;end $$;

create function rh_internal.dispatch_admin_notifications() returns void language plpgsql security definer set search_path='' as $$
declare n record;s public.rh_notification_settings;url text;token text;begin
 select * into s from public.rh_notification_settings where id;select webhook_url into url from rh_internal.notification_runtime where id;
 if not s.whatsapp_enabled or url is null or not exists(select 1 from public.profiles where id=s.recipient_profile_id and status='admin') then return;end if;
 update public.rh_admin_notifications set whatsapp_status='falha',error='Não foi possível iniciar o envio após três tentativas.' where whatsapp_status='aguardando' and attempts>=3 and last_attempt_at<now()-interval '11 minutes';
 update public.rh_admin_notifications set whatsapp_status='incerto',error='Envio sem confirmação. Confira o n8n antes de reenviar.' where whatsapp_status='enviando' and last_attempt_at<now()-interval '15 minutes';
 for n in select id from public.rh_admin_notifications where (whatsapp_status='aguardando_configuracao' or (whatsapp_status='aguardando' and last_attempt_at<now()-interval '11 minutes')) and attempts<3 order by created_at limit 10 for update skip locked loop
  token=encode(extensions.gen_random_bytes(32),'hex');
  insert into rh_internal.notification_dispatch(id,token,expires_at) values(n.id,token,now()+interval '10 minutes') on conflict(id) do update set token=excluded.token,expires_at=excluded.expires_at,claimed=false;
  perform net.http_post(url:=url,body:=jsonb_build_object('eventId',n.id,'eventToken',token),headers:='{"Content-Type":"application/json"}'::jsonb,timeout_milliseconds:=15000);
  update public.rh_admin_notifications set whatsapp_status='aguardando',last_attempt_at=now(),attempts=attempts+1 where id=n.id;
 end loop;
end $$;
revoke all on function rh_internal.dispatch_admin_notifications() from public,anon,authenticated;

create schema rh_notifications_internal;
revoke all on schema rh_notifications_internal from public,authenticated,anon;
create function rh_notifications_internal.notification_claim(p_id uuid,p_token text) returns jsonb language plpgsql security definer set search_path='' as $$
declare n public.rh_admin_notifications;s public.rh_notification_settings;phone text;begin
 if length(p_token)<>64 then raise exception 'Evento inválido';end if;
 perform 1 from rh_internal.notification_dispatch where id=p_id and token=p_token and expires_at>now() and not claimed for update;
 if not found then raise exception 'Evento expirado ou já processado';end if;
 select * into s from public.rh_notification_settings where id;
 if not s.whatsapp_enabled or not exists(select 1 from public.profiles where id=s.recipient_profile_id and status='admin') then raise exception 'Notificações desativadas';end if;
 phone=s.recipient_whatsapp;if s.employee_id is not null then select whatsapp into phone from public.funcionarios_epi where id=s.employee_id;end if;
 phone=regexp_replace(coalesce(phone,''),'[^0-9]','','g');if length(phone) in(10,11) then phone='55'||phone;end if;
 if phone !~ '^55[1-9][0-9][0-9]{8,9}$' then raise exception 'Destinatário inválido';end if;
 select * into n from public.rh_admin_notifications where id=p_id and whatsapp_status='aguardando' for update;
 if not found then raise exception 'Evento indisponível';end if;
 update rh_internal.notification_dispatch set claimed=true where id=p_id;
 update public.rh_admin_notifications set whatsapp_status='enviando' where id=p_id;
 return jsonb_build_object('eventId',p_id,'chatId',phone||'@c.us','message',n.message_text);
end $$;
create function public.rh_notification_claim(p_id uuid,p_token text) returns jsonb language sql security invoker set search_path='' as $$select rh_notifications_internal.notification_claim(p_id,p_token);$$;
create function rh_notifications_internal.notification_complete(p_id uuid,p_token text,p_success boolean) returns void language plpgsql security definer set search_path='' as $$begin
 if not exists(select 1 from rh_internal.notification_dispatch where id=p_id and token=p_token and claimed and expires_at>now()) then raise exception 'Evento inválido';end if;
 update public.rh_admin_notifications set whatsapp_status=case when p_success then 'aceito' else 'falha' end,sent_at=case when p_success then now() else null end,error=case when p_success then null else 'WAHA informou falha. Confira a execução no n8n.' end where id=p_id and whatsapp_status='enviando';
 delete from rh_internal.notification_dispatch where id=p_id;
end $$;
create function public.rh_notification_complete(p_id uuid,p_token text,p_success boolean) returns void language sql security invoker set search_path='' as $$select rh_notifications_internal.notification_complete(p_id,p_token,p_success);$$;
revoke all on function rh_notifications_internal.notification_claim(uuid,text),public.rh_notification_claim(uuid,text),rh_notifications_internal.notification_complete(uuid,text,boolean),public.rh_notification_complete(uuid,text,boolean) from public;
grant usage on schema rh_notifications_internal to anon,authenticated;
grant execute on function rh_notifications_internal.notification_claim(uuid,text),public.rh_notification_claim(uuid,text),rh_notifications_internal.notification_complete(uuid,text,boolean),public.rh_notification_complete(uuid,text,boolean) to anon,authenticated;
select cron.schedule('rh_admin_notifications','* * * * *','select rh_internal.dispatch_admin_notifications()');
create index admin_notifications_pending on public.rh_admin_notifications(created_at) where whatsapp_status in ('aguardando_configuracao','aguardando');
notify pgrst,'reload schema';
