 CREATE TRIGGER zz_stock_equipment AFTER INSERT OR UPDATE ON public.rh_equipment_movements FOR EACH ROW EXECUTE FUNCTION rh_internal.stock_equipment();
DO $$ DECLARE definition text; BEGIN
 SELECT pg_get_triggerdef(oid) INTO definition FROM pg_trigger WHERE tgrelid='public.rh_equipment_movements'::regclass AND tgname='rh_equipment_sheet_webhook';
 IF definition IS NULL THEN RAISE EXCEPTION 'Webhook de equipamentos existente não encontrado.'; END IF;
 definition:=replace(definition,'rh_equipment_sheet_webhook','rh_catalog_sheet_webhook');
 definition:=replace(definition,'ON public.rh_equipment_movements','ON public.rh_product_events');
 EXECUTE definition;
END $$;
CREATE POLICY stock_operations_internal ON rh_internal.stock_operations FOR ALL TO service_role USING(true) WITH CHECK(true);
NOTIFY pgrst,'reload schema';
