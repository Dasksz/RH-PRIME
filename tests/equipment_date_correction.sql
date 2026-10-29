-- Teste transacional: toda movimentação, auditoria e webhook enfileirado é revertido.
begin;
select set_config('request.jwt.claim.sub',(select id::text from public.profiles where status='admin' limit 1),true);
set local role authenticated;
do $$
declare emp uuid;op uuid=gen_random_uuid();ret uuid=gen_random_uuid();delivery uuid;before_snapshot jsonb;receipt jsonb;result jsonb;today date=(now() at time zone 'America/Sao_Paulo')::date;
begin
 select id into emp from public.funcionarios_epi where data_desligamento is null limit 1;
 receipt=public.rh_registrar_equipamentos(emp,'fardamento',op,jsonb_build_array(jsonb_build_object('equipamento','TESTE CORRECAO DATA','quantidade',2,'data',(today-60)::text)),null);
 select id into delivery from public.rh_equipment_movements where operacao_id=op and tipo='entrega';
 before_snapshot=receipt->'snapshot';
 result=public.rh_corrigir_data_entrega(delivery,today-30,today-60,'Teste transacional de correção');
 if result->>'data_movimento'<>(today-30)::text then raise exception 'A nova data não foi persistida';end if;
 if (select quantidade from public.rh_equipment_movements where id=delivery)<>2 then raise exception 'Quantidade modificada';end if;
 if not exists(select 1 from public.rh_equipment_date_corrections where entrega_id=delivery and data_anterior=today-60 and data_corrigida=today-30 and created_by=auth.uid() and primeiro_nome<>'') then raise exception 'Auditoria ou autor ausente';end if;
 if (select registrado_por from public.rh_equipment_movements where id=delivery)='' then raise exception 'Autor da entrega não registrado';end if;
 if (select snapshot from public.rh_equipment_receipts where id=op)<>before_snapshot then raise exception 'Documento anterior foi modificado';end if;
 begin
  perform public.rh_corrigir_data_entrega(delivery,today-20,today-60,'Teste de concorrência');raise exception 'FALHOU_CONCORRENCIA';
 exception when others then if sqlerrm='FALHOU_CONCORRENCIA' then raise;end if;end;
 begin
  perform public.rh_corrigir_data_entrega(delivery,today+1,today-30,'Data futura não permitida');raise exception 'FALHOU_FUTURO';
 exception when others then if sqlerrm='FALHOU_FUTURO' then raise;end if;end;
 perform public.rh_registrar_equipamentos(emp,'fardamento',ret,'[]',jsonb_build_object('origem',delivery,'tipo','devolucao','quantidade',1,'data',(today-10)::text,'motivo','Teste'));
 begin
  perform public.rh_corrigir_data_entrega(delivery,today-5,today-30,'Entrega após devolução');raise exception 'FALHOU_ORDEM';
 exception when others then if sqlerrm='FALHOU_ORDEM' then raise;end if;end;
 if (select data_movimento from public.rh_equipment_movements where id=delivery)<>today-30 then raise exception 'Falha deixou data parcial';end if;
 if (select count(*) from public.rh_equipment_date_corrections where entrega_id=delivery)<>1 then raise exception 'Auditoria duplicada';end if;
 if not exists(select 1 from public.funcionarios_epi where id=emp and fardamento_itens like '%TESTE CORRECAO DATA%') then raise exception 'Projeção não sincronizada';end if;
 begin
  update public.rh_equipment_movements set data_movimento=today-25 where id=delivery;raise exception 'FALHOU_UPDATE_DIRETO';
 exception when others then if sqlerrm='FALHOU_UPDATE_DIRETO' then raise;end if;end;
 perform set_config('request.jwt.claim.sub','',true);
 begin
  perform public.rh_corrigir_data_entrega(delivery,today-25,today-30,'Sem autenticação');raise exception 'FALHOU_AUTH';
 exception when others then if sqlerrm='FALHOU_AUTH' then raise;end if;end;
end $$;
rollback;
