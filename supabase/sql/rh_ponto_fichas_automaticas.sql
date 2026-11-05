-- Fichas e cobranças recorrentes. Datas e relógio de America/Sao_Paulo.
begin;
create table public.rh_ponto_fichas_config (
 id boolean primary key default true check(id), ativo boolean not null default true,
 inicio date not null default '2026-11-01', pdf_desde date not null default '2026-12-01',
 hora integer not null default 9 check(hora between 7 and 17)
);
insert into public.rh_ponto_fichas_config(id) values(true);
alter table public.rh_ponto_fichas_config enable row level security;
revoke all on public.rh_ponto_fichas_config from public,anon,authenticated;
grant select,update on public.rh_ponto_fichas_config to authenticated;
create policy fichas_config_admin on public.rh_ponto_fichas_config for all to authenticated
 using((select rh_internal.is_admin())) with check((select rh_internal.is_admin()));

create table public.rh_ponto_fichas_envios (
 id uuid primary key default gen_random_uuid(), funcionario_id uuid not null references public.funcionarios_epi(id),
 mes date not null check(extract(day from mes)=1), tipo text not null check(tipo in ('ficha','parcial','final')),
 agendado date not null, inscricao timestamptz not null, notificacao_id uuid unique references public.rh_admin_notifications(id),
 criado_em timestamptz not null default now(), unique(funcionario_id,mes,tipo)
);
alter table public.rh_ponto_fichas_envios enable row level security;
revoke all on public.rh_ponto_fichas_envios from public,anon,authenticated;
grant select on public.rh_ponto_fichas_envios to authenticated;
create policy fichas_envios_admin on public.rh_ponto_fichas_envios for select to authenticated using((select rh_internal.is_admin()));
create table rh_internal.ponto_fichas_runtime(id boolean primary key default true check(id),webhook_url text);
alter table rh_internal.ponto_fichas_runtime enable row level security;
revoke all on rh_internal.ponto_fichas_runtime from public,anon,authenticated;
insert into rh_internal.ponto_fichas_runtime(id) values(true);

create function rh_internal.ponto_fichas_util(d date) returns boolean
language plpgsql immutable set search_path='' as $$
declare y integer=extract(year from d);a integer;b integer;c integer;dd integer;e integer;f integer;g integer;h integer;i integer;k integer;l integer;m integer;pascoa date;
begin
 if extract(isodow from d)>5 or to_char(d,'MM-DD') in('01-01','04-21','05-01','07-02','09-07','10-12','11-02','11-15','12-25')
 or (y>=2024 and to_char(d,'MM-DD')='11-20') then return false;end if;
 a=y%19;b=y/100;c=y%100;dd=b/4;e=b%4;f=(b+8)/25;g=(b-f+1)/3;h=(19*a+b-dd-g+15)%30;i=c/4;k=c%4;
 l=(32+2*e+2*i-h-k)%7;m=(a+11*h+22*l)/451;pascoa=make_date(y,(h+l-7*m+114)/31,(h+l-7*m+114)%31+1);
 return d<>pascoa-2;
end $$;
create function rh_internal.ponto_fichas_datas(p_mes date) returns jsonb
language sql immutable set search_path='' as $$
 with dias as(select d::date d from generate_series(date_trunc('month',p_mes)::date,(date_trunc('month',p_mes)+interval '1 month -1 day')::date,interval '1 day') d),uteis as(select d from dias where rh_internal.ponto_fichas_util(d))
 select jsonb_build_object('ficha',min(d),'final',max(d),'parcial',(select d from uteis order by abs(d-(date_trunc('month',p_mes)::date+14)),d desc limit 1)) from uteis
$$;
create function public.rh_ponto_fichas_datas(p_mes date) returns jsonb language sql security invoker set search_path='' as $$select rh_internal.ponto_fichas_datas(p_mes);$$;
revoke all on function rh_internal.ponto_fichas_util(date),rh_internal.ponto_fichas_datas(date),public.rh_ponto_fichas_datas(date) from public,anon,authenticated;
grant execute on function rh_internal.ponto_fichas_util(date),rh_internal.ponto_fichas_datas(date),public.rh_ponto_fichas_datas(date) to authenticated;

-- Um telefone inválido bloqueia apenas aquele destinatário, sem interromper os demais.
create function rh_internal.ponto_fichas_phone(v text) returns text language plpgsql immutable set search_path='' as $$
declare p text=regexp_replace(coalesce(v,''),'[^0-9]','','g');begin
 if length(p) in(10,11) then p='55'||p;end if;
 return case when p ~ '^55[1-9][0-9][0-9]{8,9}$' then p end;
end $$;
create function rh_internal.ponto_fichas_queue(p_hoje date,p_hora integer) returns integer language plpgsql security definer set search_path='' as $$
declare cfg public.rh_ponto_fichas_config;v_mes date=date_trunc('month',p_hoje)::date;datas jsonb;r record;fase text;due date;event_id uuid;total integer=0;phone text;
begin
 perform pg_advisory_xact_lock(87111205);
 select * into cfg from public.rh_ponto_fichas_config where id;
 if not cfg.ativo or p_hoje<cfg.inicio or p_hora<cfg.hora or p_hora>=18 then return 0;end if;
 datas=rh_internal.ponto_fichas_datas(v_mes);
 foreach fase in array array['ficha','parcial','final'] loop
  due=(datas->>fase)::date;
  if p_hoje<due or (fase='ficha' and (v_mes<cfg.pdf_desde or p_hoje>=(datas->>'parcial')::date))
   or (fase='parcial' and p_hoje>=(datas->>'final')::date) then continue;end if;
  for r in select e.id,e.nome,e.whatsapp,d.criado_em from public.rh_ponto_fichas_destinatarios d join public.funcionarios_epi e on e.id=d.funcionario_id
   where e.data_desligamento is null and coalesce(rh_internal.experience_date(e.admissao),p_hoje)<=p_hoje loop
   if exists(select 1 from public.rh_ponto_fichas_envios j where j.funcionario_id=r.id and j.mes=v_mes and j.tipo=fase) then continue;end if;
   phone=rh_internal.ponto_fichas_phone(r.whatsapp);event_id=gen_random_uuid();
   insert into public.rh_admin_notifications(id,employee_id,employee_name,source_table,operation,title,message_text,recipient_phone,whatsapp_status,error,actor_name,details)
   values(event_id,r.id,r.nome,'ponto_fichas','AGENDADO','Ficha de ponto — '||fase||': '||r.nome,'Aguardando preparação no momento do envio.',phone,
   case when phone is null then 'bloqueado' else 'ficha_pendente' end,case when phone is null then 'Cadastre um WhatsApp válido com DDD.' end,'Sistema',jsonb_build_object('mes',v_mes,'tipo',fase,'agendado',due));
   insert into public.rh_ponto_fichas_envios(funcionario_id,mes,tipo,agendado,inscricao,notificacao_id) values(r.id,v_mes,fase,due,r.criado_em,event_id);total=total+1;
  end loop;
 end loop;return total;
end $$;

create function rh_internal.ponto_fichas_valid(p_id uuid) returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.rh_ponto_fichas_envios j join public.rh_ponto_fichas_destinatarios r on r.funcionario_id=j.funcionario_id and r.criado_em=j.inscricao
 join public.funcionarios_epi e on e.id=r.funcionario_id join public.rh_admin_notifications n on n.id=j.notificacao_id
 cross join public.rh_ponto_fichas_config c
 where n.id=p_id and c.id and c.ativo and e.data_desligamento is null
 and rh_internal.ponto_fichas_phone(e.whatsapp)=n.recipient_phone
 and (now() at time zone 'America/Sao_Paulo')::date>=j.agendado
 and date_trunc('month',now() at time zone 'America/Sao_Paulo')::date=j.mes
 and extract(hour from now() at time zone 'America/Sao_Paulo') between c.hora and 17
 and (j.tipo<>'ficha' or (now() at time zone 'America/Sao_Paulo')::date<(rh_internal.ponto_fichas_datas(j.mes)->>'parcial')::date)
 and (j.tipo<>'parcial' or (now() at time zone 'America/Sao_Paulo')::date<(rh_internal.ponto_fichas_datas(j.mes)->>'final')::date))
$$;

create function rh_internal.ponto_fichas_dispatch() returns void language plpgsql security definer set search_path='' as $$
declare n record;url text;token text;begin
 select webhook_url into url from rh_internal.ponto_fichas_runtime where id;
 if url is null then return;end if;
 update public.rh_admin_notifications set whatsapp_status='incerto',error='Sem confirmação do WhatsApp. Confira o n8n antes de reenviar.' where source_table='ponto_fichas' and whatsapp_status='enviando' and last_attempt_at<now()-interval '15 minutes';
 update public.rh_admin_notifications set whatsapp_status='falha',error='O n8n não confirmou o início após três tentativas.' where source_table='ponto_fichas' and whatsapp_status='aguardando' and attempts>=3 and last_attempt_at<now()-interval '11 minutes';
 -- Revalidar o contato antes de emitir uma capacidade; nunca reaproveitar um envio já iniciado.
 update public.rh_admin_notifications n set recipient_phone=rh_internal.ponto_fichas_phone(e.whatsapp),whatsapp_status=case when rh_internal.ponto_fichas_phone(e.whatsapp) is null then 'bloqueado' else 'ficha_pendente' end,error=case when rh_internal.ponto_fichas_phone(e.whatsapp) is null then 'Cadastre um WhatsApp válido com DDD.' end
 from public.rh_ponto_fichas_envios j join public.rh_ponto_fichas_destinatarios r on r.funcionario_id=j.funcionario_id and r.criado_em=j.inscricao join public.funcionarios_epi e on e.id=j.funcionario_id
 where n.id=j.notificacao_id and n.whatsapp_status in('bloqueado','ficha_pendente') and (n.recipient_phone is distinct from rh_internal.ponto_fichas_phone(e.whatsapp) or (n.whatsapp_status='bloqueado' and rh_internal.ponto_fichas_phone(e.whatsapp) is not null));
 for n in select id from public.rh_admin_notifications where source_table='ponto_fichas' and attempts<3
 and (whatsapp_status='ficha_pendente' or (whatsapp_status='aguardando' and last_attempt_at<now()-interval '11 minutes'))
 and rh_internal.ponto_fichas_valid(id) order by created_at limit 10 for update skip locked loop
  token=encode(extensions.gen_random_bytes(32),'hex');
  insert into rh_internal.notification_dispatch(id,token,expires_at) values(n.id,token,now()+interval '10 minutes')
  on conflict(id) do update set token=excluded.token,expires_at=excluded.expires_at,claimed=false;
  perform net.http_post(url:=url,body:=jsonb_build_object('eventId',n.id,'eventToken',token),headers:='{"Content-Type":"application/json"}'::jsonb,timeout_milliseconds:=15000);
  update public.rh_admin_notifications set whatsapp_status='aguardando',last_attempt_at=now(),attempts=attempts+1 where id=n.id;
 end loop;
end $$;

-- O fluxo administrativo original preserva suas regras. Fichas usam uma capacidade própria.
alter function rh_notifications_internal.notification_claim(uuid,text) rename to notification_previous_claim;
create function rh_notifications_internal.notification_claim(p_id uuid,p_token text) returns jsonb language plpgsql security definer set search_path='' as $$
declare n public.rh_admin_notifications;j public.rh_ponto_fichas_envios;e public.funcionarios_epi;c public.empresas;r public.rh_ponto_fichas_destinatarios;msg text;greeting text;localtime timestamp=now() at time zone 'America/Sao_Paulo';wanted text;outcome jsonb;
begin
 select * into n from public.rh_admin_notifications where id=p_id;
 if n.source_table is distinct from 'ponto_fichas' then return rh_notifications_internal.notification_previous_claim(p_id,p_token);end if;
 if p_token is null or length(p_token)<>64 then raise exception 'Evento inválido';end if;
 perform 1 from rh_internal.notification_dispatch where id=p_id and token=p_token and expires_at>now() and not claimed for update;
 if not found then raise exception 'Evento expirado ou já processado';end if;
 select * into n from public.rh_admin_notifications where id=p_id and whatsapp_status='aguardando' for update;
 if not found or not rh_internal.ponto_fichas_valid(p_id) then raise exception 'Colaborador, lista ou prazo mudou; envio cancelado';end if;
 select * into j from public.rh_ponto_fichas_envios where notificacao_id=p_id;
 select * into e from public.funcionarios_epi where id=j.funcionario_id;
 select * into r from public.rh_ponto_fichas_destinatarios where funcionario_id=e.id for share;
 greeting=case when extract(hour from localtime)<12 then 'Bom dia' when extract(hour from localtime)<18 then 'Boa tarde' else 'Boa noite' end;
 msg=greeting||', '||initcap(split_part(btrim(e.nome),' ',1))||'!';
 msg=msg||case j.tipo when 'parcial' then E'\n\nPassando para solicitar o envio da parcial dos seus registros de ponto de '||to_char(j.mes,'MM/YYYY')||'. Por favor, envie ao RH uma foto ou cópia legível da ficha preenchida até o momento.'
 when 'final' then E'\n\nPassando para solicitar o envio da sua ficha de ponto de '||to_char(j.mes,'MM/YYYY')||' completamente preenchida e assinada. Se ainda houver expediente hoje, conclua os registros após a saída e encaminhe a ficha ao RH.'
 else E'\n\nSegue sua ficha de ponto de '||to_char(j.mes,'MM/YYYY')||' para preenchimento diário dos horários reais e assinatura. Guarde a ficha: solicitaremos uma parcial no meio do mês e a ficha completa no último dia útil.' end||E'\n\nObrigado!\nPRIME RH';
 outcome=jsonb_build_object('eventId',p_id,'chatId',n.recipient_phone||'@c.us','message',msg,'kind',j.tipo);
 if j.tipo='ficha' then
  if e.empresa_id is not null then select * into c from public.empresas where id=e.empresa_id;
  else
   wanted=case when upper(e.local_registro) like '%NUNES%' then '48986353000139' when upper(e.local_registro) like '%JEQUI%' then '52522019000282' when upper(e.local_registro) like '%PRIME%' then '52522019000100' else regexp_replace(coalesce(e.local_registro,''),'[^0-9]','','g') end;
   select * into c from public.empresas where regexp_replace(cnpj,'[^0-9]','','g')=wanted;
  end if;
  if c.id is null or nullif(trim(e.funcao),'') is null or length(regexp_replace(coalesce(e.cpf,''),'[^0-9]','','g'))<>11 then raise exception 'Complete empresa, função e CPF antes de gerar a ficha';end if;
  outcome=outcome||jsonb_build_object('sheet',jsonb_build_object('month',to_char(j.mes,'YYYY-MM'),'employee',jsonb_build_object('nome',e.nome,'funcao',e.funcao,'cpf',e.cpf),'company',jsonb_build_object('nome',c.nome,'cnpj',c.cnpj),'city',r.cidade_trabalho));
 end if;
 update rh_internal.notification_dispatch set claimed=true where id=p_id;
 update public.rh_admin_notifications set whatsapp_status='enviando',message_text=msg where id=p_id;
 return outcome;
end $$;
create or replace function public.rh_notification_claim(p_id uuid,p_token text) returns jsonb language sql security invoker set search_path='' as $$select rh_notifications_internal.notification_claim(p_id,p_token);$$;
revoke all on function rh_notifications_internal.notification_previous_claim(uuid,text),rh_notifications_internal.notification_claim(uuid,text) from public,anon,authenticated;
grant execute on function rh_notifications_internal.notification_claim(uuid,text) to anon,authenticated;

create function rh_notifications_internal.notification_uncertain(p_id uuid,p_token text) returns void language plpgsql security definer set search_path='' as $$begin
 if not exists(select 1 from rh_internal.notification_dispatch d join public.rh_admin_notifications n on n.id=d.id
 where d.id=p_id and d.token=p_token and d.claimed and d.expires_at>now() and n.source_table='ponto_fichas') then raise exception 'Evento inválido';end if;
 update public.rh_admin_notifications set whatsapp_status='incerto',error='O WhatsApp respondeu sem identificação da mensagem. Confira o n8n antes de reenviar.' where id=p_id and whatsapp_status='enviando';
 delete from rh_internal.notification_dispatch where id=p_id;
end $$;
create function public.rh_notification_uncertain(p_id uuid,p_token text) returns void language sql security invoker set search_path='' as $$select rh_notifications_internal.notification_uncertain(p_id,p_token);$$;
revoke all on function rh_notifications_internal.notification_uncertain(uuid,text),public.rh_notification_uncertain(uuid,text) from public;
grant execute on function rh_notifications_internal.notification_uncertain(uuid,text),public.rh_notification_uncertain(uuid,text) to anon,authenticated;

-- Impede que os disparadores gerais capturem fichas para outro destinatário.
do $$declare def text;begin
 select pg_get_functiondef('rh_internal.dispatch_admin_notifications()'::regprocedure) into def;
 if position('where experience_admission is null and (' in def)=0 then raise exception 'Formato inesperado do disparador administrativo';end if;
 execute replace(def,'where experience_admission is null and (','where source_table<>''ponto_fichas'' and experience_admission is null and (');
end $$;

create function rh_internal.ponto_fichas_removed() returns trigger language plpgsql security definer set search_path='' as $$begin
 update public.rh_admin_notifications n set whatsapp_status='cancelado',error='Colaborador retirado da lista de fichas.' from public.rh_ponto_fichas_envios j
 where j.notificacao_id=n.id and j.funcionario_id=old.funcionario_id and n.whatsapp_status in('ficha_pendente','bloqueado','aguardando');
 delete from rh_internal.notification_dispatch d using public.rh_admin_notifications n where d.id=n.id and n.source_table='ponto_fichas' and n.employee_id=old.funcionario_id and not d.claimed;
 return old;end $$;
create trigger ponto_fichas_removed after delete on public.rh_ponto_fichas_destinatarios for each row execute function rh_internal.ponto_fichas_removed();

-- Um resumo por etapa, depois dos resultados; aceita atraso sem repetir mensagens.
create unique index ponto_fichas_resumo_unique on public.rh_admin_notifications((details->>'mes'),(details->>'tipo')) where source_table='ponto_fichas_resumo';
create function rh_internal.ponto_fichas_resumos() returns integer language plpgsql security definer set search_path='' as $$
declare batch record;msg text;total integer=0;begin
 for batch in select j.mes,j.tipo,min(n.created_at) started,
 count(*) total,count(*) filter(where n.whatsapp_status='aceito') aceitos,
 count(*) filter(where n.whatsapp_status in('ficha_pendente','aguardando','enviando')) pendentes,
 string_agg(n.employee_name||': '||case n.whatsapp_status when 'aceito' then 'aceito pelo WhatsApp' when 'falha' then 'falha' when 'incerto' then 'conferir envio incerto' when 'bloqueado' then 'cadastro incompleto' when 'cancelado' then 'cancelado' else 'aguardando confirmação' end,E'\n' order by n.employee_name) linhas
 from public.rh_ponto_fichas_envios j join public.rh_admin_notifications n on n.id=j.notificacao_id
 where n.source_table='ponto_fichas' and j.mes=date_trunc('month',now() at time zone 'America/Sao_Paulo')::date
 and not exists(select 1 from public.rh_admin_notifications s where s.source_table='ponto_fichas_resumo' and s.details->>'mes'=j.mes::text and s.details->>'tipo'=j.tipo)
 group by j.mes,j.tipo loop
  if batch.started>now()-interval '10 minutes' or (batch.pendentes>0 and batch.started>now()-interval '1 hour') then continue;end if;
  msg='Bom dia! PRIME RH — Fichas de ponto '||to_char(batch.mes,'MM/YYYY')||E'\nEtapa: '||case batch.tipo when 'ficha' then 'envio da nova ficha' when 'parcial' then 'solicitação da parcial' else 'solicitação da ficha completa' end
  ||E'\n\nAceitos pelo WhatsApp: '||batch.aceitos||' de '||batch.total||E'\n\n'||batch.linhas||E'\n\nAcompanhe a devolução das fichas com os colaboradores. Aceite de envio não confirma leitura nem recebimento da ficha preenchida.';
  insert into public.rh_admin_notifications(source_table,operation,title,message_text,details,actor_name)
  values('ponto_fichas_resumo','RESUMO','Resumo das fichas de ponto — '||batch.tipo,msg,jsonb_build_object('mes',batch.mes,'tipo',batch.tipo),'Sistema') on conflict do nothing;
  total=total+1;
 end loop;return total;
end $$;

create function rh_internal.ponto_fichas_tick() returns void language plpgsql security definer set search_path='' as $$
declare localtime timestamp=now() at time zone 'America/Sao_Paulo';begin
 perform rh_internal.ponto_fichas_queue(localtime::date,extract(hour from localtime)::integer);
 perform rh_internal.ponto_fichas_dispatch();perform rh_internal.ponto_fichas_resumos();
end $$;
revoke all on function rh_internal.ponto_fichas_phone(text),rh_internal.ponto_fichas_queue(date,integer),rh_internal.ponto_fichas_valid(uuid),rh_internal.ponto_fichas_dispatch(),rh_internal.ponto_fichas_removed(),rh_internal.ponto_fichas_resumos(),rh_internal.ponto_fichas_tick() from public,anon,authenticated;

create view public.rh_ponto_fichas_historico with(security_invoker=true) as
 select j.id,j.funcionario_id,j.mes,j.tipo,j.agendado,n.whatsapp_status status,n.sent_at enviado_em,n.error erro,n.employee_name nome
 from public.rh_ponto_fichas_envios j join public.rh_admin_notifications n on n.id=j.notificacao_id;
revoke all on public.rh_ponto_fichas_historico from public,anon;
grant select on public.rh_ponto_fichas_historico to authenticated;
select cron.schedule('rh_ponto_fichas','*/5 * * * *','select rh_internal.ponto_fichas_tick()');
notify pgrst,'reload schema';
commit;
