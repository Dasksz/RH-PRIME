-- Allow recording vacation taken in advance of its selected accrual period.
-- The selected period remains the source of balance; the event keeps an explicit flag.
ALTER TABLE public.rh_ferias_lancamentos
  ADD COLUMN IF NOT EXISTS antecipada boolean NOT NULL DEFAULT false;

DO $migration$
DECLARE
  definition text;
  old_guard text := 'if days>0 and start_date<=p.fim then raise exception ''Gozo anterior à aquisição completa: revise o período; antecipação exige tratamento específico pelo DP'';end if;';
  new_guard text := 'if days>0 and start_date>=p.inicio and start_date<=p.fim then raise exception ''Gozo durante o período aquisitivo: confira e selecione o período correto.'';end if; if days>0 and start_date<p.inicio and end_date>=p.inicio then raise exception ''O gozo antecipado deve terminar antes do início do período aquisitivo selecionado.'';end if; if days>0 and start_date<p.inicio and (not coalesce((p_payload->>''antecipada'')::boolean,false) or not coalesce((p_payload->>''concordancia'')::boolean,false) or length(trim(obs))<10) then raise exception ''Gozo antecipado exige marcação explícita, concordância registrada e observação para conferência pelo DP.'';end if; if coalesce((p_payload->>''antecipada'')::boolean,false) and (days=0 or start_date>=p.inicio) then raise exception ''Marque gozo antecipado somente quando a saída começar antes do período aquisitivo.'';end if;';
  old_insert text := 'insert into public.rh_ferias_lancamentos(periodo_id,inicio,fim,dias_gozo,dias_abono,status,observacao,concordancia,created_by) values(pid,start_date,end_date,days,sold,st,obs,coalesce((p_payload->>''concordancia'')::boolean,false),auth.uid()) returning id into lid;';
  new_insert text := 'insert into public.rh_ferias_lancamentos(periodo_id,inicio,fim,dias_gozo,dias_abono,status,observacao,concordancia,antecipada,created_by) values(pid,start_date,end_date,days,sold,st,obs,coalesce((p_payload->>''concordancia'')::boolean,false),coalesce((p_payload->>''antecipada'')::boolean,false),auth.uid()) returning id into lid;';
BEGIN
  SELECT pg_get_functiondef('rh_internal.rh_vacation_mutate(text,jsonb)'::regprocedure)
    INTO definition;

  IF position(old_guard IN definition)=0 OR position(old_insert IN definition)=0 THEN
    RAISE EXCEPTION 'A função de lançamento de férias mudou; revise as validações de gozo antes de aplicar esta migração.';
  END IF;

  definition := replace(definition,old_guard,new_guard);
  definition := replace(definition,old_insert,new_insert);
  EXECUTE definition;
END
$migration$;
