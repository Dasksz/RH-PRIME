-- Exportação local: guarda somente o manifesto e avisos, nunca os bytes dos PDFs.
create table public.rh_signature_exports (
 id uuid primary key references public.rh_delivery_batches(id),
 documents jsonb not null check(jsonb_typeof(documents)='array' and jsonb_array_length(documents) between 1 and 1000),
 confirmed_at timestamptz, confirmed_by uuid references auth.users(id),
 created_at timestamptz not null default now()
);
alter table public.rh_signature_exports enable row level security;
revoke all on public.rh_signature_exports from public,anon,authenticated;
grant select on public.rh_signature_exports to authenticated;
grant all on public.rh_signature_exports to service_role;
create policy signature_exports_admin on public.rh_signature_exports for select to authenticated using((select rh_internal.is_admin()));

create function rh_internal.rh_register_signature_export(p_id uuid,p_name text,p_type text,p_period text,p_documents jsonb)
returns uuid language plpgsql security definer set search_path='' as $$
declare item jsonb; e public.funcionarios_epi; notice_id uuid;
begin
 if auth.uid() is null or not rh_internal.is_admin() then raise exception 'Acesso restrito';end if;
 if p_id is null or p_name is null or length(trim(p_name)) not between 1 and 160 or p_type is null or length(p_type) not between 1 and 100 or p_period is null or p_period !~ '^((0[1-9]|1[0-2])/[0-9]{4}|[0-9]{4})$'
 or p_documents is null or jsonb_typeof(p_documents)<>'array' or jsonb_array_length(p_documents) not between 1 and 1000 or octet_length(p_documents::text)>2097152 then raise exception 'Manifesto inválido';end if;
 -- Serializa a mesma exportação e torna o registro idempotente.
 perform pg_advisory_xact_lock(hashtextextended(p_id::text,0));
 if exists(select 1 from public.rh_signature_exports where id=p_id) then
  if not exists(select 1 from public.rh_signature_exports x join public.rh_delivery_batches b on b.id=x.id where x.id=p_id and x.documents=p_documents and b.document_type=p_type and b.period=p_period) then raise exception 'Lote já registrado com outros documentos';end if;
  return p_id;
 end if;
 for item in select value from jsonb_array_elements(p_documents) loop
  select * into e from public.funcionarios_epi where id=(item->>'employee_id')::uuid;
  if not found or e.data_desligamento is not null then raise exception 'Colaborador indisponível ou desligado';end if;
  if coalesce(item->>'sha256','') !~ '^[a-f0-9]{64}$' or coalesce(item->>'filename','') !~ '^[0-9]{11}-[^/\\]+[.]pdf$' or left(item->>'filename',11)<>regexp_replace(coalesce(e.cpf,''),'[^0-9]','','g') or length(item->>'filename')>200 then raise exception 'CPF, nome ou integridade do PDF inválidos';end if;
 end loop;
 insert into public.rh_delivery_batches(id,name,document_type,period,created_by) values(p_id,trim(p_name),p_type,p_period,auth.uid());
 insert into public.rh_signature_exports(id,documents) values(p_id,p_documents);
 -- Um aviso por colaborador, mesmo que possua vários PDFs no lote.
 for item in select distinct on (value->>'employee_id') value from jsonb_array_elements(p_documents) order by value->>'employee_id' loop
  notice_id=gen_random_uuid();
  insert into public.rh_delivery_documents(id,funcionario_id,document_type,period,filename,sha256,storage_path,status,source,link,batch_id)
  values(notice_id,(item->>'employee_id')::uuid,p_type,p_period,item->>'filename',encode(sha256(convert_to(p_id::text||':'||(item->>'employee_id'),'UTF8')),'hex'),notice_id::text||'.pdf','ready','link','https://sistema.facilitaponto.com.br/portal',p_id);
 end loop;
 return p_id;
end $$;

create function public.rh_register_signature_export(p_id uuid,p_name text,p_type text,p_period text,p_documents jsonb)
returns uuid language sql security invoker set search_path='' as $$select rh_internal.rh_register_signature_export(p_id,p_name,p_type,p_period,p_documents);$$;
revoke all on function rh_internal.rh_register_signature_export(uuid,text,text,text,jsonb),public.rh_register_signature_export(uuid,text,text,text,jsonb) from public,anon;
grant execute on function rh_internal.rh_register_signature_export(uuid,text,text,text,jsonb),public.rh_register_signature_export(uuid,text,text,text,jsonb) to authenticated;

create function rh_internal.rh_confirm_signature_export(p_id uuid,p_confirmed boolean)
returns integer language plpgsql security definer set search_path='' as $$
declare d public.rh_delivery_documents; e public.funcionarios_epi; phone_value text; total integer=0;
begin
 if auth.uid() is null or not rh_internal.is_admin() then raise exception 'Acesso restrito';end if;
 if p_confirmed is distinct from true then raise exception 'Confirme a publicação no Facilita Ponto antes de autorizar avisos';end if;
 perform 1 from public.rh_signature_exports where id=p_id for update;
 if not found then raise exception 'Exportação não encontrada';end if;
 update public.rh_signature_exports set confirmed_at=coalesce(confirmed_at,now()),confirmed_by=coalesce(confirmed_by,auth.uid()) where id=p_id;
 for d in select * from public.rh_delivery_documents where batch_id=p_id and (status='ready' or (status='failed' and error='SIGNATURE_PHONE_INVALID' and approved_at is null)) for update loop
  select * into e from public.funcionarios_epi where id=d.funcionario_id;
  phone_value=regexp_replace(coalesce(e.whatsapp,''),'[^0-9]','','g');
  if length(phone_value) in(10,11) then phone_value='55'||phone_value;end if;
  if e.id is null or e.data_desligamento is not null or phone_value !~ '^55[1-9][0-9][0-9]{8,9}$' then
   update public.rh_delivery_documents set status='failed',error='SIGNATURE_PHONE_INVALID',updated_at=now() where id=d.id;
   continue;
  end if;
  update public.rh_delivery_documents set status='queued',link='https://sistema.facilitaponto.com.br/portal',phone=phone_value,
   message_text='Olá, '||e.nome||E'!\n\nAqui é do RH. Seus documentos de '||d.document_type||', referentes a '||d.period||E', estão disponíveis no Facilita Ponto para visualização e assinatura.\n\nAcesse o Portal do Colaborador:\nhttps://sistema.facilitaponto.com.br/portal\n\nFaça login com seu CPF (somente números) e o código da empresa: 032612.\nApós entrar, abra os documentos disponíveis e conclua a assinatura.\n\nEm caso de dificuldade, procure o RH.',
   approved_by=auth.uid(),approved_at=now(),error=null,updated_at=now() where id=d.id;
  total=total+1;
 end loop;
 return total;
end $$;
create function public.rh_confirm_signature_export(p_id uuid,p_confirmed boolean)
returns integer language sql security invoker set search_path='' as $$select rh_internal.rh_confirm_signature_export(p_id,p_confirmed);$$;
revoke all on function rh_internal.rh_confirm_signature_export(uuid,boolean),public.rh_confirm_signature_export(uuid,boolean) from public,anon;
grant execute on function rh_internal.rh_confirm_signature_export(uuid,boolean),public.rh_confirm_signature_export(uuid,boolean) to authenticated;

-- Também bloqueia tentativas de aprovação pela tela/RPC antigos antes da confirmação.
create function rh_internal.signature_notice_guard() returns trigger language plpgsql set search_path='' as $$
begin
 if new.status in ('queued','sending') and exists(select 1 from public.rh_signature_exports where id=new.batch_id) then
  if not exists(select 1 from public.rh_signature_exports where id=new.batch_id and confirmed_at is not null) or new.source<>'link' or new.link<>'https://sistema.facilitaponto.com.br/portal' or position('032612' in coalesce(new.message_text,''))=0 or position('CPF' in coalesce(new.message_text,''))=0 then raise exception 'Confirme a publicação e use o portal e as instruções do Facilita Ponto';end if;
 end if;
 return new;
end $$;
revoke all on function rh_internal.signature_notice_guard() from public,anon,authenticated;
create trigger signature_notice_guard before insert or update on public.rh_delivery_documents for each row execute function rh_internal.signature_notice_guard();
notify pgrst,'reload schema';
