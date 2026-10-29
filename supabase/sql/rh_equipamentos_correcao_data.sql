-- Correção auditada da data efetiva. Fichas emitidas e movimentos vinculados são preservados.
begin;
alter table public.rh_equipment_movements add column registrado_por text not null default '';
-- Recupera apenas autores comprovados por created_by; não atribui autor ao legado sem usuário.
alter table public.rh_equipment_movements disable trigger equipment_validate;
update public.rh_equipment_movements m set registrado_por=split_part(trim(p.name),' ',1)
from public.profiles p where p.id=m.created_by and nullif(trim(p.name),'') is not null;
alter table public.rh_equipment_movements enable trigger equipment_validate;
create table public.rh_equipment_date_corrections (
 id uuid primary key default gen_random_uuid(),entrega_id uuid not null references public.rh_equipment_movements(id),
 funcionario_id uuid not null references public.funcionarios_epi(id),data_anterior date,data_corrigida date not null,
 motivo text not null check(length(trim(motivo)) between 3 and 500),created_by uuid not null references auth.users(id),
 primeiro_nome text not null default '',created_at timestamptz not null default now()
);
create index equipment_date_corrections_delivery on public.rh_equipment_date_corrections(entrega_id,created_at desc);
alter table public.rh_equipment_date_corrections enable row level security;
revoke all on public.rh_equipment_date_corrections from public,anon,authenticated;
grant select on public.rh_equipment_date_corrections to authenticated;
grant all on public.rh_equipment_date_corrections to service_role;
create policy equipment_date_corrections_read on public.rh_equipment_date_corrections for select to authenticated
using(rh_internal.can_read_employee(funcionario_id));
grant update(data_movimento) on public.rh_equipment_movements to authenticated;
create policy equipment_correct_date on public.rh_equipment_movements for update to authenticated
using(auth.uid() is not null and rh_internal.can_write() and rh_internal.can_read_employee(funcionario_id))
with check(auth.uid() is not null and rh_internal.can_write() and rh_internal.can_read_employee(funcionario_id));

-- Somente o gatilho pode escrever a auditoria. A autenticação e o acesso ao colaborador são verificados.
create function rh_internal.equipment_date_audit() returns trigger language plpgsql security definer set search_path='' as $$
begin
 if auth.uid() is null or not rh_internal.can_write() or not rh_internal.can_read_employee(new.funcionario_id) then raise exception 'Sem permissão para corrigir a entrega.';end if;
 if old.data_movimento is not distinct from new.data_movimento then return new;end if;
 insert into public.rh_equipment_date_corrections(entrega_id,funcionario_id,data_anterior,data_corrigida,motivo,created_by,primeiro_nome)
 values(new.id,new.funcionario_id,old.data_movimento,new.data_movimento,current_setting('rh.equipment_correction_reason',true),auth.uid(),coalesce((select split_part(trim(name),' ',1) from public.profiles where id=auth.uid()),''));
 return new;
end $$;
revoke all on function rh_internal.equipment_date_audit() from public,anon,authenticated;
create trigger equipment_date_audit after update of data_movimento on public.rh_equipment_movements for each row execute function rh_internal.equipment_date_audit();

create function public.rh_corrigir_data_entrega(p_entrega uuid,p_data date,p_data_anterior date,p_motivo text)
returns jsonb language plpgsql security invoker set search_path='' as $$
declare m public.rh_equipment_movements; emp uuid;texto text;ultima date;
begin
 if auth.uid() is null or not rh_internal.can_write() then raise exception 'Sem permissão para corrigir entregas.';end if;
 select funcionario_id into emp from public.rh_equipment_movements where id=p_entrega;
 if emp is null or not rh_internal.can_read_employee(emp) then raise exception 'Entrega indisponível.';end if;
 perform 1 from public.funcionarios_epi where id=emp for update;
 select * into m from public.rh_equipment_movements where id=p_entrega for update;
 if m.tipo<>'entrega' then raise exception 'Selecione uma entrega.';end if;
 if m.data_movimento is distinct from p_data_anterior then raise exception 'A data foi alterada por outro usuário. Atualize a tela.';end if;
 if p_data is null or p_data>(now() at time zone 'America/Sao_Paulo')::date then raise exception 'Informe uma data válida, sem usar data futura.';end if;
 if p_data=m.data_movimento then return to_jsonb(m);end if;
 if length(trim(coalesce(p_motivo,''))) not between 3 and 500 then raise exception 'Informe o motivo da correção (3 a 500 caracteres).';end if;
 perform set_config('rh.equipment_date_correction',m.id::text,true);
 perform set_config('rh.equipment_correction_reason',trim(p_motivo),true);
 update public.rh_equipment_movements set data_movimento=p_data where id=m.id returning * into m;
 perform set_config('rh.equipment_date_correction','',true);
 perform set_config('rh.equipment_correction_reason','',true);
 -- Mesma projeção utilizada no registro de entregas: mantém a lista e os alertas sincronizados.
 select string_agg(x.descricao||' ('||case when x.ca<>'' then 'CA: '||x.ca||', ' else '' end||'Qtd: '||s.saldo||case when x.data_movimento is not null then ' - '||coalesce((select max(v.data_verificacao) from public.rh_equipment_checks v where v.entrega_id=x.id),x.data_movimento)::text else '' end||')','; ' order by x.data_movimento desc nulls last,x.id),max(coalesce((select max(v.data_verificacao) from public.rh_equipment_checks v where v.entrega_id=x.id),x.data_movimento))
 into texto,ultima from public.rh_equipment_movements x
 cross join lateral(select x.quantidade-coalesce(sum(r.quantidade),0) saldo from public.rh_equipment_movements r where r.entrega_origem_id=x.id and r.tipo in ('devolucao','baixa')) s
 where x.funcionario_id=m.funcionario_id and x.categoria=m.categoria and x.tipo='entrega' and s.saldo>0;
 if m.categoria='epi' then update public.funcionarios_epi set epi_itens=coalesce(texto,''),epi_data=coalesce(to_char(ultima,'DD/MM/YYYY'),'') where id=m.funcionario_id;
 else update public.funcionarios_epi set fardamento_itens=coalesce(texto,''),fardamento_data=coalesce(to_char(ultima,'DD/MM/YYYY'),'') where id=m.funcionario_id;end if;
 return to_jsonb(m);
end $$;
revoke all on function public.rh_corrigir_data_entrega(uuid,date,date,text) from public,anon;
grant execute on function public.rh_corrigir_data_entrega(uuid,date,date,text) to authenticated;
-- A validação existente é atualizada no bloco seguinte, mantendo as regras de inserção.
CREATE OR REPLACE FUNCTION rh_internal.equipment_validate()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
declare e public.funcionarios_epi; original public.rh_equipment_movements; used integer;
begin
 if tg_op='UPDATE' then
 if auth.uid() is null or not rh_internal.can_write() or not rh_internal.can_read_employee(old.funcionario_id) then raise exception 'Sem permissão para corrigir entregas.';end if;
 if current_setting('rh.equipment_date_correction',true) is distinct from old.id::text then raise exception 'Use a ação Editar data para corrigir esta entrega.';end if;
 if old.tipo<>'entrega' or (to_jsonb(new)-'data_movimento') is distinct from (to_jsonb(old)-'data_movimento') then raise exception 'A correção permite alterar somente a data de entrega.';end if;
 if new.data_movimento is null or new.data_movimento>(now() at time zone 'America/Sao_Paulo')::date then raise exception 'Informe uma data válida, sem usar data futura.';end if;
 if exists(select 1 from public.rh_equipment_movements r where r.entrega_origem_id=old.id and r.data_movimento<new.data_movimento) or exists(select 1 from public.rh_equipment_checks v where v.entrega_id=old.id and v.data_verificacao<new.data_movimento) then raise exception 'A entrega não pode ficar após uma devolução, troca ou verificação já registrada.';end if;
 if old.entrega_origem_id is not null and exists(select 1 from public.rh_equipment_movements r where r.entrega_origem_id=old.entrega_origem_id and r.operacao_id=old.operacao_id and r.tipo in ('devolucao','baixa') and r.data_movimento>new.data_movimento) then raise exception 'O substituto não pode ser entregue antes da devolução de origem.';end if;
 return new;
end if;
 if tg_op<>'INSERT' then raise exception 'Histórico de equipamentos é imutável.'; end if;
 select * into e from public.funcionarios_epi where id=new.funcionario_id for update;
 if not found then raise exception 'Colaborador indisponível.'; end if;
 if current_user='authenticated' and (auth.uid() is null or not rh_internal.can_write() or not rh_internal.can_read_employee(e.id)) then raise exception 'Sem permissão para registrar equipamentos.'; end if;
 if new.legado then raise exception 'Importação de legado não permitida nesta operação.'; end if;
 if new.data_movimento > (now() at time zone 'America/Sao_Paulo')::date then raise exception 'Data da movimentação não pode estar no futuro.'; end if;
 if new.tipo='entrega' and e.data_desligamento is not null then raise exception 'Nova entrega bloqueada para colaborador desligado.'; end if;
 if new.entrega_origem_id is not null then
  select * into original from public.rh_equipment_movements where id=new.entrega_origem_id;
  if not found or original.tipo<>'entrega' or original.funcionario_id<>new.funcionario_id or original.categoria<>new.categoria then raise exception 'Entrega de origem inválida.'; end if;
  if new.data_movimento<original.data_movimento then raise exception 'Movimentação anterior à entrega original.'; end if;
  if new.tipo<>'entrega' then
   select coalesce(sum(quantidade),0) into used from public.rh_equipment_movements where entrega_origem_id=original.id and tipo in ('devolucao','baixa');
   if used+new.quantidade>original.quantidade then raise exception 'Quantidade superior ao saldo em posse. Atualize a tela.'; end if;
   new.equipamento=original.equipamento;new.complemento=original.complemento;new.ca=original.ca;
  end if;
 end if;
 new.equipamento=trim(new.equipamento);new.complemento=trim(new.complemento);
 new.descricao=new.equipamento||case when new.complemento<>'' then ' - '||new.complemento else '' end;
 new.created_by=auth.uid();new.created_at=now();new.registrado_por=coalesce((select split_part(trim(name),' ',1) from public.profiles where id=auth.uid()),'');
 return new;
end $function$;
commit;
