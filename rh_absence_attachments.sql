ALTER TABLE public.rh_absenteismo
  ADD COLUMN IF NOT EXISTS atestado_path text,
  ADD COLUMN IF NOT EXISTS atestado_nome text,
  ADD COLUMN IF NOT EXISTS atestado_mime text,
  ADD COLUMN IF NOT EXISTS atestado_size integer;
ALTER TABLE public.rh_absenteismo ADD CONSTRAINT rh_absenteismo_atestado_complete CHECK (
 (atestado_path IS NULL AND atestado_nome IS NULL AND atestado_mime IS NULL AND atestado_size IS NULL)
 OR (atestado_path IS NOT NULL AND atestado_nome IS NOT NULL AND length(atestado_nome) BETWEEN 1 AND 255
 AND atestado_mime IS NOT NULL AND atestado_size IS NOT NULL
 AND atestado_mime IN ('application/pdf','image/jpeg','image/png') AND atestado_size BETWEEN 1 AND 10485760)
);
INSERT INTO storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
VALUES ('rh-atestados','rh-atestados',false,10485760,ARRAY['application/pdf','image/jpeg','image/png']);

CREATE FUNCTION rh_internal.can_access_absence_file(p_path text,p_write boolean DEFAULT false)
RETURNS boolean LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
DECLARE employee uuid; BEGIN
 IF auth.uid() IS NULL OR NOT rh_internal.is_approved() THEN RETURN false; END IF;
 IF p_path IS NULL OR p_path !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\.(pdf|jpg|png)$' THEN RETURN false; END IF;
 employee:=split_part(p_path,'/',1)::uuid;
 RETURN (NOT p_write OR rh_internal.can_write())
 AND (rh_internal.has_full_access() OR rh_internal.can_read_employee(employee));
END $$;
REVOKE ALL ON FUNCTION rh_internal.can_access_absence_file(text,boolean) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION rh_internal.can_access_absence_file(text,boolean) TO authenticated;

CREATE POLICY rh_atestados_insert ON storage.objects FOR INSERT TO authenticated
WITH CHECK (bucket_id='rh-atestados' AND rh_internal.can_access_absence_file(name,true));
CREATE POLICY rh_atestados_read ON storage.objects FOR SELECT TO authenticated
USING (bucket_id='rh-atestados' AND rh_internal.can_access_absence_file(name,false)
 AND EXISTS (SELECT 1 FROM public.rh_absenteismo a WHERE a.atestado_path=name));
CREATE POLICY rh_atestados_delete ON storage.objects FOR DELETE TO authenticated
USING (bucket_id='rh-atestados' AND rh_internal.can_access_absence_file(name,true)
 AND NOT EXISTS (SELECT 1 FROM public.rh_absenteismo a WHERE a.atestado_path=name));
-- SELECT is also required by Storage remove, including for unattached uploads.
CREATE POLICY rh_atestados_unlinked_write_read ON storage.objects FOR SELECT TO authenticated
USING (bucket_id='rh-atestados' AND rh_internal.can_access_absence_file(name,true)
 AND NOT EXISTS (SELECT 1 FROM public.rh_absenteismo a WHERE a.atestado_path=name));

CREATE FUNCTION rh_internal.validate_absence_attachment() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE meta jsonb; BEGIN
 IF new.atestado_path IS NULL THEN RETURN new; END IF;
 IF tg_op='UPDATE' AND new.atestado_path IS NOT DISTINCT FROM old.atestado_path
 AND new.atestado_nome IS NOT DISTINCT FROM old.atestado_nome
 AND new.atestado_mime IS NOT DISTINCT FROM old.atestado_mime
 AND new.atestado_size IS NOT DISTINCT FROM old.atestado_size
 AND new.funcionario_id IS NOT DISTINCT FROM old.funcionario_id THEN RETURN new; END IF;
 IF new.funcionario_id IS NULL OR split_part(new.atestado_path,'/',1)<>new.funcionario_id::text
 OR new.atestado_path !~ '^[0-9a-f-]{36}/[0-9a-f-]{36}\.(pdf|jpg|png)$' THEN
  RAISE EXCEPTION 'O atestado deve pertencer ao colaborador selecionado'; END IF;
 SELECT metadata INTO meta FROM storage.objects WHERE bucket_id='rh-atestados' AND name=new.atestado_path;
 IF meta IS NULL OR meta->>'mimetype' IS DISTINCT FROM new.atestado_mime
 OR (meta->>'size')::bigint IS DISTINCT FROM new.atestado_size::bigint THEN
  RAISE EXCEPTION 'Arquivo de atestado não confirmado no armazenamento'; END IF;
 RETURN new;
END $$;
REVOKE ALL ON FUNCTION rh_internal.validate_absence_attachment() FROM PUBLIC,anon,authenticated;
CREATE TRIGGER zz_rh_validate_absence_attachment BEFORE INSERT OR UPDATE ON public.rh_absenteismo
FOR EACH ROW EXECUTE FUNCTION rh_internal.validate_absence_attachment();
