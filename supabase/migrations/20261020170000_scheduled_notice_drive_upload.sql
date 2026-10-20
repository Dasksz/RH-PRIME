ALTER TABLE public.funcionarios_epi
  ADD COLUMN IF NOT EXISTS aviso_previo_path text,
  ADD COLUMN IF NOT EXISTS aviso_previo_nome text,
  ADD COLUMN IF NOT EXISTS aviso_previo_mime text,
  ADD COLUMN IF NOT EXISTS aviso_previo_size integer,
  ADD COLUMN IF NOT EXISTS rescisao_path text,
  ADD COLUMN IF NOT EXISTS rescisao_nome text,
  ADD COLUMN IF NOT EXISTS rescisao_mime text,
  ADD COLUMN IF NOT EXISTS rescisao_size integer;

ALTER TABLE public.funcionarios_epi ADD CONSTRAINT funcionarios_epi_notice_documents_complete CHECK (
  ((aviso_previo_path IS NULL AND aviso_previo_nome IS NULL AND aviso_previo_mime IS NULL AND aviso_previo_size IS NULL)
    OR (aviso_previo_path IS NOT NULL AND aviso_previo_nome IS NOT NULL AND length(aviso_previo_nome) BETWEEN 1 AND 255
      AND aviso_previo_mime IN ('application/pdf','image/jpeg','image/png') AND aviso_previo_size BETWEEN 1 AND 10485760))
  AND
  ((rescisao_path IS NULL AND rescisao_nome IS NULL AND rescisao_mime IS NULL AND rescisao_size IS NULL)
    OR (rescisao_path IS NOT NULL AND rescisao_nome IS NOT NULL AND length(rescisao_nome) BETWEEN 1 AND 255
      AND rescisao_mime IN ('application/pdf','image/jpeg','image/png') AND rescisao_size BETWEEN 1 AND 10485760))
);

INSERT INTO storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
VALUES ('rh-documentos-desligamento','rh-documentos-desligamento',false,10485760,ARRAY['application/pdf','image/jpeg','image/png'])
ON CONFLICT(id) DO UPDATE SET public=false,file_size_limit=10485760,allowed_mime_types=EXCLUDED.allowed_mime_types;

CREATE FUNCTION rh_internal.can_access_notice_file(p_path text,p_write boolean DEFAULT false)
RETURNS boolean LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
DECLARE employee uuid;
BEGIN
  IF auth.uid() IS NULL OR NOT rh_internal.is_approved() OR NOT rh_internal.has_full_access() THEN RETURN false; END IF;
  IF p_path IS NULL OR p_path !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\.(pdf|jpg|png)$' THEN RETURN false; END IF;
  employee:=split_part(p_path,'/',1)::uuid;
  RETURN (NOT p_write OR rh_internal.can_write()) AND EXISTS(SELECT 1 FROM public.funcionarios_epi e WHERE e.id=employee);
END $$;
REVOKE ALL ON FUNCTION rh_internal.can_access_notice_file(text,boolean) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION rh_internal.can_access_notice_file(text,boolean) TO authenticated;

CREATE POLICY rh_notice_insert ON storage.objects FOR INSERT TO authenticated
  WITH CHECK (bucket_id='rh-documentos-desligamento' AND rh_internal.can_access_notice_file(name,true));
CREATE POLICY rh_notice_read ON storage.objects FOR SELECT TO authenticated
  USING (bucket_id='rh-documentos-desligamento' AND rh_internal.can_access_notice_file(name,false)
    AND EXISTS(SELECT 1 FROM public.funcionarios_epi e WHERE e.aviso_previo_path=name OR e.rescisao_path=name));
CREATE POLICY rh_notice_delete ON storage.objects FOR DELETE TO authenticated
  USING (bucket_id='rh-documentos-desligamento' AND rh_internal.can_access_notice_file(name,true)
    AND NOT EXISTS(SELECT 1 FROM public.funcionarios_epi e WHERE e.aviso_previo_path=name OR e.rescisao_path=name));
CREATE POLICY rh_notice_unlinked_read ON storage.objects FOR SELECT TO authenticated
  USING (bucket_id='rh-documentos-desligamento' AND rh_internal.can_access_notice_file(name,true)
    AND NOT EXISTS(SELECT 1 FROM public.funcionarios_epi e WHERE e.aviso_previo_path=name OR e.rescisao_path=name));

CREATE FUNCTION rh_internal.validate_scheduled_notice_attachment() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE meta jsonb; extension text; person text; scheduled_date date; expected_path text; expected_mime text; expected_size integer;
BEGIN
  scheduled_date:=coalesce(new.data_desligamento,new.data_desligamento_programada);
  IF new.cumprindo_aviso_previo AND scheduled_date IS NULL THEN
    RAISE EXCEPTION 'Informe a data do desligamento para registrar aviso prévio';
  END IF;
  IF new.cumprindo_aviso_previo AND new.aviso_previo_path IS NULL THEN
    RAISE EXCEPTION 'Anexe o documento do aviso prévio';
  END IF;
  IF new.rescisao_path IS NOT NULL AND new.data_desligamento IS NULL THEN
    RAISE EXCEPTION 'O documento da rescisão só pode ser anexado após informar o desligamento efetivado';
  END IF;
  SELECT left(upper(regexp_replace(trim(coalesce(new.nome,'')),'\s+',' ','g')),205) INTO person;
  FOREACH expected_path IN ARRAY ARRAY[new.aviso_previo_path,new.rescisao_path] LOOP
    IF expected_path IS NULL THEN CONTINUE; END IF;
    IF new.id IS NULL OR split_part(expected_path,'/',1)<>new.id::text
      OR expected_path !~ '^[0-9a-f-]{36}/[0-9a-f-]{36}\.(pdf|jpg|png)$' THEN
      RAISE EXCEPTION 'O documento deve pertencer ao colaborador selecionado';
    END IF;
    IF expected_path=new.aviso_previo_path THEN expected_mime:=new.aviso_previo_mime;expected_size:=new.aviso_previo_size;
    ELSE expected_mime:=new.rescisao_mime;expected_size:=new.rescisao_size; END IF;
    SELECT metadata INTO meta FROM storage.objects WHERE bucket_id='rh-documentos-desligamento' AND name=expected_path;
    IF meta IS NULL OR meta->>'mimetype' IS DISTINCT FROM expected_mime OR (meta->>'size')::bigint IS DISTINCT FROM expected_size::bigint THEN
      RAISE EXCEPTION 'O documento de desligamento não foi confirmado no armazenamento';
    END IF;
  END LOOP;
  IF new.aviso_previo_path IS NOT NULL THEN
    extension:=CASE new.aviso_previo_mime WHEN 'application/pdf' THEN '.pdf' WHEN 'image/jpeg' THEN '.jpg' WHEN 'image/png' THEN '.png' ELSE '' END;
    IF new.cumprindo_aviso_previo THEN
      new.aviso_previo_nome:='AVISO PREVIO - '||person||' - '||to_char(scheduled_date,'DD.MM.YYYY')||extension;
    ELSIF new.aviso_previo_nome IS NULL THEN RAISE EXCEPTION 'Nome do aviso prévio inválido'; END IF;
  END IF;
  IF new.rescisao_path IS NOT NULL THEN
    extension:=CASE new.rescisao_mime WHEN 'application/pdf' THEN '.pdf' WHEN 'image/jpeg' THEN '.jpg' WHEN 'image/png' THEN '.png' ELSE '' END;
    new.rescisao_nome:='RESCISAO - '||person||' - '||to_char(new.data_desligamento,'DD.MM.YYYY')||extension;
  END IF;
  IF new.aviso_previo_nome IS NOT NULL AND length(new.aviso_previo_nome)>255 OR new.rescisao_nome IS NOT NULL AND length(new.rescisao_nome)>255 THEN
    RAISE EXCEPTION 'Nome do documento muito longo';
  END IF;
  RETURN new;
END $$;
REVOKE ALL ON FUNCTION rh_internal.validate_scheduled_notice_attachment() FROM PUBLIC,anon,authenticated;
CREATE TRIGGER zz_rh_validate_scheduled_notice BEFORE INSERT OR UPDATE ON public.funcionarios_epi
  FOR EACH ROW EXECUTE FUNCTION rh_internal.validate_scheduled_notice_attachment();

CREATE TABLE rh_internal.scheduled_notice_drive_state (
  employee_id uuid NOT NULL REFERENCES public.funcionarios_epi(id) ON DELETE CASCADE,
  document_kind text NOT NULL CHECK(document_kind IN ('aviso_previo','rescisao')),
  status text NOT NULL CHECK(status IN ('pending','processing','completed','failed')),
  revision bigint NOT NULL DEFAULT 1, claimed_revision bigint, claimed_at timestamptz,
  drive_file_id text, source_path text NOT NULL, filename text NOT NULL, sha256 text, error text,
  updated_at timestamptz NOT NULL DEFAULT now(), PRIMARY KEY(employee_id,document_kind)
);
ALTER TABLE rh_internal.scheduled_notice_drive_state ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON rh_internal.scheduled_notice_drive_state FROM PUBLIC,anon,authenticated;
CREATE POLICY scheduled_notice_drive_state_service ON rh_internal.scheduled_notice_drive_state
  FOR ALL TO service_role USING(true) WITH CHECK(true);

CREATE FUNCTION rh_internal.queue_scheduled_notice_drive() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE old_aviso text;old_aviso_name text;old_rescisao text;old_rescisao_name text;
BEGIN
  IF tg_op='UPDATE' THEN old_aviso:=old.aviso_previo_path;old_aviso_name:=old.aviso_previo_nome;old_rescisao:=old.rescisao_path;old_rescisao_name:=old.rescisao_nome; END IF;
  IF new.aviso_previo_path IS NOT NULL AND (tg_op='INSERT' OR ROW(new.aviso_previo_path,new.aviso_previo_nome) IS DISTINCT FROM ROW(old_aviso,old_aviso_name)) THEN
    INSERT INTO rh_internal.scheduled_notice_drive_state(employee_id,document_kind,status,source_path,filename)
      VALUES(new.id,'aviso_previo','pending',new.aviso_previo_path,new.aviso_previo_nome)
    ON CONFLICT(employee_id,document_kind) DO UPDATE SET status='pending',revision=scheduled_notice_drive_state.revision+1,claimed_at=NULL,claimed_revision=NULL,
      drive_file_id=CASE WHEN scheduled_notice_drive_state.source_path=excluded.source_path THEN scheduled_notice_drive_state.drive_file_id ELSE NULL END,
      source_path=excluded.source_path,filename=excluded.filename,sha256=NULL,error=NULL,updated_at=now();
  END IF;
  IF new.rescisao_path IS NOT NULL AND (tg_op='INSERT' OR ROW(new.rescisao_path,new.rescisao_nome) IS DISTINCT FROM ROW(old_rescisao,old_rescisao_name)) THEN
    INSERT INTO rh_internal.scheduled_notice_drive_state(employee_id,document_kind,status,source_path,filename)
      VALUES(new.id,'rescisao','pending',new.rescisao_path,new.rescisao_nome)
    ON CONFLICT(employee_id,document_kind) DO UPDATE SET status='pending',revision=scheduled_notice_drive_state.revision+1,claimed_at=NULL,claimed_revision=NULL,
      drive_file_id=CASE WHEN scheduled_notice_drive_state.source_path=excluded.source_path THEN scheduled_notice_drive_state.drive_file_id ELSE NULL END,
      source_path=excluded.source_path,filename=excluded.filename,sha256=NULL,error=NULL,updated_at=now();
  END IF;
  RETURN new;
END $$;
REVOKE ALL ON FUNCTION rh_internal.queue_scheduled_notice_drive() FROM PUBLIC,anon,authenticated;
CREATE TRIGGER zz_rh_queue_scheduled_notice_drive AFTER INSERT OR UPDATE ON public.funcionarios_epi
  FOR EACH ROW EXECUTE FUNCTION rh_internal.queue_scheduled_notice_drive();

CREATE FUNCTION public.rh_claim_scheduled_notice_drive() RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE selected_id uuid;selected_kind text;result jsonb;
BEGIN
  SELECT s.employee_id,s.document_kind INTO selected_id,selected_kind FROM rh_internal.scheduled_notice_drive_state s
  JOIN public.funcionarios_epi e ON e.id=s.employee_id
  WHERE (s.document_kind='aviso_previo' AND e.aviso_previo_path=s.source_path OR s.document_kind='rescisao' AND e.rescisao_path=s.source_path)
    AND (s.status='pending' OR (s.status='processing' AND s.claimed_at<now()-interval '8 minutes'))
  ORDER BY s.updated_at FOR UPDATE OF s SKIP LOCKED LIMIT 1;
  IF selected_id IS NULL THEN RETURN '[]'::jsonb; END IF;
  UPDATE rh_internal.scheduled_notice_drive_state SET status='processing',revision=revision+1,claimed_revision=revision+1,claimed_at=now(),updated_at=now()
    WHERE employee_id=selected_id AND document_kind=selected_kind;
  SELECT jsonb_build_array(jsonb_build_object('id',e.id,'revision',s.revision,'document_kind',s.document_kind,'employee_name',e.nome,
    'storage_path',s.source_path,'filename',s.filename,
    'mime',CASE WHEN s.document_kind='aviso_previo' THEN e.aviso_previo_mime ELSE e.rescisao_mime END,
    'size',CASE WHEN s.document_kind='aviso_previo' THEN e.aviso_previo_size ELSE e.rescisao_size END,'drive_file_id',s.drive_file_id)) INTO result
  FROM public.funcionarios_epi e JOIN rh_internal.scheduled_notice_drive_state s ON s.employee_id=e.id
  WHERE e.id=selected_id AND s.document_kind=selected_kind;
  RETURN coalesce(result,'[]'::jsonb);
END $$;
REVOKE ALL ON FUNCTION public.rh_claim_scheduled_notice_drive() FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.rh_claim_scheduled_notice_drive() TO service_role;

CREATE FUNCTION public.rh_finish_scheduled_notice_drive(p_id uuid,p_kind text,p_revision bigint,p_file_id text DEFAULT NULL,p_sha256 text DEFAULT NULL,p_error text DEFAULT NULL) RETURNS boolean
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$ BEGIN
  IF p_error IS NULL AND (p_file_id IS NULL OR p_file_id!~'^[A-Za-z0-9_-]{10,200}$' OR p_sha256 IS NULL OR p_sha256!~'^[a-f0-9]{64}$') THEN RAISE EXCEPTION 'Documento do desligamento não confirmado'; END IF;
  UPDATE rh_internal.scheduled_notice_drive_state SET status=CASE WHEN p_error IS NULL THEN 'completed' ELSE 'failed' END,
    drive_file_id=CASE WHEN p_error IS NULL THEN p_file_id ELSE drive_file_id END,sha256=p_sha256,error=left(p_error,500),claimed_at=NULL,claimed_revision=NULL,updated_at=now()
  WHERE employee_id=p_id AND document_kind=p_kind AND revision=p_revision AND claimed_revision=p_revision AND status='processing';
  RETURN found;
END $$;
REVOKE ALL ON FUNCTION public.rh_finish_scheduled_notice_drive(uuid,text,bigint,text,text,text) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.rh_finish_scheduled_notice_drive(uuid,text,bigint,text,text,text) TO service_role;

CREATE FUNCTION public.rh_scheduled_notice_drive_status(p_employee_id uuid) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$ DECLARE result jsonb; BEGIN
  IF auth.uid() IS NULL OR NOT rh_internal.is_approved() OR NOT rh_internal.has_full_access() THEN RAISE EXCEPTION 'Acesso não autorizado'; END IF;
  SELECT coalesce(jsonb_agg(jsonb_build_object('kind',s.document_kind,'status',s.status,'error',s.error,
    'link',CASE WHEN s.status='completed' THEN 'https://drive.google.com/file/d/'||s.drive_file_id||'/view' ELSE NULL END)),'[]'::jsonb)
  INTO result FROM rh_internal.scheduled_notice_drive_state s WHERE s.employee_id=p_employee_id;
  RETURN result;
END $$;
REVOKE ALL ON FUNCTION public.rh_scheduled_notice_drive_status(uuid) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.rh_scheduled_notice_drive_status(uuid) TO authenticated;

CREATE FUNCTION public.rh_retry_scheduled_notice_drive(p_employee_id uuid,p_kind text DEFAULT NULL) RETURNS boolean
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$ BEGIN
  IF auth.uid() IS NULL OR NOT rh_internal.can_write() OR NOT rh_internal.has_full_access() THEN RAISE EXCEPTION 'Acesso não autorizado'; END IF;
  UPDATE rh_internal.scheduled_notice_drive_state SET status='pending',revision=revision+1,claimed_at=NULL,claimed_revision=NULL,error=NULL,updated_at=now()
  WHERE employee_id=p_employee_id AND status='failed' AND (p_kind IS NULL OR document_kind=p_kind);
  RETURN found;
END $$;
REVOKE ALL ON FUNCTION public.rh_retry_scheduled_notice_drive(uuid,text) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.rh_retry_scheduled_notice_drive(uuid,text) TO authenticated;

NOTIFY pgrst,'reload schema';
