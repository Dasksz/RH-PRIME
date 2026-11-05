-- Evita colisão com LOCALTIME do SQL e mantém todo o relógio no fuso do RH.
do $$declare item record;def text;begin
 for item in select p.oid from pg_proc p join pg_namespace n on n.oid=p.pronamespace
 where n.nspname in('rh_internal','rh_notifications_internal')
 and p.proname in('ponto_fichas_tick','fichas_poll_complete','notification_fichas_previous_claim') loop
  select pg_get_functiondef(item.oid) into def;
  execute regexp_replace(def,'\mlocaltime\M','v_local_time','g');
 end loop;
end $$;
