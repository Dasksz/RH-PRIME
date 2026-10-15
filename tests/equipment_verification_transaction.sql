-- Teste integral sem persistir registros: todas as alterações são revertidas.
begin;
select set_config('request.jwt.claim.sub',(select id::text from public.profiles where status='admin' limit 1),true);
set local role authenticated;
do $$
declare emp uuid; op1 uuid:=gen_random_uuid(); op2 uuid:=gen_random_uuid(); op3 uuid:=gen_random_uuid(); op4 uuid:=gen_random_uuid();
 a uuid; b uuid; replacement uuid; rec jsonb; n integer; before_n integer; today date:=(now() at time zone 'America/Sao_Paulo')::date;
begin
 select id into emp from public.funcionarios_epi where data_desligamento is null limit 1;
 if emp is null then raise exception 'Fixture indisponível'; end if;
 perform public.rh_registrar_equipamentos(emp,'epi',op1,jsonb_build_array(
  jsonb_build_object('equipamento','TESTE TRANSACIONAL BOTA','quantidade',2,'data',today-1),
  jsonb_build_object('equipamento','TESTE TRANSACIONAL LUVA','quantidade',1,'data',today-1)),null);
 select id into a from public.rh_equipment_movements where operacao_id=op1 and equipamento='TESTE TRANSACIONAL BOTA';
 select id into b from public.rh_equipment_movements where operacao_id=op1 and equipamento='TESTE TRANSACIONAL LUVA';
 perform public.rh_registrar_equipamentos(emp,'epi',op2,jsonb_build_array(
  jsonb_build_object('equipamento','TESTE SUBSTITUTO BOTA','quantidade',1,'data',today,'origem',a),
  jsonb_build_object('equipamento','TESTE SUBSTITUTO LUVA','quantidade',1,'data',today,'origem',b)),jsonb_build_array(
  jsonb_build_object('origem',a,'quantidade',1,'data',today,'motivo','Rasgo'),
  jsonb_build_object('origem',b,'quantidade',1,'data',today,'motivo','Defeito')));
 select count(*) into n from public.rh_equipment_movements where operacao_id=op2;
 if n<>4 then raise exception 'Esperadas quatro movimentações: %',n; end if;
 perform public.rh_registrar_equipamentos(emp,'epi',op2,'[]','[]');
 select count(*) into n from public.rh_equipment_receipts where id=op2;
 if n<>1 then raise exception 'Idempotência falhou'; end if;
 select id into replacement from public.rh_equipment_movements where operacao_id=op2 and equipamento='TESTE SUBSTITUTO LUVA';
 rec:=public.rh_registrar_equipamentos(emp,'epi',op3,jsonb_build_array(
  jsonb_build_object('acao','verificacao','origem',a,'data',today),
  jsonb_build_object('acao','verificacao','origem',replacement,'data',today)),'[]');
 select count(*) into n from public.rh_equipment_movements where operacao_id=op3;
 if n<>0 then raise exception 'Conferência gerou entrega indevida'; end if;
 select count(*) into n from public.rh_equipment_checks where operacao_id=op3;
 if n<>2 then raise exception 'Esperadas duas conferências'; end if;
 if not exists(select 1 from public.rh_equipment_checks where operacao_id=op3 and entrega_id=a and quantidade=1) then raise exception 'Saldo parcial conferido incorreto'; end if;
 if not exists(select 1 from public.rh_equipment_movements where id=a and data_movimento=today-1) then raise exception 'Data original alterada'; end if;
 if jsonb_array_length(rec->'snapshot'->'verificacoes')<2 then raise exception 'Conferências ausentes da ficha'; end if;
 if not exists(select 1 from public.funcionarios_epi where id=emp and epi_itens like '%TESTE TRANSACIONAL BOTA (Qtd: 1 - '||today::text||')%') then raise exception 'Prazo periódico não atualizado no resumo'; end if;
 select count(*) into before_n from public.rh_equipment_movements where funcionario_id=emp;
 begin
  perform public.rh_registrar_equipamentos(emp,'epi',op4,'[]',jsonb_build_array(
   jsonb_build_object('origem',a,'quantidade',1,'data',today,'motivo','Rasgo'),
   jsonb_build_object('origem',b,'quantidade',1,'data',today,'motivo','Defeito')));
  raise exception 'SALDO_NAO_VALIDADO';
 exception when others then if sqlerrm='SALDO_NAO_VALIDADO' then raise; end if; end;
 select count(*) into n from public.rh_equipment_movements where funcionario_id=emp;
 if n<>before_n then raise exception 'Falha de atomicidade'; end if;
 begin
  perform public.rh_registrar_equipamentos(emp,'epi',op4,jsonb_build_array(jsonb_build_object('acao','verificacao','origem',b,'data',today)),'[]');
  raise exception 'ITEM_DEVOLVIDO_VERIFICADO';
 exception when others then if sqlerrm='ITEM_DEVOLVIDO_VERIFICADO' then raise; end if; end;
 perform set_config('request.jwt.claim.sub','',true);
 begin
  perform public.rh_registrar_equipamentos(emp,'epi',op4,'[]','[]');raise exception 'ACESSO_ANONIMO_PERMITIDO';
 exception when others then if sqlerrm='ACESSO_ANONIMO_PERMITIDO' then raise; end if; end;
end $$;
rollback;
