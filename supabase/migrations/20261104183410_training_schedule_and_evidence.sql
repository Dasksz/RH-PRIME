CREATE TABLE public.rh_trainings (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(), nome text NOT NULL CHECK(length(trim(nome)) BETWEEN 1 AND 220),
 data_programada date NOT NULL CHECK(extract(isodow FROM data_programada) BETWEEN 1 AND 5), data_original date, data_realizacao date, status text NOT NULL DEFAULT 'agendado' CHECK(status IN ('agendado','concluido')),
 modalidade text NOT NULL CHECK(modalidade IN ('Online','Presencial','Híbrido')), carga_horaria numeric(6,2) NOT NULL CHECK(carga_horaria>0 AND carga_horaria<=1000),
 publico_alvo text NOT NULL DEFAULT '' CHECK(length(publico_alvo)<=3000), observacoes text NOT NULL DEFAULT '' CHECK(length(observacoes)<=5000),
 empresas integer[] NOT NULL DEFAULT ARRAY[4,5,6], versao integer NOT NULL DEFAULT 1, source_key text UNIQUE,
 drive_folder_id text, created_by uuid, created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(),
 CHECK((status='concluido' AND data_realizacao IS NOT NULL) OR (status='agendado' AND data_realizacao IS NULL))
);
CREATE INDEX rh_trainings_schedule ON public.rh_trainings(data_programada,id);
CREATE TABLE public.rh_training_files (
 id uuid PRIMARY KEY, treinamento_id uuid NOT NULL REFERENCES public.rh_trainings,
 nome text NOT NULL CHECK(length(nome) BETWEEN 1 AND 180), mime text NOT NULL, tamanho integer NOT NULL CHECK(tamanho BETWEEN 1 AND 10485760),
 sha256 text NOT NULL CHECK(sha256 ~ '^[0-9a-f]{64}$'), status text NOT NULL DEFAULT 'pendente' CHECK(status IN ('pendente','enviando','arquivado','falhou')),
 drive_file_id text, drive_url text, erro text, created_by uuid NOT NULL, created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(),
 UNIQUE(treinamento_id,sha256)
);
CREATE INDEX rh_training_files_training ON public.rh_training_files(treinamento_id,created_at);
CREATE TABLE public.rh_training_events(id uuid PRIMARY KEY DEFAULT gen_random_uuid(),treinamento_id uuid NOT NULL REFERENCES public.rh_trainings,antes jsonb,depois jsonb NOT NULL,created_by uuid NOT NULL,created_at timestamptz NOT NULL DEFAULT now());
CREATE INDEX rh_training_events_training ON public.rh_training_events(treinamento_id,created_at DESC);
CREATE TABLE rh_internal.training_operations(id uuid PRIMARY KEY,payload jsonb NOT NULL,result jsonb NOT NULL);
ALTER TABLE rh_internal.training_operations ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON rh_internal.training_operations FROM PUBLIC,anon,authenticated;
ALTER TABLE public.rh_trainings ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.rh_training_files ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.rh_training_events ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.rh_trainings,public.rh_training_files,public.rh_training_events FROM PUBLIC,anon,authenticated;
GRANT SELECT ON public.rh_trainings,public.rh_training_files,public.rh_training_events TO authenticated;
GRANT ALL ON public.rh_trainings,public.rh_training_files,public.rh_training_events TO service_role;
CREATE POLICY trainings_read ON public.rh_trainings FOR SELECT TO authenticated USING(EXISTS(SELECT 1 FROM public.profiles WHERE id=(SELECT auth.uid()) AND status IN ('admin','aprovado')));
CREATE POLICY training_files_read ON public.rh_training_files FOR SELECT TO authenticated USING(EXISTS(SELECT 1 FROM public.rh_trainings t WHERE t.id=treinamento_id));
CREATE POLICY training_events_read ON public.rh_training_events FOR SELECT TO authenticated USING((SELECT rh_internal.is_admin()));

CREATE FUNCTION rh_internal.training_save(payload jsonb) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE old public.rh_trainings; saved public.rh_trainings; prior rh_internal.training_operations; op uuid; target uuid; result jsonb; request jsonb; companies integer[]; actual date;
BEGIN
 IF auth.uid() IS NULL OR NOT rh_internal.is_admin() THEN RAISE EXCEPTION 'Somente administradores podem alterar treinamentos.'; END IF;
 PERFORM pg_advisory_xact_lock(73411929);
 op:=(payload->>'operacao_id')::uuid;IF op IS NULL THEN RAISE EXCEPTION 'Identificador da operação obrigatório.'; END IF;
 request:=payload||jsonb_build_object('responsavel',auth.uid());
 SELECT * INTO prior FROM rh_internal.training_operations WHERE id=op;
 IF FOUND THEN IF prior.payload IS DISTINCT FROM request THEN RAISE EXCEPTION 'Operação já utilizada.'; END IF;RETURN prior.result; END IF;
 target:=nullif(payload->>'id','')::uuid;
 IF target IS NOT NULL THEN
  SELECT * INTO old FROM public.rh_trainings WHERE id=target FOR UPDATE;
  IF NOT FOUND OR old.versao IS DISTINCT FROM (payload->>'versao')::integer THEN RAISE EXCEPTION 'O treinamento mudou. Atualize antes de salvar.'; END IF;
 ELSE target:=gen_random_uuid();END IF;
 IF jsonb_typeof(payload->'empresas') IS DISTINCT FROM 'array' THEN RAISE EXCEPTION 'Selecione as empresas do treinamento.'; END IF;
 companies:=ARRAY(SELECT DISTINCT value::integer FROM jsonb_array_elements_text(payload->'empresas'));
 IF cardinality(companies)=0 OR EXISTS(SELECT 1 FROM unnest(companies)x WHERE NOT EXISTS(SELECT 1 FROM public.empresas e WHERE e.id=x)) THEN RAISE EXCEPTION 'Selecione empresas cadastradas.'; END IF;
 IF payload->>'status' NOT IN ('agendado','concluido') OR payload->>'status' IS NULL THEN RAISE EXCEPTION 'Situação inválida.'; END IF;
 actual:=CASE WHEN payload->>'status'='concluido' THEN nullif(payload->>'data_realizacao','')::date END;
 IF payload->>'status'='concluido' AND (actual IS NULL OR actual>(now() AT TIME ZONE 'America/Sao_Paulo')::date) THEN RAISE EXCEPTION 'Informe uma data de realização válida, até hoje.'; END IF;
 IF old.id IS NOT NULL AND actual IS DISTINCT FROM old.data_realizacao AND EXISTS(SELECT 1 FROM public.rh_training_files WHERE treinamento_id=old.id) THEN RAISE EXCEPTION 'A data de realização está vinculada aos comprovantes arquivados. Preserve-a; a data programada pode ser ajustada.'; END IF;
 INSERT INTO public.rh_trainings(id,nome,data_programada,data_realizacao,status,modalidade,carga_horaria,publico_alvo,observacoes,empresas,created_by)
 VALUES(target,trim(payload->>'nome'),(payload->>'data_programada')::date,actual,payload->>'status',payload->>'modalidade',(payload->>'carga_horaria')::numeric,coalesce(payload->>'publico_alvo',''),coalesce(payload->>'observacoes',''),companies,auth.uid())
 ON CONFLICT(id) DO UPDATE SET nome=excluded.nome,data_programada=excluded.data_programada,data_realizacao=excluded.data_realizacao,status=excluded.status,modalidade=excluded.modalidade,carga_horaria=excluded.carga_horaria,publico_alvo=excluded.publico_alvo,observacoes=excluded.observacoes,empresas=excluded.empresas,versao=public.rh_trainings.versao+1,updated_at=now() RETURNING * INTO saved;
 INSERT INTO public.rh_training_events(treinamento_id,antes,depois,created_by) VALUES(target,CASE WHEN old.id IS NULL THEN NULL ELSE to_jsonb(old) END,to_jsonb(saved),auth.uid());
 result:=to_jsonb(saved);INSERT INTO rh_internal.training_operations VALUES(op,request,result);RETURN result;
END $$;
REVOKE ALL ON FUNCTION rh_internal.training_save(jsonb) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION rh_internal.training_save(jsonb) TO authenticated;
CREATE FUNCTION public.rh_save_training(payload jsonb) RETURNS jsonb LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$ SELECT rh_internal.training_save(payload) $$;
REVOKE ALL ON FUNCTION public.rh_save_training(jsonb) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.rh_save_training(jsonb) TO authenticated;

CREATE FUNCTION rh_internal.training_prepare_file(payload jsonb) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE t public.rh_trainings; f public.rh_training_files; file_id uuid; filename text;
BEGIN
 IF auth.uid() IS NULL OR NOT rh_internal.is_admin() THEN RAISE EXCEPTION 'Somente administradores podem anexar comprovantes.'; END IF;
 PERFORM pg_advisory_xact_lock(73411929);
 SELECT * INTO t FROM public.rh_trainings WHERE id=(payload->>'treinamento_id')::uuid;
 IF NOT FOUND OR t.status<>'concluido' THEN RAISE EXCEPTION 'Marque o treinamento como concluído antes de anexar comprovantes.'; END IF;
 IF payload->>'mime' NOT IN ('application/pdf','image/jpeg','image/png','image/webp','application/vnd.openxmlformats-officedocument.wordprocessingml.document','application/vnd.openxmlformats-officedocument.spreadsheetml.sheet','text/plain') THEN RAISE EXCEPTION 'Formato de arquivo não permitido.'; END IF;
 SELECT * INTO f FROM public.rh_training_files WHERE treinamento_id=t.id AND sha256=payload->>'sha256';IF FOUND THEN RETURN to_jsonb(f); END IF;
 file_id:=(payload->>'id')::uuid;filename:=left(regexp_replace(trim(payload->>'nome'),'[[:cntrl:]/\\]','_','g'),180);
 INSERT INTO public.rh_training_files(id,treinamento_id,nome,mime,tamanho,sha256,created_by) VALUES(file_id,t.id,filename,payload->>'mime',(payload->>'tamanho')::integer,payload->>'sha256',auth.uid()) RETURNING * INTO f;
 RETURN to_jsonb(f);
END $$;
REVOKE ALL ON FUNCTION rh_internal.training_prepare_file(jsonb) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION rh_internal.training_prepare_file(jsonb) TO authenticated;
CREATE FUNCTION public.rh_prepare_training_file(payload jsonb) RETURNS jsonb LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$ SELECT rh_internal.training_prepare_file(payload) $$;
REVOKE ALL ON FUNCTION public.rh_prepare_training_file(jsonb) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.rh_prepare_training_file(jsonb) TO authenticated;

CREATE FUNCTION public.rh_begin_training_upload(file_id uuid) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE f public.rh_training_files;t public.rh_trainings;
BEGIN
 SELECT * INTO f FROM public.rh_training_files WHERE id=file_id FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'Comprovante não encontrado.'; END IF;
 SELECT * INTO t FROM public.rh_trainings WHERE id=f.treinamento_id;
 IF t.status<>'concluido' THEN RAISE EXCEPTION 'Treinamento não concluído.'; END IF;
 IF f.status<>'arquivado' THEN UPDATE public.rh_training_files SET status='enviando',erro=NULL,updated_at=now() WHERE id=file_id; END IF;
 RETURN jsonb_build_object('arquivo',to_jsonb(f),'treinamento',to_jsonb(t));
END $$;
REVOKE ALL ON FUNCTION public.rh_begin_training_upload(uuid) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.rh_begin_training_upload(uuid) TO service_role;
CREATE FUNCTION public.rh_finish_training_upload(payload jsonb) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE f public.rh_training_files;
BEGIN
 SELECT * INTO f FROM public.rh_training_files WHERE id=(payload->>'id')::uuid FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'Comprovante não encontrado.'; END IF;
 IF f.status='arquivado' THEN RETURN to_jsonb(f); END IF;
 IF coalesce(payload->>'erro','')<>'' THEN
  UPDATE public.rh_training_files SET status='falhou',erro=left(payload->>'erro',500),updated_at=now() WHERE id=f.id RETURNING * INTO f;RETURN to_jsonb(f);
 END IF;
 IF payload->>'sha256' IS DISTINCT FROM f.sha256 OR coalesce(payload->>'drive_file_id','') !~ '^[A-Za-z0-9_-]{10,150}$' OR coalesce(payload->>'folder_id','') !~ '^[A-Za-z0-9_-]{10,150}$' OR coalesce(payload->>'drive_url','') !~ '^https://drive.google.com/' THEN RAISE EXCEPTION 'Arquivo do Drive não confirmado.'; END IF;
 UPDATE public.rh_training_files SET status='arquivado',drive_file_id=payload->>'drive_file_id',drive_url=payload->>'drive_url',erro=NULL,updated_at=now() WHERE id=f.id RETURNING * INTO f;
 UPDATE public.rh_trainings SET drive_folder_id=payload->>'folder_id' WHERE id=f.treinamento_id;
 RETURN to_jsonb(f);
END $$;
REVOKE ALL ON FUNCTION public.rh_finish_training_upload(jsonb) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.rh_finish_training_upload(jsonb) TO service_role;

INSERT INTO public.rh_trainings(nome,data_original,data_programada,modalidade,carga_horaria,publico_alvo,source_key) VALUES
('Percepção de Risco','2026-10-07','2026-12-07','Online',1,'GHE 03, GHE 04 e Lideranças','cronograma-2026-01'),
('Direção Defensiva','2026-10-10','2026-12-10','Online',8,'GHE 01 (Vendedores, Promotores, Supervisores) + GHE 02 (Motoristas/Ajudantes)','cronograma-2026-02'),
('Combate a Princípio de Incêndio - NR 23','2026-10-13','2026-12-14','Presencial',4,'Brigada de Emergência (Conforme PPCIP)','cronograma-2026-03'),
('Movimentação Manual de Carga - NR 17','2026-10-15','2026-12-15','Presencial',4,'GHE 03 (Galpão) e GHE 02 (Motoristas/Ajudantes)','cronograma-2026-04'),
('NR 12 (Máquinas - Teórico)','2026-10-17','2026-12-17','Online',8,'GHE 05 (Op. Empilhadeira)','cronograma-2026-05'),
('NR 6 (EPI) - Parte 1','2026-10-20','2026-12-21','Online',2,'Operação Galpão e Campo (Uso, Guarda e Conservação)','cronograma-2026-06'),
('NR 6 (EPI) - Parte 2','2026-10-22','2026-12-22','Online',2,'Operação Galpão e Campo (Certificado de Aprovação e Trocas)','cronograma-2026-07'),
('Operador de Empilhadeira - NR 11/NR 12','2026-11-10','2027-01-11','Presencial',8,'GHE 05 (Op. Empilhadeira) - Prática','cronograma-2026-08'),
('NR 35 (Trabalho em Altura)','2026-11-12','2027-01-12','Presencial',8,'Equipe de Manutenção Predial/Galpão','cronograma-2026-09');
NOTIFY pgrst,'reload schema';
