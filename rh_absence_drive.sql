ALTER TABLE public.rh_absenteismo
 ADD COLUMN atestado_tipo text,
 ADD COLUMN atestado_data date,
 ADD COLUMN atestado_dias integer;
ALTER TABLE public.rh_absenteismo ADD CONSTRAINT rh_absenteismo_document_kind
 CHECK (atestado_tipo IS NULL OR atestado_tipo IN ('atestado','comparecimento'));
ALTER TABLE public.rh_absenteismo ADD CONSTRAINT rh_absenteismo_document_days
 CHECK (atestado_dias IS NULL OR atestado_dias BETWEEN 1 AND 3660);

CREATE FUNCTION rh_internal.name_absence_attachment() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE person text; extension text; BEGIN
 IF new.atestado_path IS NULL THEN
  new.atestado_tipo:=NULL;new.atestado_data:=NULL;new.atestado_dias:=NULL;RETURN new;
 END IF;
 new.atestado_tipo:=coalesce(new.atestado_tipo,'atestado');
 new.atestado_data:=coalesce(new.atestado_data,new.data_inicio);
 IF new.atestado_data IS NULL THEN RAISE EXCEPTION 'Informe a data do documento'; END IF;
 IF new.atestado_tipo='atestado' THEN
  new.atestado_dias:=coalesce(new.atestado_dias,new.data_fim-new.data_inicio+1,1);
  IF new.atestado_dias NOT BETWEEN 1 AND 3660 THEN RAISE EXCEPTION 'Quantidade de dias inválida'; END IF;
 ELSE new.atestado_dias:=NULL; END IF;
 SELECT left(upper(regexp_replace(trim(nome),'\s+',' ','g')),220) INTO person FROM public.funcionarios_epi WHERE id=new.funcionario_id;
 IF person IS NULL THEN RAISE EXCEPTION 'Colaborador não encontrado'; END IF;
 extension:=CASE new.atestado_mime WHEN 'application/pdf' THEN '.pdf' WHEN 'image/jpeg' THEN '.jpg' WHEN 'image/png' THEN '.png' ELSE '' END;
 new.atestado_nome:=CASE new.atestado_tipo WHEN 'comparecimento' THEN 'COMPARECIMENTO ' ELSE 'ATESTADO - ' END
 ||to_char(new.atestado_data,'DD.MM')
 ||CASE WHEN new.atestado_tipo='atestado' THEN ' '||new.atestado_dias||CASE WHEN new.atestado_dias=1 THEN ' DIA' ELSE ' DIAS' END ELSE '' END
 ||' - '||person||extension;
 RETURN new;
END $$;
REVOKE ALL ON FUNCTION rh_internal.name_absence_attachment() FROM PUBLIC,anon,authenticated;
CREATE TRIGGER zy_rh_name_absence_attachment BEFORE INSERT OR UPDATE ON public.rh_absenteismo
FOR EACH ROW EXECUTE FUNCTION rh_internal.name_absence_attachment();

CREATE TABLE rh_internal.absence_drive_state (
 absence_id integer PRIMARY KEY REFERENCES public.rh_absenteismo(id) ON DELETE CASCADE,
 status text NOT NULL CHECK(status IN ('pending','processing','completed','failed')),
 revision bigint NOT NULL DEFAULT 1,
 claimed_revision bigint,
 claimed_at timestamptz,
 drive_file_id text,
 source_path text,
 filename text,
 sha256 text,
 error text,
 updated_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE rh_internal.absence_drive_state ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON rh_internal.absence_drive_state FROM PUBLIC,anon,authenticated;
CREATE POLICY absence_drive_state_internal ON rh_internal.absence_drive_state FOR ALL TO service_role USING(true) WITH CHECK(true);
CREATE TABLE rh_internal.absence_drive_worker (
 id boolean PRIMARY KEY DEFAULT true CHECK(id),
 last_seen_at timestamptz NOT NULL
);
ALTER TABLE rh_internal.absence_drive_worker ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON rh_internal.absence_drive_worker FROM PUBLIC,anon,authenticated;
CREATE POLICY absence_drive_worker_internal ON rh_internal.absence_drive_worker FOR ALL TO service_role USING(true) WITH CHECK(true);

CREATE FUNCTION rh_internal.queue_absence_drive() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$ BEGIN
 IF new.atestado_path IS NULL THEN DELETE FROM rh_internal.absence_drive_state WHERE absence_id=new.id;RETURN new; END IF;
 IF tg_op='UPDATE' AND ROW(new.atestado_path,new.atestado_nome,new.atestado_mime,new.atestado_size,new.funcionario_id,new.atestado_data)
 IS NOT DISTINCT FROM ROW(old.atestado_path,old.atestado_nome,old.atestado_mime,old.atestado_size,old.funcionario_id,old.atestado_data) THEN RETURN new; END IF;
 INSERT INTO rh_internal.absence_drive_state(absence_id,status,source_path,filename)
 VALUES(new.id,'pending',new.atestado_path,new.atestado_nome)
 ON CONFLICT(absence_id) DO UPDATE SET status='pending',revision=absence_drive_state.revision+1,claimed_at=NULL,claimed_revision=NULL,
 drive_file_id=CASE WHEN absence_drive_state.source_path=excluded.source_path THEN absence_drive_state.drive_file_id ELSE NULL END,
 source_path=excluded.source_path,filename=excluded.filename,sha256=NULL,error=NULL,updated_at=now();
 RETURN new;
END $$;
REVOKE ALL ON FUNCTION rh_internal.queue_absence_drive() FROM PUBLIC,anon,authenticated;
CREATE TRIGGER zz_rh_queue_absence_drive AFTER INSERT OR UPDATE ON public.rh_absenteismo
FOR EACH ROW EXECUTE FUNCTION rh_internal.queue_absence_drive();

CREATE FUNCTION public.rh_claim_absence_drive() RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE selected_id integer; result jsonb; BEGIN
 INSERT INTO rh_internal.absence_drive_worker(id,last_seen_at) VALUES(true,now())
 ON CONFLICT(id) DO UPDATE SET last_seen_at=excluded.last_seen_at;
 SELECT s.absence_id INTO selected_id FROM rh_internal.absence_drive_state s
 JOIN public.rh_absenteismo a ON a.id=s.absence_id
 WHERE a.atestado_path IS NOT NULL AND (s.status='pending' OR (s.status='processing' AND s.claimed_at<now()-interval '8 minutes'))
 ORDER BY s.updated_at FOR UPDATE OF s SKIP LOCKED LIMIT 1;
 IF selected_id IS NULL THEN RETURN '[]'::jsonb; END IF;
 UPDATE rh_internal.absence_drive_state SET status='processing',revision=revision+1,claimed_revision=revision+1,claimed_at=now(),updated_at=now() WHERE absence_id=selected_id;
 SELECT jsonb_build_array(jsonb_build_object('id',a.id,'revision',s.revision,'funcionario_id',a.funcionario_id,'employee_name',e.nome,
 'storage_path',a.atestado_path,'filename',a.atestado_nome,'mime',a.atestado_mime,'size',a.atestado_size,
 'year',to_char(a.atestado_data,'YYYY'),'drive_file_id',s.drive_file_id)) INTO result
 FROM public.rh_absenteismo a JOIN public.funcionarios_epi e ON e.id=a.funcionario_id
 JOIN rh_internal.absence_drive_state s ON s.absence_id=a.id WHERE a.id=selected_id;
 RETURN coalesce(result,'[]'::jsonb);
END $$;
REVOKE ALL ON FUNCTION public.rh_claim_absence_drive() FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.rh_claim_absence_drive() TO service_role;

CREATE FUNCTION public.rh_finish_absence_drive(p_id integer,p_revision bigint,p_file_id text DEFAULT NULL,p_sha256 text DEFAULT NULL,p_error text DEFAULT NULL) RETURNS boolean
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$ BEGIN
 IF p_error IS NULL AND (p_file_id IS NULL OR p_file_id!~'^[A-Za-z0-9_-]{10,200}$' OR p_sha256 IS NULL OR p_sha256!~'^[a-f0-9]{64}$') THEN
  RAISE EXCEPTION 'Arquivo do Drive não confirmado'; END IF;
 UPDATE rh_internal.absence_drive_state SET status=CASE WHEN p_error IS NULL THEN 'completed' ELSE 'failed' END,
 drive_file_id=CASE WHEN p_error IS NULL THEN p_file_id ELSE drive_file_id END,sha256=p_sha256,error=left(p_error,500),
 claimed_at=NULL,claimed_revision=NULL,updated_at=now()
 WHERE absence_id=p_id AND revision=p_revision AND claimed_revision=p_revision AND status='processing';
 RETURN found;
END $$;
REVOKE ALL ON FUNCTION public.rh_finish_absence_drive(integer,bigint,text,text,text) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.rh_finish_absence_drive(integer,bigint,text,text,text) TO service_role;

CREATE FUNCTION rh_internal.rh_absence_drive_status(p_ids integer[]) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$ BEGIN
 IF auth.uid() IS NULL OR NOT rh_internal.is_approved() THEN RAISE EXCEPTION 'Acesso não autorizado'; END IF;
 RETURN jsonb_build_object('worker_ready',coalesce((SELECT last_seen_at>now()-interval '10 minutes' FROM rh_internal.absence_drive_worker WHERE id),false),
 'records',coalesce((SELECT jsonb_agg(jsonb_build_object('id',a.id,'status',s.status,'error',s.error,'link',CASE WHEN s.status='completed' THEN 'https://drive.google.com/file/d/'||s.drive_file_id||'/view' ELSE NULL END))
 FROM rh_internal.absence_drive_state s JOIN public.rh_absenteismo a ON a.id=s.absence_id WHERE a.id=ANY(p_ids)
 AND (rh_internal.has_full_access() OR rh_internal.can_read_employee(a.funcionario_id))),'[]'::jsonb));
END $$;
REVOKE ALL ON FUNCTION rh_internal.rh_absence_drive_status(integer[]) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION rh_internal.rh_absence_drive_status(integer[]) TO authenticated;

CREATE FUNCTION rh_internal.rh_retry_absence_drive(p_id integer) RETURNS boolean
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$ BEGIN
 IF auth.uid() IS NULL OR NOT rh_internal.can_write() OR NOT EXISTS(SELECT 1 FROM public.rh_absenteismo a WHERE a.id=p_id AND a.atestado_path IS NOT NULL AND (rh_internal.has_full_access() OR rh_internal.can_read_employee(a.funcionario_id))) THEN RAISE EXCEPTION 'Acesso não autorizado'; END IF;
 UPDATE rh_internal.absence_drive_state SET status='pending',revision=revision+1,claimed_at=NULL,claimed_revision=NULL,error=NULL,updated_at=now() WHERE absence_id=p_id AND status='failed';
 RETURN found;
END $$;
REVOKE ALL ON FUNCTION rh_internal.rh_retry_absence_drive(integer) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION rh_internal.rh_retry_absence_drive(integer) TO authenticated;

CREATE FUNCTION public.rh_absence_drive_status(p_ids integer[]) RETURNS jsonb
LANGUAGE sql STABLE SECURITY INVOKER SET search_path='' AS $$ SELECT rh_internal.rh_absence_drive_status(p_ids); $$;
REVOKE ALL ON FUNCTION public.rh_absence_drive_status(integer[]) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.rh_absence_drive_status(integer[]) TO authenticated;
CREATE FUNCTION public.rh_retry_absence_drive(p_id integer) RETURNS boolean
LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$ SELECT rh_internal.rh_retry_absence_drive(p_id); $$;
REVOKE ALL ON FUNCTION public.rh_retry_absence_drive(integer) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.rh_retry_absence_drive(integer) TO authenticated;

-- Existing attachments, if any, also enter the Drive queue.
UPDATE public.rh_absenteismo SET atestado_tipo=coalesce(atestado_tipo,'atestado') WHERE atestado_path IS NOT NULL;
