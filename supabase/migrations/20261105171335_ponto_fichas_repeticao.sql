begin;
alter table public.rh_ponto_fichas_autorizacoes add column tentativas smallint not null default 1 check(tentativas between 1 and 2),
 add column dia_ultima_pergunta date not null default ((now() at time zone 'America/Sao_Paulo')::date),add column envio_ate timestamptz;

-- Uma pergunta por vez evita que a mesma resposta 1 autorize etapas diferentes.
do $$declare def text;begin
 select pg_get_functiondef('rh_internal.ponto_fichas_approval_queue(date,integer)'::regprocedure) into def;
 def=replace(def,'phone=rh_internal.ponto_fichas_admin_phone();',
 'if exists(select 1 from public.rh_ponto_fichas_autorizacoes where status=''pendente'' and expira_em+interval ''10 minutes''>now()) then return 0;end if;
 phone=rh_internal.ponto_fichas_admin_phone();');
 def=replace(def,'p_hoje<>due or (fase=''ficha''',
 'p_hoje<due or (fase=''ficha'' and p_hoje>=(datas->>''parcial'')::date) or (fase=''parcial'' and p_hoje>=(datas->>''final'')::date) or (fase=''ficha''');
 def=replace(def,'notificacao_id,expira_em)','notificacao_id,dia_ultima_pergunta,expira_em)');
 def=replace(def,'people,phone,event_id,(p_hoje+time','people,phone,event_id,p_hoje,(p_hoje+time');
 def=replace(def,'Sem resposta, nada será enviado aos colaboradores.','Sem resposta, repetiremos esta pergunta uma única vez amanhã, às 7h. Se a segunda pergunta também ficar sem resposta até as 18h, esta etapa será encerrada sem envio.');
 def=replace(def,'total=total+1;','total=total+1;return total;');
 execute def;
end $$;

create function rh_internal.ponto_fichas_retry_queue(p_hoje date,p_hora integer) returns integer language plpgsql security definer set search_path='' as $$
declare a public.rh_ponto_fichas_autorizacoes;people jsonb;names text;event_id uuid;phone text;begin
 perform pg_advisory_xact_lock(87111205);
 if p_hora<7 or p_hora>=18 or not exists(select 1 from public.rh_ponto_fichas_config where id and ativo) then return 0;end if;
 if exists(select 1 from public.rh_ponto_fichas_autorizacoes where status='pendente' and expira_em+interval '10 minutes'>now()) then return 0;end if;
 select * into a from public.rh_ponto_fichas_autorizacoes where status='expirado' and tentativas=1 and dia_ultima_pergunta=p_hoje-1 order by criado_em limit 1 for update;
 if not found then return 0;end if;phone=rh_internal.ponto_fichas_admin_phone();if phone is null then return 0;end if;
 select jsonb_agg(jsonb_build_object('id',e.id,'inscricao',r.criado_em) order by e.nome),string_agg('• '||e.nome,E'\n' order by e.nome)
 into people,names from public.rh_ponto_fichas_destinatarios r join public.funcionarios_epi e on e.id=r.funcionario_id
 where e.data_desligamento is null and coalesce(rh_internal.experience_date(e.admissao),p_hoje)<=p_hoje;
 if people is null then update public.rh_ponto_fichas_autorizacoes set status='cancelado' where id=a.id;return 0;end if;
 event_id=gen_random_uuid();
 insert into public.rh_admin_notifications(id,source_table,operation,title,message_text,recipient_phone,whatsapp_status,actor_name,details)
 values(event_id,'ponto_fichas_autorizacao','ULTIMA_PERGUNTA','Última confirmação das fichas de ponto — '||a.tipo,
 'Bom dia! Esta é a última confirmação: deseja '||case a.tipo when 'ficha' then 'enviar as novas fichas de ponto em PDF' when 'parcial' then 'enviar um lembrete solicitando a parcial da ficha de ponto' else 'enviar um lembrete solicitando a ficha de ponto completamente preenchida e assinada' end
 ||' aos colaboradores da lista de ponto manual?'||E'\nCompetência: '||to_char(a.mes,'MM/YYYY')||E'\n\n'||names
 ||E'\n\n1 — Sim, enviar\n2 — Não enviar\n\nResponda apenas 1 ou 2 nesta conversa, até as 18h de hoje. Sem resposta, esta etapa será encerrada sem envio. Não haverá outra repetição desta pergunta.',
 phone,'ficha_autorizacao_pendente','Sistema',jsonb_build_object('autorizacao',a.id,'mes',a.mes,'tipo',a.tipo,'tentativa',2));
 update public.rh_ponto_fichas_autorizacoes set status='pendente',tentativas=2,dia_ultima_pergunta=p_hoje,expira_em=(p_hoje+time '18:00') at time zone 'America/Sao_Paulo',
 destinatarios=people,recipient_phone=phone,notificacao_id=event_id where id=a.id;
 return 1;
end $$;

-- Permite enviar a cobrança final autorizada na repetição do primeiro dia do mês seguinte.
create or replace function rh_internal.ponto_fichas_queue(p_hoje date,p_hora integer) returns integer language plpgsql security definer set search_path='' as $$
declare cfg public.rh_ponto_fichas_config;a record;r record;event_id uuid;due date;phone text;total integer=0;begin
 perform pg_advisory_xact_lock(87111205);select * into cfg from public.rh_ponto_fichas_config where id;
 if not cfg.ativo or p_hora<7 or p_hora>=20 then return 0;end if;
 for a in select * from public.rh_ponto_fichas_autorizacoes where status='aprovado' and coalesce(envio_ate,expira_em)>now() order by criado_em loop
  due=(rh_internal.ponto_fichas_datas(a.mes)->>a.tipo)::date;if p_hoje<due then continue;end if;
  for r in select e.id,e.nome,e.whatsapp,d.criado_em from public.rh_ponto_fichas_destinatarios d join public.funcionarios_epi e on e.id=d.funcionario_id
   where e.data_desligamento is null and coalesce(rh_internal.experience_date(e.admissao),p_hoje)<=p_hoje
   and exists(select 1 from jsonb_array_elements(a.destinatarios)t where t->>'id'=e.id::text and (t->>'inscricao')::timestamptz=d.criado_em) loop
   if exists(select 1 from public.rh_ponto_fichas_envios j where j.funcionario_id=r.id and j.mes=a.mes and j.tipo=a.tipo) then continue;end if;
   phone=rh_internal.ponto_fichas_phone(r.whatsapp);event_id=gen_random_uuid();
   insert into public.rh_admin_notifications(id,employee_id,employee_name,source_table,operation,title,message_text,recipient_phone,whatsapp_status,error,actor_name,details)
   values(event_id,r.id,r.nome,'ponto_fichas','AUTORIZADO','Ficha de ponto — '||a.tipo||': '||r.nome,'Aguardando preparação no momento do envio.',phone,
   case when phone is null then 'bloqueado' else 'ficha_pendente' end,case when phone is null then 'Cadastre um WhatsApp válido com DDD.' end,'Sistema',jsonb_build_object('mes',a.mes,'tipo',a.tipo,'agendado',due,'autorizacao',a.id));
   insert into public.rh_ponto_fichas_envios(funcionario_id,mes,tipo,agendado,inscricao,notificacao_id) values(r.id,a.mes,a.tipo,due,r.criado_em,event_id);total=total+1;
  end loop;
 end loop;return total;
end $$;
create or replace function rh_internal.ponto_fichas_base_valid(p_id uuid) returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.rh_ponto_fichas_envios j join public.rh_ponto_fichas_destinatarios r on r.funcionario_id=j.funcionario_id and r.criado_em=j.inscricao
 join public.funcionarios_epi e on e.id=r.funcionario_id join public.rh_admin_notifications n on n.id=j.notificacao_id cross join public.rh_ponto_fichas_config c
 where n.id=p_id and n.source_table='ponto_fichas' and c.id and c.ativo and e.data_desligamento is null
 and rh_internal.ponto_fichas_phone(e.whatsapp)=n.recipient_phone and (now() at time zone 'America/Sao_Paulo')::date>=j.agendado)
$$;

-- A consulta após as 18h só aceita respostas que chegaram antes do prazo; não é prazo extra.
do $$declare def text;begin
 select pg_get_functiondef('rh_internal.ponto_fichas_valid(uuid)'::regprocedure) into def;
 execute replace(def,'a.expira_em>now()','coalesce(a.envio_ate,a.expira_em)>now()');
 select pg_get_functiondef('rh_internal.ponto_fichas_approval_valid(uuid)'::regprocedure) into def;
 execute replace(def,'a.expira_em>now()','a.expira_em+interval ''10 minutes''>now()');
 select pg_get_functiondef('rh_internal.ponto_fichas_poll_dispatch()'::regprocedure) into def;
 execute replace(def,'x.expira_em>now()','x.expira_em+interval ''10 minutes''>now()');
 select pg_get_functiondef('rh_notifications_internal.fichas_poll_complete(uuid,text,jsonb)'::regprocedure) into def;
 execute replace(def,'respondido_em=now() where id=p_id','respondido_em=now(),envio_ate=case answer when ''1'' then greatest(a.expira_em,now()+interval ''30 minutes'') end where id=p_id');
 select pg_get_functiondef('rh_internal.ponto_fichas_resumos()'::regprocedure) into def;
 execute replace(def,'j.mes=date_trunc(''month'',now() at time zone ''America/Sao_Paulo'')::date','n.created_at>now()-interval ''7 days''');
 select pg_get_functiondef('rh_internal.ponto_fichas_approval_dispatch()'::regprocedure) into def;
 execute replace(def,'and rh_internal.ponto_fichas_approval_valid(id)','and rh_internal.ponto_fichas_approval_valid(id) and exists(select 1 from public.rh_ponto_fichas_autorizacoes a where a.notificacao_id=rh_admin_notifications.id and a.expira_em>now())');
end $$;

create or replace function rh_internal.ponto_fichas_tick() returns void language plpgsql security definer set search_path='' as $$
declare v_local_time timestamp=now() at time zone 'America/Sao_Paulo';begin
 update public.rh_ponto_fichas_autorizacoes set status=case when expira_em+interval '10 minutes'<=now() then 'expirado' else 'cancelado' end where status='pendente'
 and (expira_em+interval '10 minutes'<=now() or recipient_phone is distinct from rh_internal.ponto_fichas_admin_phone());
 update public.rh_admin_notifications n set whatsapp_status='cancelado',error='Autorização encerrada ou colaborador fora da lista.' from public.rh_ponto_fichas_envios j
 where n.id=j.notificacao_id and n.whatsapp_status in('ficha_pendente','bloqueado','aguardando')
 and (not exists(select 1 from public.rh_ponto_fichas_destinatarios r join public.funcionarios_epi e on e.id=r.funcionario_id where r.funcionario_id=j.funcionario_id and r.criado_em=j.inscricao and e.data_desligamento is null)
 or not exists(select 1 from public.rh_ponto_fichas_autorizacoes a where a.mes=j.mes and a.tipo=j.tipo and a.status='aprovado' and coalesce(a.envio_ate,a.expira_em)>now()));
 update public.rh_admin_notifications n set whatsapp_status='cancelado',error='Pergunta expirada ou cancelada; nenhum envio autorizado.' from public.rh_ponto_fichas_autorizacoes a
 where a.notificacao_id=n.id and a.status in('expirado','cancelado','recusado') and n.whatsapp_status in('ficha_autorizacao_pendente','aguardando');
 perform rh_internal.ponto_fichas_retry_queue(v_local_time::date,extract(hour from v_local_time)::integer);
 perform rh_internal.ponto_fichas_approval_queue(v_local_time::date,extract(hour from v_local_time)::integer);
 perform rh_internal.ponto_fichas_approval_dispatch();perform rh_internal.ponto_fichas_poll_dispatch();
 perform rh_internal.ponto_fichas_queue(v_local_time::date,extract(hour from v_local_time)::integer);
 perform rh_internal.ponto_fichas_dispatch();perform rh_internal.ponto_fichas_resumos();
end $$;
revoke all on function rh_internal.ponto_fichas_retry_queue(date,integer) from public,anon,authenticated;
notify pgrst,'reload schema';
commit;
