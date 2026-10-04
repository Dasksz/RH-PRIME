-- Vincula novos afastamentos/férias/devoluções e impede identidade contraditória.
create or replace function rh_internal.bind_related() returns trigger
language plpgsql security definer set search_path='' as $$
declare data jsonb:=to_jsonb(new); previous jsonb; field text; employee public.funcionarios_epi; n integer; changed_name boolean:=false; changed_cpf boolean:=false; begin
 field:=case when tg_table_name='rh_desligados' then 'nome' else 'funcionario_nome' end;
 if tg_op='UPDATE' then
  previous:=to_jsonb(old);
  changed_name:=(data->>field) is distinct from (previous->>field);
  changed_cpf:=(data->>'cpf') is distinct from (previous->>'cpf');
 end if;
 if changed_cpf and nullif(data->>'cpf','') is not null then
  select count(*) into n from public.funcionarios_epi where cpf=data->>'cpf';
  if n=1 then select * into employee from public.funcionarios_epi where cpf=data->>'cpf'; end if;
 elsif changed_name then
  select count(*) into n from public.funcionarios_epi where upper(trim(nome))=upper(trim(data->>field));
  if n=1 then select * into employee from public.funcionarios_epi where upper(trim(nome))=upper(trim(data->>field)); end if;
 elsif nullif(data->>'funcionario_id','') is not null then
  select * into employee from public.funcionarios_epi where id=(data->>'funcionario_id')::uuid;
 elsif nullif(data->>'cpf','') is not null then
  select * into employee from public.funcionarios_epi where cpf=data->>'cpf';
 end if;
 if employee.id is null and not changed_name and not changed_cpf then
  select count(*) into n from public.funcionarios_epi where upper(trim(nome))=upper(trim(data->>field));
  if n=1 then select * into employee from public.funcionarios_epi where upper(trim(nome))=upper(trim(data->>field)); end if;
 end if;
 if employee.id is not null then
  new:=jsonb_populate_record(new,jsonb_build_object('funcionario_id',employee.id,'cpf',employee.cpf,field,employee.nome));
 elsif (changed_name or changed_cpf) and nullif(previous->>'funcionario_id','') is not null then
  raise exception 'Cadastro correspondente não encontrado. Edite nome/CPF no cadastro de colaboradores ou escolha um cadastro existente.';
 end if;
 return new;
end $$;
revoke all on function rh_internal.bind_related() from public,anon,authenticated;
do $$ declare t text; begin
 foreach t in array array['rh_absenteismo','rh_ferias','rh_desligados','devolucoes_pendentes'] loop
  execute format('create trigger rh_bind_related before insert or update on public.%I for each row execute function rh_internal.bind_related()',t);
 end loop;
end $$;
-- Verifica vínculo criado por nome, sem CPF enviado pelo front-end antigo.
do $$ declare employee uuid; absence integer; testcpf text; begin
 begin
  loop testcpf:='997'||lpad((floor(random()*100000000))::bigint::text,8,'0'); exit when not exists(select 1 from public.funcionarios_epi where cpf=testcpf); end loop;
  insert into public.funcionarios_epi(nome,cpf,admissao) values('__RH_TESTE_VINCULO__',testcpf,'01/01/2025') returning id into employee;
  insert into public.rh_absenteismo(funcionario_nome,data_inicio,data_fim,horas_perdidas) values('__RH_TESTE_VINCULO__','2026-10-01','2026-10-01',2) returning id into absence;
  if not exists(select 1 from public.rh_absenteismo where id=absence and funcionario_id=employee and cpf=testcpf and horas_perdidas=2) then raise exception 'Vínculo automático não confirmado.'; end if;
  update public.funcionarios_epi set nome='__RH_TESTE_VINCULO_NOVO__' where id=employee;
  if not exists(select 1 from public.rh_absenteismo where id=absence and funcionario_nome='__RH_TESTE_VINCULO_NOVO__' and funcionario_id=employee) then raise exception 'Identidade não propagada.'; end if;
  raise exception 'RH_TESTE_ROLLBACK_OK';
 exception when raise_exception then if sqlerrm<>'RH_TESTE_ROLLBACK_OK' then raise; end if; end;
end $$;

