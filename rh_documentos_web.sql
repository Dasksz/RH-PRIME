alter table public.rh_automation_settings add column documents_enabled boolean not null default false;
alter table public.rh_automation_settings add column n8n_enabled boolean not null default false;
alter table public.rh_automation_settings add column last_documents_worker_at timestamptz;
alter table public.rh_automation_settings add column next_message_at timestamptz;
alter table public.rh_automation_settings add column messages_count integer not null default 0;
grant update(documents_enabled,n8n_enabled) on public.rh_automation_settings to authenticated;
create table public.rh_delivery_documents (
 id uuid primary key, funcionario_id uuid not null references public.funcionarios_epi(id) on delete restrict,
 document_type text not null check(length(document_type) between 1 and 100), period text not null check(length(period) between 1 and 50),
 filename text not null check(length(filename) between 1 and 200), sha256 text not null check(sha256 ~ '^[a-f0-9]{64}$'),
 storage_path text not null unique check(storage_path=id::text||'.pdf'),
 status text not null default 'prepared' check(status in ('prepared','uploading','ready','queued','sending','accepted','uncertain','failed','cancelled')),
 drive_file_id text, link text, phone text, message_text text, error text,
 approved_by uuid references auth.users(id), approved_at timestamptz,
 created_at timestamptz not null default now(),updated_at timestamptz not null default now(),
 unique(funcionario_id,document_type,period,sha256)
);
create index rh_delivery_status on public.rh_delivery_documents(status,updated_at);
create table public.rh_delivery_events(id bigint generated always as identity primary key,document_id uuid not null references public.rh_delivery_documents(id),status text not null,detail text,created_at timestamptz not null default now());
create index rh_delivery_event_document on public.rh_delivery_events(document_id);
alter table public.rh_delivery_documents enable row level security;
alter table public.rh_delivery_events enable row level security;
revoke all on public.rh_delivery_documents,public.rh_delivery_events from anon,authenticated;
grant select on public.rh_delivery_documents,public.rh_delivery_events to authenticated;
grant insert on public.rh_delivery_documents to authenticated;
grant all on public.rh_delivery_documents,public.rh_delivery_events to service_role;
grant usage,select on sequence public.rh_delivery_events_id_seq to service_role;
create policy delivery_admin on public.rh_delivery_documents for all to authenticated using ((select rh_internal.is_admin())) with check ((select rh_internal.is_admin()));
create policy delivery_event_admin on public.rh_delivery_events for select to authenticated using ((select rh_internal.is_admin()));
create function rh_internal.delivery_guard() returns trigger language plpgsql set search_path='' as $$
begin
 if current_user='authenticated' and (new.status<>'prepared' or new.drive_file_id is not null or new.approved_at is not null or new.message_text is not null or new.phone is not null) then raise exception 'Importe como documento preparado'; end if;
 return new;
end $$;
revoke all on function rh_internal.delivery_guard() from public,anon,authenticated;
create trigger rh_delivery_insert_guard before insert on public.rh_delivery_documents for each row execute function rh_internal.delivery_guard();
create function rh_internal.delivery_audit() returns trigger language plpgsql security definer set search_path='' as $$ begin
 insert into public.rh_delivery_events(document_id,status,detail) values(new.id,new.status,left(new.error,500));return new;end $$;
revoke all on function rh_internal.delivery_audit() from public,anon,authenticated;
create trigger rh_delivery_audit after insert or update on public.rh_delivery_documents for each row execute function rh_internal.delivery_audit();
-- RPCs de aprovação/cancelamento: checks de administrador antes de qualquer escrita privilegiada.
create function public.rh_approve_delivery(p_id uuid,p_link text,p_message text) returns void language plpgsql security definer set search_path='' as $$
declare e public.funcionarios_epi; d public.rh_delivery_documents; destination_phone text; begin
 if auth.uid() is null or not rh_internal.is_admin() then raise exception 'Acesso restrito'; end if;
 select * into d from public.rh_delivery_documents where id=p_id for update;
 if d.status<>'ready' then raise exception 'Documento ainda não pronto para aprovação'; end if;
 select * into e from public.funcionarios_epi where id=d.funcionario_id;
 if e.data_desligamento is not null then raise exception 'Envio automático bloqueado para desligado'; end if;
 destination_phone=regexp_replace(coalesce(e.whatsapp,''),'[^0-9]','','g');if length(destination_phone) in(10,11) then destination_phone='55'||destination_phone;end if;
 if destination_phone !~ '^55[1-9][0-9][0-9]{8,9}$' then raise exception 'WhatsApp inválido'; end if;
 if p_link !~ '^https://' or length(p_message) not between 1 and 8000 or position(p_link in p_message)=0 then raise exception 'Informe mensagem e link HTTPS válidos'; end if;
 update public.rh_delivery_documents set link=p_link,message_text=p_message,phone=destination_phone,approved_by=auth.uid(),approved_at=now(),status='queued',updated_at=now() where id=p_id;
end $$;
-- Evitar ambiguidade entre variável e coluna.
create function public.rh_cancel_delivery(p_id uuid) returns void language plpgsql security definer set search_path='' as $$ begin
 if auth.uid() is null or not rh_internal.is_admin() then raise exception 'Acesso restrito'; end if;
 update public.rh_delivery_documents set status='cancelled',updated_at=now() where id=p_id and status in('prepared','ready','queued','failed');
 if not found then raise exception 'Não é possível cancelar esta situação'; end if;
end $$;
revoke all on function public.rh_approve_delivery(uuid,text,text),public.rh_cancel_delivery(uuid) from public,anon;
grant execute on function public.rh_approve_delivery(uuid,text,text),public.rh_cancel_delivery(uuid) to authenticated;
create function public.rh_claim_document(p_send boolean default false) returns setof public.rh_delivery_documents language plpgsql security invoker set search_path='' as $$
begin
 update public.rh_automation_settings set last_documents_worker_at=now() where id;
 if not (select documents_enabled from public.rh_automation_settings where id) then return; end if;
 -- Envios interrompidos são incertos, nunca reenviados automaticamente.
 update public.rh_delivery_documents set status='uncertain',error='Execução interrompida durante envio. Confira no n8n antes de reenviar.',updated_at=now() where status='sending' and updated_at<now()-interval '15 minutes';
 update public.rh_delivery_documents set status='prepared',error='Retomando upload interrompido',updated_at=now() where status='uploading' and updated_at<now()-interval '15 minutes';
 if p_send then
  if not (select n8n_enabled and (next_message_at is null or next_message_at<=now()) from public.rh_automation_settings where id) then return; end if;
  return query update public.rh_delivery_documents set status='sending',updated_at=now() where id=(select id from public.rh_delivery_documents where status='queued' order by created_at for update skip locked limit 1) returning *;
 else
  return query update public.rh_delivery_documents set status='uploading',updated_at=now() where id=(select id from public.rh_delivery_documents where status='prepared' order by created_at for update skip locked limit 1) returning *;
 end if;
end $$;
revoke all on function public.rh_claim_document(boolean) from public,anon,authenticated;
grant execute on function public.rh_claim_document(boolean) to service_role;
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types) values('rh-documentos','rh-documentos',false,10485760,array['application/pdf']);
create policy rh_documents_storage_read on storage.objects for select to authenticated using(bucket_id='rh-documentos' and (select rh_internal.is_admin()));
create policy rh_documents_storage_insert on storage.objects for insert to authenticated with check(bucket_id='rh-documentos' and (select rh_internal.is_admin()) and name ~ '^[a-f0-9-]{36}\.pdf$');
create policy rh_documents_storage_delete on storage.objects for delete to authenticated using(bucket_id='rh-documentos' and (select rh_internal.is_admin()));
