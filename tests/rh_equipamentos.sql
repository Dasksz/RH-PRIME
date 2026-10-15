-- Todos os lançamentos e notificações deste teste são revertidos.
begin;
select set_config('request.jwt.claim.sub',(select id::text from public.profiles where status='admin' limit 1),true);
set local role authenticated;
do $$
declare emp uuid; a uuid=gen_random_uuid(); b uuid=gen_random_uuid(); c uuid=gen_random_uuid(); origin uuid; replacement uuid; doc jsonb; again jsonb; before_snapshot jsonb; total integer;
begin
 select id into emp from public.funcionarios_epi where data_desligamento is null limit 1;
 if emp is null then raise exception 'Colaborador para teste indisponível.'; end if;
 doc=public.rh_registrar_equipamentos(emp,'epi',a,jsonb_build_array(jsonb_build_object('equipamento','BOTA','complemento','TESTE - tamanho 42','ca','12345','quantidade',2,'data',current_date::text)),null);
 select id into origin from public.rh_equipment_movements where operacao_id=a and tipo='entrega';
 before_snapshot=doc->'snapshot';
 doc=public.rh_registrar_equipamentos(emp,'epi',b,jsonb_build_array(jsonb_build_object('equipamento','BOTA','complemento','OUTRA MARCA - tamanho 42','ca','67890','quantidade',1,'data',current_date::text)),jsonb_build_object('origem',origin,'tipo','devolucao','quantidade',1,'data',current_date::text,'motivo','Rasgo','observacao','Costura lateral'));
 select id into replacement from public.rh_equipment_movements where operacao_id=b and tipo='entrega';
 if not exists(select 1 from public.rh_equipment_movements where id=replacement and entrega_origem_id=origin) then raise exception 'Substituto sem vínculo'; end if;
 select quantidade-(select coalesce(sum(quantidade),0) from public.rh_equipment_movements where entrega_origem_id=origin and tipo<>'entrega') into total from public.rh_equipment_movements where id=origin;
 if total<>1 then raise exception 'Saldo parcial incorreto'; end if;
 again=public.rh_registrar_equipamentos(emp,'epi',b,'[]',null);
 if doc<>again then raise exception 'Repetição alterou comprovante'; end if;
 if (select snapshot from public.rh_equipment_receipts where id=a)<>before_snapshot then raise exception 'Ficha antiga alterada'; end if;
 begin
  perform public.rh_registrar_equipamentos(emp,'epi',c,'[]',jsonb_build_object('origem',origin,'tipo','devolucao','quantidade',2,'data',current_date::text,'motivo','Excesso'));
  raise exception 'TESTE_FALHOU_EXCESSO';
 exception when others then if sqlerrm='TESTE_FALHOU_EXCESSO' then raise; end if; end;
 if exists(select 1 from public.rh_equipment_movements where operacao_id=c) then raise exception 'Falha deixou registro parcial'; end if;
 begin
  update public.rh_equipment_movements set motivo='alterado' where id=origin;
  raise exception 'TESTE_FALHOU_IMUTAVEL';
 exception when others then if sqlerrm='TESTE_FALHOU_IMUTAVEL' then raise; end if; end;
 raise notice 'OK: entrega, complemento, troca, devolução parcial, saldo, idempotência, snapshot e rollback de falha.';
end $$;
rollback;
