-- Avoid collision between PL/pgSQL row variable m and the movement table alias.
CREATE OR REPLACE FUNCTION public.rh_registrar_equipamentos(p_funcionario uuid,p_categoria text,p_operacao uuid,p_itens jsonb DEFAULT '[]',p_devolucao jsonb DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $$
DECLARE e public.funcionarios_epi; receipt public.rh_equipment_receipts; it jsonb; dev jsonb; devolucoes jsonb; origem uuid; texto text; ultima date; m public.rh_equipment_movements; correction public.rh_equipment_item_corrections; parts text[]; item_name text;
BEGIN
  IF auth.uid() IS NULL OR NOT rh_internal.can_write() OR NOT rh_internal.can_read_employee(p_funcionario) THEN RAISE EXCEPTION 'Acesso não autorizado.'; END IF;
  SELECT * INTO e FROM public.funcionarios_epi WHERE id=p_funcionario FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Colaborador indisponível.'; END IF;
  SELECT * INTO receipt FROM public.rh_equipment_receipts WHERE id=p_operacao;
  IF FOUND THEN
    IF receipt.funcionario_id<>p_funcionario OR receipt.categoria<>p_categoria THEN RAISE EXCEPTION 'Operação já utilizada.'; END IF;
    RETURN to_jsonb(receipt);
  END IF;
  IF p_categoria NOT IN ('epi','fardamento') OR p_itens IS NULL OR jsonb_typeof(p_itens)<>'array' OR jsonb_array_length(p_itens)>100 THEN RAISE EXCEPTION 'Lista de equipamentos inválida.'; END IF;
  devolucoes:=CASE WHEN p_devolucao IS NULL OR p_devolucao='null'::jsonb THEN '[]'::jsonb WHEN jsonb_typeof(p_devolucao)='object' THEN jsonb_build_array(p_devolucao) ELSE p_devolucao END;
  IF jsonb_typeof(devolucoes)<>'array' OR jsonb_array_length(devolucoes)>100 THEN RAISE EXCEPTION 'Lista de devoluções inválida.'; END IF;
  FOR dev IN SELECT value FROM jsonb_array_elements(devolucoes) LOOP
    IF jsonb_typeof(dev)<>'object' OR coalesce(dev->>'tipo','devolucao') NOT IN ('devolucao','baixa') THEN RAISE EXCEPTION 'Tipo de devolução inválido.'; END IF;
    origem:=(dev->>'origem')::uuid;
    INSERT INTO public.rh_equipment_movements(funcionario_id,operacao_id,categoria,tipo,equipamento,descricao,quantidade,data_movimento,entrega_origem_id,motivo,observacao,comprovante)
    VALUES(p_funcionario,p_operacao,p_categoria,coalesce(dev->>'tipo','devolucao'),'','',(dev->>'quantidade')::integer,(dev->>'data')::date,origem,dev->>'motivo',coalesce(dev->>'observacao',''),coalesce(dev->>'comprovante',''));
  END LOOP;
  FOR it IN SELECT value FROM jsonb_array_elements(p_itens) LOOP
    IF it->>'acao'='verificacao' THEN
      INSERT INTO public.rh_equipment_checks(funcionario_id,entrega_id,operacao_id,categoria,descricao,quantidade,data_verificacao,observacao)
      VALUES(p_funcionario,(it->>'origem')::uuid,p_operacao,p_categoria,'',1,(it->>'data')::date,coalesce(it->>'observacao',''));
      CONTINUE;
    ELSIF it->>'acao'='corrigir' THEN
      SELECT * INTO m FROM public.rh_equipment_movements WHERE id=(it->>'origem')::uuid AND funcionario_id=p_funcionario AND categoria=p_categoria FOR UPDATE;
      IF NOT FOUND OR m.tipo<>'entrega' THEN RAISE EXCEPTION 'Entrega selecionada inválida.'; END IF;
      item_name:=trim(regexp_replace(coalesce(it->>'nome',''),'\s+',' ','g'));
      parts:=regexp_match(item_name,'^(.*?)(?:\s+-\s+(.*))?$');
      PERFORM set_config('rh.equipment_item_correction',m.id::text,true);
      PERFORM set_config('rh.equipment_item_correction_operation',p_operacao::text,true);
      INSERT INTO public.rh_equipment_item_corrections(
        funcionario_id,entrega_id,operacao_id,categoria,descricao_anterior,descricao,
        equipamento_anterior,equipamento,complemento_anterior,complemento,ca_anterior,ca,
        tamanho_anterior,tamanho,quantidade_anterior,quantidade,data_entrega_anterior,data_entrega,
        comprovante_anterior,comprovante,data_verificacao
      ) VALUES(
        p_funcionario,m.id,p_operacao,p_categoria,m.descricao,'',m.equipamento,coalesce(parts[1],''),m.complemento,coalesce(parts[2],''),m.ca,coalesce(it->>'ca',''),
        m.tamanho,coalesce(it->>'tamanho',''),m.quantidade,(it->>'quantidade')::integer,m.data_movimento,(it->>'data')::date,
        m.comprovante,coalesce(it->>'comprovante',''),(it->>'verificacao')::date
      ) RETURNING * INTO correction;
      IF m.data_movimento IS DISTINCT FROM correction.data_entrega THEN
        PERFORM set_config('rh.equipment_date_correction',m.id::text,true);
        PERFORM set_config('rh.equipment_correction_reason','Correção completa dos dados do item durante verificação.',true);
      END IF;
      UPDATE public.rh_equipment_movements SET equipamento=correction.equipamento,complemento=correction.complemento,
        descricao=correction.descricao,ca=correction.ca,tamanho=correction.tamanho,quantidade=correction.quantidade,
        data_movimento=correction.data_entrega,comprovante=correction.comprovante WHERE id=m.id;
      PERFORM set_config('rh.equipment_item_correction','',true);
      PERFORM set_config('rh.equipment_item_correction_operation','',true);
      PERFORM set_config('rh.equipment_date_correction','',true);
      PERFORM set_config('rh.equipment_correction_reason','',true);
      CONTINUE;
    ELSIF it ? 'acao' AND it->>'acao'<>'entrega' THEN RAISE EXCEPTION 'Ação inválida.';
    END IF;
    origem:=coalesce(nullif(it->>'origem','')::uuid,CASE WHEN jsonb_typeof(p_devolucao)='object' THEN (p_devolucao->>'origem')::uuid ELSE NULL END);
    IF origem IS NOT NULL AND NOT EXISTS(SELECT 1 FROM jsonb_array_elements(devolucoes) d WHERE (d->>'origem')::uuid=origem AND (it->>'data')::date>=(d->>'data')::date) THEN RAISE EXCEPTION 'Substituto sem devolução/baixa correspondente ou com data anterior.'; END IF;
    INSERT INTO public.rh_equipment_movements(funcionario_id,operacao_id,categoria,tipo,equipamento,complemento,descricao,ca,tamanho,quantidade,data_movimento,entrega_origem_id,motivo,comprovante)
    VALUES(p_funcionario,p_operacao,p_categoria,'entrega',it->>'equipamento',coalesce(it->>'complemento',''),'',coalesce(it->>'ca',''),coalesce(it->>'tamanho',''),(it->>'quantidade')::integer,(it->>'data')::date,origem,CASE WHEN origem IS NULL THEN '' ELSE 'Substituição de equipamento' END,coalesce(it->>'comprovante',''));
  END LOOP;
  IF jsonb_array_length(p_itens)>0 OR jsonb_array_length(devolucoes)>0 THEN
    SELECT string_agg(movement.descricao||' ('||CASE WHEN movement.ca<>'' THEN 'CA: '||movement.ca||', ' ELSE '' END||CASE WHEN movement.tamanho<>'' THEN 'Tamanho: '||movement.tamanho||', ' ELSE '' END||'Qtd: '||s.saldo||CASE WHEN movement.data_movimento IS NOT NULL THEN ' - '||coalesce((SELECT max(v.data_verificacao) FROM public.rh_equipment_checks v WHERE v.entrega_id=movement.id),movement.data_movimento)::text ELSE '' END||')','; ' ORDER BY movement.data_movimento DESC NULLS LAST,movement.id),max(coalesce((SELECT max(v.data_verificacao) FROM public.rh_equipment_checks v WHERE v.entrega_id=movement.id),movement.data_movimento))
    INTO texto,ultima FROM public.rh_equipment_movements movement
    CROSS JOIN LATERAL(SELECT movement.quantidade-coalesce(sum(r.quantidade),0) saldo FROM public.rh_equipment_movements r WHERE r.entrega_origem_id=movement.id AND r.tipo IN ('devolucao','baixa'))s
    WHERE movement.funcionario_id=p_funcionario AND movement.categoria=p_categoria AND movement.tipo='entrega' AND s.saldo>0;
    IF p_categoria='epi' THEN UPDATE public.funcionarios_epi SET epi_itens=coalesce(texto,''),epi_data=coalesce(to_char(ultima,'DD/MM/YYYY'),'') WHERE id=p_funcionario;
    ELSE UPDATE public.funcionarios_epi SET fardamento_itens=coalesce(texto,''),fardamento_data=coalesce(to_char(ultima,'DD/MM/YYYY'),'') WHERE id=p_funcionario; END IF;
  END IF;
  INSERT INTO public.rh_equipment_receipts(id,funcionario_id,categoria,snapshot) VALUES(p_operacao,p_funcionario,p_categoria,'{}') RETURNING * INTO receipt;
  RETURN to_jsonb(receipt);
END $$;
