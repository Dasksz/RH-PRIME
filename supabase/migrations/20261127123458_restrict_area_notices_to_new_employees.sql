CREATE OR REPLACE FUNCTION rh_internal.enqueue_area_notices()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  employee public.funcionarios_epi;
  event_label text;
BEGIN
  IF NEW.source_table IS DISTINCT FROM 'funcionarios_epi'
     OR NEW.operation IS DISTINCT FROM 'INSERT'
     OR NEW.employee_id IS NULL THEN
    RETURN NEW;
  END IF;
  event_label:='Inclusão de colaborador';
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
END $function$;

CREATE OR REPLACE FUNCTION rh_internal.area_notice_valid(p_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE
 SET search_path TO ''
AS $function$
  SELECT EXISTS(
    SELECT 1 FROM public.rh_admin_notifications n
    JOIN public.rh_admin_notifications origin ON origin.id::text=n.details->>'evento_origem'
      AND origin.source_table='funcionarios_epi' AND origin.operation='INSERT'
      AND origin.employee_id=n.employee_id
    JOIN public.funcionarios_epi e ON e.id=n.employee_id
    JOIN public.profiles p ON p.id=n.recipient_profile_id
    WHERE n.id=p_id AND n.source_table='avisos_area' AND n.operation='INSERT' AND n.recipient_phone=p.whatsapp
      AND (n.details->>'unidade') IS NOT DISTINCT FROM e.unidade
      AND (n.details->>'setor') IS NOT DISTINCT FROM e.setor
      AND rh_internal.profile_subscribed_to_area(p,e.unidade,e.setor)
  )
$function$;

CREATE OR REPLACE FUNCTION rh_internal.notify_admin_event()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare before_row jsonb;after_row jsonb;record_row jsonb;diff jsonb='{}';k text;actor text;employee uuid;person text;title text;msg text;begin
 if tg_table_name<>'profiles' and (auth.uid() is null or pg_trigger_depth()>1) then return coalesce(new,old);end if;
 -- Novos cadastros de acesso e de colaboradores também geram avisos quando aplicável.
 if not (tg_table_name in ('profiles','funcionarios_epi') and tg_op='INSERT') and rh_internal.is_admin() then return coalesce(new,old);end if;
 if tg_op='UPDATE' and new is not distinct from old then return new;end if;
 before_row=case when tg_op<>'INSERT' then to_jsonb(old) else '{}' end;after_row=case when tg_op<>'DELETE' then to_jsonb(new) else '{}' end;record_row=case when tg_op='DELETE' then before_row else after_row end;
 if not coalesce((select case when tg_table_name='profiles' and tg_op='INSERT' then notify_new_access else notify_changes end from public.rh_notification_settings where id),false) then return coalesce(new,old);end if;
 select coalesce(name,email) into actor from public.profiles where id=auth.uid();actor=coalesce(actor,'Novo cadastro');
 employee=nullif(record_row->>'funcionario_id','')::uuid;
 if tg_table_name='funcionarios_epi' then employee=(record_row->>'id')::uuid;end if;
 if tg_table_name in ('rh_ferias_lancamentos','rh_ferias_documentos') then select funcionario_id into employee from public.rh_ferias_periodos where id=(record_row->>'periodo_id')::uuid;end if;
 if employee is not null then select nome into person from public.funcionarios_epi where id=employee;end if;
 person=coalesce(person,record_row->>'funcionario_nome',record_row->>'nome',record_row->>'name','');
 for k in select key from jsonb_object_keys(before_row||after_row) as key loop
  if before_row->k is distinct from after_row->k and k not in ('updated_at','created_at','access_version') then diff=diff||jsonb_build_object(k,jsonb_build_object('antes',before_row->k,'depois',after_row->k));end if;
 end loop;
 if diff='{}' then return coalesce(new,old);end if;
 title=case when tg_table_name='profiles' and tg_op='INSERT' then 'Novo cadastro: '||person when tg_table_name='rh_absenteismo' then 'Registro de falta/atestado: '||person when tg_table_name='profiles' then 'Perfil atualizado: '||person when tg_table_name like 'rh_ferias%' then 'Férias atualizadas: '||person else 'Alteração em '||tg_table_name||': '||person end;
 msg='RH PRIME — '||title||E'\nResponsável: '||actor||E'\nOperação: '||tg_op;
 if tg_table_name='profiles' and tg_op='INSERT' then msg=msg||E'\nE-mail: '||coalesce(record_row->>'email','')||E'\nAguardando aprovação.';end if;
 for k in select key from jsonb_object_keys(diff) as key loop
  if k in ('data_inicio','data_fim','mes_ref','horas_perdidas','status','unidade','setor','role','access_mode','access_level','data_desligamento','inicio','fim','dias','tipo','assinatura_status') then msg=msg||E'\n'||k||': '||coalesce(diff->k->>'antes','—')||' → '||coalesce(diff->k->>'depois','—');end if;
 end loop;
 msg=left(msg,6000)||E'\nConfira no administrativo: https://dasksz.github.io/RH-PRIME/admin.html';
 insert into public.rh_admin_notifications(actor_id,actor_name,employee_id,employee_name,source_table,operation,title,details,message_text) values(auth.uid(),actor,employee,person,tg_table_name,tg_op,title,diff,msg);return coalesce(new,old);
end $function$;

UPDATE public.rh_admin_notifications
SET whatsapp_status='cancelado', error='Aviso de área fora da regra de inclusão de colaboradores.'
WHERE source_table='avisos_area'
  AND whatsapp_status IN ('aguardando_configuracao','aguardando')
  AND NOT rh_internal.area_notice_valid(id);
