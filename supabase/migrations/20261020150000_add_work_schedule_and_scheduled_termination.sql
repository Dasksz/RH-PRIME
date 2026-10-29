ALTER TABLE public.funcionarios_epi
  ADD COLUMN IF NOT EXISTS carga_horaria_semanal numeric(6,2),
  ADD COLUMN IF NOT EXISTS jornada_diaria_minutos integer,
  ADD COLUMN IF NOT EXISTS dias_trabalho_semana smallint,
  ADD COLUMN IF NOT EXISTS data_desligamento_programada date,
  ADD COLUMN IF NOT EXISTS cumprindo_aviso_previo boolean NOT NULL DEFAULT false;

ALTER TABLE public.rh_absenteismo
  ADD COLUMN IF NOT EXISTS carga_horaria_semanal numeric(6,2),
  ADD COLUMN IF NOT EXISTS jornada_diaria_minutos integer,
  ADD COLUMN IF NOT EXISTS dias_trabalho_semana smallint;


CREATE OR REPLACE FUNCTION rh_internal.process_scheduled_terminations()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  local_now timestamp without time zone := timezone('America/Sao_Paulo', now());
  e public.funcionarios_epi%ROWTYPE;
  notice text;
BEGIN
  IF local_now::time < time '07:30' THEN RETURN; END IF;

  FOR e IN
    SELECT *
    FROM public.funcionarios_epi
    WHERE data_desligamento IS NULL
      AND data_desligamento_programada IS NOT NULL
      AND data_desligamento_programada <= local_now::date
    ORDER BY data_desligamento_programada, id
    FOR UPDATE SKIP LOCKED
  LOOP
    UPDATE public.funcionarios_epi
    SET data_desligamento = e.data_desligamento_programada
    WHERE id = e.id AND data_desligamento IS NULL;

    notice := CASE WHEN e.cumprindo_aviso_previo THEN 'Sim' ELSE 'Não' END;
    INSERT INTO public.rh_admin_notifications(
      actor_name, employee_id, employee_name, source_table, operation,
      title, details, message_text
    ) VALUES (
      'Agendamento automático', e.id, e.nome, 'funcionarios_epi', 'UPDATE',
      'Desligamento programado: ' || COALESCE(e.nome, 'Colaborador'),
      jsonb_build_object(
        'data_desligamento', e.data_desligamento_programada,
        'cumprindo_aviso_previo', e.cumprindo_aviso_previo
      ),
      left('RH PRIME — Desligamento programado concluído.' || E'\nColaborador: ' || COALESCE(e.nome, '') || E'\nData: ' || to_char(e.data_desligamento_programada, 'DD/MM/YYYY') || E'\nCumpria aviso prévio: ' || notice || E'\nO cadastro foi marcado como desligado automaticamente.', 6000)
    );
  END LOOP;
END;
$$;

REVOKE ALL ON FUNCTION rh_internal.process_scheduled_terminations() FROM PUBLIC, anon, authenticated;

DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
    PERFORM cron.unschedule(jobid) FROM cron.job WHERE jobname = 'rh_scheduled_terminations';
    PERFORM cron.schedule('rh_scheduled_terminations', '* * * * *', 'select rh_internal.process_scheduled_terminations()');
  END IF;
END;
$$;


NOTIFY pgrst, 'reload schema';
