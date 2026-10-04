-- RH PRIME: consistência de identidade, histórico e autorização.
-- O snapshot privado permite conferir/restaurar os dados anteriores à migração.
create schema if not exists rh_internal;
revoke all on schema rh_internal from public, anon;
grant usage on schema rh_internal to authenticated, service_role;
create table if not exists rh_internal.backups (
  id bigint generated always as identity primary key,
  created_at timestamptz not null default now(),
  motivo text not null, snapshot jsonb not null
);
revoke all on rh_internal.backups from public, anon, authenticated;
insert into rh_internal.backups(motivo,snapshot)
select 'Antes da correção RH 2026-10-04',jsonb_build_object(
  'funcionarios_epi',(select jsonb_agg(t) from public.funcionarios_epi t),
  'rh_movimentacoes',(select jsonb_agg(t) from public.rh_movimentacoes t),
  'rh_ferias',(select jsonb_agg(t) from public.rh_ferias t),
  'rh_absenteismo',(select jsonb_agg(t) from public.rh_absenteismo t),
  'rh_desligados',(select jsonb_agg(t) from public.rh_desligados t),
  'devolucoes_pendentes',(select jsonb_agg(t) from public.devolucoes_pendentes t),
  'profiles',(select jsonb_agg(t) from public.profiles t),
  'epi_funcao',(select jsonb_agg(t) from public.epi_funcao t));

create or replace function rh_internal.is_approved() returns boolean
language sql stable security definer set search_path = '' as $$
  select auth.uid() is not null and exists(select 1 from public.profiles where id=auth.uid() and status in ('aprovado','admin'))
$$;
create or replace function rh_internal.is_admin() returns boolean
language sql stable security definer set search_path = '' as $$
  select auth.uid() is not null and exists(select 1 from public.profiles where id=auth.uid() and status='admin')
$$;
revoke all on function rh_internal.is_approved(),rh_internal.is_admin() from public,anon;
grant execute on function rh_internal.is_approved(),rh_internal.is_admin() to authenticated,service_role;

-- Daniel César é o perfil com nome igual ao autor/proprietário do repositório.
-- A associação exige um único perfil aprovado com esse nome.
do $$ begin
 if (select count(*) from public.profiles where name='Daniel César' and status in ('aprovado','admin'))<>1 then
   raise exception 'Não foi possível identificar um único administrador existente.';
 end if;
 update public.profiles set status='admin' where name='Daniel César' and status='aprovado';
end $$;

create or replace function rh_internal.protect_profile() returns trigger
language plpgsql security invoker set search_path='' as $$
begin
 if auth.uid() is not null and not rh_internal.is_admin()
    and (new.status is distinct from old.status or new.id is distinct from old.id or new.email is distinct from old.email) then
   raise exception 'Somente o administrador pode alterar aprovação, identidade ou e-mail do perfil.';
 end if;
 return new;
end $$;
revoke all on function rh_internal.protect_profile() from public,anon,authenticated;
drop trigger if exists rh_protect_profile on public.profiles;
create trigger rh_protect_profile before update on public.profiles for each row execute function rh_internal.protect_profile();

do $$ declare p record; t text; begin
 for p in select schemaname,tablename,policyname from pg_policies where schemaname='public' and tablename in
 ('profiles','funcionarios_epi','empresas','rh_movimentacoes','rh_absenteismo','rh_ferias','epi_funcao','devolucoes_pendentes','rh_desligados','sistema_logs','configuracoes_admin') loop
   execute format('drop policy %I on public.%I',p.policyname,p.tablename);
 end loop;
 foreach t in array array['funcionarios_epi','rh_movimentacoes','rh_absenteismo','rh_ferias','devolucoes_pendentes','rh_desligados'] loop
   execute format('alter table public.%I enable row level security',t);
   execute format('revoke all on public.%I from anon,authenticated',t);
   execute format('grant select,insert,update,delete on public.%I to authenticated',t);
   execute format('create policy rh_approved on public.%I for all to authenticated using ((select rh_internal.is_approved())) with check ((select rh_internal.is_approved()))',t);
 end loop;
 foreach t in array array['empresas','epi_funcao','configuracoes_admin'] loop
   execute format('revoke all on public.%I from anon,authenticated',t);
   execute format('grant select,insert,update,delete on public.%I to authenticated',t);
   execute format('create policy rh_admin on public.%I for all to authenticated using ((select rh_internal.is_admin())) with check ((select rh_internal.is_admin()))',t);
   if t<>'configuracoes_admin' then
     execute format('create policy rh_read on public.%I for select to authenticated using ((select rh_internal.is_approved()))',t);
   end if;
 end loop;
end $$;
revoke all on public.profiles from anon,authenticated;
grant select,update on public.profiles to authenticated;
create policy rh_profile_read on public.profiles for select to authenticated using (id=(select auth.uid()) or (select rh_internal.is_admin()));
create policy rh_profile_update on public.profiles for update to authenticated using (id=(select auth.uid()) or (select rh_internal.is_admin())) with check (id=(select auth.uid()) or (select rh_internal.is_admin()));
drop trigger if exists trigger_clean_old_sistema_logs on public.sistema_logs;
revoke all on public.sistema_logs from anon,authenticated;
grant select,insert on public.sistema_logs to authenticated;
create policy rh_logs_read on public.sistema_logs for select to authenticated using ((select rh_internal.is_approved()));
create policy rh_logs_insert on public.sistema_logs for insert to authenticated with check ((select rh_internal.is_approved()));
grant usage,select on all sequences in schema public to authenticated;
revoke execute on function public.handle_new_user(),public.rls_auto_enable() from public,anon,authenticated;

alter table public.funcionarios_epi add column if not exists data_desligamento date;
alter table public.funcionarios_epi add column if not exists motivo_saida text;
alter table public.rh_movimentacoes add column if not exists carga_horaria integer default 220;
do $$ declare t text; begin
 foreach t in array array['rh_movimentacoes','rh_absenteismo','rh_ferias','devolucoes_pendentes','rh_desligados'] loop
   execute format('alter table public.%I add column if not exists funcionario_id uuid references public.funcionarios_epi(id) on delete restrict',t);
   execute format('create index if not exists %I on public.%I (funcionario_id)',t||'_funcionario_id_idx',t);
 end loop;
end $$;

-- Preenche somente correspondências de nome únicas e sem conflito de CPF válido.
do $$ declare t text; nf text; begin
 foreach t in array array['rh_movimentacoes','rh_absenteismo','rh_ferias','devolucoes_pendentes','rh_desligados'] loop
   nf:=case when t='rh_desligados' then 'nome' else 'funcionario_nome' end;
   execute format($sql$
    update public.%I r set funcionario_id=f.id,cpf=f.cpf
    from public.funcionarios_epi f
    where r.funcionario_id is null and upper(trim(r.%I))=upper(trim(f.nome))
      and (r.cpf is null or r.cpf !~ '^[0-9]{11}$' or r.cpf=f.cpf)
      and (select count(*) from public.funcionarios_epi x where upper(trim(x.nome))=upper(trim(f.nome)))=1
   $sql$,t,nf);
 end loop;
end $$;
-- Registros históricos sem cadastro ativo: CPF somente de arquivo desligado único.
do $$ declare t text; begin
 foreach t in array array['rh_movimentacoes','rh_absenteismo','rh_ferias'] loop
   execute format($sql$
    update public.%I r set cpf=d.cpf from public.rh_desligados d
    where (r.cpf is null or r.cpf !~ '^[0-9]{11}$') and d.cpf ~ '^[0-9]{11}$'
     and upper(trim(r.funcionario_nome))=upper(trim(d.nome))
     and (select count(*) from public.rh_desligados x where upper(trim(x.nome))=upper(trim(d.nome)))=1
   $sql$,t);
 end loop;
end $$;
create unique index if not exists funcionarios_epi_cpf_unique on public.funcionarios_epi(cpf);
-- Cabeçalho importado é dado espúrio confirmado, com backup acima.
delete from public.epi_funcao where funcao='Função';

create or replace function rh_internal.parse_date(v text) returns date
language plpgsql immutable security invoker set search_path='' as $$
begin
 if nullif(trim(v),'') is null then return null; end if;
 if v ~ '^\d{4}-\d{2}-\d{2}$' then return v::date; end if;
 if v ~ '^\d{2}/\d{2}/\d{4}$' then return pg_catalog.to_date(v,'DD/MM/YYYY'); end if;
 return null;
exception when others then return null;
end $$;
revoke all on function rh_internal.parse_date(text) from public,anon,authenticated;

create or replace function rh_internal.sync_employee() returns trigger
language plpgsql security definer set search_path='' as $$
declare adm date; n integer; oldname text; begin
 if auth.uid() is not null and not rh_internal.is_approved() then raise exception 'Acesso RH não aprovado.'; end if;
 if pg_trigger_depth()>2 then return new; end if;
 if new.cpf is null or new.cpf !~ '^[0-9]{11}$' then raise exception 'CPF deve conter 11 dígitos.'; end if;
 adm:=rh_internal.parse_date(new.admissao);
 if adm is null then raise exception 'Data de admissão inválida.'; end if;
 oldname:=case when tg_op='UPDATE' then old.nome else new.nome end;
 if tg_op='UPDATE' then
   update public.rh_movimentacoes set funcionario_nome=new.nome,cpf=new.cpf where funcionario_id=new.id and (funcionario_nome is distinct from new.nome or cpf is distinct from new.cpf);
   update public.rh_absenteismo set funcionario_nome=new.nome,cpf=new.cpf where funcionario_id=new.id and (funcionario_nome is distinct from new.nome or cpf is distinct from new.cpf);
   update public.rh_ferias set funcionario_nome=new.nome,cpf=new.cpf where funcionario_id=new.id and (funcionario_nome is distinct from new.nome or cpf is distinct from new.cpf);
   update public.devolucoes_pendentes set funcionario_nome=new.nome,cpf=new.cpf where funcionario_id=new.id and (funcionario_nome is distinct from new.nome or cpf is distinct from new.cpf);
   update public.rh_desligados set nome=new.nome,cpf=new.cpf where funcionario_id=new.id and (nome is distinct from new.nome or cpf is distinct from new.cpf);
 end if;
 select count(*) into n from public.rh_movimentacoes where funcionario_id=new.id;
 if n=0 then
   insert into public.rh_movimentacoes(funcionario_id,funcionario_nome,cpf,data_admissao,data_desligamento,motivo_saida,carga_horaria)
   values(new.id,new.nome,new.cpf,adm,new.data_desligamento,new.motivo_saida,coalesce(new.carga_horaria,220));
 elsif n=1 then
   update public.rh_movimentacoes set data_admissao=adm,data_desligamento=new.data_desligamento,motivo_saida=new.motivo_saida,carga_horaria=coalesce(new.carga_horaria,220) where funcionario_id=new.id and (data_admissao is distinct from adm or data_desligamento is distinct from new.data_desligamento or motivo_saida is distinct from new.motivo_saida or carga_horaria is distinct from coalesce(new.carga_horaria,220));
 else raise exception 'Mais de um vínculo de movimentação. Confira readmissões antes de editar.';
 end if;
 if new.data_desligamento is null and not exists(select 1 from public.rh_ferias where funcionario_id=new.id) then
   insert into public.rh_ferias(funcionario_id,funcionario_nome,cpf,data_inicio_aquisitivo,data_fim_aquisitivo,data_vencimento,dias_direito,dias_gozados,dias_abonados,status)
   values(new.id,new.nome,new.cpf,adm,(adm+interval '1 year'-interval '1 day')::date,(adm+interval '1 year'-interval '1 day'+interval '11 months')::date,30,0,0,'pendente');
 end if;
 if new.data_desligamento is not null then
   if new.data_desligamento<adm then raise exception 'Desligamento anterior à admissão.'; end if;
   if not exists(select 1 from public.rh_desligados where funcionario_id=new.id and data_desligamento=new.data_desligamento) then
     insert into public.rh_desligados(funcionario_id,cpf,nome,funcao,setor,unidade,admissao,data_desligamento,motivo_saida,whatsapp,tamanho_farda,calcado,calca,sexo,carga_horaria,local_registro,epi_data,epi_itens,fardamento_data,fardamento_itens)
     values(new.id,new.cpf,new.nome,new.funcao,new.setor,new.unidade,new.admissao,new.data_desligamento,new.motivo_saida,new.whatsapp,new.tamanho_farda,new.calcado,new.calca,new.sexo,new.carga_horaria,new.local_registro,new.epi_data,new.epi_itens,new.fardamento_data,new.fardamento_itens);
   else
     update public.rh_desligados set nome=new.nome,cpf=new.cpf,motivo_saida=new.motivo_saida where funcionario_id=new.id and data_desligamento=new.data_desligamento;
   end if;
   if (coalesce(new.epi_itens,'')<>'' or coalesce(new.fardamento_itens,'')<>'') and not exists(select 1 from public.devolucoes_pendentes where funcionario_id=new.id and data_desligamento=new.data_desligamento) then
     insert into public.devolucoes_pendentes(funcionario_id,funcionario_nome,cpf,funcao,setor,unidade,local_registro,data_admissao,data_desligamento,epi_data,epi_itens,fardamento_data,fardamento_itens,status)
     values(new.id,new.nome,new.cpf,new.funcao,new.setor,new.unidade,new.local_registro,adm,new.data_desligamento,new.epi_data,new.epi_itens,new.fardamento_data,new.fardamento_itens,'pendente');
   end if;
 end if;
 return new;
end $$;
revoke all on function rh_internal.sync_employee() from public,anon,authenticated;

-- Alteração de movimentação via Sheets também aplica o desligamento no cadastro.
create or replace function rh_internal.sync_movement() returns trigger
language plpgsql security definer set search_path='' as $$
declare f public.funcionarios_epi; n integer; begin
 if auth.uid() is not null and not rh_internal.is_approved() then raise exception 'Acesso RH não aprovado.'; end if;
 if pg_trigger_depth()>1 then return new; end if;
 if new.funcionario_id is null then
   select count(*) into n from public.funcionarios_epi where cpf=new.cpf or (nullif(new.cpf,'') is null and upper(trim(nome))=upper(trim(new.funcionario_nome)));
   if n=1 then select * into f from public.funcionarios_epi where cpf=new.cpf or (nullif(new.cpf,'') is null and upper(trim(nome))=upper(trim(new.funcionario_nome))); new.funcionario_id:=f.id;
   else return new; end if;
 else select * into f from public.funcionarios_epi where id=new.funcionario_id; end if;
 if f.id is null then return new; end if;
 new.cpf:=f.cpf;
 update public.rh_movimentacoes set funcionario_id=f.id,cpf=f.cpf where id=new.id and (funcionario_id is distinct from f.id or cpf is distinct from f.cpf);
 update public.funcionarios_epi set nome=new.funcionario_nome,admissao=to_char(new.data_admissao,'DD/MM/YYYY'),carga_horaria=coalesce(new.carga_horaria,220),data_desligamento=new.data_desligamento,motivo_saida=new.motivo_saida
 where id=f.id and (nome is distinct from new.funcionario_nome or rh_internal.parse_date(admissao) is distinct from new.data_admissao or data_desligamento is distinct from new.data_desligamento or motivo_saida is distinct from new.motivo_saida or carga_horaria is distinct from coalesce(new.carga_horaria,220));
 return new;
end $$;
revoke all on function rh_internal.sync_movement() from public,anon,authenticated;

create or replace function rh_internal.archive_vacation() returns trigger
language plpgsql security invoker set search_path='' as $$
begin
 if new.data_inicio_aquisitivo is distinct from old.data_inicio_aquisitivo then
   new.historico_periodos:=coalesce(old.historico_periodos,'[]'::jsonb)||jsonb_build_array((to_jsonb(old)-'historico_periodos')||jsonb_build_object('arquivado_em',now()));
 end if;
 return new;
end $$;
revoke all on function rh_internal.archive_vacation() from public,anon,authenticated;
drop trigger if exists rh_archive_vacation on public.rh_ferias;
create trigger rh_archive_vacation before update on public.rh_ferias for each row execute function rh_internal.archive_vacation();

update public.rh_movimentacoes m set carga_horaria=coalesce(f.carga_horaria,220) from public.funcionarios_epi f where m.funcionario_id=f.id;

-- Snapshot inicial do cadastro reflete desligamentos já registrados.
update public.funcionarios_epi f set data_desligamento=m.data_desligamento,motivo_saida=m.motivo_saida
from public.rh_movimentacoes m where m.funcionario_id=f.id and (select count(*) from public.rh_movimentacoes x where x.funcionario_id=f.id)=1;
drop trigger if exists rh_sync_employee on public.funcionarios_epi;
create trigger rh_sync_employee after insert or update on public.funcionarios_epi for each row execute function rh_internal.sync_employee();
drop trigger if exists rh_sync_movement on public.rh_movimentacoes;
create trigger rh_sync_movement after insert or update on public.rh_movimentacoes for each row execute function rh_internal.sync_movement();

create or replace function rh_internal.audit_change() returns trigger
language plpgsql security definer set search_path='' as $$
begin
 if auth.uid() is not null and not rh_internal.is_approved() then raise exception 'Acesso RH não aprovado.'; end if;
 insert into public.sistema_logs(tabela_afetada,tipo_operacao,descricao,dados_anteriores,dados_novos)
 values(tg_table_name,tg_op,'Gravação confirmada no banco ('||tg_table_name||')',case when tg_op<>'INSERT' then to_jsonb(old) end,case when tg_op<>'DELETE' then to_jsonb(new) end);
 return coalesce(new,old);
end $$;
revoke all on function rh_internal.audit_change() from public,anon,authenticated;
do $$ declare t text; begin
 foreach t in array array['funcionarios_epi','rh_movimentacoes','rh_absenteismo','rh_ferias','rh_desligados','devolucoes_pendentes','empresas','epi_funcao'] loop
   execute format('drop trigger if exists rh_audit_change on public.%I',t);
   execute format('create trigger rh_audit_change after insert or update or delete on public.%I for each row execute function rh_internal.audit_change()',t);
 end loop;
end $$;

-- Os webhooks antigos ficam suspensos até a nova versão do Apps Script ser implantada.
-- Evita executar regras antigas de exclusão durante a atualização.
do $$ declare t text; hook record; url text := 'https://script.google.com/macros/s/AKfycbxiOCFqmTythI4H9Lemp_b_9fsZcJrDZX-CBGWleVq0jV22EDtYASP5XmnWE5_7vqqg/exec'; begin
 for hook in select c.relname,t.tgname from pg_trigger t join pg_class c on c.oid=t.tgrelid join pg_namespace n on n.oid=c.relnamespace join pg_proc p on p.oid=t.tgfoid where n.nspname='public' and p.proname='http_request' loop
   execute format('drop trigger %I on public.%I',hook.tgname,hook.relname);
 end loop;
 foreach t in array array['funcionarios_epi','rh_movimentacoes','rh_absenteismo','rh_ferias','rh_desligados','devolucoes_pendentes','empresas','epi_funcao'] loop
   execute format('create trigger rh_sheet_webhook after insert or update or delete on public.%I for each row execute function supabase_functions.http_request(%L,%L,%L,%L,%L)',t,url,'POST','{"Content-type":"application/json"}','{}','30000');
   execute format('alter table public.%I disable trigger rh_sheet_webhook',t);
   if not exists(select 1 from pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename=t) then
     execute format('alter publication supabase_realtime add table public.%I',t);
   end if;
 end loop;
end $$;
-- RPC de ativação restrita à chave de servidor; URL e tabelas não são parâmetros.
create or replace function public.rh_ativar_webhooks() returns boolean
language plpgsql security definer set search_path='' as $$
declare t text; begin
 foreach t in array array['funcionarios_epi','rh_movimentacoes','rh_absenteismo','rh_ferias','rh_desligados','devolucoes_pendentes','empresas','epi_funcao'] loop
   execute format('alter table public.%I enable trigger rh_sheet_webhook',t);
 end loop;
 return true;
end $$;
revoke all on function public.rh_ativar_webhooks() from public,anon,authenticated;
grant execute on function public.rh_ativar_webhooks() to service_role;

-- Teste de regressão em subtransação: nenhuma pessoa fictícia fica persistida.
do $$ declare emp uuid; mov integer; vac integer; absent integer; testcpf text; testcpf2 text; begin
 begin
  loop testcpf:='999'||lpad((floor(random()*100000000))::bigint::text,8,'0'); exit when not exists(select 1 from public.funcionarios_epi where cpf=testcpf); end loop;
  loop testcpf2:='998'||lpad((floor(random()*100000000))::bigint::text,8,'0'); exit when not exists(select 1 from public.funcionarios_epi where cpf=testcpf2); end loop;
  insert into public.funcionarios_epi(nome,cpf,admissao,carga_horaria,epi_itens) values('__RH_TESTE_REGRESSAO__',testcpf,'01/01/2025',110,'CAPACETE') returning id into emp;
  select id into mov from public.rh_movimentacoes where funcionario_id=emp;
  select id into vac from public.rh_ferias where funcionario_id=emp;
  if mov is null or vac is null then raise exception 'Regressão: admissão sem movimentação/férias.'; end if;
  insert into public.rh_absenteismo(funcionario_id,funcionario_nome,cpf,data_inicio,data_fim,horas_perdidas,carga_horaria) values(emp,'__RH_TESTE_REGRESSAO__',testcpf,'2026-10-01','2026-10-01',2,110) returning id into absent;
  update public.funcionarios_epi set nome='__RH_TESTE_RENOMEADO__',cpf=testcpf2,carga_horaria=220 where id=emp;
  if not exists(select 1 from public.rh_movimentacoes where id=mov and funcionario_nome='__RH_TESTE_RENOMEADO__' and cpf=testcpf2 and carga_horaria=220) then raise exception 'Regressão: identidade/carga não propagada.'; end if;
  if not exists(select 1 from public.rh_absenteismo where id=absent and cpf=testcpf2 and horas_perdidas=2 and carga_horaria=110) then raise exception 'Regressão: horas históricas alteradas.'; end if;
  update public.rh_ferias set data_inicio_aquisitivo='2026-01-01',data_fim_aquisitivo='2026-12-31' where id=vac;
  if (select jsonb_array_length(historico_periodos) from public.rh_ferias where id=vac)<>1 then raise exception 'Regressão: histórico do período perdido.'; end if;
  update public.rh_movimentacoes set data_desligamento='2026-10-03',motivo_saida='voluntario' where id=mov;
  if not exists(select 1 from public.funcionarios_epi where id=emp and data_desligamento='2026-10-03') then raise exception 'Regressão: desligamento via movimentação não propagado.'; end if;
  if not exists(select 1 from public.rh_desligados where funcionario_id=emp) or not exists(select 1 from public.devolucoes_pendentes where funcionario_id=emp) then raise exception 'Regressão: desligamento sem arquivo/devolução.'; end if;
  if not exists(select 1 from public.rh_absenteismo where id=absent) or not exists(select 1 from public.rh_ferias where id=vac) then raise exception 'Regressão: histórico excluído no desligamento.'; end if;
  raise exception 'RH_TESTE_ROLLBACK_OK';
 exception when raise_exception then
  if sqlerrm<>'RH_TESTE_ROLLBACK_OK' then raise; end if;
 end;
end $$;
