-- Excluir lançamento incorreto sem registrar uma devolução física.
CREATE TABLE public.rh_equipment_exclusions (
 entrega_id uuid PRIMARY KEY REFERENCES public.rh_equipment_movements(id),
 funcionario_id uuid NOT NULL REFERENCES public.funcionarios_epi(id),
 motivo text NOT NULL CHECK(length(trim(motivo)) BETWEEN 3 AND 500),
 antes jsonb NOT NULL, created_by uuid NOT NULL, created_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.rh_equipment_exclusions ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.rh_equipment_exclusions FROM PUBLIC,anon,authenticated;
GRANT SELECT ON public.rh_equipment_exclusions TO authenticated;
CREATE POLICY equipment_exclusions_read ON public.rh_equipment_exclusions FOR SELECT TO authenticated USING(rh_internal.can_read_employee(funcionario_id));
DO $$ DECLARE definition text; BEGIN
 SELECT pg_get_viewdef('public.rh_equipment_current'::regclass,true) INTO definition;
 definition:=regexp_replace(trim(definition),';$','');
 EXECUTE 'CREATE OR REPLACE VIEW public.rh_equipment_current WITH(security_invoker=true) AS '||definition||' WHERE NOT EXISTS (SELECT 1 FROM public.rh_equipment_exclusions x WHERE x.entrega_id=m.id)';
END $$;
CREATE FUNCTION rh_internal.equipment_exclude(p_entrega uuid,p_motivo text) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE m public.rh_equipment_movements; b public.rh_equipment_products; emp uuid; op uuid:=gen_random_uuid(); last_day date;
BEGIN
 IF auth.uid() IS NULL OR NOT rh_internal.can_write() THEN RAISE EXCEPTION 'Sem permissão para excluir entregas.'; END IF;
 IF p_motivo IS NULL OR length(trim(p_motivo)) NOT BETWEEN 3 AND 500 THEN RAISE EXCEPTION 'Informe o motivo da exclusão.'; END IF;
 PERFORM pg_advisory_xact_lock(73411928);
 SELECT funcionario_id INTO emp FROM public.rh_equipment_movements WHERE id=p_entrega;
 IF emp IS NULL OR NOT rh_internal.can_read_employee(emp) THEN RAISE EXCEPTION 'Entrega indisponível.'; END IF;
 PERFORM 1 FROM public.funcionarios_epi WHERE id=emp FOR UPDATE;
 SELECT * INTO m FROM public.rh_equipment_movements WHERE id=p_entrega FOR UPDATE;
 IF m.tipo<>'entrega' THEN RAISE EXCEPTION 'Selecione uma entrega.'; END IF;
 IF EXISTS(SELECT 1 FROM public.rh_equipment_exclusions WHERE entrega_id=m.id) THEN RETURN jsonb_build_object('id',m.id,'excluido',true); END IF;
 IF EXISTS(SELECT 1 FROM public.rh_equipment_movements WHERE entrega_origem_id=m.id) THEN RAISE EXCEPTION 'Esta entrega possui devolução, baixa ou reposição vinculada. Corrija os vínculos antes de excluir.'; END IF;
 SELECT * INTO b FROM public.rh_equipment_products WHERE movimento_id=m.id;
 INSERT INTO public.rh_equipment_exclusions(entrega_id,funcionario_id,motivo,antes,created_by) VALUES(m.id,emp,trim(p_motivo),to_jsonb(m),auth.uid());
 IF b.descontado THEN PERFORM rh_internal.stock_delta(b.produto_id,b.filial,b.tamanho,m.quantidade,op,'Exclusão de entrega registrada incorretamente',m.id); END IF;
 PERFORM rh_internal.stock_refresh_employee(emp);
 SELECT max(coalesce((SELECT max(c.data_verificacao) FROM public.rh_equipment_checks c WHERE c.entrega_id=v.id),v.data_movimento)) INTO last_day
 FROM public.rh_equipment_current v WHERE v.funcionario_id=emp AND v.categoria=m.categoria AND v.tipo='entrega';
 IF m.categoria='epi' THEN UPDATE public.funcionarios_epi SET epi_data=to_char(last_day,'DD/MM/YYYY') WHERE id=emp;
 ELSE UPDATE public.funcionarios_epi SET fardamento_data=to_char(last_day,'DD/MM/YYYY') WHERE id=emp; END IF;
 RETURN jsonb_build_object('id',m.id,'excluido',true);
END $$;
REVOKE ALL ON FUNCTION rh_internal.equipment_exclude(uuid,text) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION rh_internal.equipment_exclude(uuid,text) TO authenticated;
CREATE FUNCTION public.rh_excluir_entrega(p_entrega uuid,p_motivo text) RETURNS jsonb LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$ SELECT rh_internal.equipment_exclude(p_entrega,p_motivo) $$;
REVOKE ALL ON FUNCTION public.rh_excluir_entrega(uuid,text) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.rh_excluir_entrega(uuid,text) TO authenticated;
CREATE FUNCTION rh_internal.equipment_exclusion_guard() RETURNS trigger LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $$
BEGIN
 IF EXISTS(SELECT 1 FROM public.rh_equipment_exclusions WHERE entrega_id=CASE WHEN TG_TABLE_NAME='rh_equipment_checks' THEN (to_jsonb(new)->>'entrega_id')::uuid ELSE new.id END OR entrega_id=(to_jsonb(new)->>'entrega_origem_id')::uuid) THEN RAISE EXCEPTION 'Entrega excluída. Atualize a tela.'; END IF;
 RETURN new;
END $$;
REVOKE ALL ON FUNCTION rh_internal.equipment_exclusion_guard() FROM PUBLIC,anon,authenticated;
CREATE TRIGGER equipment_exclusion_guard BEFORE INSERT OR UPDATE ON public.rh_equipment_movements FOR EACH ROW EXECUTE FUNCTION rh_internal.equipment_exclusion_guard();
CREATE TRIGGER equipment_exclusion_guard BEFORE INSERT ON public.rh_equipment_checks FOR EACH ROW EXECUTE FUNCTION rh_internal.equipment_exclusion_guard();
NOTIFY pgrst,'reload schema';
