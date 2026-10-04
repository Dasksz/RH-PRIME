-- Ao fechar um período, preserva também o lançamento que motivou o fechamento.
create or replace function rh_internal.archive_vacation() returns trigger
language plpgsql security invoker set search_path='' as $$
declare archived jsonb; begin
 if new.data_inicio_aquisitivo is distinct from old.data_inicio_aquisitivo then
  archived:=to_jsonb(old)-'historico_periodos';
  if new.historico_periodos is distinct from old.historico_periodos and jsonb_typeof(new.historico_periodos)='array' and jsonb_array_length(new.historico_periodos)>jsonb_array_length(coalesce(old.historico_periodos,'[]'::jsonb)) then
   archived:=new.historico_periodos->(jsonb_array_length(new.historico_periodos)-1);
   if archived->>'data_inicio_aquisitivo' is distinct from old.data_inicio_aquisitivo::text then raise exception 'Período arquivado diferente do encerrado.'; end if;
  end if;
  new.historico_periodos:=coalesce(old.historico_periodos,'[]'::jsonb)||jsonb_build_array(archived||jsonb_build_object('arquivado_em',now()));
 end if;
 return new;
end $$;
