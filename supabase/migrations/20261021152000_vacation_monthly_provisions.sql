CREATE OR REPLACE FUNCTION rh_internal.vacation_start_allowed(p_start date)
RETURNS boolean
LANGUAGE sql
IMMUTABLE
SET search_path=''
AS $$
  SELECT p_start IS NOT NULL
    AND extract(isodow FROM p_start)::integer BETWEEN 1 AND 3
    AND NOT (
      to_char(p_start,'MM-DD') IN ('01-01','04-21','05-01','09-07','10-12','11-02','11-15','12-25')
      OR (to_char(p_start,'MM-DD')='11-20' AND extract(year FROM p_start)::integer>=2024)
    )
$$;
REVOKE ALL ON FUNCTION rh_internal.vacation_start_allowed(date) FROM PUBLIC,anon,authenticated;

CREATE TABLE public.rh_ferias_provisoes (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  funcionario_id uuid NOT NULL REFERENCES public.funcionarios_epi(id) ON DELETE RESTRICT,
  periodo_inicio date NOT NULL,
  periodo_fim date NOT NULL,
  data_inicio date NOT NULL,
  dias_provisionados integer NOT NULL CHECK(dias_provisionados BETWEEN 1 AND 30),
  status text NOT NULL DEFAULT 'ativa' CHECK(status IN ('ativa','cancelada')),
  observacao text NOT NULL DEFAULT '' CHECK(length(observacao)<=2000),
  created_by uuid REFERENCES auth.users(id),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CHECK(periodo_fim>=periodo_inicio AND periodo_fim<(periodo_inicio+interval '1 year')::date),
  CHECK(rh_internal.vacation_start_allowed(data_inicio))
);
CREATE INDEX rh_ferias_provisoes_employee_idx ON public.rh_ferias_provisoes(funcionario_id);
CREATE INDEX rh_ferias_provisoes_month_idx ON public.rh_ferias_provisoes(data_inicio) WHERE status='ativa';
CREATE UNIQUE INDEX rh_ferias_provisoes_period_active_idx ON public.rh_ferias_provisoes(funcionario_id,periodo_inicio) WHERE status='ativa';

ALTER TABLE public.rh_ferias_provisoes ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.rh_ferias_provisoes FROM PUBLIC,anon,authenticated;
GRANT SELECT ON public.rh_ferias_provisoes TO authenticated;
GRANT ALL ON public.rh_ferias_provisoes TO service_role;
CREATE POLICY ferias_provisoes_read ON public.rh_ferias_provisoes
  FOR SELECT TO authenticated USING(rh_internal.can_read_employee(funcionario_id));
CREATE TRIGGER ferias_provisoes_audit AFTER INSERT OR UPDATE ON public.rh_ferias_provisoes
  FOR EACH ROW EXECUTE FUNCTION rh_internal.ferias_audit();

CREATE OR REPLACE FUNCTION rh_internal.rh_vacation_provision_mutate(p_action text,p_payload jsonb)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=''
AS $$
DECLARE
  provision public.rh_ferias_provisoes;
  employee public.funcionarios_epi;
  provision_id uuid;
  employee_id uuid;
  period_start date;
  period_end date;
  start_date date;
  days integer;
  obs text;
  today date:=(now() at time zone 'America/Sao_Paulo')::date;
BEGIN
  IF auth.uid() IS NULL OR NOT rh_internal.can_write() THEN RAISE EXCEPTION 'Acesso de edição necessário.'; END IF;
  IF p_action<>'salvar' THEN RAISE EXCEPTION 'Ação de provisão inválida.'; END IF;

  provision_id:=nullif(p_payload->>'id','')::uuid;
  IF provision_id IS NOT NULL THEN
    SELECT * INTO provision FROM public.rh_ferias_provisoes WHERE id=provision_id FOR UPDATE;
    IF provision.id IS NULL OR NOT rh_internal.can_read_employee(provision.funcionario_id) THEN
      RAISE EXCEPTION 'Provisão fora da área autorizada.';
    END IF;
    employee_id:=provision.funcionario_id;
  ELSE
    employee_id:=nullif(p_payload->>'funcionario_id','')::uuid;
  END IF;

  SELECT * INTO employee FROM public.funcionarios_epi WHERE id=employee_id;
  IF employee.id IS NULL OR NOT rh_internal.can_read_employee(employee.id) THEN
    RAISE EXCEPTION 'Colaborador fora da área autorizada.';
  END IF;
  IF employee.data_desligamento IS NOT NULL AND employee.data_desligamento<today THEN
    RAISE EXCEPTION 'Não é possível criar provisão para colaborador desligado.';
  END IF;

  period_start:=(p_payload->>'periodo_inicio')::date;
  period_end:=(p_payload->>'periodo_fim')::date;
  start_date:=(p_payload->>'data_inicio')::date;
  days:=(p_payload->>'dias_provisionados')::integer;
  obs:=coalesce(p_payload->>'observacao','');
  IF period_end<period_start OR period_end>=(period_start+interval '1 year')::date THEN
    RAISE EXCEPTION 'Confira o período aquisitivo selecionado.';
  END IF;
  IF days NOT BETWEEN 1 AND 30 OR length(obs)>2000 THEN
    RAISE EXCEPTION 'Informe de 1 a 30 dias de provisão e uma observação de até 2.000 caracteres.';
  END IF;
  IF NOT rh_internal.vacation_start_allowed(start_date) THEN
    RAISE EXCEPTION 'A data de início deve ser de segunda a quarta-feira e não pode ser feriado nacional.';
  END IF;

  PERFORM pg_advisory_xact_lock(hashtext(employee.id::text));
  IF EXISTS(
    SELECT 1 FROM public.rh_ferias_provisoes p
    WHERE p.funcionario_id=employee.id AND p.periodo_inicio=period_start AND p.status='ativa'
      AND p.id IS DISTINCT FROM provision_id
  ) THEN RAISE EXCEPTION 'Já existe provisão para esse período aquisitivo. Edite a provisão existente.'; END IF;

  IF EXISTS(
    SELECT 1 FROM public.rh_ferias_provisoes p
    WHERE p.funcionario_id=employee.id AND p.status='ativa' AND p.id IS DISTINCT FROM provision_id
      AND p.data_inicio<start_date+days AND p.data_inicio+p.dias_provisionados>start_date
  ) THEN RAISE EXCEPTION 'As datas se sobrepõem a outra provisão desse colaborador.'; END IF;

  IF EXISTS(
    SELECT 1 FROM public.rh_ferias_lancamentos l
    JOIN public.rh_ferias_periodos p ON p.id=l.periodo_id
    WHERE p.funcionario_id=employee.id AND l.status<>'cancelado'
      AND l.inicio<start_date+days AND l.fim>start_date
  ) THEN RAISE EXCEPTION 'As datas se sobrepõem a uma programação de férias já registrada.'; END IF;

  IF provision_id IS NULL THEN
    INSERT INTO public.rh_ferias_provisoes(funcionario_id,periodo_inicio,periodo_fim,data_inicio,dias_provisionados,observacao,created_by)
    VALUES(employee.id,period_start,period_end,start_date,days,obs,auth.uid()) RETURNING id INTO provision_id;
  ELSE
    UPDATE public.rh_ferias_provisoes
    SET periodo_inicio=period_start,periodo_fim=period_end,data_inicio=start_date,dias_provisionados=days,observacao=obs,updated_at=now()
    WHERE id=provision_id;
  END IF;
  RETURN provision_id;
END $$;
REVOKE ALL ON FUNCTION rh_internal.rh_vacation_provision_mutate(text,jsonb) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION rh_internal.rh_vacation_provision_mutate(text,jsonb) TO authenticated;
CREATE OR REPLACE FUNCTION public.rh_vacation_provision_mutate(p_action text,p_payload jsonb)
RETURNS uuid
LANGUAGE sql
SECURITY INVOKER
SET search_path=''
AS $$ SELECT rh_internal.rh_vacation_provision_mutate(p_action,p_payload); $$;
REVOKE ALL ON FUNCTION public.rh_vacation_provision_mutate(text,jsonb) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.rh_vacation_provision_mutate(text,jsonb) TO authenticated;

DO $migration$
DECLARE
  definition text;
  needle text:='if st=''programado'' and e.data_desligamento is not null then raise exception ''Programação bloqueada para desligado'';end if;';
  replacement text;
BEGIN
  SELECT pg_get_functiondef('rh_internal.rh_vacation_mutate(text,jsonb)'::regprocedure) INTO definition;
  IF position(needle IN definition)=0 THEN
    RAISE EXCEPTION 'Não foi possível localizar a validação de programação de férias; revise a função antes de atualizar.';
  END IF;
  replacement:=needle||' if st=''programado'' and days>0 and not rh_internal.vacation_start_allowed(start_date) then raise exception ''A data de início deve ser de segunda a quarta-feira e não pode ser feriado nacional.'';end if;';
  EXECUTE replace(definition,needle,replacement);
END $migration$;
