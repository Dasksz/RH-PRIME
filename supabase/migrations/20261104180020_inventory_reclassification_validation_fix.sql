CREATE OR REPLACE FUNCTION rh_internal.equipment_check_validate()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
declare original public.rh_equipment_movements; used integer;
begin
 if tg_op<>'INSERT' then raise exception 'Histórico de verificações é imutável.'; end if;
 if auth.uid() is null or not rh_internal.can_write() or not rh_internal.can_read_employee(new.funcionario_id) then raise exception 'Sem permissão para verificar equipamentos.'; end if;
 perform 1 from public.funcionarios_epi where id=new.funcionario_id for update;
 select * into original from public.rh_equipment_movements where id=new.entrega_id;
 if not found or original.tipo<>'entrega' or original.funcionario_id<>new.funcionario_id or rh_internal.equipment_category(original.id) IS DISTINCT FROM NEW.categoria then raise exception 'Entrega de origem inválida.'; end if;
 if new.data_verificacao>(now() at time zone 'America/Sao_Paulo')::date or new.data_verificacao<original.data_movimento then raise exception 'Data de verificação inválida.'; end if;
 select coalesce(sum(quantidade),0) into used from public.rh_equipment_movements where entrega_origem_id=original.id and tipo in ('devolucao','baixa');
 if used>=original.quantidade then raise exception 'Equipamento não está mais em posse do colaborador.'; end if;
 new.quantidade=original.quantidade-used;new.descricao=original.descricao;
 new.created_by=auth.uid();new.created_at=now();return new;
end $function$
;
CREATE OR REPLACE FUNCTION rh_internal.equipment_item_correction_validate()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
DECLARE original public.rh_equipment_movements; used integer; parts text[];
BEGIN
  IF auth.uid() IS NULL OR NOT rh_internal.can_write() OR NOT rh_internal.can_read_employee(NEW.funcionario_id) THEN
    RAISE EXCEPTION 'Sem permissão para corrigir o item.';
  END IF;
  SELECT * INTO original FROM public.rh_equipment_movements WHERE id=NEW.entrega_id FOR UPDATE;
  IF NOT FOUND OR original.tipo<>'entrega' OR original.funcionario_id<>NEW.funcionario_id OR rh_internal.equipment_category(original.id) IS DISTINCT FROM NEW.categoria THEN
    RAISE EXCEPTION 'Entrega selecionada inválida.';
  END IF;
  IF NEW.data_verificacao IS NULL OR NEW.data_verificacao>(now() AT TIME ZONE 'America/Sao_Paulo')::date THEN
    RAISE EXCEPTION 'Informe uma data de verificação válida.';
  END IF;
  SELECT coalesce(sum(quantidade),0) INTO used FROM public.rh_equipment_movements WHERE entrega_origem_id=original.id AND tipo IN ('devolucao','baixa');
  IF used>NEW.quantidade THEN RAISE EXCEPTION 'A quantidade corrigida é menor que o que já foi devolvido ou baixado.'; END IF;
  IF length(trim(coalesce(NEW.equipamento,''))) NOT BETWEEN 1 AND 200 OR length(coalesce(NEW.complemento,''))>300 OR length(coalesce(NEW.ca,''))>80 OR length(coalesce(NEW.tamanho,''))>30 THEN
    RAISE EXCEPTION 'Confira o nome, complemento, C.A. e tamanho do item.';
  END IF;
  IF NEW.data_entrega IS NULL OR NEW.data_entrega>(now() AT TIME ZONE 'America/Sao_Paulo')::date THEN
    RAISE EXCEPTION 'A data da entrega precisa ser válida e não pode ser futura.';
  END IF;
  IF NEW.data_verificacao<NEW.data_entrega THEN RAISE EXCEPTION 'A verificação não pode ser anterior à data corrigida da entrega.'; END IF;
  IF EXISTS(SELECT 1 FROM public.rh_equipment_movements r WHERE r.entrega_origem_id=original.id AND r.data_movimento<NEW.data_entrega)
     OR EXISTS(SELECT 1 FROM public.rh_equipment_checks v WHERE v.entrega_id=original.id AND v.data_verificacao<NEW.data_entrega) THEN
    RAISE EXCEPTION 'A entrega não pode ficar depois de uma devolução ou verificação já registrada.';
  END IF;
  IF original.entrega_origem_id IS NOT NULL AND EXISTS(
    SELECT 1 FROM public.rh_equipment_movements r WHERE r.entrega_origem_id=original.entrega_origem_id
      AND r.operacao_id=original.operacao_id AND r.tipo IN ('devolucao','baixa') AND r.data_movimento>NEW.data_entrega
  ) THEN RAISE EXCEPTION 'O substituto não pode ser entregue antes da devolução de origem.'; END IF;
  NEW.equipamento:=trim(regexp_replace(NEW.equipamento,'\s+',' ','g'));
  NEW.complemento:=trim(regexp_replace(NEW.complemento,'\s+',' ','g'));
  NEW.ca:=trim(NEW.ca);
  NEW.tamanho:=trim(NEW.tamanho);
  NEW.comprovante:=trim(NEW.comprovante);
  NEW.descricao:=NEW.equipamento||CASE WHEN NEW.complemento<>'' THEN ' - '||NEW.complemento ELSE '' END;
  IF length(NEW.descricao)>500 THEN RAISE EXCEPTION 'O nome completo do item deve ter até 500 caracteres.'; END IF;
  IF current_setting('rh.equipment_item_correction',true) IS DISTINCT FROM NEW.entrega_id::text
    OR current_setting('rh.equipment_item_correction_operation',true) IS DISTINCT FROM NEW.operacao_id::text THEN
    RAISE EXCEPTION 'Correções de itens só podem ser registradas dentro de uma verificação.';
  END IF;
  NEW.descricao_anterior:=original.descricao;
  NEW.equipamento_anterior:=original.equipamento;
  NEW.complemento_anterior:=original.complemento;
  NEW.ca_anterior:=original.ca;
  NEW.tamanho_anterior:=original.tamanho;
  NEW.quantidade_anterior:=original.quantidade;
  NEW.data_entrega_anterior:=original.data_movimento;
  NEW.comprovante_anterior:=original.comprovante;
  NEW.created_by:=auth.uid(); NEW.created_at:=now();
  RETURN NEW;
END $function$
;
CREATE OR REPLACE FUNCTION public.rh_registrar_equipamentos(p_funcionario uuid, p_categoria text, p_operacao uuid, p_itens jsonb DEFAULT '[]'::jsonb, p_devolucao jsonb DEFAULT NULL::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
DECLARE e public.funcionarios_epi; receipt public.rh_equipment_receipts; it jsonb; dev jsonb; devolucoes jsonb; origem uuid; texto text; ultima date; m public.rh_equipment_movements; correction public.rh_equipment_item_corrections; parts text[]; item_name text;
BEGIN
  PERFORM pg_advisory_xact_lock(73411928);
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
      SELECT * INTO m FROM public.rh_equipment_movements WHERE id=(it->>'origem')::uuid AND funcionario_id=p_funcionario AND rh_internal.equipment_category(id)=p_categoria FOR UPDATE;
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
    INTO texto,ultima FROM public.rh_equipment_current movement
    CROSS JOIN LATERAL(SELECT movement.quantidade-coalesce(sum(r.quantidade),0) saldo FROM public.rh_equipment_movements r WHERE r.entrega_origem_id=movement.id AND r.tipo IN ('devolucao','baixa'))s
    WHERE movement.funcionario_id=p_funcionario AND movement.categoria=p_categoria AND movement.tipo='entrega' AND s.saldo>0;
    IF p_categoria='epi' THEN UPDATE public.funcionarios_epi SET epi_itens=coalesce(texto,''),epi_data=coalesce(to_char(ultima,'DD/MM/YYYY'),'') WHERE id=p_funcionario;
    ELSE UPDATE public.funcionarios_epi SET fardamento_itens=coalesce(texto,''),fardamento_data=coalesce(to_char(ultima,'DD/MM/YYYY'),'') WHERE id=p_funcionario; END IF;
  END IF;
  INSERT INTO public.rh_equipment_receipts(id,funcionario_id,categoria,snapshot) VALUES(p_operacao,p_funcionario,p_categoria,'{}') RETURNING * INTO receipt;
  RETURN to_jsonb(receipt);
END $function$
;
