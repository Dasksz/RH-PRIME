-- Após rh_experiencia.sql e rh_experiencia_periodos.sql. Nenhuma chamada externa; rollback integral.
begin;
do $$
declare e uuid;p uuid;n uuid;first_notice uuid;today date=(now() at time zone 'America/Sao_Paulo')::date;
 test record;expected integer;token text=repeat('a',64);payload jsonb;begin
 select id into p from public.profiles where status='admin' limit 1;
 select f.id into e from public.funcionarios_epi f where f.data_desligamento is null
 and not exists(select 1 from public.rh_admin_notifications n where n.employee_id=f.id and n.experience_admission is not null) limit 1;
 if e is null or p is null then raise exception 'Fixture indisponível';end if;
 update public.profiles set name='  CARLOS   EDUARDO  ',whatsapp='5511999999999',experience_notifications=true where id=p;
 update public.funcionarios_epi set manager_profile_id=p where id=e;
 for test in select * from (values(37,0),(38,1),(44,1),(45,0),(82,0),(83,2),(89,2),(90,0)) v(day,period) loop
  update public.funcionarios_epi set admissao=to_char(today-test.day,'DD/MM/YYYY') where id=e;
  perform rh_internal.experience_queue();perform rh_internal.experience_queue();
  expected=case when test.period=0 then 0 else 1 end;
  if (select count(*) from public.rh_admin_notifications where employee_id=e and experience_admission=today-test.day)<>expected
  then raise exception 'Contagem inválida no dia %',test.day;end if;
  if test.period<>0 then
   select id into n from public.rh_admin_notifications where employee_id=e and experience_admission=today-test.day;
   if not rh_internal.experience_event_valid(n) or
   (select experience_period from public.rh_admin_notifications where id=n)<>test.period
   then raise exception 'Período incorreto no dia %',test.day;end if;
   if test.day in (38,83) and (select position('*Dias restantes neste período:* 7' in message_text) from public.rh_admin_notifications where id=n)=0
   then raise exception 'Mensagem deve indicar 7 dias restantes';end if;
   if (select position(to_char(today-test.day+case test.period when 1 then 45 else 90 end,'DD/MM/YYYY') in message_text) from public.rh_admin_notifications where id=n)=0
   then raise exception 'Data de término incorreta';end if;
   if (select position('Olá, Carlos!' in message_text)=0 or message_text ~ 'https?://' from public.rh_admin_notifications where id=n)
   then raise exception 'Mensagem deve usar o primeiro nome e não deve conter link';end if;
  end if;
 end loop;
 -- Primeiro período já avisado não impede o aviso do segundo para a mesma admissão.
 update public.funcionarios_epi set admissao=(today-83)::text where id=e;
 select id into n from public.rh_admin_notifications where employee_id=e and experience_admission=today-83 and experience_period=2;
 insert into public.rh_admin_notifications(employee_id,employee_name,source_table,operation,title,message_text,
 recipient_profile_id,recipient_phone,experience_admission,experience_period,whatsapp_status)
 select employee_id,employee_name,'experiencia','ALERTA','Fixture primeiro período','Fixture sem envio',
 recipient_profile_id,recipient_phone,experience_admission,1,'aceito' from public.rh_admin_notifications where id=n
 returning id into first_notice;
 perform rh_internal.experience_queue();
 if (select count(*) from public.rh_admin_notifications where employee_id=e and experience_admission=today-83)<>2
 then raise exception 'Os dois períodos devem ser independentes';end if;
 if rh_internal.experience_event_valid(first_notice) then raise exception 'Primeiro período vencido aceito';end if;
 update public.funcionarios_epi set data_desligamento=today where id=e;
 if rh_internal.experience_event_valid(n) then raise exception 'Desligado aceito';end if;
 update public.funcionarios_epi set data_desligamento=null,manager_profile_id=null where id=e;
 if rh_internal.experience_event_valid(n) then raise exception 'Sem gestor aceito';end if;
 update public.funcionarios_epi set manager_profile_id=p where id=e;
 update public.profiles set whatsapp='5521999999999' where id=p;
 if rh_internal.experience_event_valid(n) then raise exception 'Telefone alterado aceito';end if;
 update public.profiles set whatsapp='5511999999999',experience_notifications=false where id=p;
 if rh_internal.experience_event_valid(n) then raise exception 'Avisos desativados aceitos';end if;
 update public.profiles set experience_notifications=true where id=p;
 update public.rh_admin_notifications set whatsapp_status='aguardando' where id=n;
 insert into rh_internal.notification_dispatch(id,token,expires_at) values(n,token,now()+interval '10 minutes');
 begin
  perform public.rh_notification_claim(n,repeat('b',64));raise exception 'Token incorreto aceito';
 exception when raise_exception then if sqlerrm='Token incorreto aceito' then raise;end if;end;
 payload=public.rh_notification_claim(n,token);
 if payload->>'chatId'<>'5511999999999@c.us' or position('2º período' in payload->>'message')=0
 then raise exception 'Destinatário ou mensagem incorretos';end if;
 begin
  perform public.rh_notification_claim(n,token);raise exception 'Evento repetido aceito';
 exception when raise_exception then if sqlerrm='Evento repetido aceito' then raise;end if;end;
 perform public.rh_notification_complete(n,token,true);
 perform rh_internal.experience_queue();
 if (select whatsapp_status from public.rh_admin_notifications where id=n)<>'aceito'
 or (select whatsapp_status from public.rh_admin_notifications where id=first_notice)<>'aceito'
 then raise exception 'Um período já enviado foi reaberto';end if;
 if rh_internal.experience_date('31/02/2026') is not null then raise exception 'Data inválida aceita';end if;
end $$;
select 'PASS: dias 37/38/44/45/82/83/89/90, dois avisos independentes, primeiro nome, ausência de link, gestores, desligamento, opt-in, tokens e duplicidade; nenhum envio externo' as result;
rollback;

