DO $migration$
DECLARE
  definition text;
  needle text := 'IF p_action<>''salvar'' THEN RAISE EXCEPTION ''Ação de provisão inválida.''; END IF;';
  replacement text := $replace$
IF p_action='cancelar' THEN
    provision_id:=nullif(p_payload->>'id','')::uuid;
    IF provision_id IS NULL THEN RAISE EXCEPTION 'Selecione a provisão que será excluída.'; END IF;
    SELECT * INTO provision FROM public.rh_ferias_provisoes WHERE id=provision_id FOR UPDATE;
    IF provision.id IS NULL OR provision.status<>'ativa' OR NOT rh_internal.can_read_employee(provision.funcionario_id) THEN
      RAISE EXCEPTION 'Provisão ativa não encontrada ou fora da área autorizada.';
    END IF;
    obs:=trim(coalesce(p_payload->>'motivo',''));
    IF length(obs)<10 OR length(obs)>1800 THEN
      RAISE EXCEPTION 'Informe um motivo de 10 a 1.800 caracteres.';
    END IF;
    PERFORM pg_advisory_xact_lock(hashtext(provision.funcionario_id::text));
    UPDATE public.rh_ferias_provisoes
    SET status='cancelada',
        observacao='Cancelada pelo RH em '||to_char((now() at time zone 'America/Sao_Paulo')::date,'DD/MM/YYYY')||'. Motivo: '||obs,
        updated_at=now()
    WHERE id=provision_id;
    RETURN provision_id;
  END IF;
  IF p_action<>'salvar' THEN RAISE EXCEPTION 'Ação de provisão inválida.'; END IF;
$replace$;
BEGIN
  SELECT pg_get_functiondef('rh_internal.rh_vacation_provision_mutate(text,jsonb)'::regprocedure)
    INTO definition;
  IF position(needle IN definition)=0 THEN
    RAISE EXCEPTION 'A função de provisão mudou; revise a regra de cancelamento antes de aplicar esta migração.';
  END IF;
  definition:=replace(definition,needle,replacement);
  EXECUTE definition;
END
$migration$;
