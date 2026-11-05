-- O registro do laço não deve ter o mesmo nome do alias SQL da atualização de contatos.
do $$declare def text;begin
 select pg_get_functiondef('rh_internal.ponto_fichas_dispatch()'::regprocedure) into def;
 def=replace(def,'declare n record;','declare pending_event record;');
 def=replace(def,'for n in select id','for pending_event in select id');
 def=replace(def,'values(n.id,token','values(pending_event.id,token');
 def=replace(def,'''eventId'',n.id','''eventId'',pending_event.id');
 def=replace(def,'where id=n.id','where id=pending_event.id');
 execute def;
end $$;
