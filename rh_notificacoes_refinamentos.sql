-- Alterações propagadas por sincronização não geram avisos repetidos.
create or replace function rh_internal.notify_admin_event() returns trigger language plpgsql security definer set search_path='' as $$
declare before_row jsonb;after_row jsonb;record_row jsonb;diff jsonb='{}';k text;actor text;employee uuid;person text;title text;msg text;begin
 if tg_table_name<>'profiles' and (auth.uid() is null or pg_trigger_depth()>1) then return coalesce(new,old);end if;
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
end $$;
do $$declare t text;begin foreach t in array array['rh_ferias_periodos','rh_ferias_lancamentos','rh_ferias_documentos'] loop execute format('create trigger rh_notify_admin_event after insert or update or delete on public.%I for each row execute function rh_internal.notify_admin_event()',t);end loop;end $$;
-- Ativar o canal começa a enviar eventos novos; os anteriores permanecem no painel.
create function rh_internal.notification_activation() returns trigger language plpgsql security definer set search_path='' as $$begin
 if new.whatsapp_enabled and not old.whatsapp_enabled then update public.rh_admin_notifications set whatsapp_status='somente_painel' where whatsapp_status='aguardando_configuracao';end if;return new;
end $$;
revoke all on function rh_internal.notification_activation() from public,anon,authenticated;
create trigger notification_activation after update on public.rh_notification_settings for each row execute function rh_internal.notification_activation();
notify pgrst,'reload schema';
