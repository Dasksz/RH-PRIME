alter table public.rh_delivery_documents
 add column drive_verified_at timestamptz,
 add column storage_deleted_at timestamptz,
 add column storage_cleanup_error text;
create or replace function rh_internal.delivery_guard() returns trigger language plpgsql set search_path='' as $$
begin
 if current_user='authenticated' and (new.status<>'prepared' or new.drive_file_id is not null or new.approved_at is not null or new.message_text is not null or new.phone is not null or new.drive_verified_at is not null or new.storage_deleted_at is not null or new.storage_cleanup_error is not null) then raise exception 'Importe como documento preparado';end if;
 return new;
end $$;
comment on column public.rh_delivery_documents.storage_deleted_at is 'Cópia temporária removida pela Storage API somente após verificar o conteúdo SHA-256 no Drive; histórico e links preservados.';
notify pgrst,'reload schema';
