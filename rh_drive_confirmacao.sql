alter table public.rh_drive_jobs drop constraint rh_drive_jobs_status_check;
alter table public.rh_drive_jobs add constraint rh_drive_jobs_status_check check(status in('waiting','processing','awaiting_choice','done','failed'));
alter table public.rh_drive_jobs add column folder_candidates jsonb not null default '[]'::jsonb,
 add column folder_employee jsonb, add column folder_choice text, add column choice_revision integer;

-- Qualquer nova revisão invalida a descoberta/decisão anterior.
create function rh_internal.reset_folder_choice() returns trigger language plpgsql set search_path='' as $$ begin
 if new.revision<>old.revision then new.folder_candidates='[]';new.folder_employee=null;new.folder_choice=null;new.choice_revision=null;end if;return new;
end $$;
revoke all on function rh_internal.reset_folder_choice() from public,anon,authenticated;
create trigger rh_reset_folder_choice before update on public.rh_drive_jobs for each row execute function rh_internal.reset_folder_choice();

create function public.rh_request_folder_choice(p_id uuid,p_revision integer,p_candidates jsonb,p_employee jsonb)
returns boolean language plpgsql security invoker set search_path='' as $$ begin
 if jsonb_typeof(p_candidates)<>'array' or jsonb_array_length(p_candidates) not between 1 and 100 then raise exception 'Candidatos inválidos';end if;
 update public.rh_drive_jobs set status='awaiting_choice',folder_candidates=p_candidates,folder_employee=p_employee,
 folder_choice=null,choice_revision=null,error='Pasta existente encontrada. Aguardando sua escolha.',updated_at=now()
 where id=p_id and status='processing' and revision=p_revision and claimed_revision=p_revision and not link_only;
 return found;
end $$;
revoke all on function public.rh_request_folder_choice(uuid,integer,jsonb,jsonb) from public,anon,authenticated;
grant execute on function public.rh_request_folder_choice(uuid,integer,jsonb,jsonb) to service_role;

create function rh_internal.rh_choose_employee_folder(p_id uuid,p_revision integer,p_folder text)
returns void language plpgsql security definer set search_path='' as $$
declare j public.rh_drive_jobs;e public.funcionarios_epi;begin
 if auth.uid() is null or not rh_internal.is_admin() then raise exception 'Acesso restrito';end if;
 select * into j from public.rh_drive_jobs where id=p_id for update;
 if not found or j.status<>'awaiting_choice' or j.revision<>p_revision then raise exception 'A solicitação mudou. Atualize o painel.';end if;
 select * into e from public.funcionarios_epi where id=j.funcionario_id;
 if not found or e.data_desligamento is not null then raise exception 'Colaborador indisponível ou desligado';end if;
 if j.folder_employee is distinct from jsonb_build_object('nome',e.nome,'cpf',e.cpf) then raise exception 'Nome ou CPF mudou. Solicite nova busca em Automações.';end if;
 if exists(select 1 from public.rh_drive_links where funcionario_id=e.id) then raise exception 'Já existe vínculo. Atualize e confira em Automações.';end if;
 if p_folder is null or (p_folder<>'new' and not exists(select 1 from jsonb_array_elements(j.folder_candidates) c where c->>'id'=p_folder)) then raise exception 'Escolha uma pasta da lista';end if;
 update public.rh_drive_jobs set folder_choice=p_folder,choice_revision=revision,status='waiting',error='Escolha registrada. Aguardando processamento.',updated_at=now() where id=j.id;
end $$;
revoke all on function rh_internal.rh_choose_employee_folder(uuid,integer,text) from public,anon;
grant execute on function rh_internal.rh_choose_employee_folder(uuid,integer,text) to authenticated;
create function public.rh_choose_employee_folder(p_id uuid,p_revision integer,p_folder text)
returns void language sql security invoker set search_path='' as $$select rh_internal.rh_choose_employee_folder(p_id,p_revision,p_folder);$$;
revoke all on function public.rh_choose_employee_folder(uuid,integer,text) from public,anon;
grant execute on function public.rh_choose_employee_folder(uuid,integer,text) to authenticated;

-- Um processador antigo não pode reutilizar pastas sem confirmação.
create function public.rh_claim_drive_with_choice() returns setof public.rh_drive_jobs language plpgsql security invoker set search_path='' as $$ begin
 update public.rh_automation_settings set last_worker_at=now() where id;
 if not(select drive_enabled from public.rh_automation_settings where id) then return;end if;
 update public.rh_drive_jobs set status='waiting',error='Retomando execução interrompida',updated_at=now() where status='processing' and not link_only and updated_at<now()-interval '15 minutes';
 return query update public.rh_drive_jobs set status='processing',claimed_revision=revision,updated_at=now() where id=(select id from public.rh_drive_jobs where status='waiting' and not link_only order by updated_at for update skip locked limit 1) returning *;
end $$;
revoke all on function public.rh_claim_drive_with_choice() from public,anon,authenticated;
grant execute on function public.rh_claim_drive_with_choice() to service_role;
create or replace function public.rh_claim_drive() returns setof public.rh_drive_jobs language sql security invoker set search_path='' as $$select * from public.rh_drive_jobs where false;$$;
notify pgrst,'reload schema';
