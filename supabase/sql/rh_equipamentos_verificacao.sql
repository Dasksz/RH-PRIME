-- Verificação única com várias devoluções e substituições; mantém compatibilidade com o formulário anterior.
create or replace function public.rh_registrar_equipamentos(p_funcionario uuid,p_categoria text,p_operacao uuid,p_itens jsonb default '[]',p_devolucao jsonb default null)
returns jsonb language plpgsql security invoker set search_path='' as $$
declare e public.funcionarios_epi; receipt public.rh_equipment_receipts; it jsonb; dev jsonb; devolucoes jsonb; origem uuid; texto text; ultima date;
begin
 if auth.uid() is null or not rh_internal.can_write() or not rh_internal.can_read_employee(p_funcionario) then raise exception 'Acesso não autorizado.'; end if;
 select * into e from public.funcionarios_epi where id=p_funcionario for update;
 if not found then raise exception 'Colaborador indisponível.'; end if;
 select * into receipt from public.rh_equipment_receipts where id=p_operacao;
 if found then
  if receipt.funcionario_id<>p_funcionario or receipt.categoria<>p_categoria then raise exception 'Operação já utilizada.'; end if;
  return to_jsonb(receipt);
 end if;
 if p_categoria not in ('epi','fardamento') or p_itens is null or jsonb_typeof(p_itens)<>'array' or jsonb_array_length(p_itens)>100 then raise exception 'Lista de equipamentos inválida.'; end if;
 devolucoes=case when p_devolucao is null or p_devolucao='null'::jsonb then '[]'::jsonb when jsonb_typeof(p_devolucao)='object' then jsonb_build_array(p_devolucao) else p_devolucao end;
 if jsonb_typeof(devolucoes)<>'array' or jsonb_array_length(devolucoes)>100 then raise exception 'Lista de devoluções inválida.'; end if;
 for dev in select value from jsonb_array_elements(devolucoes) loop
  if jsonb_typeof(dev)<>'object' or coalesce(dev->>'tipo','devolucao') not in ('devolucao','baixa') then raise exception 'Tipo de devolução inválido.'; end if;
  origem=(dev->>'origem')::uuid;
  insert into public.rh_equipment_movements(funcionario_id,operacao_id,categoria,tipo,equipamento,descricao,quantidade,data_movimento,entrega_origem_id,motivo,observacao,comprovante)
  values(p_funcionario,p_operacao,p_categoria,coalesce(dev->>'tipo','devolucao'),'','',(dev->>'quantidade')::integer,(dev->>'data')::date,origem,dev->>'motivo',coalesce(dev->>'observacao',''),coalesce(dev->>'comprovante',''));
 end loop;
 for it in select value from jsonb_array_elements(p_itens) loop
  if it->>'acao'='verificacao' then
   insert into public.rh_equipment_checks(funcionario_id,entrega_id,operacao_id,categoria,descricao,quantidade,data_verificacao,observacao)
   values(p_funcionario,(it->>'origem')::uuid,p_operacao,p_categoria,'',1,(it->>'data')::date,coalesce(it->>'observacao',''));
   continue;
  elsif it ? 'acao' and it->>'acao'<>'entrega' then raise exception 'Ação inválida.';
  end if;
  origem=coalesce(nullif(it->>'origem','')::uuid,case when jsonb_typeof(p_devolucao)='object' then (p_devolucao->>'origem')::uuid else null end);
  if origem is not null and not exists(select 1 from jsonb_array_elements(devolucoes) d where (d->>'origem')::uuid=origem and (it->>'data')::date>=(d->>'data')::date) then raise exception 'Substituto sem devolução/baixa correspondente ou com data anterior.'; end if;
  insert into public.rh_equipment_movements(funcionario_id,operacao_id,categoria,tipo,equipamento,complemento,descricao,ca,quantidade,data_movimento,entrega_origem_id,motivo,comprovante)
  values(p_funcionario,p_operacao,p_categoria,'entrega',it->>'equipamento',coalesce(it->>'complemento',''),'',coalesce(it->>'ca',''),(it->>'quantidade')::integer,(it->>'data')::date,origem,case when origem is null then '' else 'Substituição de equipamento' end,coalesce(it->>'comprovante',''));
 end loop;
 -- Os campos antigos passam a representar somente o saldo em posse.
 if jsonb_array_length(p_itens)>0 or jsonb_array_length(devolucoes)>0 then
  select string_agg(m.descricao||' ('||case when m.ca<>'' then 'CA: '||m.ca||', ' else '' end||'Qtd: '||s.saldo||case when m.data_movimento is not null then ' - '||coalesce((select max(v.data_verificacao) from public.rh_equipment_checks v where v.entrega_id=m.id),m.data_movimento)::text else '' end||')','; ' order by m.data_movimento desc nulls last,m.id), max(coalesce((select max(v.data_verificacao) from public.rh_equipment_checks v where v.entrega_id=m.id),m.data_movimento))
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
