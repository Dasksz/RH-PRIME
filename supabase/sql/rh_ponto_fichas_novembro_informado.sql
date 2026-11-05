-- Informação do RH em 05/11/2026: fichas de novembro já enviadas fora deste fluxo.
-- Não afirma uma data de envio nem um aceite do WhatsApp; não dispara mensagens.
do $$declare r record;event_id uuid;begin
 for r in select d.*,e.nome from public.rh_ponto_fichas_destinatarios d join public.funcionarios_epi e on e.id=d.funcionario_id loop
  if exists(select 1 from public.rh_ponto_fichas_envios where funcionario_id=r.funcionario_id and mes='2026-11-01' and tipo='ficha') then continue;end if;
  event_id=gen_random_uuid();
  insert into public.rh_admin_notifications(id,employee_id,employee_name,source_table,operation,title,message_text,whatsapp_status,actor_name,details)
  values(event_id,r.funcionario_id,r.nome,'ponto_fichas_manual','INFORMADO','Ficha de novembro já enviada pelo RH','O RH informou que a ficha deste mês já foi enviada. Não reenviar automaticamente.','informado_rh','RH',jsonb_build_object('mes','2026-11-01','tipo','ficha','informado_em','2026-11-05'));
  insert into public.rh_ponto_fichas_envios(funcionario_id,mes,tipo,agendado,inscricao,notificacao_id) values(r.funcionario_id,'2026-11-01','ficha','2026-11-05',r.criado_em,event_id);
 end loop;
end $$;
