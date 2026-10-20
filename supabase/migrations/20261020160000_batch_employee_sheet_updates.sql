CREATE OR REPLACE FUNCTION rh_internal.employee_sheet_batch_webhook()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE ids jsonb; request_id bigint;
BEGIN
  SELECT jsonb_agg(to_jsonb(n)->'id') INTO ids FROM new_rows AS n;
  IF ids IS NULL OR jsonb_array_length(ids)=0 THEN RETURN NULL; END IF;
  SELECT net.http_post(
    url := 'https://script.google.com/macros/s/AKfycbxiOCFqmTythI4H9Lemp_b_9fsZcJrDZX-CBGWleVq0jV22EDtYASP5XmnWE5_7vqqg/exec',
    body := jsonb_build_object('type','BATCH','schema','public','table','funcionarios_epi','ids',ids),
    headers := '{"Content-Type":"application/json"}'::jsonb,
    timeout_milliseconds := 30000
  ) INTO request_id;
  INSERT INTO supabase_functions.hooks(hook_table_id,hook_name,request_id) VALUES(TG_RELID,TG_NAME,request_id);
  RETURN NULL;
END;
$$;
REVOKE ALL ON FUNCTION rh_internal.employee_sheet_batch_webhook() FROM PUBLIC,anon,authenticated;

DROP TRIGGER IF EXISTS rh_sheet_webhook ON public.funcionarios_epi;
CREATE TRIGGER rh_sheet_webhook AFTER INSERT OR DELETE ON public.funcionarios_epi
  FOR EACH ROW EXECUTE FUNCTION supabase_functions.http_request(
    'https://script.google.com/macros/s/AKfycbxiOCFqmTythI4H9Lemp_b_9fsZcJrDZX-CBGWleVq0jV22EDtYASP5XmnWE5_7vqqg/exec',
    'POST','{"Content-type":"application/json"}','{}','30000'
  );
CREATE TRIGGER rh_sheet_webhook_update_batch AFTER UPDATE ON public.funcionarios_epi
  REFERENCING NEW TABLE AS new_rows FOR EACH STATEMENT
  EXECUTE FUNCTION rh_internal.employee_sheet_batch_webhook();

CREATE OR REPLACE FUNCTION public.rh_ativar_webhooks()
RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE t text;
BEGIN
  FOREACH t IN ARRAY ARRAY['funcionarios_epi','rh_movimentacoes','rh_absenteismo','rh_ferias','rh_desligados','devolucoes_pendentes','empresas','epi_funcao'] LOOP
    EXECUTE format('ALTER TABLE public.%I ENABLE TRIGGER rh_sheet_webhook',t);
    IF t='funcionarios_epi' THEN EXECUTE 'ALTER TABLE public.funcionarios_epi ENABLE TRIGGER rh_sheet_webhook_update_batch'; END IF;
  END LOOP;
  RETURN true;
END;
$$;
REVOKE ALL ON FUNCTION public.rh_ativar_webhooks() FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.rh_ativar_webhooks() TO service_role;

NOTIFY pgrst,'reload schema';
