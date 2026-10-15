-- Conferências periódicas preservam a entrega original e registram o saldo conferido.
create table public.rh_equipment_checks (
 id uuid primary key default gen_random_uuid(),
 funcionario_id uuid not null references public.funcionarios_epi(id),
 entrega_id uuid not null references public.rh_equipment_movements(id),
 operacao_id uuid not null references public.rh_equipment_receipts(id) deferrable initially deferred,
 categoria text not null check(categoria in ('epi','fardamento')),
 descricao text not null,
 quantidade integer not null check(quantidade between 1 and 10000),
 data_verificacao date not null,
 condicao text not null default 'boas_condicoes' check(condicao='boas_condicoes'),
 observacao text not null default '' check(length(observacao)<=2000),
 created_by uuid default auth.uid(),created_at timestamptz not null default now(),
 unique(operacao_id,entrega_id)
);
create index rh_equipment_check_employee on public.rh_equipment_checks(funcionario_id,categoria,id);
create index rh_equipment_check_delivery on public.rh_equipment_checks(entrega_id,data_verificacao desc,created_at desc);
alter table public.rh_equipment_checks enable row level security;
revoke all on public.rh_equipment_checks from public,anon,authenticated;
grant select,insert on public.rh_equipment_checks to authenticated;
grant all on public.rh_equipment_checks to service_role;
create policy equipment_check_read on public.rh_equipment_checks for select to authenticated using(rh_internal.can_read_employee(funcionario_id));
create policy equipment_check_insert on public.rh_equipment_checks for insert to authenticated with check(rh_internal.can_write() and rh_internal.can_read_employee(funcionario_id) and created_by=(select auth.uid()));
create function rh_internal.equipment_check_validate() returns trigger language plpgsql security invoker set search_path='' as $$
declare original public.rh_equipment_movements; used integer;
begin
 if tg_op<>'INSERT' then raise exception 'Histórico de verificações é imutável.'; end if;
 if auth.uid() is null or not rh_internal.can_write() or not rh_internal.can_read_employee(new.funcionario_id) then raise exception 'Sem permissão para verificar equipamentos.'; end if;
 perform 1 from public.funcionarios_epi where id=new.funcionario_id for update;
 select * into original from public.rh_equipment_movements where id=new.entrega_id;
 if not found or original.tipo<>'entrega' or original.funcionario_id<>new.funcionario_id or original.categoria<>new.categoria then raise exception 'Entrega de origem inválida.'; end if;
 if new.data_verificacao>(now() at time zone 'America/Sao_Paulo')::date or new.data_verificacao<original.data_movimento then raise exception 'Data de verificação inválida.'; end if;
 select coalesce(sum(quantidade),0) into used from public.rh_equipment_movements where entrega_origem_id=original.id and tipo in ('devolucao','baixa');
 if used>=original.quantidade then raise exception 'Equipamento não está mais em posse do colaborador.'; end if;
 new.quantidade=original.quantidade-used;new.descricao=original.descricao;
 new.created_by=auth.uid();new.created_at=now();return new;
end $$;
revoke all on function rh_internal.equipment_check_validate() from public,anon,authenticated;
create trigger equipment_check_validate before insert or update or delete on public.rh_equipment_checks for each row execute function rh_internal.equipment_check_validate();

create or replace function rh_internal.equipment_receipt_snapshot() returns trigger language plpgsql security invoker set search_path='' as $$
begin
 if tg_op<>'INSERT' then raise exception 'Documento emitido é imutável.'; end if;
 new.created_by=auth.uid();new.created_at=now();
 select jsonb_build_object('colaborador',jsonb_build_object('nome',e.nome,'cpf',e.cpf,'funcao',e.funcao,'setor',e.setor,'unidade',e.unidade,'admissao',e.admissao,'local_registro',e.local_registro),
  'empresa',coalesce((select to_jsonb(x) from public.empresas x where x.cnpj=case when upper(e.local_registro) like '%JEQUI%' then '52.522.019/0002-82' when upper(e.local_registro) like '%ILH%' then '52.522.019/0001-00' when upper(e.local_registro) like '%NUNES%' or upper(e.local_registro) like '%VIEIRA%' or upper(e.local_registro) like '%ITABUNA%' then '48.986.353/0001-39' end limit 1),'{}'::jsonb),
  'categoria',new.categoria,'emitido_em',new.created_at,'operacao_id',new.id,
  'movimentos',coalesce((select jsonb_agg(to_jsonb(m) order by m.data_movimento nulls first,m.created_at,m.id) from public.rh_equipment_movements m where m.funcionario_id=e.id and m.categoria=new.categoria),'[]'::jsonb),
  'verificacoes',coalesce((select jsonb_agg(to_jsonb(v) order by v.data_verificacao,v.created_at,v.id) from public.rh_equipment_checks v where v.funcionario_id=e.id and v.categoria=new.categoria),'[]'::jsonb)) into new.snapshot
 from public.funcionarios_epi e where e.id=new.funcionario_id;
 if new.snapshot is null then raise exception 'Colaborador indisponível.'; end if;
 return new;
end $$;
