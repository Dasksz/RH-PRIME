-- Gestão de acessos e limites de leitura/edição por filial e setor.
alter table public.profiles
 add column role text not null default 'nenhum',
 add column access_mode text not null default 'nenhum',
 add column access_level text not null default 'consulta',
 add column access_scopes jsonb not null default '[]',
 add column access_version integer not null default 0;
update public.profiles set role=case when status='admin' then 'administrador' else 'nenhum' end,
 access_mode=case when status in ('admin','aprovado') then 'todos' else 'nenhum' end,
 access_level=case when status in ('admin','aprovado') then 'edicao' else 'consulta' end;
alter table public.profiles
 add constraint profile_role_options check(role in ('nenhum','supervisor','coordenador','gerente','administrador')),
 add constraint profile_mode_options check(access_mode in ('nenhum','todos','areas')),
 add constraint profile_level_options check(access_level in ('consulta','edicao')),
 add constraint profile_scopes_array check(jsonb_typeof(access_scopes)='array');

create function rh_internal.can_access_area(p_unit text,p_sector text) returns boolean
 language sql stable security definer set search_path='' as $$
 select auth.uid() is not null and exists(select 1 from public.profiles p where p.id=auth.uid()
 and p.status in ('admin','aprovado') and (p.status='admin' or p.access_mode='todos'
 or (p.access_mode='areas' and exists(select 1 from jsonb_array_elements(p.access_scopes) s
 where (s->>'unidade' is null or s->>'unidade'=p_unit)
 and (s->>'setor' is null or s->>'setor'=p_sector)))))
$$;
create function rh_internal.can_read_employee(p_employee uuid) returns boolean
 language sql stable security definer set search_path='' as $$
 select auth.uid() is not null and exists(select 1 from public.funcionarios_epi e
 where e.id=p_employee and rh_internal.can_access_area(e.unidade,e.setor))
$$;
create function rh_internal.can_write() returns boolean language sql stable security definer set search_path='' as $$
 select auth.uid() is not null and exists(select 1 from public.profiles where id=auth.uid()
 and (status='admin' or (status='aprovado' and access_level='edicao' and access_mode in ('todos','areas'))))
$$;
create function rh_internal.has_full_access() returns boolean language sql stable security definer set search_path='' as $$
 select auth.uid() is not null and exists(select 1 from public.profiles where id=auth.uid()
 and (status='admin' or (status='aprovado' and access_mode='todos')))
$$;
create function rh_internal.can_read_period(p_period uuid) returns boolean language sql stable security definer set search_path='' as $$
 select auth.uid() is not null and exists(select 1 from public.rh_ferias_periodos where id=p_period and rh_internal.can_read_employee(funcionario_id))
$$;
revoke all on function rh_internal.can_access_area(text,text),rh_internal.can_read_employee(uuid),rh_internal.can_write(),rh_internal.has_full_access(),rh_internal.can_read_period(uuid) from public,anon;
grant execute on function rh_internal.can_access_area(text,text),rh_internal.can_read_employee(uuid),rh_internal.can_write(),rh_internal.has_full_access(),rh_internal.can_read_period(uuid) to authenticated;

create or replace function rh_internal.protect_profile() returns trigger language plpgsql set search_path='' as $$
declare item jsonb;begin
 if auth.uid() is not null and not rh_internal.is_admin() and
 (to_jsonb(new)-'name') is distinct from (to_jsonb(old)-'name') then
 raise exception 'Somente o administrador pode configurar acessos.';end if;
 if new.status not in ('pendente','aprovado','admin','bloqueado') then raise exception 'Situação de acesso inválida';end if;
 if new.status='admin' then new.role='administrador';new.access_mode='todos';new.access_level='edicao';new.access_scopes='[]';
 elsif new.role='administrador' then raise exception 'Administrador exige situação admin';end if;
 if new.access_mode='areas' and jsonb_array_length(new.access_scopes)=0 then raise exception 'Selecione ao menos uma área';end if;
 if jsonb_array_length(new.access_scopes)>50 then raise exception 'Máximo de 50 áreas por perfil';end if;
 for item in select value from jsonb_array_elements(new.access_scopes) loop
  if jsonb_typeof(item)<>'object' or not (item ? 'unidade' and item ? 'setor') or (item-'unidade'-'setor')<>'{}'::jsonb
  or (item->>'unidade' is null and item->>'setor' is null)
  or (item->>'unidade' is not null and not exists(select 1 from public.funcionarios_epi where unidade=item->>'unidade'))
  or (item->>'setor' is not null and not exists(select 1 from public.funcionarios_epi where setor=item->>'setor')) then
   raise exception 'Área inválida: selecione filial e/ou setor cadastrados';end if;
 end loop;
 if old.status='admin' and new.status<>'admin' then
  perform pg_advisory_xact_lock(82100506);
  if not exists(select 1 from public.profiles where status='admin' and id<>old.id) then raise exception 'Mantenha ao menos um administrador';end if;
 end if;
 new.access_version=old.access_version+1;return new;
end $$;

create table public.rh_access_notifications(
 id uuid primary key default gen_random_uuid(),profile_id uuid not null references public.profiles(id) on delete cascade,
 created_at timestamptz not null default now(),seen_at timestamptz,unique(profile_id));
alter table public.rh_access_notifications enable row level security;
revoke all on public.rh_access_notifications from anon,authenticated;
grant select,update on public.rh_access_notifications to authenticated;
create policy access_notice_read on public.rh_access_notifications for select to authenticated using((select rh_internal.is_admin()));
create policy access_notice_update on public.rh_access_notifications for update to authenticated using((select rh_internal.is_admin())) with check((select rh_internal.is_admin()));
create function rh_internal.new_access_notice() returns trigger language plpgsql security definer set search_path='' as $$
begin insert into public.rh_access_notifications(profile_id) values(new.id) on conflict do nothing;return new;end $$;
revoke all on function rh_internal.new_access_notice() from public,anon,authenticated;
create trigger rh_new_access_notice after insert on public.profiles for each row execute function rh_internal.new_access_notice();
insert into public.rh_access_notifications(profile_id) select id from public.profiles where status='pendente' on conflict do nothing;

-- Políticas restritivas complementam as regras de aprovação existentes.
create policy scope_read on public.funcionarios_epi as restrictive for select to authenticated using(rh_internal.can_access_area(unidade,setor));
create policy scope_insert on public.funcionarios_epi as restrictive for insert to authenticated with check(rh_internal.can_write() and rh_internal.can_access_area(unidade,setor));
create policy scope_update on public.funcionarios_epi as restrictive for update to authenticated using(rh_internal.can_write() and rh_internal.can_access_area(unidade,setor)) with check(rh_internal.can_write() and rh_internal.can_access_area(unidade,setor));
create policy scope_delete on public.funcionarios_epi as restrictive for delete to authenticated using(rh_internal.can_write() and rh_internal.can_access_area(unidade,setor));
do $$declare t text;predicate text;begin
 foreach t in array array['rh_movimentacoes','rh_absenteismo','rh_ferias','devolucoes_pendentes','rh_desligados'] loop
  predicate='(rh_internal.has_full_access() or rh_internal.can_read_employee(funcionario_id))';
  execute format('create policy scope_read on public.%I as restrictive for select to authenticated using(%s)',t,predicate);
  execute format('create policy scope_insert on public.%I as restrictive for insert to authenticated with check(rh_internal.can_write() and %s)',t,predicate);
  execute format('create policy scope_update on public.%I as restrictive for update to authenticated using(rh_internal.can_write() and %s) with check(rh_internal.can_write() and %s)',t,predicate,predicate);
  execute format('create policy scope_delete on public.%I as restrictive for delete to authenticated using(rh_internal.can_write() and %s)',t,predicate);
 end loop;
end $$;
create policy scope_read on public.rh_ferias_periodos as restrictive for select to authenticated using(rh_internal.can_read_employee(funcionario_id));
create policy scope_read on public.rh_ferias_lancamentos as restrictive for select to authenticated using(rh_internal.can_read_period(periodo_id));
create policy scope_read on public.rh_ferias_documentos as restrictive for select to authenticated using(rh_internal.can_read_period(periodo_id));
create policy scope_read on public.rh_ferias_eventos as restrictive for select to authenticated using(rh_internal.has_full_access());
create policy scope_read on public.sistema_logs as restrictive for select to authenticated using(rh_internal.has_full_access());

-- RPCs privilegiadas de férias: consulta não pode gravar e escopo é validado antes do acesso.
do $$declare definition text;fname text;begin
 foreach fname in array array['rh_vacation_mutate','rh_vacation_document'] loop
  select pg_get_functiondef(p.oid) into definition from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='rh_internal' and p.proname=fname;
  definition=replace(definition,'if auth.uid() is null or not rh_internal.is_approved()', 'if auth.uid() is null or not rh_internal.can_write()');
  if fname='rh_vacation_mutate' then
   definition=replace(definition, 'if e.id is null then raise exception ''Colaborador não encontrado'';end if;', 'if e.id is null or not rh_internal.can_read_employee(e.id) then raise exception ''Colaborador fora da área autorizada'';end if;');
   definition=replace(definition, 'if p.id is null then raise exception ''Período não encontrado'';end if;', 'if p.id is null or not rh_internal.can_read_employee(p.funcionario_id) then raise exception ''Período fora da área autorizada'';end if;');
  else
   definition=replace(definition, 'if p.id is null then raise exception ''Período inexistente'';end if;', 'if p.id is null or not rh_internal.can_read_employee(p.funcionario_id) then raise exception ''Período fora da área autorizada'';end if;');
   definition=replace(definition, 'if d.id is null then raise exception ''Documento não encontrado'';end if;', 'if d.id is null or not rh_internal.can_read_period(d.periodo_id) then raise exception ''Documento fora da área autorizada'';end if;');
  end if;
  if position('fora da área autorizada' in definition)=0 then raise exception 'Formato da RPC mudou: revise antes de aplicar';end if;
  execute definition;
 end loop;
end $$;
create index profiles_access_status on public.profiles(status);
create index access_notice_unseen on public.rh_access_notifications(created_at) where seen_at is null;
notify pgrst,'reload schema';
