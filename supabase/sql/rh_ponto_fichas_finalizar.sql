-- Tabelas de capacidades não possuem acesso pelo cliente, inclusive sob RLS.
create policy ponto_fichas_runtime_no_client on rh_internal.ponto_fichas_runtime for all to anon,authenticated using(false) with check(false);
create policy ponto_fichas_polls_no_client on rh_internal.ponto_fichas_polls for all to anon,authenticated using(false) with check(false);
do $$declare def text;begin
 select pg_get_functiondef('rh_notifications_internal.fichas_poll_complete(uuid,text,jsonb)'::regprocedure) into def;
 execute replace(def,'jsonb_typeof(p_messages)<>''array''','jsonb_typeof(p_messages) is distinct from ''array''');
 select pg_get_functiondef('rh_internal.ponto_fichas_tick()'::regprocedure) into def;
 def=replace(def,'perform rh_internal.ponto_fichas_approval_queue(',
 'update public.rh_admin_notifications n set whatsapp_status=''cancelado'',error=''Pergunta expirada ou cancelada; nenhum envio autorizado.'' from public.rh_ponto_fichas_autorizacoes a where a.notificacao_id=n.id and a.status in(''expirado'',''cancelado'',''recusado'') and n.whatsapp_status in(''ficha_autorizacao_pendente'',''aguardando'');
 perform rh_internal.ponto_fichas_approval_queue(');
 execute def;
end $$;
