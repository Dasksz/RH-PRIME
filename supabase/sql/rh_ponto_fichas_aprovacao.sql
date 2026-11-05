begin;
update public.rh_ponto_fichas_config set ativo=false,hora=7;
create table public.rh_ponto_fichas_autorizacoes(
 id uuid primary key default gen_random_uuid(),mes date not null,tipo text not null check(tipo in('ficha','parcial','final')),
 status text not null default 'pendente' check(status in('pendente','aprovado','recusado','expirado','cancelado')),
 destinatarios jsonb not null,recipient_phone text not null,notificacao_id uuid unique references public.rh_admin_notifications(id),
 criado_em timestamptz not null default now(),expira_em timestamptz not null,resposta_id text unique,respondido_em timestamptz,
 unique(mes,tipo)
);
alter table public.rh_ponto_fichas_autorizacoes enable row level security;
revoke all on public.rh_ponto_fichas_autorizacoes from public,anon,authenticated;
grant select on public.rh_ponto_fichas_autorizacoes to authenticated;
create policy fichas_autorizacoes_admin on public.rh_ponto_fichas_autorizacoes for select to authenticated using((select rh_internal.is_admin()));
create table rh_internal.ponto_fichas_polls(
 id uuid primary key references public.rh_ponto_fichas_autorizacoes(id),token text not null,expira_em timestamptz not null,
 claimed boolean not null default false,criado_em timestamptz not null default now()
);
alter table rh_internal.ponto_fichas_polls enable row level security;
revoke all on rh_internal.ponto_fichas_polls from public,anon,authenticated;

create function rh_internal.ponto_fichas_admin_phone() returns text language sql stable security definer set search_path='' as $$
 select rh_internal.ponto_fichas_phone(case when s.employee_id is null then s.recipient_whatsapp else e.whatsapp end)
 from public.rh_notification_settings s left join public.funcionarios_epi e on e.id=s.employee_id
 join public.profiles p on p.id=s.recipient_profile_id and p.status='admin' where s.id and s.whatsapp_enabled
$$;
create function rh_internal.ponto_fichas_approval_queue(p_hoje date,p_hora integer) returns integer language plpgsql security definer set search_path='' as $$
declare cfg public.rh_ponto_fichas_config;v_mes date=date_trunc('month',p_hoje)::date;datas jsonb;fase text;due date;people jsonb;names text;phone text;request_id uuid;event_id uuid;total integer=0;
begin
 perform pg_advisory_xact_lock(87111205);select * into cfg from public.rh_ponto_fichas_config where id;
 if not cfg.ativo or p_hoje<cfg.inicio or p_hora<7 or p_hora>=18 then return 0;end if;
 phone=rh_internal.ponto_fichas_admin_phone();if phone is null then return 0;end if;datas=rh_internal.ponto_fichas_datas(v_mes);
 foreach fase in array array['ficha','parcial','final'] loop
  due=(datas->>fase)::date;
  if p_hoje<>due or (fase='ficha' and v_mes<cfg.pdf_desde) or exists(select 1 from public.rh_ponto_fichas_autorizacoes a where a.mes=v_mes and a.tipo=fase) then continue;end if;
  select jsonb_agg(jsonb_build_object('id',e.id,'inscricao',r.criado_em) order by e.nome),string_agg('• '||e.nome,E'\n' order by e.nome)
  into people,names from public.rh_ponto_fichas_destinatarios r join public.funcionarios_epi e on e.id=r.funcionario_id
  where e.data_desligamento is null and coalesce(rh_internal.experience_date(e.admissao),p_hoje)<=p_hoje;
  if people is null then continue;end if;request_id=gen_random_uuid();event_id=gen_random_uuid();
  insert into public.rh_admin_notifications(id,source_table,operation,title,message_text,recipient_phone,whatsapp_status,actor_name,details)
  values(event_id,'ponto_fichas_autorizacao','PERGUNTA','Autorizar fichas de ponto — '||fase,
  'Bom dia! Deseja '||case fase when 'ficha' then 'enviar as novas fichas de ponto em PDF' when 'parcial' then 'enviar um lembrete solicitando a parcial da ficha de ponto' else 'enviar um lembrete solicitando a ficha de ponto completamente preenchida e assinada' end
  ||' aos colaboradores da lista de ponto manual?'||E'\nCompetência: '||to_char(v_mes,'MM/YYYY')||E'\n\n'||names
  ||E'\n\n1 — Sim, enviar\n2 — Não enviar\n\nResponda apenas 1 ou 2 nesta conversa. A autorização vale até as 18h de hoje. Sem resposta, nada será enviado aos colaboradores.',
  phone,'ficha_autorizacao_pendente','Sistema',jsonb_build_object('autorizacao',request_id,'mes',v_mes,'tipo',fase));
  insert into public.rh_ponto_fichas_autorizacoes(id,mes,tipo,destinatarios,recipient_phone,notificacao_id,expira_em)
  values(request_id,v_mes,fase,people,phone,event_id,(p_hoje+time '18:00') at time zone 'America/Sao_Paulo');total=total+1;
 end loop;return total;
end $$;

-- O agendador de colaboradores só pode montar lotes expressamente autorizados.
do $$declare def text;begin
 select pg_get_functiondef('rh_internal.ponto_fichas_queue(date,integer)'::regprocedure) into def;
 def=replace(def,'due=(datas->>fase)::date;', 'due=(datas->>fase)::date;
 if not exists(select 1 from public.rh_ponto_fichas_autorizacoes a where a.mes=v_mes and a.tipo=fase and a.status=''aprovado'' and a.expira_em>now()) then continue;end if;');
 if position('a.status=''aprovado''' in def)=0 then raise exception 'Formato inesperado da fila';end if;
 def=replace(def,'where e.data_desligamento is null and', 'where exists(select 1 from public.rh_ponto_fichas_autorizacoes a cross join lateral jsonb_array_elements(a.destinatarios) t where a.mes=v_mes and a.tipo=fase and a.status=''aprovado'' and a.expira_em>now() and t->>''id''=e.id::text and (t->>''inscricao'')::timestamptz=d.criado_em) and e.data_desligamento is null and');
 execute def;
end $$;
alter function rh_internal.ponto_fichas_valid(uuid) rename to ponto_fichas_base_valid;
create function rh_internal.ponto_fichas_valid(p_id uuid) returns boolean language sql stable security definer set search_path='' as $$
 select rh_internal.ponto_fichas_base_valid(p_id) and exists(select 1 from public.rh_ponto_fichas_envios j join public.rh_ponto_fichas_autorizacoes a on a.mes=j.mes and a.tipo=j.tipo
 where j.notificacao_id=p_id and a.status='aprovado' and a.expira_em>now() and a.recipient_phone=rh_internal.ponto_fichas_admin_phone())
$$;
create function rh_internal.ponto_fichas_approval_valid(p_id uuid) returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.rh_ponto_fichas_autorizacoes a cross join public.rh_ponto_fichas_config c
 where a.notificacao_id=p_id and a.status='pendente' and a.expira_em>now() and a.recipient_phone=rh_internal.ponto_fichas_admin_phone() and c.id and c.ativo)
$$;
create function rh_internal.ponto_fichas_approval_dispatch() returns void language plpgsql security definer set search_path='' as $$
declare n record;url text;token text;begin
 select webhook_url into url from rh_internal.ponto_fichas_runtime where id;if url is null then return;end if;
 update public.rh_admin_notifications set whatsapp_status='incerto',error='Pergunta sem confirmação do WhatsApp; nenhum colaborador foi autorizado.' where source_table='ponto_fichas_autorizacao' and whatsapp_status='enviando' and last_attempt_at<now()-interval '15 minutes';
 update public.rh_admin_notifications set whatsapp_status='falha',error='O n8n não confirmou a pergunta após três tentativas.' where source_table='ponto_fichas_autorizacao' and whatsapp_status='aguardando' and attempts>=3 and last_attempt_at<now()-interval '11 minutes';
 for n in select id from public.rh_admin_notifications where source_table='ponto_fichas_autorizacao' and attempts<3
 and (whatsapp_status='ficha_autorizacao_pendente' or (whatsapp_status='aguardando' and last_attempt_at<now()-interval '11 minutes'))
 and rh_internal.ponto_fichas_approval_valid(id) order by created_at limit 1 for update skip locked loop
  token=encode(extensions.gen_random_bytes(32),'hex');insert into rh_internal.notification_dispatch(id,token,expires_at) values(n.id,token,now()+interval '10 minutes')
  on conflict(id) do update set token=excluded.token,expires_at=excluded.expires_at,claimed=false;
  perform net.http_post(url:=url,body:=jsonb_build_object('eventId',n.id,'eventToken',token),headers:='{"Content-Type":"application/json"}'::jsonb,timeout_milliseconds:=15000);
  update public.rh_admin_notifications set whatsapp_status='aguardando',last_attempt_at=now(),attempts=attempts+1 where id=n.id;
 end loop;
end $$;

alter function rh_notifications_internal.notification_claim(uuid,text) rename to notification_fichas_previous_claim;
create function rh_notifications_internal.notification_claim(p_id uuid,p_token text) returns jsonb language plpgsql security definer set search_path='' as $$
declare n public.rh_admin_notifications;begin
 select * into n from public.rh_admin_notifications where id=p_id;
 if n.source_table is distinct from 'ponto_fichas_autorizacao' then return rh_notifications_internal.notification_fichas_previous_claim(p_id,p_token);end if;
 if p_token is null or length(p_token)<>64 then raise exception 'Evento inválido';end if;
 perform 1 from rh_internal.notification_dispatch where id=p_id and token=p_token and expires_at>now() and not claimed for update;
 if not found then raise exception 'Evento expirado ou já processado';end if;
 select * into n from public.rh_admin_notifications where id=p_id and whatsapp_status='aguardando' for update;
 if not found or not rh_internal.ponto_fichas_approval_valid(p_id) then raise exception 'Pergunta cancelada ou expirada';end if;
 update rh_internal.notification_dispatch set claimed=true where id=p_id;update public.rh_admin_notifications set whatsapp_status='enviando' where id=p_id;
 return jsonb_build_object('eventId',p_id,'chatId',n.recipient_phone||'@c.us','message',n.message_text,'kind','autorizacao');
end $$;
create or replace function public.rh_notification_claim(p_id uuid,p_token text) returns jsonb language sql security invoker set search_path='' as $$select rh_notifications_internal.notification_claim(p_id,p_token);$$;
revoke all on function rh_notifications_internal.notification_fichas_previous_claim(uuid,text),rh_notifications_internal.notification_claim(uuid,text) from public,anon,authenticated;
grant execute on function rh_notifications_internal.notification_claim(uuid,text) to anon,authenticated;

-- Leitura limitada à conversa do administrador, apenas enquanto uma pergunta estiver pendente.
create function rh_internal.ponto_fichas_poll_dispatch() returns void language plpgsql security definer set search_path='' as $$
declare a record;url text;secret text;begin
 select webhook_url into url from rh_internal.ponto_fichas_runtime where id;if url is null then return;end if;
 for a in select x.id from public.rh_ponto_fichas_autorizacoes x join public.rh_admin_notifications n on n.id=x.notificacao_id
 where x.status='pendente' and x.expira_em>now() and n.whatsapp_status='aceito' and rh_internal.ponto_fichas_approval_valid(n.id)
 and not exists(select 1 from rh_internal.ponto_fichas_polls p where p.id=x.id and p.expira_em>now()) for update of x skip locked loop
  secret=encode(extensions.gen_random_bytes(32),'hex');
  insert into rh_internal.ponto_fichas_polls(id,token,expira_em) values(a.id,secret,now()+interval '4 minutes')
  on conflict(id) do update set token=excluded.token,expira_em=excluded.expira_em,claimed=false,criado_em=now();
  perform net.http_post(url:=url,body:=jsonb_build_object('eventId',a.id,'eventToken',secret,'mode','poll'),headers:='{"Content-Type":"application/json"}'::jsonb,timeout_milliseconds:=15000);
 end loop;
end $$;
create function rh_notifications_internal.fichas_poll_claim(p_id uuid,p_token text) returns jsonb language plpgsql security definer set search_path='' as $$
declare a public.rh_ponto_fichas_autorizacoes;sent timestamptz;begin
 perform 1 from rh_internal.ponto_fichas_polls where id=p_id and token=p_token and expira_em>now() and not claimed for update;
 if not found then raise exception 'Consulta inválida';end if;
 select * into a from public.rh_ponto_fichas_autorizacoes where id=p_id and status='pendente' for update;
 if not found or not rh_internal.ponto_fichas_approval_valid(a.notificacao_id) then raise exception 'Pergunta indisponível';end if;
 select sent_at into sent from public.rh_admin_notifications where id=a.notificacao_id and whatsapp_status='aceito';
 if sent is null then raise exception 'Pergunta ainda não confirmada';end if;
 update rh_internal.ponto_fichas_polls set claimed=true where id=p_id;
 return jsonb_build_object('kind','poll','chatId',a.recipient_phone||'@c.us','since',floor(extract(epoch from sent)));
end $$;
create function rh_notifications_internal.fichas_poll_complete(p_id uuid,p_token text,p_messages jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare a public.rh_ponto_fichas_autorizacoes;sent timestamptz;msg jsonb;answer text;event_id uuid;localtime timestamp=now() at time zone 'America/Sao_Paulo';begin
 perform 1 from rh_internal.ponto_fichas_polls where id=p_id and token=p_token and expira_em>now() and claimed for update;
 if not found then raise exception 'Consulta inválida';end if;
 if jsonb_typeof(p_messages)<>'array' or jsonb_array_length(p_messages)>50 then raise exception 'Resposta inválida';end if;
 select * into a from public.rh_ponto_fichas_autorizacoes where id=p_id and status='pendente' for update;
 if not found or not rh_internal.ponto_fichas_approval_valid(a.notificacao_id) then raise exception 'Pergunta expirada ou cancelada';end if;
 select sent_at into sent from public.rh_admin_notifications where id=a.notificacao_id and whatsapp_status='aceito';
 if sent is null then raise exception 'Pergunta sem confirmação';end if;
 for msg in select value from jsonb_array_elements(p_messages) order by case when value->>'timestamp' ~ '^[0-9]{9,13}(\.[0-9]+)?$' then (value->>'timestamp')::numeric end nulls last loop
  if msg->>'fromMe' is distinct from 'false' or trim(coalesce(msg->>'body','')) not in('1','2') or coalesce(msg->>'id','')='' or length(msg->>'id')>300 then continue;end if;
  if replace(coalesce(msg->>'from',''),'@s.whatsapp.net','@c.us')<>a.recipient_phone||'@c.us' then continue;end if;
  if msg->>'timestamp' !~ '^[0-9]{9,10}(\.[0-9]+)?$' then continue;end if;
  if (msg->>'timestamp')::numeric<floor(extract(epoch from sent)) or (msg->>'timestamp')::numeric>extract(epoch from least(now()+interval '30 seconds',a.expira_em)) then continue;end if;
  if exists(select 1 from public.rh_ponto_fichas_autorizacoes where resposta_id=msg->>'id') then continue;end if;
  answer=trim(msg->>'body');exit;
 end loop;
 -- Consumir a consulta; nova tentativa só ocorrerá na próxima passagem do agendador.
 update rh_internal.ponto_fichas_polls set expira_em=now() where id=p_id;
 if answer is null then return jsonb_build_object('status','pendente');end if;
 update public.rh_ponto_fichas_autorizacoes set status=case answer when '1' then 'aprovado' else 'recusado' end,resposta_id=msg->>'id',respondido_em=now() where id=p_id;
 insert into public.rh_admin_notifications(source_table,operation,title,message_text,actor_name,details)
 values('ponto_fichas_decisao','RESPOSTA','Autorização de fichas de ponto',case answer when '1' then 'Autorização recebida. Vamos preparar os envios da ficha de ponto manual para a lista informada. Você receberá um resumo dos resultados.' else 'Certo. O envio desta etapa foi cancelado. Nenhuma mensagem será enviada aos colaboradores por esta solicitação.' end,'Sistema',jsonb_build_object('autorizacao',p_id));
 if answer='1' then
  perform rh_internal.ponto_fichas_queue(localtime::date,extract(hour from localtime)::integer);
  perform rh_internal.ponto_fichas_dispatch();
 end if;
 return jsonb_build_object('status',case answer when '1' then 'aprovado' else 'recusado' end);
end $$;
create function public.rh_fichas_poll_claim(p_id uuid,p_token text) returns jsonb language sql security invoker set search_path='' as $$select rh_notifications_internal.fichas_poll_claim(p_id,p_token);$$;
create function public.rh_fichas_poll_complete(p_id uuid,p_token text,p_messages jsonb) returns jsonb language sql security invoker set search_path='' as $$select rh_notifications_internal.fichas_poll_complete(p_id,p_token,p_messages);$$;
revoke all on function rh_notifications_internal.fichas_poll_claim(uuid,text),rh_notifications_internal.fichas_poll_complete(uuid,text,jsonb),public.rh_fichas_poll_claim(uuid,text),public.rh_fichas_poll_complete(uuid,text,jsonb) from public;
grant execute on function rh_notifications_internal.fichas_poll_claim(uuid,text),rh_notifications_internal.fichas_poll_complete(uuid,text,jsonb),public.rh_fichas_poll_claim(uuid,text),public.rh_fichas_poll_complete(uuid,text,jsonb) to anon,authenticated;

do $$declare def text;begin
 select pg_get_functiondef('rh_internal.dispatch_admin_notifications()'::regprocedure) into def;
 execute replace(def,'source_table<>''ponto_fichas''','source_table not in(''ponto_fichas'',''ponto_fichas_autorizacao'')');
 select pg_get_functiondef('rh_notifications_internal.notification_uncertain(uuid,text)'::regprocedure) into def;
 execute replace(def,'n.source_table=''ponto_fichas''','n.source_table in(''ponto_fichas'',''ponto_fichas_autorizacao'')');
end $$;

create or replace function rh_internal.ponto_fichas_tick() returns void language plpgsql security definer set search_path='' as $$
declare localtime timestamp=now() at time zone 'America/Sao_Paulo';begin
 update public.rh_ponto_fichas_autorizacoes set status=case when expira_em<=now() then 'expirado' else 'cancelado' end where status='pendente'
 and (expira_em<=now() or recipient_phone is distinct from rh_internal.ponto_fichas_admin_phone());
 update public.rh_admin_notifications n set whatsapp_status='cancelado',error='Autorização encerrada ou colaborador fora da lista.' from public.rh_ponto_fichas_envios j
 where n.id=j.notificacao_id and n.whatsapp_status in('ficha_pendente','bloqueado','aguardando')
 and (not exists(select 1 from public.rh_ponto_fichas_destinatarios r join public.funcionarios_epi e on e.id=r.funcionario_id where r.funcionario_id=j.funcionario_id and r.criado_em=j.inscricao and e.data_desligamento is null)
 or not exists(select 1 from public.rh_ponto_fichas_autorizacoes a where a.mes=j.mes and a.tipo=j.tipo and a.status='aprovado' and a.expira_em>now()));
 perform rh_internal.ponto_fichas_approval_queue(localtime::date,extract(hour from localtime)::integer);
 perform rh_internal.ponto_fichas_approval_dispatch();perform rh_internal.ponto_fichas_poll_dispatch();
 perform rh_internal.ponto_fichas_queue(localtime::date,extract(hour from localtime)::integer);
 perform rh_internal.ponto_fichas_dispatch();perform rh_internal.ponto_fichas_resumos();
end $$;
revoke all on function rh_internal.ponto_fichas_admin_phone(),rh_internal.ponto_fichas_approval_queue(date,integer),rh_internal.ponto_fichas_base_valid(uuid),rh_internal.ponto_fichas_valid(uuid),rh_internal.ponto_fichas_approval_valid(uuid),rh_internal.ponto_fichas_approval_dispatch(),rh_internal.ponto_fichas_poll_dispatch() from public,anon,authenticated;
notify pgrst,'reload schema';
commit;
