-- Cada colaborador e período gera um aviso por número de WhatsApp.
CREATE OR REPLACE FUNCTION rh_internal.experience_queue()
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  today date := (now() AT TIME ZONE 'America/Sao_Paulo')::date;
  total integer;
BEGIN
  -- Serialize a seleção por número para que execuções simultâneas usem a mesma fila.
  PERFORM pg_advisory_xact_lock(56482219);

  UPDATE public.rh_admin_notifications n
  SET whatsapp_status='cancelado',error='O período ou destinatário deixou de receber este aviso.'
  WHERE n.experience_admission IS NOT NULL AND n.whatsapp_status='experiencia_pendente'
    AND NOT rh_internal.experience_event_valid(n.id);

 insert into public.rh_admin_notifications(employee_id,employee_name,source_table,operation,title,message_text,
 recipient_profile_id,recipient_phone,experience_admission,experience_period,whatsapp_status,actor_name)
 select distinct on(e.id,d.admission,stage.period,p.whatsapp)
 e.id,e.nome,'experiencia','ALERTA',
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
 and not exists(
   select 1 from public.rh_admin_notifications sent
   where sent.employee_id=e.id and sent.experience_admission=d.admission
     and sent.experience_period=stage.period and sent.whatsapp_status<>'cancelado'
     and (sent.recipient_phone=p.whatsapp or sent.recipient_profile_id=p.id)
     and (sent.recipient_profile_id is distinct from p.id or sent.whatsapp_status<>'experiencia_pendente')
 )
 order by e.id,d.admission,stage.period,p.whatsapp,(p.id=e.manager_profile_id) desc nulls last,p.id
 on conflict(employee_id,experience_admission,experience_period,recipient_profile_id) where experience_admission is not null do update
 set recipient_profile_id=excluded.recipient_profile_id,recipient_phone=excluded.recipient_phone,
 message_text=excluded.message_text,employee_name=excluded.employee_name,title=excluded.title,
 whatsapp_status='experiencia_pendente',error=null
 where rh_admin_notifications.whatsapp_status in ('experiencia_pendente','cancelado')
   and rh_admin_notifications.attempts=0;
 get diagnostics total=row_count;return total;
end $function$;

-- Um evento da área também usa cada número elegível uma única vez.
CREATE OR REPLACE FUNCTION rh_internal.enqueue_area_notices() RETURNS trigger
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
  SELECT DISTINCT ON (p.whatsapp) employee.id,employee.nome,'avisos_area',NEW.operation,event_label||' · '||employee.nome,
    jsonb_build_object('evento_origem',NEW.id,'unidade',employee.unidade,'setor',employee.setor),
    'RH PRIME · '||event_label||E'\nColaborador: '||employee.nome
      ||E'\nFilial / setor: '||coalesce(employee.unidade,'—')||' / '||coalesce(employee.setor,'—')
      ||E'\nConsulte o registro no RH PRIME.',
    p.id,p.whatsapp
  FROM public.profiles p WHERE rh_internal.profile_subscribed_to_area(p,employee.unidade,employee.setor)
  ORDER BY p.whatsapp,p.id;
  RETURN NEW;
END $$;
