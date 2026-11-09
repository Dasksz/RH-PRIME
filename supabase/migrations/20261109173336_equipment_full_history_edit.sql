-- Edita a entrega original e mantém uma trilha de auditoria independente de verificações.
CREATE TABLE rh_internal.equipment_history_edits (
  id uuid PRIMARY KEY,
  entrega_id uuid NOT NULL REFERENCES public.rh_equipment_movements(id),
  antes jsonb NOT NULL,
  depois jsonb NOT NULL,
  created_by uuid NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE rh_internal.equipment_history_edits ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON rh_internal.equipment_history_edits FROM PUBLIC, anon, authenticated;
CREATE INDEX equipment_history_edits_delivery ON rh_internal.equipment_history_edits(entrega_id);

CREATE OR REPLACE FUNCTION rh_internal.equipment_validate()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
DECLARE e public.funcionarios_epi; original public.rh_equipment_movements; used integer; correction public.rh_equipment_item_corrections;
BEGIN
  IF TG_OP='UPDATE' AND current_setting('rh.equipment_history_edit',true)=old.id::text THEN
    IF auth.uid() IS NULL OR NOT rh_internal.can_write() OR NOT rh_internal.can_read_employee(old.funcionario_id)
      OR old.tipo<>'entrega'
      OR (to_jsonb(new)-ARRAY['equipamento','complemento','descricao','ca','tamanho','quantidade','data_movimento','observacao','comprovante','sem_desconto_estoque'])
        IS DISTINCT FROM (to_jsonb(old)-ARRAY['equipamento','complemento','descricao','ca','tamanho','quantidade','data_movimento','observacao','comprovante','sem_desconto_estoque']) THEN
      RAISE EXCEPTION 'Alteração não autorizada para esta entrega.';
    END IF;
    RETURN new;
  END IF;
  IF TG_OP='INSERT' AND new.sem_desconto_estoque THEN
    IF new.tipo<>'entrega' OR new.data_movimento IS NULL OR new.data_movimento>=(now() AT TIME ZONE 'America/Sao_Paulo')::date THEN
      RAISE EXCEPTION 'Registrar sem desconto de estoque é permitido somente para entregas com data anterior a hoje.';
    END IF;
  ELSIF TG_OP='UPDATE' THEN
    IF new.sem_desconto_estoque IS DISTINCT FROM old.sem_desconto_estoque THEN RAISE EXCEPTION 'A opção de estoque de uma entrega salva não pode ser alterada.'; END IF;
    IF new.sem_desconto_estoque AND new.data_movimento IS DISTINCT FROM old.data_movimento AND new.data_movimento>=(old.created_at AT TIME ZONE 'America/Sao_Paulo')::date THEN
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

-- Na edição direta, o ajuste do saldo é feito na mesma transação da correção.
CREATE OR REPLACE TRIGGER zz_stock_equipment
  AFTER INSERT OR UPDATE OF equipamento, tamanho, quantidade ON public.rh_equipment_movements
  FOR EACH ROW WHEN (current_setting('rh.equipment_history_edit',true) IS DISTINCT FROM NEW.id::text)
  EXECUTE FUNCTION rh_internal.stock_equipment();

CREATE FUNCTION rh_internal.edit_equipment_history(p_entrega uuid,p_original jsonb,p_alteracoes jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE
  m public.rh_equipment_movements;
  edited public.rh_equipment_movements;
  binding public.rh_equipment_products;
  product public.rh_products;
  employee public.funcionarios_epi;
  original_view public.rh_equipment_current;
  result jsonb;
  baseline jsonb;
  desired jsonb;
  destination_product uuid;
  destination_size text;
  branch text;
  was_debited boolean;
  debit boolean;
  change_stock boolean;
  change_date boolean;
  latest_date date;
  today date := (now() AT TIME ZONE 'America/Sao_Paulo')::date;
  edit_id uuid := gen_random_uuid();
  allowed_fields constant text[] := ARRAY['produto_id','complemento','tamanho','ca','quantidade','data_movimento','observacao','comprovante','descontado'];
BEGIN
  IF auth.uid() IS NULL OR NOT rh_internal.can_write() THEN
    RAISE EXCEPTION 'Sem permissão para corrigir entregas.';
  END IF;
  IF jsonb_typeof(p_alteracoes) IS DISTINCT FROM 'object' OR p_alteracoes-allowed_fields<>'{}' THEN
    RAISE EXCEPTION 'Campos da edição inválidos.';
  END IF;

  PERFORM pg_advisory_xact_lock(73411928);
  SELECT * INTO m FROM public.rh_equipment_movements WHERE id=p_entrega AND tipo='entrega';
  IF NOT FOUND OR NOT rh_internal.can_read_employee(m.funcionario_id) THEN RAISE EXCEPTION 'Entrega indisponível.'; END IF;
  SELECT * INTO employee FROM public.funcionarios_epi WHERE id=m.funcionario_id FOR UPDATE;
  SELECT * INTO m FROM public.rh_equipment_movements WHERE id=p_entrega FOR UPDATE;
  SELECT * INTO original_view FROM public.rh_equipment_current WHERE id=p_entrega;
  IF NOT FOUND THEN RAISE EXCEPTION 'Entrega indisponível. Atualize a tela.'; END IF;
  SELECT * INTO binding FROM public.rh_equipment_products WHERE movimento_id=p_entrega;

  was_debited:=coalesce(binding.descontado,false);
  baseline:=jsonb_build_object('produto_id',binding.produto_id,'complemento',m.complemento,'tamanho',m.tamanho,
    'ca',m.ca,'quantidade',m.quantidade,'data_movimento',m.data_movimento,'observacao',m.observacao,
    'comprovante',m.comprovante,'descontado',was_debited);
  desired:=baseline||p_alteracoes;
  IF desired=baseline THEN RETURN to_jsonb(original_view); END IF;
  IF p_original IS DISTINCT FROM baseline THEN RAISE EXCEPTION 'A entrega foi alterada por outro usuário. Atualize a tela.'; END IF;

  edited:=jsonb_populate_record(m,p_alteracoes-ARRAY['produto_id','descontado']);
  destination_product:=(desired->>'produto_id')::uuid;
  debit:=(desired->>'descontado')::boolean;
  IF edited.quantidade IS NULL OR edited.quantidade NOT BETWEEN 1 AND 10000 OR debit IS NULL
    OR edited.complemento IS NULL OR length(edited.complemento)>300 OR edited.ca IS NULL OR length(edited.ca)>80
    OR edited.tamanho IS NULL OR length(edited.tamanho)>30 OR edited.observacao IS NULL OR length(edited.observacao)>2000
    OR edited.comprovante IS NULL OR length(edited.comprovante)>2000
    OR (edited.comprovante<>'' AND edited.comprovante!~'^https?://') THEN
    RAISE EXCEPTION 'Confira a quantidade, os dados do item e o link do comprovante.';
  END IF;
  IF destination_product IS NULL AND (binding.produto_id IS NOT NULL OR debit) THEN
    RAISE EXCEPTION 'Selecione um item do estoque.';
  END IF;
  IF destination_product IS DISTINCT FROM binding.produto_id THEN
    SELECT * INTO product FROM public.rh_products WHERE id=destination_product;
    IF NOT FOUND OR NOT product.ativo OR product.categoria<>original_view.categoria
      OR NOT (product.todas_funcoes OR coalesce(employee.funcao=ANY(product.funcoes),false)) THEN
      RAISE EXCEPTION 'Selecione um item disponível para a função do colaborador nesta aba.';
    END IF;
    edited.equipamento:=product.nome;
  END IF;
  IF edited.equipamento IS DISTINCT FROM m.equipamento OR edited.complemento IS DISTINCT FROM m.complemento THEN
    edited.descricao:=edited.equipamento||CASE WHEN edited.complemento<>'' THEN ' - '||edited.complemento ELSE '' END;
  END IF;

  change_date:=edited.data_movimento IS DISTINCT FROM m.data_movimento;
  IF change_date AND (
    edited.data_movimento IS NULL OR edited.data_movimento>today
    OR EXISTS(SELECT 1 FROM public.rh_equipment_movements r WHERE r.entrega_origem_id=m.id AND r.data_movimento<edited.data_movimento)
    OR EXISTS(SELECT 1 FROM public.rh_equipment_checks v WHERE v.entrega_id=m.id AND v.data_verificacao<edited.data_movimento)
    OR EXISTS(SELECT 1 FROM public.rh_equipment_movements r WHERE r.entrega_origem_id=m.entrega_origem_id
      AND r.operacao_id=m.operacao_id AND r.tipo IN ('devolucao','baixa') AND r.data_movimento>edited.data_movimento)
  ) THEN RAISE EXCEPTION 'A data precisa respeitar as devoluções, trocas e verificações já registradas e não pode ser futura.'; END IF;
  IF edited.quantidade IS DISTINCT FROM m.quantidade AND edited.quantidade<(
    SELECT coalesce(sum(r.quantidade),0) FROM public.rh_equipment_movements r
    WHERE r.entrega_origem_id=m.id AND r.tipo IN ('devolucao','baixa')
  ) THEN RAISE EXCEPTION 'A quantidade não pode ser menor que o total já devolvido ou baixado.'; END IF;

  IF debit IS DISTINCT FROM was_debited THEN edited.sem_desconto_estoque:=NOT debit; END IF;
  IF edited.sem_desconto_estoque AND (edited.data_movimento IS NULL OR edited.data_movimento>=today) THEN
    RAISE EXCEPTION 'Selecione uma data anterior a hoje para manter a entrega sem desconto no estoque.';
  END IF;

  destination_size:=CASE WHEN destination_product IS NOT DISTINCT FROM binding.produto_id AND edited.tamanho=m.tamanho
    THEN coalesce(binding.tamanho,nullif(edited.tamanho,''),'ÚNICO') ELSE coalesce(nullif(edited.tamanho,''),'ÚNICO') END;
  branch:=coalesce(binding.filial,employee.unidade);
  IF destination_product IS NOT NULL AND (
    destination_product IS DISTINCT FROM binding.produto_id OR edited.tamanho IS DISTINCT FROM m.tamanho OR (debit AND NOT was_debited)
  ) AND NOT EXISTS(SELECT 1 FROM public.rh_products p WHERE p.id=destination_product AND destination_size=ANY(p.tamanhos)) THEN
    RAISE EXCEPTION 'Selecione um tamanho cadastrado para o item.';
  END IF;
  change_stock:=ROW(destination_product,destination_size,edited.quantidade,debit)
    IS DISTINCT FROM ROW(binding.produto_id,coalesce(binding.tamanho,destination_size),m.quantidade,was_debited);
  IF change_stock THEN
    IF was_debited AND debit AND destination_product=binding.produto_id AND destination_size=binding.tamanho THEN
      PERFORM rh_internal.stock_delta(destination_product,branch,destination_size,m.quantidade-edited.quantidade,edit_id,'Ajuste por edição de entrega',m.id);
    ELSE
      IF was_debited THEN
        PERFORM rh_internal.stock_delta(binding.produto_id,binding.filial,binding.tamanho,m.quantidade,edit_id,'Estorno por edição de entrega',m.id);
      END IF;
      IF debit THEN
        PERFORM rh_internal.stock_delta(destination_product,branch,destination_size,-edited.quantidade,edit_id,'Desconto por edição de entrega',m.id);
      END IF;
    END IF;
  END IF;
  IF change_stock AND destination_product IS NOT NULL THEN
    INSERT INTO public.rh_equipment_products(movimento_id,produto_id,filial,tamanho,descontado)
      VALUES(m.id,destination_product,branch,destination_size,debit)
      ON CONFLICT(movimento_id) DO UPDATE SET produto_id=excluded.produto_id,tamanho=excluded.tamanho,descontado=excluded.descontado;
  END IF;

  PERFORM set_config('rh.equipment_history_edit',m.id::text,true);
  PERFORM set_config('rh.equipment_correction_reason','Edição do item no histórico.',true);
  UPDATE public.rh_equipment_movements
    SET equipamento=edited.equipamento,complemento=edited.complemento,descricao=edited.descricao,ca=edited.ca,
      tamanho=edited.tamanho,quantidade=edited.quantidade,data_movimento=edited.data_movimento,
      observacao=edited.observacao,comprovante=edited.comprovante,sem_desconto_estoque=edited.sem_desconto_estoque
    WHERE id=m.id;
  PERFORM set_config('rh.equipment_history_edit','',true);
  PERFORM set_config('rh.equipment_correction_reason','',true);

  PERFORM rh_internal.stock_refresh_employee(m.funcionario_id);
  IF change_date OR edited.quantidade IS DISTINCT FROM m.quantidade THEN
    SELECT max(coalesce((SELECT max(v.data_verificacao) FROM public.rh_equipment_checks v WHERE v.entrega_id=e.id),e.data_movimento))
    INTO latest_date FROM public.rh_equipment_current e
    WHERE e.funcionario_id=m.funcionario_id AND e.categoria=original_view.categoria AND e.tipo='entrega'
      AND e.quantidade>(SELECT coalesce(sum(r.quantidade),0) FROM public.rh_equipment_movements r
        WHERE r.entrega_origem_id=e.id AND r.tipo IN ('devolucao','baixa'));
    IF original_view.categoria='epi' THEN
      UPDATE public.funcionarios_epi SET epi_data=coalesce(to_char(latest_date,'DD/MM/YYYY'),'') WHERE id=m.funcionario_id;
    ELSE
      UPDATE public.funcionarios_epi SET fardamento_data=coalesce(to_char(latest_date,'DD/MM/YYYY'),'') WHERE id=m.funcionario_id;
    END IF;
  END IF;
  SELECT to_jsonb(v) INTO result FROM public.rh_equipment_current v WHERE v.id=m.id;
  INSERT INTO rh_internal.equipment_history_edits(id,entrega_id,antes,depois,created_by)
    VALUES(edit_id,m.id,to_jsonb(original_view),result,auth.uid());
  RETURN result;
END $$;
REVOKE ALL ON FUNCTION rh_internal.edit_equipment_history(uuid,jsonb,jsonb) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION rh_internal.edit_equipment_history(uuid,jsonb,jsonb) TO authenticated;

CREATE FUNCTION public.rh_editar_entrega_historico(p_entrega uuid,p_original jsonb,p_alteracoes jsonb)
RETURNS jsonb LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$
  SELECT rh_internal.edit_equipment_history(p_entrega,p_original,p_alteracoes)
$$;
REVOKE ALL ON FUNCTION public.rh_editar_entrega_historico(uuid,jsonb,jsonb) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.rh_editar_entrega_historico(uuid,jsonb,jsonb) TO authenticated;
NOTIFY pgrst,'reload schema';
