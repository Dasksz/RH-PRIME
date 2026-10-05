create table public.rh_delivery_batches(id uuid primary key default gen_random_uuid(),name text not null check(length(name) between 1 and 160),document_type text not null,period text not null,legacy boolean not null default false,created_by uuid references auth.users(id),created_at timestamptz not null default now());
alter table public.rh_delivery_batches enable row level security;
revoke all on public.rh_delivery_batches from anon,authenticated;
grant select on public.rh_delivery_batches to authenticated;
grant all on public.rh_delivery_batches to service_role;
create policy delivery_batches_admin on public.rh_delivery_batches for select to authenticated using((select rh_internal.is_admin()));
alter table public.rh_delivery_documents add column batch_id uuid references public.rh_delivery_batches(id) on delete restrict;
create index delivery_document_batch on public.rh_delivery_documents(batch_id);
-- Registros anteriores não guardavam a identidade do lote. Agrupamento legado explícito.
do $$ declare g record;bid uuid;begin
 for g in select document_type,period,(created_at at time zone 'America/Sao_Paulo')::date as day,min(created_at) first_date from public.rh_delivery_documents group by document_type,period,(created_at at time zone 'America/Sao_Paulo')::date loop
  insert into public.rh_delivery_batches(name,document_type,period,legacy,created_at) values('Importação anterior · '||g.document_type||' · '||g.period,g.document_type,g.period,true,g.first_date) returning id into bid;
  update public.rh_delivery_documents set batch_id=bid where document_type=g.document_type and period=g.period and (created_at at time zone 'America/Sao_Paulo')::date=g.day;
 end loop;
end $$;
create function rh_internal.rh_create_delivery_batch(p_name text,p_type text,p_period text) returns uuid language plpgsql security definer set search_path='' as $$ declare bid uuid;begin
 if auth.uid() is null or not rh_internal.is_admin() then raise exception 'Acesso restrito';end if;
 if p_name is null or length(trim(p_name)) not between 1 and 160 or p_type is null or length(p_type) not between 1 and 100 or p_period is null or p_period !~ '^(0[1-9]|1[0-2])/[0-9]{4}$' then raise exception 'Lote inválido';end if;
 insert into public.rh_delivery_batches(name,document_type,period,created_by) values(trim(p_name),p_type,p_period,auth.uid()) returning id into bid;return bid;
end $$;
create function public.rh_create_delivery_batch(p_name text,p_type text,p_period text) returns uuid language sql security invoker set search_path='' as $$ select rh_internal.rh_create_delivery_batch(p_name,p_type,p_period);$$;
revoke all on function rh_internal.rh_create_delivery_batch(text,text,text),public.rh_create_delivery_batch(text,text,text) from public,anon;
grant execute on function rh_internal.rh_create_delivery_batch(text,text,text),public.rh_create_delivery_batch(text,text,text) to authenticated;
create function rh_internal.delivery_batch_guard() returns trigger language plpgsql set search_path='' as $$ begin
 if new.batch_id is not null and not exists(select 1 from public.rh_delivery_batches b where b.id=new.batch_id and b.document_type=new.document_type and b.period=new.period) then raise exception 'Tipo/competência incompatíveis com lote';end if;return new;end $$;
revoke all on function rh_internal.delivery_batch_guard() from public,anon,authenticated;
create trigger delivery_batch_guard before insert or update of batch_id,document_type,period on public.rh_delivery_documents for each row execute function rh_internal.delivery_batch_guard();
create function rh_internal.rh_retry_document_upload(p_id uuid) returns void language plpgsql security definer set search_path='' as $$ declare d public.rh_delivery_documents;begin
 if auth.uid() is null or not rh_internal.is_admin() then raise exception 'Acesso restrito';end if;
 select * into d from public.rh_delivery_documents where id=p_id for update;
 if d.id is null or d.status<>'failed' or d.source<>'upload' or d.approved_at is not null then raise exception 'Somente falhas de upload sem aprovação podem ser retomadas';end if;
 if not exists(select 1 from public.funcionarios_epi where id=d.funcionario_id and data_desligamento is null) then raise exception 'Colaborador indisponível/desligado';end if;
 if not exists(select 1 from public.rh_drive_links where funcionario_id=d.funcionario_id and not template_pending) then raise exception 'Processe/vincule primeiro a pasta do colaborador';end if;
 update public.rh_delivery_documents set status='prepared',error=null,updated_at=now() where id=p_id;
end $$;
create function public.rh_retry_document_upload(p_id uuid) returns void language sql security invoker set search_path='' as $$ select rh_internal.rh_retry_document_upload(p_id);$$;
revoke all on function rh_internal.rh_retry_document_upload(uuid),public.rh_retry_document_upload(uuid) from public,anon;
grant execute on function rh_internal.rh_retry_document_upload(uuid),public.rh_retry_document_upload(uuid) to authenticated;
notify pgrst,'reload schema';
-- Reconciliação de pastas existentes: sem criação, cópia, renomeação ou movimentação.
alter table public.rh_drive_jobs add column link_only boolean not null default false;
alter table public.rh_automation_settings add column drive_worker_version text;
create function rh_internal.rh_link_existing_drive(p_employee uuid) returns void language plpgsql security definer set search_path='' as $$ begin
 if auth.uid() is null or not rh_internal.is_admin() then raise exception 'Acesso restrito';end if;
 if not exists(select 1 from public.rh_automation_settings where id=true and drive_enabled and drive_worker_version='existing-link-v1') then raise exception 'Atualize RH_Drive_Automacoes.gs e execute instalarAutomacaoDriveRH antes de vincular pastas em lote';end if;
 if not exists(select 1 from public.funcionarios_epi where id=p_employee and data_desligamento is null) then raise exception 'Colaborador indisponível/desligado';end if;
 insert into public.rh_drive_jobs(funcionario_id,link_only) values(p_employee,true) on conflict(funcionario_id) do update set revision=rh_drive_jobs.revision+1,link_only=true,status=case when rh_drive_jobs.status='processing' then 'processing' else 'waiting' end,error=null,updated_at=now();
end $$;
create function public.rh_link_existing_drive(p_employee uuid) returns void language sql security invoker set search_path='' as $$select rh_internal.rh_link_existing_drive(p_employee);$$;
revoke all on function rh_internal.rh_link_existing_drive(uuid),public.rh_link_existing_drive(uuid) from public,anon;
grant execute on function rh_internal.rh_link_existing_drive(uuid),public.rh_link_existing_drive(uuid) to authenticated;
create or replace function public.rh_enqueue_drive(p_employee uuid) returns void language plpgsql security invoker set search_path='' as $$ begin
 if auth.uid() is null or not rh_internal.is_admin() then raise exception 'Acesso restrito';end if;
 insert into public.rh_drive_jobs(funcionario_id,link_only) values(p_employee,false) on conflict(funcionario_id) do update set revision=rh_drive_jobs.revision+1,link_only=false,status=case when rh_drive_jobs.status='processing' then 'processing' else 'waiting' end,error=null,updated_at=now();
end $$;
create or replace function rh_internal.queue_drive_change() returns trigger language plpgsql security definer set search_path='' as $$ begin
 if (select drive_enabled from public.rh_automation_settings where id) and (TG_OP='INSERT' or new.data_desligamento is distinct from old.data_desligamento) then
 insert into public.rh_drive_jobs(funcionario_id,link_only) values(new.id,false) on conflict(funcionario_id) do update set revision=rh_drive_jobs.revision+1,link_only=false,status=case when rh_drive_jobs.status='processing' then 'processing' else 'waiting' end,error=null,updated_at=now();
 end if;return new;end $$;
