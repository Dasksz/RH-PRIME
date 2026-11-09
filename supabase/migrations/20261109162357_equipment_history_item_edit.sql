-- Correção de C.A. em uma entrega salva, com auditoria separada de verificações.
CREATE TABLE rh_internal.equipment_ca_edits (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  entrega_id uuid NOT NULL REFERENCES public.rh_equipment_movements(id),
  ca_anterior text NOT NULL,
  ca text NOT NULL CHECK (length(ca) <= 80),
  created_by uuid NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE rh_internal.equipment_ca_edits ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON rh_internal.equipment_ca_edits FROM PUBLIC, anon, authenticated;
CREATE INDEX equipment_ca_edits_delivery ON rh_internal.equipment_ca_edits(entrega_id);

CREATE OR REPLACE FUNCTION rh_internal.equipment_validate()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
DECLARE e public.funcionarios_epi; original public.rh_equipment_movements; used integer; correction public.rh_equipment_item_corrections;
BEGIN
  IF TG_OP='INSERT' AND new.sem_desconto_estoque THEN
    IF new.tipo<>'entrega' OR new.data_movimento IS NULL OR new.data_movimento>=(now() AT TIME ZONE 'America/Sao_Paulo')::date THEN
      RAISE EXCEPTION 'Registrar sem desconto de estoque é permitido somente para entregas com data anterior a hoje.';
    END IF;
  ELSIF TG_OP='UPDATE' THEN
    IF new.sem_desconto_estoque IS DISTINCT FROM old.sem_desconto_estoque THEN RAISE EXCEPTION 'A opção de estoque de uma entrega salva não pode ser alterada.'; END IF;
    IF new.sem_desconto_estoque AND new.data_movimento>=(old.created_at AT TIME ZONE 'America/Sao_Paulo')::date THEN
      RAISE EXCEPTION 'Uma entrega histórica sem desconto deve permanecer anterior à data em que foi registrada.';
    END IF;
  END IF;
  IF tg_op='UPDATE' THEN
    IF auth.uid() IS NULL OR NOT rh_internal.can_write() OR NOT rh_internal.can_read_employee(old.funcionario_id) THEN RAISE EXCEPTION 'Sem permissão para corrigir entregas.'; END IF;
    IF old.tipo<>'entrega' THEN RAISE EXCEPTION 'Somente entregas podem ser corrigidas.'; END IF;
    IF current_setting('rh.equipment_ca_edit',true)=old.id::text THEN
      IF (to_jsonb(new)-'ca') IS DISTINCT FROM (to_jsonb(old)-'ca') THEN
        RAISE EXCEPTION 'Esta ação permite corrigir somente o C.A. da entrega.';
      END IF;
      RETURN new;
    END IF;
    IF current_setting('rh.equipment_item_correction',true)=old.id::text THEN
      SELECT * INTO correction FROM public.rh_equipment_item_corrections c
      WHERE c.entrega_id=old.id AND c.operacao_id::text=current_setting('rh.equipment_item_correction_operation',true)
        AND c.created_by=auth.uid() ORDER BY c.created_at DESC,c.id DESC LIMIT 1;
      IF NOT FOUND OR ROW(new.equipamento,new.complemento,new.descricao,new.ca,new.tamanho,new.quantidade,new.data_movimento,new.comprovante)
         IS DISTINCT FROM ROW(correction.equipamento,correction.complemento,correction.descricao,correction.ca,correction.tamanho,correction.quantidade,correction.data_entrega,correction.comprovante)
         OR (to_jsonb(new)-ARRAY['equipamento','complemento','descricao','ca','tamanho','quantidade','data_movimento','comprovante'])
          IS DISTINCT FROM (to_jsonb(old)-ARRAY['equipamento','complemento','descricao','ca','tamanho','quantidade','data_movimento','comprovante']) THEN
        RAISE EXCEPTION 'A correção do item não corresponde ao registro de auditoria.';
      END IF;
      SELECT coalesce(sum(quantidade),0) INTO used FROM public.rh_equipment_movements WHERE entrega_origem_id=old.id AND tipo IN ('devolucao','baixa');
      IF used>new.quantidade THEN RAISE EXCEPTION 'A quantidade não pode ser menor que o total já devolvido ou baixado.'; END IF;
      IF new.data_movimento IS NULL OR new.data_movimento>(now() AT TIME ZONE 'America/Sao_Paulo')::date
        OR EXISTS(SELECT 1 FROM public.rh_equipment_movements r WHERE r.entrega_origem_id=old.id AND r.data_movimento<new.data_movimento)
        OR EXISTS(SELECT 1 FROM public.rh_equipment_checks v WHERE v.entrega_id=old.id AND v.data_verificacao<new.data_movimento) THEN
        RAISE EXCEPTION 'A data da entrega é inválida em relação às devoluções e verificações existentes.';
      END IF;
      RETURN new;
    END IF;
    IF current_setting('rh.equipment_date_correction',true) IS DISTINCT FROM old.id::text THEN RAISE EXCEPTION 'Use a verificação para corrigir os dados do item.'; END IF;
    IF (to_jsonb(new)-'data_movimento') IS DISTINCT FROM (to_jsonb(old)-'data_movimento') THEN RAISE EXCEPTION 'A correção isolada permite alterar somente a data da entrega.'; END IF;
    IF new.data_movimento IS NULL OR new.data_movimento>(now() AT TIME ZONE 'America/Sao_Paulo')::date
      OR EXISTS(SELECT 1 FROM public.rh_equipment_movements r WHERE r.entrega_origem_id=old.id AND r.data_movimento<new.data_movimento)
      OR EXISTS(SELECT 1 FROM public.rh_equipment_checks v WHERE v.entrega_id=old.id AND v.data_verificacao<new.data_movimento) THEN
      RAISE EXCEPTION 'A entrega não pode ficar após uma devolução, troca ou verificação registrada.';
    END IF;
    RETURN new;
  END IF;
  IF tg_op<>'INSERT' THEN RAISE EXCEPTION 'Histórico de equipamentos é imutável.'; END IF;
  SELECT * INTO e FROM public.funcionarios_epi WHERE id=new.funcionario_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Colaborador indisponível.'; END IF;
  IF current_user='authenticated' AND (auth.uid() IS NULL OR NOT rh_internal.can_write() OR NOT rh_internal.can_read_employee(e.id)) THEN RAISE EXCEPTION 'Sem permissão para registrar equipamentos.'; END IF;
  IF new.legado THEN RAISE EXCEPTION 'Importação de legado não permitida nesta operação.'; END IF;
  IF new.data_movimento>(now() AT TIME ZONE 'America/Sao_Paulo')::date THEN RAISE EXCEPTION 'Data da movimentação não pode estar no futuro.'; END IF;
  IF new.tipo='entrega' AND e.data_desligamento IS NOT NULL THEN RAISE EXCEPTION 'Nova entrega bloqueada para colaborador desligado.'; END IF;
  IF new.entrega_origem_id IS NOT NULL THEN
    SELECT * INTO original FROM public.rh_equipment_movements WHERE id=new.entrega_origem_id;
    IF NOT FOUND OR original.tipo<>'entrega' OR original.funcionario_id<>new.funcionario_id OR rh_internal.equipment_category(original.id) IS DISTINCT FROM NEW.categoria THEN RAISE EXCEPTION 'Entrega de origem inválida.'; END IF;
    IF new.data_movimento<original.data_movimento THEN RAISE EXCEPTION 'Movimentação anterior à entrega original.'; END IF;
    IF new.tipo<>'entrega' THEN
      SELECT coalesce(sum(quantidade),0) INTO used FROM public.rh_equipment_movements WHERE entrega_origem_id=original.id AND tipo IN ('devolucao','baixa');
      IF used+new.quantidade>original.quantidade THEN RAISE EXCEPTION 'Quantidade superior ao saldo em posse. Atualize a tela.'; END IF;
      new.equipamento=original.equipamento;new.complemento=original.complemento;new.ca=original.ca;new.tamanho=original.tamanho;
    END IF;
  END IF;
  new.equipamento=trim(new.equipamento);new.complemento=trim(new.complemento);
  new.descricao=new.equipamento||CASE WHEN new.complemento<>'' THEN ' - '||new.complemento ELSE '' END;
  new.created_by=auth.uid();new.created_at=now();new.registrado_por=coalesce((SELECT split_part(trim(name),' ',1) FROM public.profiles WHERE id=auth.uid()),'');
  RETURN new;
END $function$;

-- A alteração do C.A. não passa pela validação de catálogo ou de saldo.
CREATE OR REPLACE TRIGGER zz_stock_equipment
  AFTER INSERT OR UPDATE OF equipamento, tamanho, quantidade ON public.rh_equipment_movements
  FOR EACH ROW EXECUTE FUNCTION rh_internal.stock_equipment();

CREATE FUNCTION rh_internal.edit_equipment_delivery_ca(p_entrega uuid, p_ca text, p_ca_anterior text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE
  movement public.rh_equipment_movements;
  employee_id uuid;
  ca_value text := trim(coalesce(p_ca,''));
BEGIN
  IF auth.uid() IS NULL OR NOT rh_internal.can_write() THEN
    RAISE EXCEPTION 'Sem permissão para corrigir entregas.';
  END IF;
  IF length(ca_value)>80 THEN RAISE EXCEPTION 'O C.A. deve ter até 80 caracteres.'; END IF;

  PERFORM pg_advisory_xact_lock(73411928);
  SELECT funcionario_id INTO employee_id FROM public.rh_equipment_movements WHERE id=p_entrega;
  IF employee_id IS NULL OR NOT rh_internal.can_read_employee(employee_id) THEN
    RAISE EXCEPTION 'Entrega indisponível.';
  END IF;
  PERFORM 1 FROM public.funcionarios_epi WHERE id=employee_id FOR UPDATE;
  SELECT * INTO movement FROM public.rh_equipment_movements WHERE id=p_entrega FOR UPDATE;
  IF NOT FOUND OR movement.tipo<>'entrega' OR EXISTS(
    SELECT 1 FROM public.rh_equipment_exclusions WHERE entrega_id=p_entrega
  ) THEN
    RAISE EXCEPTION 'Entrega indisponível. Atualize a tela.';
  END IF;

  IF movement.ca IS DISTINCT FROM ca_value THEN
    IF movement.ca IS DISTINCT FROM coalesce(p_ca_anterior,'') THEN
      RAISE EXCEPTION 'O C.A. foi alterado por outro usuário. Atualize a tela.';
    END IF;
    INSERT INTO rh_internal.equipment_ca_edits(entrega_id,ca_anterior,ca,created_by)
      VALUES(movement.id,movement.ca,ca_value,auth.uid());
    PERFORM set_config('rh.equipment_ca_edit',movement.id::text,true);
    UPDATE public.rh_equipment_movements SET ca=ca_value WHERE id=movement.id;
    PERFORM set_config('rh.equipment_ca_edit','',true);
    PERFORM rh_internal.stock_refresh_employee(employee_id);
  END IF;

  RETURN jsonb_build_object('id',movement.id,'ca',ca_value,'data_movimento',movement.data_movimento);
END $$;
REVOKE ALL ON FUNCTION rh_internal.edit_equipment_delivery_ca(uuid,text,text) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION rh_internal.edit_equipment_delivery_ca(uuid,text,text) TO authenticated;

CREATE FUNCTION public.rh_corrigir_ca_entrega(p_entrega uuid, p_ca text, p_ca_anterior text)
RETURNS jsonb LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$
  SELECT rh_internal.edit_equipment_delivery_ca(p_entrega,p_ca,p_ca_anterior)
$$;
REVOKE ALL ON FUNCTION public.rh_corrigir_ca_entrega(uuid,text,text) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.rh_corrigir_ca_entrega(uuid,text,text) TO authenticated;
NOTIFY pgrst,'reload schema';
