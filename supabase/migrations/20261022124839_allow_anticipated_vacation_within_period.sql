DO $migration$
DECLARE
  definition text;
  old_guard text := 'if days>0 and start_date>=p.inicio and start_date<=p.fim then raise exception ''Gozo durante o período aquisitivo: confira e selecione o período correto.'';end if; if days>0 and start_date<p.inicio and end_date>=p.inicio then raise exception ''O gozo antecipado deve terminar antes do início do período aquisitivo selecionado.'';end if; if days>0 and start_date<p.inicio and (not coalesce((p_payload->>''antecipada'')::boolean,false) or not coalesce((p_payload->>''concordancia'')::boolean,false) or length(trim(obs))<10) then raise exception ''Gozo antecipado exige marcação explícita, concordância registrada e observação para conferência pelo DP.'';end if; if coalesce((p_payload->>''antecipada'')::boolean,false) and (days=0 or start_date>=p.inicio) then raise exception ''Marque gozo antecipado somente quando a saída começar antes do período aquisitivo.'';end if;';
  new_guard text := 'if days>0 and start_date<p.inicio and end_date>=p.inicio then raise exception ''O gozo antecipado deve terminar antes do início do período aquisitivo selecionado.'';end if; if days>0 and start_date<=p.fim and (not coalesce((p_payload->>''antecipada'')::boolean,false) or not coalesce((p_payload->>''concordancia'')::boolean,false)) then raise exception ''Gozo antecipado do próprio período exige confirmação e concordância do colaborador.'';end if; if coalesce((p_payload->>''antecipada'')::boolean,false) and (days=0 or start_date>p.fim) then raise exception ''Marque gozo antecipado somente para férias antes da conclusão do período aquisitivo.'';end if;';
BEGIN
  SELECT pg_get_functiondef('rh_internal.rh_vacation_mutate(text,jsonb)'::regprocedure)
    INTO definition;
  IF position(old_guard IN definition)=0 THEN
    RAISE EXCEPTION 'A validação de antecipação mudou; revise a regra de gozo antes de aplicar esta migração.';
  END IF;
  definition:=replace(definition,old_guard,new_guard);
  EXECUTE definition;
END
$migration$;
