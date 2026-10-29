alter table public.rh_ponto_config add column historico_desde date not null default '2026-09-01';
-- disponivel_desde é o corte para apuração de ausências: 26/10/2026, conforme orientação do RH.
create table public.rh_ponto_ocorrencias (
 id uuid primary key default gen_random_uuid(),
 funcionario_id uuid not null references public.funcionarios_epi(id),
 dia date not null,classificacao text not null check(classificacao in('justificada','injustificada','pendente')),
 motivo text not null check(length(trim(motivo)) between 3 and 1000),
 abonar boolean not null default false check(classificacao='justificada' or not abonar),
 revisado_por uuid references auth.users(id),updated_at timestamptz not null default now(),
 unique(funcionario_id,dia)
);
create index ponto_ocorrencias_revisor on public.rh_ponto_ocorrencias(revisado_por);
create table public.rh_ponto_ocorrencias_historico (
 id bigint generated always as identity primary key,
 ocorrencia_id uuid not null references public.rh_ponto_ocorrencias(id),
 funcionario_id uuid not null references public.funcionarios_epi(id),
 antes jsonb,depois jsonb not null,por uuid references auth.users(id),criado_em timestamptz not null default now()
);
create index ponto_ocorrencias_hist_ocorrencia on public.rh_ponto_ocorrencias_historico(ocorrencia_id);
create index ponto_ocorrencias_hist_pessoa on public.rh_ponto_ocorrencias_historico(funcionario_id);
create index ponto_ocorrencias_hist_por on public.rh_ponto_ocorrencias_historico(por);
alter table public.rh_ponto_ocorrencias enable row level security;
alter table public.rh_ponto_ocorrencias_historico enable row level security;
revoke all on public.rh_ponto_ocorrencias,public.rh_ponto_ocorrencias_historico from public,anon,authenticated;
grant select,insert,update on public.rh_ponto_ocorrencias to authenticated;
grant select on public.rh_ponto_ocorrencias_historico to authenticated;
grant all on public.rh_ponto_ocorrencias,public.rh_ponto_ocorrencias_historico to service_role;
grant usage,select on sequence public.rh_ponto_ocorrencias_historico_id_seq to service_role;
create policy ponto_ocorrencias_read on public.rh_ponto_ocorrencias for select to authenticated using(rh_internal.can_read_employee(funcionario_id));
create policy ponto_ocorrencias_insert on public.rh_ponto_ocorrencias for insert to authenticated with check((select rh_internal.is_admin()));
create policy ponto_ocorrencias_update on public.rh_ponto_ocorrencias for update to authenticated using((select rh_internal.is_admin())) with check((select rh_internal.is_admin()));
create policy ponto_ocorrencias_hist_read on public.rh_ponto_ocorrencias_historico for select to authenticated using(rh_internal.can_read_employee(funcionario_id));
create function rh_internal.ponto_ocorrencia_guard() returns trigger language plpgsql set search_path='' as $$begin
 if new.dia>(now() at time zone 'America/Sao_Paulo')::date then raise exception 'Não classifique dias futuros';end if;
 if TG_OP='UPDATE' and (new.funcionario_id<>old.funcionario_id or new.dia<>old.dia) then raise exception 'Preserve o vínculo e a data da ocorrência';end if;
 new.revisado_por=auth.uid();new.updated_at=now();return new;end $$;
revoke all on function rh_internal.ponto_ocorrencia_guard() from public,anon,authenticated;
create trigger ponto_ocorrencia_guard before insert or update on public.rh_ponto_ocorrencias for each row execute function rh_internal.ponto_ocorrencia_guard();
create function rh_internal.ponto_ocorrencia_audit() returns trigger language plpgsql security definer set search_path='' as $$begin
 insert into public.rh_ponto_ocorrencias_historico(ocorrencia_id,funcionario_id,antes,depois,por) values(new.id,new.funcionario_id,case when TG_OP='UPDATE' then to_jsonb(old) else null end,to_jsonb(new),auth.uid());return new;end $$;
revoke all on function rh_internal.ponto_ocorrencia_audit() from public,anon,authenticated;
create trigger ponto_ocorrencia_audit after insert or update on public.rh_ponto_ocorrencias for each row execute function rh_internal.ponto_ocorrencia_audit();
notify pgrst,'reload schema';
