-- Executar depois de rh_experiencia.sql. Fixtures transitórias; nunca dispara HTTP/WhatsApp.
begin;
do $$
declare e uuid;p uuid;notice uuid;today date=(now() at time zone 'America/Sao_Paulo')::date;
 token text=repeat('a',64);payload jsonb;begin
 select id into p from public.profiles where status='admin' limit 1;
 select id into e from public.funcionarios_epi where data_desligamento is null limit 1;
 if e is null or p is null then raise exception 'Necessário um administrador e colaborador para fixtures';end if;
 update public.profiles set whatsapp='5511999999999',experience_notifications=true where id=p;
 update public.funcionarios_epi set manager_profile_id=p,admissao=to_char(today-79,'DD/MM/YYYY') where id=e;
 perform rh_internal.experience_queue();
 if exists(select 1 from public.rh_admin_notifications where employee_id=e and experience_admission=today-79)
 then raise exception 'Aviso antecipado no dia 79';end if;
 update public.funcionarios_epi set admissao=to_char(today-80,'DD/MM/YYYY') where id=e;
 perform rh_internal.experience_queue();perform rh_internal.experience_queue();
 if (select count(*) from public.rh_admin_notifications where employee_id=e and experience_admission=today-80)<>1
 then raise exception 'Aviso ausente ou duplicado no dia 80';end if;
 select id into notice from public.rh_admin_notifications where employee_id=e and experience_admission=today-80;
 if not rh_internal.experience_event_valid(notice) then raise exception 'Evento elegível rejeitado';end if;
 if rh_internal.experience_date('31/02/2026') is not null or rh_internal.experience_date('data inválida') is not null
 or rh_internal.experience_date('2026-02-28')<>'2026-02-28'::date then raise exception 'Conversão de admissão inválida';end if;
 update public.funcionarios_epi set data_desligamento=today where id=e;
 if rh_internal.experience_event_valid(notice) then raise exception 'Desligado aceito';end if;
 update public.funcionarios_epi set data_desligamento=null,manager_profile_id=null where id=e;
 if rh_internal.experience_event_valid(notice) then raise exception 'Sem gestor aceito';end if;
 update public.funcionarios_epi set manager_profile_id=p where id=e;
 update public.profiles set whatsapp='5521999999999' where id=p;
 if rh_internal.experience_event_valid(notice) then raise exception 'Telefone alterado aceito';end if;
 update public.profiles set whatsapp='5511999999999',experience_notifications=false where id=p;
 if rh_internal.experience_event_valid(notice) then raise exception 'Avisos desativados aceitos';end if;
 update public.profiles set experience_notifications=true where id=p;
 update public.funcionarios_epi set admissao=(today-90)::text where id=e;
 perform rh_internal.experience_queue();
 if exists(select 1 from public.rh_admin_notifications where employee_id=e and experience_admission=today-90)
 then raise exception 'Contrato terminado aceito';end if;
 if rh_internal.experience_event_valid(notice) then raise exception 'Admissão alterada aceita';end if;
 update public.funcionarios_epi set admissao=(today-89)::text where id=e;
 perform rh_internal.experience_queue();
 if not exists(select 1 from public.rh_admin_notifications where employee_id=e and experience_admission=today-89)
 then raise exception 'Aviso de recuperação ausente no dia 89';end if;
 update public.funcionarios_epi set admissao=(today-80)::text where id=e;
 update public.rh_admin_notifications set whatsapp_status='aguardando' where id=notice;
 insert into rh_internal.notification_dispatch(id,token,expires_at) values(notice,token,now()+interval '10 minutes');
 begin
  perform public.rh_notification_claim(notice,repeat('b',64));raise exception 'Token incorreto aceito';
 exception when raise_exception then if sqlerrm='Token incorreto aceito' then raise;end if;end;
 payload=public.rh_notification_claim(notice,token);
 if payload->>'chatId'<>'5511999999999@c.us' or position(E'\n' in payload->>'message')=0
 then raise exception 'Destinatário ou mensagem inválidos';end if;
 begin
  perform public.rh_notification_claim(notice,token);raise exception 'Evento repetido aceito';
 exception when raise_exception then if sqlerrm='Evento repetido aceito' then raise;end if;end;
 perform public.rh_notification_complete(notice,token,true);
 if (select whatsapp_status from public.rh_admin_notifications where id=notice)<>'aceito' then raise exception 'Conclusão não registrada';end if;
 perform rh_internal.experience_queue();
 if (select whatsapp_status from public.rh_admin_notifications where id=notice)<>'aceito' then raise exception 'Evento enviado reaberto';end if;
 raise notice 'PASS: dias 79/80/90, datas inválidas, duplicidade, gestor, desligamento, telefone, opt-in, tokens e conclusão';
end $$;
select 'PASS: datas, dias 79/80/89/90, duplicidade, gestor, desligamento, opt-in, tokens e conclusão; nenhum envio externo' as result;
rollback;
