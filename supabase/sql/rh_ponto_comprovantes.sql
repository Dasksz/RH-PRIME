-- Comprovantes de justificativa: privados, imutáveis e exclusivos do administrador RH.
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values('rh-ponto-comprovantes','rh-ponto-comprovantes',false,10485760,array['image/jpeg','image/png','image/webp','application/pdf']);
create table public.rh_ponto_anexos (
 id uuid primary key default gen_random_uuid(),
 ocorrencia_id uuid not null references public.rh_ponto_ocorrencias(id),
 path text not null unique,
 nome text not null check(length(trim(nome)) between 1 and 240),
 mime text not null check(mime in('image/jpeg','image/png','image/webp','application/pdf')),
 tamanho bigint not null check(tamanho between 1 and 10485760),
 criado_por uuid references auth.users(id),criado_em timestamptz not null default now()
);
create index ponto_anexos_ocorrencia on public.rh_ponto_anexos(ocorrencia_id);
create index ponto_anexos_autor on public.rh_ponto_anexos(criado_por);
alter table public.rh_ponto_anexos enable row level security;
revoke all on public.rh_ponto_anexos from public,anon,authenticated;
grant select,insert on public.rh_ponto_anexos to authenticated;
grant all on public.rh_ponto_anexos to service_role;
create policy ponto_anexos_read on public.rh_ponto_anexos for select to authenticated using((select rh_internal.is_admin()));
create policy ponto_anexos_insert on public.rh_ponto_anexos for insert to authenticated with check((select rh_internal.is_admin()));
create function rh_internal.ponto_anexo_guard() returns trigger language plpgsql set search_path='' as $$
declare o public.rh_ponto_ocorrencias;
begin
 select * into o from public.rh_ponto_ocorrencias where id=new.ocorrencia_id;
 if not found or split_part(new.path,'/',1)<>o.funcionario_id::text or split_part(new.path,'/',2)<>o.dia::text
  or new.path !~ '^[a-f0-9-]{36}/[0-9]{4}-[0-9]{2}-[0-9]{2}/[a-f0-9-]{36}\.(jpg|png|webp|pdf)$'
 then raise exception 'Comprovante fora do colaborador ou dia da ocorrência';end if;
 if not exists(select 1 from storage.objects s where s.bucket_id='rh-ponto-comprovantes' and s.name=new.path
  and s.metadata->>'mimetype'=new.mime and (s.metadata->>'size')::bigint=new.tamanho)
 then raise exception 'Envie o comprovante privado antes de vinculá-lo';end if;
 new.criado_por=auth.uid();new.criado_em=now();return new;
end $$;
revoke all on function rh_internal.ponto_anexo_guard() from public,anon,authenticated;
create trigger ponto_anexo_guard before insert on public.rh_ponto_anexos for each row execute function rh_internal.ponto_anexo_guard();
create policy ponto_files_read on storage.objects for select to authenticated using(bucket_id='rh-ponto-comprovantes' and (select rh_internal.is_admin()));
create policy ponto_files_insert on storage.objects for insert to authenticated with check(bucket_id='rh-ponto-comprovantes' and (select rh_internal.is_admin())
 and name ~ '^[a-f0-9-]{36}/[0-9]{4}-[0-9]{2}-[0-9]{2}/[a-f0-9-]{36}\.(jpg|png|webp|pdf)$');
-- Somente uploads ainda não vinculados podem ser removidos, para recuperação de falhas.
create policy ponto_files_cleanup on storage.objects for delete to authenticated using(bucket_id='rh-ponto-comprovantes' and (select rh_internal.is_admin())
 and not exists(select 1 from public.rh_ponto_anexos a where a.path=objects.name));
notify pgrst,'reload schema';
