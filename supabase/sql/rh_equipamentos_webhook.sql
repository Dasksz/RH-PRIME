-- Reutiliza a integração existente e sua configuração, sem expor credenciais.
do $$ declare definition text; begin
 select pg_get_triggerdef(t.oid) into definition from pg_trigger t
 where t.tgrelid='public.funcionarios_epi'::regclass and t.tgname='rh_sheet_webhook';
 if definition is null then raise exception 'Webhook existente não encontrado'; end if;
 if not exists(select 1 from pg_trigger where tgrelid='public.rh_equipment_movements'::regclass and tgname='rh_equipment_sheet_webhook') then
  execute replace(replace(definition,'rh_sheet_webhook','rh_equipment_sheet_webhook'),'ON public.funcionarios_epi','ON public.rh_equipment_movements');
 end if;
end $$;
