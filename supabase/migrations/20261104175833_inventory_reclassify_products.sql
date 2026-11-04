-- Classificação vigente do catálogo, preservando os lançamentos e PDFs emitidos.
CREATE OR REPLACE VIEW public.rh_equipment_current WITH(security_invoker=true) AS
 SELECT m.id,
    m.funcionario_id,
    m.operacao_id,
    COALESCE(p.categoria,m.categoria) AS categoria,
    m.tipo,
    COALESCE(p.nome, m.equipamento) AS equipamento,
    m.complemento,
    COALESCE(p.nome ||
        CASE
            WHEN m.complemento <> ''::text THEN ' - '::text || m.complemento
            ELSE ''::text
        END, m.descricao) AS descricao,
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
    b.descontado AS estoque_descontado
   FROM rh_equipment_movements m
     LEFT JOIN rh_equipment_products b ON b.movimento_id = m.id
     LEFT JOIN rh_products p ON p.id = b.produto_id
  WHERE NOT (EXISTS ( SELECT 1
           FROM rh_equipment_exclusions x
          WHERE x.entrega_id = m.id));
CREATE OR REPLACE FUNCTION rh_internal.equipment_category(movement_id uuid) RETURNS text
LANGUAGE sql STABLE SECURITY INVOKER SET search_path='' AS $$ SELECT categoria FROM public.rh_equipment_current WHERE id=movement_id $$;
REVOKE ALL ON FUNCTION rh_internal.equipment_category(uuid) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION rh_internal.equipment_category(uuid) TO authenticated,service_role;

-- Conferências e correções acompanham a classificação da entrega à qual pertencem.
DO $$
DECLARE tbl text; columns text;
BEGIN
 FOREACH tbl IN ARRAY ARRAY['rh_equipment_checks','rh_equipment_item_corrections'] LOOP
  SELECT string_agg(CASE WHEN a.attname='categoria' THEN 'm.categoria AS categoria' ELSE 'v.'||quote_ident(a.attname) END,',' ORDER BY a.attnum)
  INTO columns FROM pg_attribute a WHERE a.attrelid=('public.'||tbl)::regclass AND a.attnum>0 AND NOT a.attisdropped;
  EXECUTE format('CREATE OR REPLACE VIEW public.%I WITH(security_invoker=true) AS SELECT %s FROM public.%I v JOIN public.rh_equipment_current m ON m.id=v.entrega_id',tbl||'_current',columns,tbl);
  EXECUTE format('REVOKE ALL ON public.%I FROM PUBLIC,anon',tbl||'_current');
  EXECUTE format('GRANT SELECT ON public.%I TO authenticated,service_role',tbl||'_current');
 END LOOP;
END $$;

CREATE OR REPLACE FUNCTION rh_internal.equipment_receipt_snapshot()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
BEGIN
  IF tg_op<>'INSERT' THEN RAISE EXCEPTION 'Documento emitido é imutável.'; END IF;
  NEW.created_by:=auth.uid();
  NEW.created_at:=now();
  SELECT jsonb_build_object(
    'colaborador',jsonb_build_object('nome',e.nome,'cpf',e.cpf,'funcao',e.funcao,'setor',e.setor,'unidade',e.unidade,'admissao',e.admissao,'local_registro',e.local_registro),
    'empresa',coalesce(
      (SELECT to_jsonb(x) FROM public.empresas x WHERE x.id=e.empresa_id),
      (SELECT to_jsonb(x) FROM public.empresas x WHERE x.cnpj=CASE WHEN upper(e.local_registro) LIKE '%JEQUI%' THEN '52.522.019/0002-82' WHEN upper(e.local_registro) LIKE '%ILH%' THEN '52.522.019/0001-00' WHEN upper(e.local_registro) LIKE '%NUNES%' OR upper(e.local_registro) LIKE '%VIEIRA%' OR upper(e.local_registro) LIKE '%ITABUNA%' THEN '48.986.353/0001-39' END LIMIT 1),
      '{}'::jsonb),
    'categoria',NEW.categoria,'emitido_em',NEW.created_at,'operacao_id',NEW.id,
    'movimentos',coalesce((SELECT jsonb_agg(to_jsonb(m) ORDER BY m.data_movimento NULLS FIRST,m.created_at,m.id) FROM public.rh_equipment_current m WHERE m.funcionario_id=e.id AND m.categoria=NEW.categoria),'[]'::jsonb),
    'verificacoes',coalesce((SELECT jsonb_agg(to_jsonb(v) ORDER BY v.data_verificacao,v.created_at,v.id) FROM public.rh_equipment_checks_current v WHERE v.funcionario_id=e.id AND v.categoria=NEW.categoria),'[]'::jsonb),
    'correcoes',coalesce((SELECT jsonb_agg(to_jsonb(c) ORDER BY c.created_at,c.id) FROM public.rh_equipment_item_corrections_current c WHERE c.funcionario_id=e.id AND c.categoria=NEW.categoria AND c.created_at<=NEW.created_at),'[]'::jsonb)
  ) INTO NEW.snapshot FROM public.funcionarios_epi e WHERE e.id=NEW.funcionario_id;
  IF NEW.snapshot IS NULL THEN RAISE EXCEPTION 'Colaborador indisponível.'; END IF;
  RETURN NEW;
END $function$
;

CREATE OR REPLACE FUNCTION rh_internal.equipment_validate()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
DECLARE e public.funcionarios_epi; original public.rh_equipment_movements; used integer; correction public.rh_equipment_item_corrections;
BEGIN
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
END $function$
;

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
  IF b.descontado THEN PERFORM rh_internal.stock_delta(b.produto_id,b.filial,b.tamanho,old.quantidade,new.operacao_id,'Estorno por correção',new.id); END IF;
  PERFORM rh_internal.stock_delta(p.id,CASE WHEN b.descontado THEN b.filial ELSE e.unidade END,sz,-new.quantidade,new.operacao_id,'Entrega',new.id);
 END IF;
 INSERT INTO public.rh_equipment_products(movimento_id,produto_id,filial,tamanho,descontado)
 VALUES(new.id,p.id,coalesce(b.filial,e.unidade),sz,TG_OP='INSERT' OR coalesce(b.descontado,false))
 ON CONFLICT(movimento_id) DO UPDATE SET produto_id=excluded.produto_id,tamanho=excluded.tamanho;
 RETURN new;
END $function$
;

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
 if not found or original.tipo<>'entrega' or original.funcionario_id<>new.funcionario_id or original.categoria<>new.categoria then raise exception 'Entrega de origem inválida.'; end if;
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
  IF NOT FOUND OR original.tipo<>'entrega' OR original.funcionario_id<>NEW.funcionario_id OR original.categoria<>NEW.categoria THEN
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

-- A devolução permanece separada do estoque disponível; motivo e observações são os já registrados.
CREATE OR REPLACE VIEW public.rh_returned_items WITH(security_invoker=true) AS
SELECT m.id,m.produto_id,m.funcionario_id,e.nome AS funcionario_nome,m.categoria,m.equipamento,m.descricao,
 m.estoque_filial AS filial,m.tamanho,m.quantidade,m.data_movimento,m.motivo,m.observacao,m.comprovante,m.created_at,m.registrado_por
FROM public.rh_equipment_current m JOIN public.funcionarios_epi e ON e.id=m.funcionario_id
WHERE m.tipo='devolucao';
REVOKE ALL ON public.rh_returned_items FROM PUBLIC,anon;
GRANT SELECT ON public.rh_returned_items TO authenticated,service_role;

CREATE OR REPLACE FUNCTION rh_internal.product_reclassify(payload jsonb) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE source public.rh_products; target public.rh_products; s public.rh_stock;
 previous rh_internal.stock_operations; op uuid; destination text; target_id uuid; final_id uuid;
 request jsonb; result jsonb; emp uuid; affected integer; deliveries integer;
BEGIN
 IF auth.uid() IS NULL OR NOT rh_internal.is_admin() THEN RAISE EXCEPTION 'Somente administradores podem mudar o tipo dos itens.'; END IF;
 PERFORM pg_advisory_xact_lock(73411928);
 op:=(payload->>'operacao_id')::uuid;
 IF op IS NULL THEN RAISE EXCEPTION 'Identificador da alteração obrigatório.'; END IF;
 request:=payload||jsonb_build_object('tipo','reclassificacao','responsavel',auth.uid());
 SELECT * INTO previous FROM rh_internal.stock_operations WHERE id=op;
 IF FOUND THEN
  IF previous.payload IS DISTINCT FROM request THEN RAISE EXCEPTION 'Operação já utilizada para outra alteração.'; END IF;
  RETURN previous.result;
 END IF;
 SELECT * INTO source FROM public.rh_products WHERE id=(payload->>'id')::uuid FOR UPDATE;
 IF NOT FOUND OR source.versao IS DISTINCT FROM (payload->>'versao')::integer THEN RAISE EXCEPTION 'O cadastro mudou. Atualize e confira novamente.'; END IF;
 IF NOT EXISTS(SELECT 1 FROM public.rh_product_aliases WHERE produto_id=source.id) THEN RAISE EXCEPTION 'Este cadastro já foi unificado. Use o cadastro de destino.'; END IF;
 destination:=payload->>'categoria';
 IF destination IS NULL OR destination NOT IN ('epi','fardamento') OR destination=source.categoria THEN RAISE EXCEPTION 'Selecione um tipo de destino diferente do atual.'; END IF;
 target_id:=nullif(payload->>'substituto_id','')::uuid;
 SELECT count(DISTINCT m.funcionario_id),count(*) FILTER(WHERE m.tipo='entrega') INTO affected,deliveries
 FROM public.rh_equipment_products b JOIN public.rh_equipment_movements m ON m.id=b.movimento_id WHERE b.produto_id=source.id;
 IF target_id IS NULL THEN
  IF EXISTS(SELECT 1 FROM public.rh_product_aliases WHERE categoria=destination AND nome=rh_internal.product_key(source.nome) AND produto_id<>source.id) THEN
   RAISE EXCEPTION 'Já existe um item com este nome no tipo de destino. Escolha esse cadastro como substituto ou renomeie o item antes.';
  END IF;
  UPDATE public.rh_products SET categoria=destination,grupo=CASE WHEN destination='fardamento' THEN 'fardamento' ELSE 'equipamento' END,versao=versao+1,updated_at=now() WHERE id=source.id;
  INSERT INTO public.rh_product_aliases(categoria,nome,produto_id) VALUES(destination,rh_internal.product_key(source.nome),source.id) ON CONFLICT DO NOTHING;
  final_id:=source.id;
 ELSE
  SELECT * INTO target FROM public.rh_products WHERE id=target_id FOR UPDATE;
  IF NOT FOUND OR target.id=source.id OR NOT target.ativo OR target.categoria<>destination OR target.versao IS DISTINCT FROM (payload->>'versao_substituto')::integer THEN
   RAISE EXCEPTION 'Selecione um substituto ativo do tipo de destino e confira se o cadastro está atualizado.';
  END IF;
  UPDATE public.rh_products SET tamanhos=ARRAY(SELECT DISTINCT unnest(source.tamanhos||target.tamanhos) ORDER BY 1),versao=versao+1,updated_at=now() WHERE id=target.id;
  FOR s IN SELECT * FROM public.rh_stock WHERE produto_id=source.id AND quantidade>0 ORDER BY filial,tamanho LOOP
   PERFORM rh_internal.stock_delta(source.id,s.filial,s.tamanho,-s.quantidade,op,'Mudança de tipo e unificação em '||target.nome);
   PERFORM rh_internal.stock_delta(target.id,s.filial,s.tamanho,s.quantidade,op,'Mudança de tipo e unificação de '||source.nome);
  END LOOP;
  UPDATE public.rh_equipment_products SET produto_id=target.id WHERE produto_id=source.id;
  UPDATE public.rh_product_aliases SET produto_id=target.id WHERE produto_id=source.id;
  UPDATE public.rh_products SET ativo=false,versao=versao+1,updated_at=now() WHERE id=source.id;
  final_id:=target.id;
 END IF;
 INSERT INTO public.rh_product_events(produto_id,antes,depois,created_by)
 VALUES(source.id,to_jsonb(source),jsonb_build_object('acao','reclassificacao','operacao_id',op,'categoria',destination,'cadastro_destino',final_id,'substituido',target_id IS NOT NULL,'colaboradores',affected,'entregas',deliveries),auth.uid());
 FOR emp IN SELECT DISTINCT m.funcionario_id FROM public.rh_equipment_products b JOIN public.rh_equipment_movements m ON m.id=b.movimento_id WHERE b.produto_id=final_id ORDER BY m.funcionario_id LOOP
  PERFORM rh_internal.stock_refresh_employee(emp);
 END LOOP;
 result:=jsonb_build_object('operacao_id',op,'id',final_id,'categoria',destination,'substituido',target_id IS NOT NULL,'colaboradores',affected,'entregas',deliveries);
 INSERT INTO rh_internal.stock_operations(id,payload,result) VALUES(op,request,result);
 RETURN result;
END $$;
REVOKE ALL ON FUNCTION rh_internal.product_reclassify(jsonb) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION rh_internal.product_reclassify(jsonb) TO authenticated;
CREATE OR REPLACE FUNCTION public.rh_reclassify_product(payload jsonb) RETURNS jsonb
LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$ SELECT rh_internal.product_reclassify(payload) $$;
REVOKE ALL ON FUNCTION public.rh_reclassify_product(jsonb) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.rh_reclassify_product(jsonb) TO authenticated;
NOTIFY pgrst,'reload schema';
