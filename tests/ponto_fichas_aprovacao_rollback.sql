-- Testa a autorização sem chamar o WhatsApp; tudo é desfeito ao final.
begin;
update public.rh_ponto_fichas_config set ativo=true;
update rh_internal.ponto_fichas_runtime set webhook_url=null;
do $$declare n integer;a public.rh_ponto_fichas_autorizacoes;b public.rh_ponto_fichas_autorizacoes;event_id uuid;who uuid;token text=repeat('a',64);result jsonb;ts numeric=extract(epoch from now());begin
 if rh_internal.ponto_fichas_datas('2026-11-01')->>'parcial'<>'2026-11-16' or rh_internal.ponto_fichas_datas('2026-11-01')->>'final'<>'2026-11-30' then raise exception 'Datas de novembro incorretas';end if;
 if rh_internal.ponto_fichas_datas('2027-02-01')->>'final'<>'2027-02-26' then raise exception 'Último dia útil incorreto';end if;
 if rh_internal.ponto_fichas_util('2026-11-20') or rh_internal.ponto_fichas_util('2027-03-26') or rh_internal.ponto_fichas_util('2027-07-02') then raise exception 'Feriado tratado como útil';end if;
 if not rh_internal.ponto_fichas_util('2026-12-31') then raise exception 'Ponto facultativo virou feriado';end if;
 if rh_internal.ponto_fichas_approval_queue('2026-11-05',7)<>0 or rh_internal.ponto_fichas_approval_queue('2026-11-16',6)<>0 then raise exception 'Pergunta fora do horário/data';end if;
 if rh_internal.ponto_fichas_queue('2026-11-16',9)<>0 then raise exception 'Envio sem autorização';end if;
 if rh_internal.ponto_fichas_approval_queue('2026-11-16',7)<>1 then raise exception 'Esperava uma pergunta';end if;
 if rh_internal.ponto_fichas_approval_queue('2026-11-16',7)<>0 then raise exception 'Pergunta repetida';end if;
 if rh_internal.ponto_fichas_queue('2026-11-16',9)<>0 then raise exception 'Pendente não autoriza';end if;
 select * into a from public.rh_ponto_fichas_autorizacoes where mes='2026-11-01' and tipo='parcial';
 update public.rh_admin_notifications set whatsapp_status='aceito',sent_at=now()-interval '2 minutes' where id=a.notificacao_id;
 insert into rh_internal.ponto_fichas_polls(id,token,expira_em) values(a.id,token,now()+interval '4 minutes');
 result=public.rh_fichas_poll_claim(a.id,token);if result->>'chatId'<>a.recipient_phone||'@c.us' then raise exception 'Consulta de outra conversa';end if;
 result=public.rh_fichas_poll_complete(a.id,token,jsonb_build_array(
 jsonb_build_object('id','teste-antigo','from',a.recipient_phone||'@c.us','fromMe',false,'body','1','timestamp',ts-10000),
 jsonb_build_object('id','teste-outro','from','5500000000000@c.us','fromMe',false,'body','1','timestamp',ts),
 jsonb_build_object('id','teste-saida','from',a.recipient_phone||'@c.us','fromMe',true,'body','1','timestamp',ts)));
 if result->>'status'<>'pendente' then raise exception 'Aceitou resposta antiga, de outro número ou enviada pelo robô';end if;
 update rh_internal.ponto_fichas_polls set token=repeat('b',64),expira_em=now()+interval '4 minutes',claimed=false where id=a.id;
 perform public.rh_fichas_poll_claim(a.id,repeat('b',64));
 result=public.rh_fichas_poll_complete(a.id,repeat('b',64),jsonb_build_array(jsonb_build_object('id','teste-aceito','from',a.recipient_phone||'@c.us','fromMe',false,'body','1','timestamp',ts)));
 if result->>'status'<>'aprovado' then raise exception 'Não aprovou resposta 1';end if;
 begin perform public.rh_fichas_poll_complete(a.id,repeat('b',64),'[]');raise exception 'Reutilizou resposta';exception when raise_exception then if sqlerrm='Reutilizou resposta' then raise;end if;end;
 n=rh_internal.ponto_fichas_queue('2026-11-16',9);if n<>4 then raise exception 'Esperava quatro parciais, obtive %',n;end if;
 if rh_internal.ponto_fichas_queue('2026-11-16',9)<>0 then raise exception 'Duplicou lote';end if;
 perform rh_internal.ponto_fichas_approval_queue('2026-11-30',7);
 select * into b from public.rh_ponto_fichas_autorizacoes where mes='2026-11-01' and tipo='final';
 update public.rh_admin_notifications set whatsapp_status='aceito',sent_at=now()-interval '2 minutes' where id=b.notificacao_id;
 insert into rh_internal.ponto_fichas_polls(id,token,expira_em) values(b.id,token,now()+interval '4 minutes');perform public.rh_fichas_poll_claim(b.id,token);
 result=public.rh_fichas_poll_complete(b.id,token,jsonb_build_array(jsonb_build_object('id','teste-recusado','from',b.recipient_phone||'@c.us','fromMe',false,'body','2','timestamp',ts)));
 if result->>'status'<>'recusado' or rh_internal.ponto_fichas_queue('2026-11-30',9)<>0 then raise exception 'Resposta 2 enviou mensagens';end if;
 perform rh_internal.ponto_fichas_approval_queue('2026-12-01',7);
 update public.rh_ponto_fichas_autorizacoes set expira_em=now()-interval '1 second' where mes='2026-12-01';
 if rh_internal.ponto_fichas_queue('2026-12-01',9)<>0 then raise exception 'Enviou após expirar';end if;
 select notificacao_id,funcionario_id into event_id,who from public.rh_ponto_fichas_envios where mes='2026-11-01' and tipo='parcial' limit 1;
 update public.rh_ponto_fichas_envios set agendado=(now() at time zone 'America/Sao_Paulo')::date where notificacao_id=event_id;
 update public.rh_admin_notifications set whatsapp_status='aguardando' where id=event_id;
 insert into rh_internal.notification_dispatch(id,token,expires_at) values(event_id,token,now()+interval '10 minutes');
 result=public.rh_notification_claim(event_id,token);
 if result->>'kind'<>'parcial' or result->>'message' not like '%parcial%' then raise exception 'Mensagem incorreta';end if;
 begin perform public.rh_notification_claim(event_id,token);raise exception 'Repetiu capacidade';exception when raise_exception then if sqlerrm='Repetiu capacidade' then raise;end if;end;
 perform public.rh_notification_complete(event_id,token,true);
 if (select whatsapp_status from public.rh_admin_notifications where id=event_id)<>'aceito' then raise exception 'Aceite não registrado';end if;
 delete from public.rh_ponto_fichas_destinatarios where funcionario_id=who;
 if exists(select 1 from public.rh_ponto_fichas_envios j join public.rh_admin_notifications n on n.id=j.notificacao_id where j.funcionario_id=who and n.whatsapp_status in('ficha_pendente','aguardando')) then raise exception 'Remoção não cancelou';end if;
 if not exists(select 1 from public.rh_admin_notifications where id=event_id and whatsapp_status='aceito') then raise exception 'Histórico perdido';end if;
 if has_table_privilege('anon','public.rh_ponto_fichas_envios','select') or has_table_privilege('anon','public.rh_ponto_fichas_autorizacoes','select') then raise exception 'Dados expostos';end if;
 if has_function_privilege('anon','rh_internal.ponto_fichas_queue(date,integer)','execute') then raise exception 'Agendador exposto';end if;
 -- Uma consulta atrasada aceita resposta recebida antes do prazo, nunca uma resposta posterior.
 update public.rh_ponto_fichas_autorizacoes set status='pendente',expira_em=now()-interval '2 minutes',envio_ate=null where id=a.id;
 update public.rh_admin_notifications set whatsapp_status='aceito',sent_at=now()-interval '10 minutes' where id=a.notificacao_id;
 update rh_internal.ponto_fichas_polls set token=repeat('c',64),expira_em=now()+interval '4 minutes',claimed=false where id=a.id;
 perform public.rh_fichas_poll_claim(a.id,repeat('c',64));
 result=public.rh_fichas_poll_complete(a.id,repeat('c',64),jsonb_build_array(jsonb_build_object('id','teste-depois-prazo','from',a.recipient_phone||'@c.us','fromMe',false,'body','1','timestamp',ts-119)));
 if result->>'status'<>'pendente' then raise exception 'Aceitou resposta enviada após o prazo';end if;
 update rh_internal.ponto_fichas_polls set token=repeat('d',64),expira_em=now()+interval '4 minutes',claimed=false where id=a.id;
 perform public.rh_fichas_poll_claim(a.id,repeat('d',64));
 result=public.rh_fichas_poll_complete(a.id,repeat('d',64),jsonb_build_array(jsonb_build_object('id','teste-antes-prazo','from',a.recipient_phone||'@c.us','fromMe',false,'body','1','timestamp',ts-121)));
 if result->>'status'<>'aprovado' or not exists(select 1 from public.rh_ponto_fichas_autorizacoes where id=a.id and envio_ate>now()) then raise exception 'Perdeu resposta que chegou antes do prazo';end if;
end $$;
rollback;
