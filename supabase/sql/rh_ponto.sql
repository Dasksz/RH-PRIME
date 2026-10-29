-- Registros de ponto: credenciais no Vault, acesso por colaborador e escrita pelo servidor.
create table public.rh_ponto_config (
 id boolean primary key default true check(id),
 disponivel_desde date not null default '2026-10-26',
 fuso text not null default 'America/Sao_Paulo'
);
insert into public.rh_ponto_config(id) values(true);
create table public.rh_ponto_jornadas (
 funcionario_id uuid primary key references public.funcionarios_epi(id),
 minutos_dia integer not null check(minutos_dia between 1 and 1440),
 minutos_semana integer not null check(minutos_semana between 1 and 10080),
 dias integer[] not null default array[1,2,3,4,5] check(cardinality(dias) between 1 and 7 and dias <@ array[0,1,2,3,4,5,6]),
 updated_at timestamptz not null default now()
);
create table public.rh_ponto_consultas (
 id bigint generated always as identity primary key,
 funcionario_id uuid not null references public.funcionarios_epi(id),
 inicio date not null,fim date not null check(fim>=inicio),
 iniciado_em timestamptz not null,consultado_em timestamptz not null default now(),
 sucesso boolean not null,quantidade integer not null default 0,
 erro text,resposta jsonb,por uuid references auth.users(id)
);
create index ponto_consultas_pessoa on public.rh_ponto_consultas(funcionario_id,consultado_em desc);
create index ponto_consultas_por on public.rh_ponto_consultas(por);
create table public.rh_ponto_marcacoes (
 id bigint generated always as identity primary key,
 funcionario_id uuid not null references public.funcionarios_epi(id),
 data_hora timestamp not null,entrada_saida text not null check(entrada_saida in('E','S')),
 tipo_registro text not null check(tipo_registro in('A','M')),
 situacao text not null,obs text,fingerprint text not null,
 consulta_id bigint not null references public.rh_ponto_consultas(id),
 unique(funcionario_id,fingerprint)
);
create index ponto_marcacoes_pessoa_dia on public.rh_ponto_marcacoes(funcionario_id,data_hora);
create index ponto_marcacoes_consulta on public.rh_ponto_marcacoes(consulta_id);
do $$ declare t text; begin
 foreach t in array array['rh_ponto_jornadas','rh_ponto_consultas','rh_ponto_marcacoes'] loop
  execute format('alter table public.%I enable row level security',t);
  execute format('revoke all on public.%I from public,anon,authenticated',t);
  execute format('grant select on public.%I to authenticated',t);
  execute format('grant all on public.%I to service_role',t);
  execute format('create policy ponto_leitura on public.%I for select to authenticated using(rh_internal.can_read_employee(funcionario_id))',t);
 end loop;
end $$;
grant usage,select on sequence public.rh_ponto_consultas_id_seq,public.rh_ponto_marcacoes_id_seq to service_role;
alter table public.rh_ponto_config enable row level security;
revoke all on public.rh_ponto_config from public,anon,authenticated;
grant select on public.rh_ponto_config to authenticated;
create policy ponto_config_leitura on public.rh_ponto_config for select to authenticated using((select rh_internal.has_full_access()));
grant all on public.rh_ponto_config to service_role;
grant insert,update on public.rh_ponto_jornadas to authenticated;
create policy ponto_jornada_insert on public.rh_ponto_jornadas for insert to authenticated with check((select rh_internal.is_admin()));
create policy ponto_jornada_update on public.rh_ponto_jornadas for update to authenticated using((select rh_internal.is_admin())) with check((select rh_internal.is_admin()));

-- Um UPDATE de conjunto usa o webhook em lote existente; nenhum registro com valores preenchidos é substituído.
update public.funcionarios_epi set
 carga_horaria_semanal=coalesce(carga_horaria_semanal,44),
 dias_trabalho_semana=coalesce(dias_trabalho_semana,5),
 jornada_diaria_minutos=coalesce(jornada_diaria_minutos,round(coalesce(carga_horaria_semanal,44)*60/coalesce(dias_trabalho_semana,5))::integer)
where carga_horaria_semanal is null or dias_trabalho_semana is null or jornada_diaria_minutos is null;
create function rh_internal.ponto_jornada_padrao() returns trigger language plpgsql set search_path='' as $$begin
 new.carga_horaria_semanal=coalesce(new.carga_horaria_semanal,44);
 new.dias_trabalho_semana=coalesce(new.dias_trabalho_semana,5);
 new.jornada_diaria_minutos=coalesce(new.jornada_diaria_minutos,round(new.carga_horaria_semanal*60/new.dias_trabalho_semana)::integer);
 return new;end $$;
revoke all on function rh_internal.ponto_jornada_padrao() from public,anon,authenticated;
create trigger ponto_jornada_padrao before insert or update on public.funcionarios_epi for each row execute function rh_internal.ponto_jornada_padrao();

create function rh_internal.ponto_segredos() returns jsonb language plpgsql security definer set search_path='' as $$declare result jsonb;begin
 if auth.role() is distinct from 'service_role' then raise exception 'Servidor obrigatório';end if;
 select jsonb_object_agg(name,decrypted_secret) into result from vault.decrypted_secrets where name in('rh_facilita_empresa','rh_facilita_senha_sha1');
 if result is null or not(result ? 'rh_facilita_empresa' and result ? 'rh_facilita_senha_sha1') then raise exception 'Integração não configurada';end if;
 return result;end $$;
create function public.rh_ponto_segredos() returns jsonb language sql security invoker set search_path='' as $$select rh_internal.ponto_segredos();$$;
revoke all on function rh_internal.ponto_segredos(),public.rh_ponto_segredos() from public,anon,authenticated;
grant usage on schema rh_internal to service_role;
grant execute on function rh_internal.ponto_segredos(),public.rh_ponto_segredos() to service_role;

create function rh_internal.ponto_salvar_consulta(p_funcionario uuid,p_inicio date,p_fim date,p_iniciado timestamptz,p_registros jsonb,p_erro text,p_por uuid)
returns bigint language plpgsql security definer set search_path='' as $$
declare cid bigint;item jsonb;stamp timestamp;fp text;
begin
 if auth.role() is distinct from 'service_role' then raise exception 'Servidor obrigatório';end if;
 if p_inicio is null or p_fim is null or p_fim<p_inicio or p_fim-p_inicio>62 or p_iniciado is null then raise exception 'Período inválido';end if;
 if not exists(select 1 from public.funcionarios_epi where id=p_funcionario) then raise exception 'Colaborador inválido';end if;
 if p_por is not null and not exists(select 1 from public.profiles where id=p_por and status='admin') then raise exception 'Administrador obrigatório';end if;
 perform pg_advisory_xact_lock(hashtextextended(p_funcionario::text,61726));
 if p_erro is null and exists(select 1 from public.rh_ponto_consultas where funcionario_id=p_funcionario and sucesso and iniciado_em>p_iniciado and inicio<=p_fim and fim>=p_inicio) then raise exception 'Já existe consulta mais recente; atualize a tela';end if;
 if p_erro is null and (p_registros is null or jsonb_typeof(p_registros)<>'array' or jsonb_array_length(p_registros)>10000 or octet_length(p_registros::text)>2097152) then raise exception 'Resposta inválida';end if;
 -- Valida tudo antes de substituir a fotografia do período. Erros nunca apagam marcações anteriores.
 if p_erro is null then
  for item in select value from jsonb_array_elements(p_registros) loop
   if coalesce(item->>'data_hora','') !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2}$' or coalesce(item->>'entrada_saida','') not in('E','S') or coalesce(item->>'tipo_registro','') not in('A','M') or coalesce(item->>'situacao','') not in('Aprovado (Auto)','Aprovado Manualmente','Rejeitado (Auto)','Pendente','Reprovado Manualmente','Abono/Atestado') or length(coalesce(item->>'obs',''))>4000 then raise exception 'Marcação inválida';end if;
   stamp=(item->>'data_hora')::timestamp;
   if stamp::date<p_inicio or stamp::date>p_fim then raise exception 'Marcação fora da consulta';end if;
  end loop;
 end if;
 insert into public.rh_ponto_consultas(funcionario_id,inicio,fim,iniciado_em,sucesso,quantidade,erro,resposta,por)
 values(p_funcionario,p_inicio,p_fim,p_iniciado,p_erro is null,case when p_erro is null then jsonb_array_length(p_registros) else 0 end,left(p_erro,500),case when p_erro is null then p_registros else null end,p_por) returning id into cid;
 if p_erro is not null then return cid;end if;
 delete from public.rh_ponto_marcacoes where funcionario_id=p_funcionario and data_hora>=p_inicio::timestamp and data_hora<(p_fim+1)::timestamp;
 for item in select value from jsonb_array_elements(p_registros) loop
  fp=encode(sha256(convert_to((item->>'data_hora')||'|'||(item->>'entrada_saida')||'|'||(item->>'tipo_registro'),'UTF8')),'hex');
  insert into public.rh_ponto_marcacoes(funcionario_id,data_hora,entrada_saida,tipo_registro,situacao,obs,fingerprint,consulta_id)
  values(p_funcionario,(item->>'data_hora')::timestamp,item->>'entrada_saida',item->>'tipo_registro',item->>'situacao',item->>'obs',fp,cid)
  on conflict(funcionario_id,fingerprint) do update set situacao=excluded.situacao,obs=excluded.obs,consulta_id=excluded.consulta_id;
 end loop;
 return cid;
end $$;
create function public.rh_ponto_salvar_consulta(p_funcionario uuid,p_inicio date,p_fim date,p_iniciado timestamptz,p_registros jsonb,p_erro text default null,p_por uuid default null)
returns bigint language sql security invoker set search_path='' as $$select rh_internal.ponto_salvar_consulta(p_funcionario,p_inicio,p_fim,p_iniciado,p_registros,p_erro,p_por);$$;
revoke all on function rh_internal.ponto_salvar_consulta(uuid,date,date,timestamptz,jsonb,text,uuid),public.rh_ponto_salvar_consulta(uuid,date,date,timestamptz,jsonb,text,uuid) from public,anon,authenticated;
grant execute on function rh_internal.ponto_salvar_consulta(uuid,date,date,timestamptz,jsonb,text,uuid),public.rh_ponto_salvar_consulta(uuid,date,date,timestamptz,jsonb,text,uuid) to service_role;
notify pgrst,'reload schema';
