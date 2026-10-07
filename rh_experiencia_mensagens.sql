-- Primeiro nome do gestor no cumprimento; mensagens sem link para o sistema.
begin;
create or replace function rh_internal.experience_queue() returns integer
 language plpgsql security definer set search_path='' as $$
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

revoke all on function rh_internal.experience_queue() from public,anon,authenticated;
select rh_internal.experience_queue();
commit;
