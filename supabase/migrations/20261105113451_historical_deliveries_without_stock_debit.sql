-- Registro histórico optativo, sem alteração do saldo atual.
ALTER TABLE public.rh_equipment_movements ADD COLUMN sem_desconto_estoque boolean NOT NULL DEFAULT false;
ALTER TABLE public.rh_equipment_movements ADD CONSTRAINT equipment_historical_stock_mode CHECK(NOT sem_desconto_estoque OR tipo='entrega');
COMMENT ON COLUMN public.rh_equipment_movements.sem_desconto_estoque IS 'Entrega histórica registrada sem movimentar o saldo de estoque atual; opção imutável após o registro.';
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

CREATE OR REPLACE FUNCTION rh_internal.stock_equipment()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE p public.rh_products; b public.rh_equipment_products; e public.funcionarios_epi; sz text;
BEGIN
 IF auth.uid() IS NULL OR NOT rh_internal.can_write() OR NOT rh_internal.can_read_employee(new.funcionario_id) THEN RAISE EXCEPTION 'Sem permissão para entrega.'; END IF;
 -- Uma trava única ordena catálogo, correções e saldos, evitando corrida entre entregas/renomeação.
 PERFORM pg_advisory_xact_lock(73411928);
 IF new.tipo<>'entrega' THEN
  INSERT INTO public.rh_equipment_products(movimento_id,produto_id,filial,tamanho,descontado)
  SELECT new.id,produto_id,filial,tamanho,false FROM public.rh_equipment_products WHERE movimento_id=new.entrega_origem_id ON CONFLICT DO NOTHING;
  RETURN new; -- Devolução avariada/perda não é entrada disponível; o RH confere e registra a entrada.
 END IF;
 SELECT * INTO p FROM public.rh_products WHERE id=(SELECT produto_id FROM public.rh_product_aliases WHERE categoria=coalesce(rh_internal.equipment_category(new.id),new.categoria) AND nome=rh_internal.product_key(new.equipamento));
 IF NOT FOUND THEN RAISE EXCEPTION 'Cadastre o item no Estoque antes de entregar.'; END IF;
 IF TG_OP='INSERT' AND p.categoria<>new.categoria THEN RAISE EXCEPTION 'O item pertence a outro tipo. Atualize a tela e selecione a aba correta.'; END IF;
 SELECT * INTO b FROM public.rh_equipment_products WHERE movimento_id=new.id;
 IF TG_OP='UPDATE' AND ROW(old.equipamento,old.tamanho,old.quantidade) IS NOT DISTINCT FROM ROW(new.equipamento,new.tamanho,new.quantidade) THEN RETURN new; END IF;
 SELECT * INTO e FROM public.funcionarios_epi WHERE id=new.funcionario_id;
 sz:=coalesce(nullif(trim(new.tamanho),''),'ÚNICO');
 IF TG_OP='INSERT' OR b.descontado THEN
  IF NOT p.ativo OR NOT (p.todas_funcoes OR e.funcao=ANY(p.funcoes)) THEN RAISE EXCEPTION 'Item indisponível para a função %.',e.funcao; END IF;
  IF NOT sz=ANY(p.tamanhos) THEN RAISE EXCEPTION 'Selecione um tamanho cadastrado para %.',p.nome; END IF;
  IF NOT new.sem_desconto_estoque THEN
  IF b.descontado THEN PERFORM rh_internal.stock_delta(b.produto_id,b.filial,b.tamanho,old.quantidade,new.operacao_id,'Estorno por correção',new.id); END IF;
  PERFORM rh_internal.stock_delta(p.id,CASE WHEN b.descontado THEN b.filial ELSE e.unidade END,sz,-new.quantidade,new.operacao_id,'Entrega',new.id);
  END IF;
 END IF;
 INSERT INTO public.rh_equipment_products(movimento_id,produto_id,filial,tamanho,descontado)
 VALUES(new.id,p.id,coalesce(b.filial,e.unidade),sz,(TG_OP='INSERT' AND NOT new.sem_desconto_estoque) OR coalesce(b.descontado,false))
 ON CONFLICT(movimento_id) DO UPDATE SET produto_id=excluded.produto_id,tamanho=excluded.tamanho;
 RETURN new;
END $function$;

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
    INSERT INTO public.rh_equipment_movements(funcionario_id,operacao_id,categoria,tipo,equipamento,complemento,descricao,ca,tamanho,quantidade,data_movimento,entrega_origem_id,motivo,comprovante,sem_desconto_estoque)
    VALUES(p_funcionario,p_operacao,p_categoria,'entrega',it->>'equipamento',coalesce(it->>'complemento',''),'',coalesce(it->>'ca',''),coalesce(it->>'tamanho',''),(it->>'quantidade')::integer,(it->>'data')::date,origem,CASE WHEN origem IS NULL THEN '' ELSE 'Substituição de equipamento' END,coalesce(it->>'comprovante',''),coalesce((it->>'sem_desconto_estoque')::boolean,false));
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
END $function$;

CREATE OR REPLACE VIEW public.rh_equipment_current WITH(security_invoker=true) AS
 SELECT m.id,
    m.funcionario_id,
    m.operacao_id,
    COALESCE(p.categoria, m.categoria) AS categoria,
    m.tipo,
    COALESCE(p.nome, m.equipamento) AS equipamento,
    m.complemento,
    COALESCE((p.nome ||
        CASE
            WHEN (m.complemento <> ''::text) THEN (' - '::text || m.complemento)
            ELSE ''::text
        END), m.descricao) AS descricao,
    m.ca,
    m.quantidade,
    m.data_movimento,
    m.entrega_origem_id,
    m.motivo,
    m.observacao,
    m.comprovante,
    m.legado,
    m.legado_chave,
    m.created_by,
    m.created_at,
    m.registrado_por,
    m.tamanho,
    b.produto_id,
    b.filial AS estoque_filial,
    b.descontado AS estoque_descontado,
    m.sem_desconto_estoque
   FROM ((rh_equipment_movements m
     LEFT JOIN rh_equipment_products b ON ((b.movimento_id = m.id)))
     LEFT JOIN rh_products p ON ((p.id = b.produto_id)))
  WHERE (NOT (EXISTS ( SELECT 1
           FROM rh_equipment_exclusions x
          WHERE (x.entrega_id = m.id))));
NOTIFY pgrst,'reload schema';

