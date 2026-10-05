-- Automação web: administração no navegador, execução no Google Apps Script.
create table public.rh_automation_settings (
 id boolean primary key default true check(id), drive_enabled boolean not null default false,
 active_folder_id text not null default '195JwYHEJdRY1u5DEL7tB7dSHn16DRVb4',
 former_folder_id text not null default '1v2Pt5YWqnW_bWRA9R7l6OQeMM7G_Tlrm',
 template_folder_id text not null default '1GeMrdoaynkvuHiPotbpfyJeiw8hBVDcd',
 message_template text not null default 'Olá, {nome}! Seu documento {tipo}, referente a {competencia}, está disponível: {link}',
 last_worker_at timestamptz,
 check(active_folder_id<>former_folder_id and template_folder_id<>active_folder_id and template_folder_id<>former_folder_id)
);
insert into public.rh_automation_settings(id) values(true);
create table public.rh_drive_links (
 funcionario_id uuid primary key references public.funcionarios_epi(id) on delete restrict,
 folder_id text not null unique check(folder_id ~ '^[A-Za-z0-9_-]{10,200}$'),
 template_pending boolean not null default false, updated_at timestamptz not null default now()
);
create table public.rh_drive_jobs (
 id uuid primary key default gen_random_uuid(), funcionario_id uuid not null unique references public.funcionarios_epi(id) on delete restrict,
 revision integer not null default 1, claimed_revision integer,
 status text not null default 'waiting' check(status in ('waiting','processing','done','failed')),
 error text, created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create index rh_drive_jobs_status on public.rh_drive_jobs(status,updated_at);
create table public.rh_drive_events (
 id bigint generated always as identity primary key, funcionario_id uuid not null,
 status text not null, detail text, created_at timestamptz not null default now()
);
create table public.rh_document_registry (
 id uuid primary key default gen_random_uuid(), funcionario_id uuid not null references public.funcionarios_epi(id) on delete restrict,
 document_type text not null check(length(document_type) between 1 and 100), period text not null check(length(period) between 1 and 50),
 url text not null check(url ~ '^https://'), notes text not null default '',
 status text not null default 'prepared' check(status in ('prepared','sent_manual','signed_manual')),
 created_at timestamptz not null default now()
);
do $$ declare t text; begin
 foreach t in array array['rh_automation_settings','rh_drive_links','rh_drive_jobs','rh_drive_events','rh_document_registry'] loop
 execute format('alter table public.%I enable row level security',t);
 execute format('revoke all on public.%I from anon,authenticated',t);
 execute format('grant select on public.%I to authenticated',t);
 execute format('grant all on public.%I to service_role',t);
 execute format('create policy admin_access on public.%I for all to authenticated using ((select rh_internal.is_admin())) with check ((select rh_internal.is_admin()))',t);
 end loop;
end $$;
grant update(drive_enabled,active_folder_id,former_folder_id,template_folder_id,message_template) on public.rh_automation_settings to authenticated;
grant insert,update on public.rh_drive_links,public.rh_document_registry to authenticated;
grant insert,update on public.rh_drive_jobs to authenticated;
grant usage,select on sequence public.rh_drive_events_id_seq to service_role;
create function rh_internal.record_drive_event() returns trigger language plpgsql security definer set search_path='' as $$
begin
 insert into public.rh_drive_events(funcionario_id,status,detail) values(new.funcionario_id,new.status,left(new.error,500));
 return new;
end $$;
revoke all on function rh_internal.record_drive_event() from public,anon,authenticated;
create trigger rh_drive_job_audit after insert or update on public.rh_drive_jobs for each row execute function rh_internal.record_drive_event();
create function rh_internal.queue_drive_change() returns trigger language plpgsql security definer set search_path='' as $$
begin
 if (select drive_enabled from public.rh_automation_settings where id) then
 if TG_OP='INSERT' or new.data_desligamento is distinct from old.data_desligamento then
 insert into public.rh_drive_jobs(funcionario_id) values(new.id)
 on conflict(funcionario_id) do update set revision=rh_drive_jobs.revision+1,
 status=case when rh_drive_jobs.status='processing' then 'processing' else 'waiting' end,error=null,updated_at=now();
 end if; end if; return new;
end $$;
revoke all on function rh_internal.queue_drive_change() from public,anon,authenticated;
create trigger rh_queue_drive_change after insert or update of data_desligamento on public.funcionarios_epi for each row execute function rh_internal.queue_drive_change();
create function public.rh_enqueue_drive(p_employee uuid) returns void language plpgsql security invoker set search_path='' as $$
begin
 if not rh_internal.is_admin() then raise exception 'Acesso restrito'; end if;
 insert into public.rh_drive_jobs(funcionario_id) values(p_employee)
 on conflict(funcionario_id) do update set revision=rh_drive_jobs.revision+1,
 status=case when rh_drive_jobs.status='processing' then 'processing' else 'waiting' end,error=null,updated_at=now();
end $$;
revoke all on function public.rh_enqueue_drive(uuid) from public,anon;
grant execute on function public.rh_enqueue_drive(uuid) to authenticated;
-- Somente o processador servidor pode obter/concluir tarefas.
create function public.rh_claim_drive() returns setof public.rh_drive_jobs language plpgsql security invoker set search_path='' as $$
begin
 update public.rh_automation_settings set last_worker_at=now() where id;
 if not (select drive_enabled from public.rh_automation_settings where id) then return; end if;
 -- Uma execução Apps Script termina em até 6 minutos. Recuperar apenas após 15 minutos.
 update public.rh_drive_jobs set status='waiting',error='Retomando execução interrompida',updated_at=now()
 where status='processing' and updated_at < now()-interval '15 minutes';
 return query update public.rh_drive_jobs set status='processing',claimed_revision=revision,updated_at=now()
 where id=(select id from public.rh_drive_jobs where status='waiting' order by updated_at for update skip locked limit 1) returning *;
end $$;
create function public.rh_finish_drive(p_id uuid,p_revision integer,p_error text default null) returns void language sql security invoker set search_path='' as $$
 update public.rh_drive_jobs set status=case when revision<>p_revision then 'waiting' when p_error is null then 'done' else 'failed' end,
 error=left(p_error,500),updated_at=now() where id=p_id and status='processing' and claimed_revision=p_revision;
$$;
revoke all on function public.rh_claim_drive(),public.rh_finish_drive(uuid,integer,text) from public,anon,authenticated;
grant execute on function public.rh_claim_drive(),public.rh_finish_drive(uuid,integer,text) to service_role;
