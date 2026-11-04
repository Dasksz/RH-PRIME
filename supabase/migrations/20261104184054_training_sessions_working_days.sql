ALTER TABLE public.rh_trainings ADD COLUMN etapas jsonb NOT NULL DEFAULT '[]', ADD COLUMN dia_integral boolean NOT NULL DEFAULT false;
UPDATE public.rh_trainings SET dia_integral=true WHERE source_key='cronograma-2026-08';
UPDATE public.rh_trainings SET etapas=jsonb_build_array(jsonb_build_object('data',data_programada,'horas',carga_horaria));
UPDATE public.rh_trainings SET etapas=jsonb_build_array(jsonb_build_object('data',data_programada,'horas',4),jsonb_build_object('data',CASE source_key WHEN 'cronograma-2026-02' THEN '2026-12-11' WHEN 'cronograma-2026-05' THEN '2026-12-18' ELSE '2027-01-13' END,'horas',4)) WHERE source_key IN ('cronograma-2026-02','cronograma-2026-05','cronograma-2026-09');
CREATE FUNCTION rh_internal.validate_training_sessions() RETURNS trigger LANGUAGE plpgsql SET search_path='' AS $$
DECLARE part jsonb; d date; previous date; hours numeric; total numeric:=0;
BEGIN
 IF jsonb_typeof(NEW.etapas)<>'array' OR jsonb_array_length(NEW.etapas) NOT BETWEEN 1 AND 250 THEN RAISE EXCEPTION 'Informe as etapas do treinamento.'; END IF;
 FOR part IN SELECT value FROM jsonb_array_elements(NEW.etapas) LOOP
  d:=(part->>'data')::date;hours:=(part->>'horas')::numeric;
  IF d IS NULL OR extract(isodow FROM d)>5 THEN RAISE EXCEPTION 'Programe cada etapa de segunda a sexta-feira.'; END IF;
  IF hours IS NULL OR hours<=0 OR hours>(CASE WHEN NEW.dia_integral THEN 1000 ELSE 4 END) THEN RAISE EXCEPTION 'Cada etapa aceita até 4 horas por dia. A exceção é o curso de operador de empilhadeira cadastrado.'; END IF;
  IF previous IS NOT NULL AND d<=previous THEN RAISE EXCEPTION 'Cada etapa deve ocorrer em um dia posterior à anterior.'; END IF;
  IF previous IS NULL AND d<>NEW.data_programada THEN RAISE EXCEPTION 'O início deve corresponder à primeira etapa.'; END IF;
  previous:=d;total:=total+hours;
 END LOOP;
 IF total<>NEW.carga_horaria THEN RAISE EXCEPTION 'A soma das etapas deve corresponder à carga horária do curso.'; END IF;
 RETURN NEW;
END $$;
REVOKE ALL ON FUNCTION rh_internal.validate_training_sessions() FROM PUBLIC,anon,authenticated;
CREATE TRIGGER validate_training_sessions BEFORE INSERT OR UPDATE ON public.rh_trainings FOR EACH ROW EXECUTE FUNCTION rh_internal.validate_training_sessions();
CREATE OR REPLACE FUNCTION rh_internal.training_save(payload jsonb) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
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
 INSERT INTO public.rh_trainings(id,nome,data_programada,data_realizacao,status,modalidade,carga_horaria,publico_alvo,observacoes,empresas,etapas,dia_integral,created_by)
 VALUES(target,trim(payload->>'nome'),(payload->>'data_programada')::date,actual,payload->>'status',payload->>'modalidade',(payload->>'carga_horaria')::numeric,coalesce(payload->>'publico_alvo',''),coalesce(payload->>'observacoes',''),companies,coalesce(payload->'etapas','[]'::jsonb),coalesce(old.dia_integral,false),auth.uid())
 ON CONFLICT(id) DO UPDATE SET nome=excluded.nome,data_programada=excluded.data_programada,data_realizacao=excluded.data_realizacao,status=excluded.status,modalidade=excluded.modalidade,carga_horaria=excluded.carga_horaria,publico_alvo=excluded.publico_alvo,observacoes=excluded.observacoes,empresas=excluded.empresas,etapas=excluded.etapas,versao=public.rh_trainings.versao+1,updated_at=now() RETURNING * INTO saved;
 INSERT INTO public.rh_training_events(treinamento_id,antes,depois,created_by) VALUES(target,CASE WHEN old.id IS NULL THEN NULL ELSE to_jsonb(old) END,to_jsonb(saved),auth.uid());
 result:=to_jsonb(saved);INSERT INTO rh_internal.training_operations VALUES(op,request,result);RETURN result;
END $$;

NOTIFY pgrst,'reload schema';
