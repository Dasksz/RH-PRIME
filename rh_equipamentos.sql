-- Histórico de equipamentos: registros imutáveis e trocas atômicas.
create table public.rh_equipment_movements (
 id uuid primary key default gen_random_uuid(),
 funcionario_id uuid not null references public.funcionarios_epi(id),
 operacao_id uuid not null,
 categoria text not null check(categoria in ('epi','fardamento')),
 tipo text not null check(tipo in ('entrega','devolucao','baixa')),
 equipamento text not null check(length(trim(equipamento)) between 1 and 200),
 complemento text not null default '' check(length(complemento)<=300),
 descricao text not null,
 ca text not null default '' check(length(ca)<=80),
 quantidade integer not null check(quantidade between 1 and 10000),
 data_movimento date,
 entrega_origem_id uuid references public.rh_equipment_movements(id),
 motivo text not null default '' check(length(motivo)<=300),
 observacao text not null default '' check(length(observacao)<=2000),
 comprovante text not null default '' check(comprovante='' or comprovante ~ '^https?://'),
 legado boolean not null default false,
 legado_chave text unique,
 created_by uuid default auth.uid(), created_at timestamptz not null default now(),
 check((tipo='entrega') or (entrega_origem_id is not null and length(trim(motivo))>0)),
 check(legado or data_movimento is not null)
);
create index rh_equipment_employee on public.rh_equipment_movements(funcionario_id,categoria,data_movimento);
create index rh_equipment_origin on public.rh_equipment_movements(entrega_origem_id);
create index rh_equipment_operation on public.rh_equipment_movements(operacao_id);
create table public.rh_equipment_receipts (
 id uuid primary key,
 funcionario_id uuid not null references public.funcionarios_epi(id),
 categoria text not null check(categoria in ('epi','fardamento')),
 snapshot jsonb not null,
 created_by uuid default auth.uid(), created_at timestamptz not null default now()
);
alter table public.rh_equipment_movements enable row level security;
alter table public.rh_equipment_receipts enable row level security;
revoke all on public.rh_equipment_movements,public.rh_equipment_receipts from public,anon,authenticated;
grant select,insert on public.rh_equipment_movements,public.rh_equipment_receipts to authenticated;
grant all on public.rh_equipment_movements,public.rh_equipment_receipts to service_role;
create policy equipment_read on public.rh_equipment_movements for select to authenticated using(rh_internal.can_read_employee(funcionario_id));
create policy equipment_insert on public.rh_equipment_movements for insert to authenticated with check(rh_internal.can_write() and rh_internal.can_read_employee(funcionario_id) and created_by=auth.uid() and not legado);
create policy equipment_receipt_read on public.rh_equipment_receipts for select to authenticated using(rh_internal.can_read_employee(funcionario_id));
create policy equipment_receipt_insert on public.rh_equipment_receipts for insert to authenticated with check(rh_internal.can_write() and rh_internal.can_read_employee(funcionario_id) and created_by=auth.uid());

-- Importação fiel do texto legado: datas desconhecidas permanecem desconhecidas.
create function rh_internal.equipment_legacy_date(v text) returns date language plpgsql immutable set search_path='' as $$
begin
 if trim(coalesce(v,'')) ~ '^\d{4}-\d{2}-\d{2}$' then return trim(v)::date; end if;
 if trim(coalesce(v,'')) ~ '^\d{2}/\d{2}/\d{4}$' then return to_date(trim(v),'DD/MM/YYYY'); end if;
 return null;
exception when others then return null; end $$;
revoke all on function rh_internal.equipment_legacy_date(text) from public,anon,authenticated;
insert into public.rh_equipment_movements(funcionario_id,operacao_id,categoria,tipo,equipamento,descricao,ca,quantidade,data_movimento,comprovante,legado,legado_chave)
select e.id,gen_random_uuid(),v.categoria,'entrega',
 coalesce(nullif(trim(m.parts[1]),''),trim(p.item)),coalesce(nullif(trim(m.parts[1]),''),trim(p.item)),
 coalesce(trim(m.parts[2]),''),coalesce(nullif(m.parts[3],'')::integer,1),
 rh_internal.equipment_legacy_date(coalesce(m.parts[4],v.data)),
 case when coalesce(v.link,'') ~ '^https?://' then v.link else '' end,true,e.id::text||':'||v.categoria||':'||p.idx
from public.funcionarios_epi e
cross join lateral (values ('epi',e.epi_itens,e.epi_data,e.epi_link),('fardamento',e.fardamento_itens,e.fardamento_data,e.fardamento_link)) v(categoria,itens,data,link)
cross join lateral regexp_split_to_table(coalesce(v.itens,''),';') with ordinality p(item,idx)
cross join lateral (select regexp_match(trim(p.item),'^(.*?)\s*\((?:CA:\s*(.*?),\s*)?Qtd:\s*([0-9]+)(?:\s*-\s*(\d{4}-\d{2}-\d{2}|\d{2}/\d{2}/\d{4}))?\)$','i') parts) m
where trim(p.item)<>'' and coalesce(nullif(m.parts[3],'')::numeric,1) between 1 and 10000;

create function rh_internal.equipment_validate() returns trigger language plpgsql security invoker set search_path='' as $$
declare e public.funcionarios_epi; original public.rh_equipment_movements; used integer;
begin
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
 new.created_by=auth.uid();new.created_at=now();
 return new;
end $$;
revoke all on function rh_internal.equipment_validate() from public,anon,authenticated;
create trigger equipment_validate before insert or update or delete on public.rh_equipment_movements for each row execute function rh_internal.equipment_validate();

-- A fotografia do documento é produzida pelo banco, nunca aceita do navegador.
create function rh_internal.equipment_receipt_snapshot() returns trigger language plpgsql security invoker set search_path='' as $$
begin
 if tg_op<>'INSERT' then raise exception 'Documento emitido é imutável.'; end if;
 new.created_by=auth.uid();new.created_at=now();
 select jsonb_build_object('colaborador',jsonb_build_object('nome',e.nome,'cpf',e.cpf,'funcao',e.funcao,'setor',e.setor,'unidade',e.unidade,'admissao',e.admissao,'local_registro',e.local_registro),
  'empresa',coalesce((select to_jsonb(x) from public.empresas x where x.cnpj=case when upper(e.local_registro) like '%JEQUI%' then '52.522.019/0002-82' when upper(e.local_registro) like '%ILH%' then '52.522.019/0001-00' when upper(e.local_registro) like '%NUNES%' or upper(e.local_registro) like '%VIEIRA%' or upper(e.local_registro) like '%ITABUNA%' then '48.986.353/0001-39' end limit 1),'{}'::jsonb),
  'categoria',new.categoria,'emitido_em',new.created_at,'operacao_id',new.id,
  'movimentos',coalesce((select jsonb_agg(to_jsonb(m) order by m.data_movimento nulls first,m.created_at,m.id) from public.rh_equipment_movements m where m.funcionario_id=e.id and m.categoria=new.categoria),'[]'::jsonb)) into new.snapshot
 from public.funcionarios_epi e where e.id=new.funcionario_id;
 if new.snapshot is null then raise exception 'Colaborador indisponível.'; end if;
 return new;
end $$;
revoke all on function rh_internal.equipment_receipt_snapshot() from public,anon,authenticated;
create trigger equipment_receipt_snapshot before insert or update or delete on public.rh_equipment_receipts for each row execute function rh_internal.equipment_receipt_snapshot();

create function public.rh_registrar_equipamentos(p_funcionario uuid,p_categoria text,p_operacao uuid,p_itens jsonb default '[]',p_devolucao jsonb default null)
returns jsonb language plpgsql security invoker set search_path='' as $$
declare e public.funcionarios_epi; receipt public.rh_equipment_receipts; it jsonb; origem uuid; texto text; ultima date;
begin
 if auth.uid() is null or not rh_internal.can_write() or not rh_internal.can_read_employee(p_funcionario) then raise exception 'Acesso não autorizado.'; end if;
 select * into e from public.funcionarios_epi where id=p_funcionario for update;
 if not found then raise exception 'Colaborador indisponível.'; end if;
 select * into receipt from public.rh_equipment_receipts where id=p_operacao;
 if found then
  if receipt.funcionario_id<>p_funcionario or receipt.categoria<>p_categoria then raise exception 'Operação já utilizada.'; end if;
  return to_jsonb(receipt);
 end if;
 if p_categoria not in ('epi','fardamento') or jsonb_typeof(p_itens)<>'array' or jsonb_array_length(p_itens)>100 then raise exception 'Lista de equipamentos inválida.'; end if;
 if p_devolucao is not null then
  if coalesce(p_devolucao->>'tipo','devolucao') not in ('devolucao','baixa') then raise exception 'Tipo de devolução inválido.'; end if;
  origem=(p_devolucao->>'origem')::uuid;
  insert into public.rh_equipment_movements(funcionario_id,operacao_id,categoria,tipo,equipamento,descricao,quantidade,data_movimento,entrega_origem_id,motivo,observacao,comprovante)
  values(p_funcionario,p_operacao,p_categoria,coalesce(p_devolucao->>'tipo','devolucao'),'','',(p_devolucao->>'quantidade')::integer,(p_devolucao->>'data')::date,origem,p_devolucao->>'motivo',coalesce(p_devolucao->>'observacao',''),coalesce(p_devolucao->>'comprovante',''));
 end if;
 for it in select value from jsonb_array_elements(p_itens) loop
  insert into public.rh_equipment_movements(funcionario_id,operacao_id,categoria,tipo,equipamento,complemento,descricao,ca,quantidade,data_movimento,entrega_origem_id,motivo,comprovante)
  values(p_funcionario,p_operacao,p_categoria,'entrega',it->>'equipamento',coalesce(it->>'complemento',''),'',coalesce(it->>'ca',''),(it->>'quantidade')::integer,(it->>'data')::date,origem,case when origem is null then '' else 'Substituição de equipamento' end,coalesce(it->>'comprovante',''));
 end loop;
 -- Os campos antigos passam a representar somente o saldo em posse.
 if jsonb_array_length(p_itens)>0 or p_devolucao is not null then
  select string_agg(m.descricao||' ('||case when m.ca<>'' then 'CA: '||m.ca||', ' else '' end||'Qtd: '||s.saldo||case when m.data_movimento is not null then ' - '||m.data_movimento::text else '' end||')','; ' order by m.data_movimento desc nulls last,m.id), max(m.data_movimento)
  into texto,ultima from public.rh_equipment_movements m
  cross join lateral (select m.quantidade-coalesce(sum(r.quantidade),0) saldo from public.rh_equipment_movements r where r.entrega_origem_id=m.id and r.tipo in ('devolucao','baixa')) s
  where m.funcionario_id=p_funcionario and m.categoria=p_categoria and m.tipo='entrega' and s.saldo>0;
  if p_categoria='epi' then update public.funcionarios_epi set epi_itens=coalesce(texto,''),epi_data=coalesce(to_char(ultima,'DD/MM/YYYY'),'') where id=p_funcionario;
  else update public.funcionarios_epi set fardamento_itens=coalesce(texto,''),fardamento_data=coalesce(to_char(ultima,'DD/MM/YYYY'),'') where id=p_funcionario;end if;
 end if;
 insert into public.rh_equipment_receipts(id,funcionario_id,categoria,snapshot) values(p_operacao,p_funcionario,p_categoria,'{}') returning * into receipt;
 return to_jsonb(receipt);
end $$;
revoke all on function public.rh_registrar_equipamentos(uuid,text,uuid,jsonb,jsonb) from public,anon;
grant execute on function public.rh_registrar_equipamentos(uuid,text,uuid,jsonb,jsonb) to authenticated;
notify pgrst,'reload schema';
