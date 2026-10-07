-- Aplicar após rh_experiencia.sql: dois avisos independentes, aos 38 e 83 dias.
begin;
alter table public.rh_admin_notifications add column experience_period smallint;
-- Avisos legados de 90 dias pertencem ao segundo período; preservar os já enviados.
update public.rh_admin_notifications set experience_period=2 where experience_admission is not null;
alter table public.rh_admin_notifications add constraint experience_period_valid check
 ((experience_admission is null and experience_period is null) or
  (experience_admission is not null and experience_period is not null and experience_period in (1,2)));
drop index public.experience_notice_contract;
create unique index experience_notice_contract_period
 on public.rh_admin_notifications(employee_id,experience_admission,experience_period)
 where experience_admission is not null;

-- Recalcular mensagens pendentes segundo a nova regra, invalidando capacidades antigas.
delete from rh_internal.notification_dispatch d using public.rh_admin_notifications n
 where n.id=d.id and n.experience_admission is not null
 and n.whatsapp_status in ('experiencia_pendente','aguardando') and not d.claimed;
update public.rh_admin_notifications set whatsapp_status='experiencia_pendente',attempts=0,last_attempt_at=null
 where experience_admission is not null and whatsapp_status='aguardando'
 and not exists(select 1 from rh_internal.notification_dispatch d where d.id=rh_admin_notifications.id and d.claimed);

create or replace function rh_internal.experience_queue() returns integer
 language plpgsql security definer set search_path='' as $$
declare today date=(now() at time zone 'America/Sao_Paulo')::date;total integer;begin
 insert into public.rh_admin_notifications(employee_id,employee_name,source_table,operation,title,message_text,
 recipient_profile_id,recipient_phone,experience_admission,experience_period,whatsapp_status,actor_name)
 select e.id,e.nome,'experiencia','ALERTA',
 'Experiência — '||stage.period::text||'º período próximo do fim: '||e.nome,
 '*PRIME RH | Contrato de experiência*'||E'\n\nOlá, '||coalesce(p.name,'gestor')||'!'
 ||E'\nO '||stage.period::text||'º período de experiência do colaborador abaixo está próximo do término.'
 ||E'\n\n*Colaborador:* '||e.nome||E'\n*Função:* '||coalesce(e.funcao,'Não informada')
 ||E'\n*Filial / setor:* '||coalesce(e.unidade,'—')||' / '||coalesce(e.setor,'—')
 ||E'\n*Admissão:* '||to_char(d.admission,'DD/MM/YYYY')
 ||E'\n*Período:* '||stage.period::text||'º de 45 dias (total: 90 dias)'
 ||E'\n*Término do '||stage.period::text||'º período:* '||to_char(d.admission+stage.deadline,'DD/MM/YYYY')
 ||E'\n*Dias restantes neste período:* '||(d.admission+stage.deadline-today)::text
 ||case when stage.period=1 then
 E'\n\nPor favor, avalie o colaborador e alinhe com o RH as providências para o término do primeiro período.'
 else E'\n\nPor favor, conclua a avaliação e alinhe com o RH as providências antes do término total da experiência.' end
 ||E'\n\nAcesse: https://dasksz.github.io/RH-PRIME/colaboradores.html',
 p.id,p.whatsapp,d.admission,stage.period,'experiencia_pendente','Sistema'
 from public.funcionarios_epi e join public.profiles p on p.id=e.manager_profile_id
 cross join lateral (select rh_internal.experience_date(e.admissao) admission) d
 cross join (values(1::smallint,38,45),(2::smallint,83,90)) stage(period,alert_day,deadline)
 where e.data_desligamento is null and today>=d.admission+stage.alert_day and today<d.admission+stage.deadline
 and p.experience_notifications and p.whatsapp<>''
 and rh_internal.experience_manager_allowed(p.id,e.unidade,e.setor)
 on conflict(employee_id,experience_admission,experience_period) where experience_admission is not null do update
 set recipient_profile_id=excluded.recipient_profile_id,recipient_phone=excluded.recipient_phone,
 message_text=excluded.message_text,employee_name=excluded.employee_name,title=excluded.title
 where rh_admin_notifications.whatsapp_status='experiencia_pendente';
 get diagnostics total=row_count;return total;
end $$;

create or replace function rh_internal.experience_event_valid(p_id uuid) returns boolean
 language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.rh_admin_notifications n
 join public.funcionarios_epi e on e.id=n.employee_id join public.profiles p on p.id=n.recipient_profile_id
 where n.id=p_id and n.experience_admission is not null and n.experience_period in (1,2)
 and e.manager_profile_id=p.id and rh_internal.experience_date(e.admissao)=n.experience_admission
 and e.data_desligamento is null
 and (now() at time zone 'America/Sao_Paulo')::date>=n.experience_admission+
 case n.experience_period when 1 then 38 else 83 end
 and (now() at time zone 'America/Sao_Paulo')::date<n.experience_admission+
 case n.experience_period when 1 then 45 else 90 end
 and p.experience_notifications and p.whatsapp<>'' and p.whatsapp=n.recipient_phone
 and rh_internal.experience_manager_allowed(p.id,e.unidade,e.setor))
 $$;
revoke all on function rh_internal.experience_queue(),rh_internal.experience_event_valid(uuid) from public,anon,authenticated;
-- Renova textos e datas dos avisos elegíveis antes que o disparador os processe.
select rh_internal.experience_queue();
notify pgrst,'reload schema';
commit;

