ALTER TABLE public.rh_equipment_movements
  ADD COLUMN IF NOT EXISTS tamanho text NOT NULL DEFAULT '';
ALTER TABLE public.rh_equipment_movements
  ADD CONSTRAINT rh_equipment_movement_size_length CHECK (length(tamanho) <= 30);

CREATE TABLE public.rh_equipment_item_corrections (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  funcionario_id uuid NOT NULL REFERENCES public.funcionarios_epi(id),
  entrega_id uuid NOT NULL REFERENCES public.rh_equipment_movements(id),
  operacao_id uuid NOT NULL REFERENCES public.rh_equipment_receipts(id) DEFERRABLE INITIALLY DEFERRED,
  categoria text NOT NULL CHECK (categoria IN ('epi','fardamento')),
  descricao_anterior text NOT NULL,
  descricao text NOT NULL CHECK (length(trim(descricao)) BETWEEN 1 AND 500),
  equipamento_anterior text NOT NULL,
  equipamento text NOT NULL CHECK (length(trim(equipamento)) BETWEEN 1 AND 200),
  complemento_anterior text NOT NULL,
  complemento text NOT NULL CHECK (length(complemento) <= 300),
  ca_anterior text NOT NULL,
  ca text NOT NULL CHECK (length(ca) <= 80),
  tamanho_anterior text NOT NULL,
  tamanho text NOT NULL CHECK (length(tamanho) <= 30),
  quantidade_anterior integer NOT NULL,
  quantidade integer NOT NULL CHECK (quantidade BETWEEN 1 AND 10000),
  data_entrega_anterior date,
  data_entrega date NOT NULL,
  comprovante_anterior text NOT NULL,
  comprovante text NOT NULL CHECK (comprovante = '' OR comprovante ~ '^https?://'),
  data_verificacao date NOT NULL,
  created_by uuid NOT NULL DEFAULT auth.uid(),
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (operacao_id, entrega_id)
);
CREATE INDEX rh_equipment_item_corrections_latest
  ON public.rh_equipment_item_corrections(funcionario_id,categoria,entrega_id,created_at DESC);
ALTER TABLE public.rh_equipment_item_corrections ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.rh_equipment_item_corrections FROM PUBLIC,anon,authenticated;
GRANT SELECT,INSERT ON public.rh_equipment_item_corrections TO authenticated;
GRANT ALL ON public.rh_equipment_item_corrections TO service_role;
CREATE POLICY equipment_item_correction_read ON public.rh_equipment_item_corrections
  FOR SELECT TO authenticated USING (rh_internal.can_read_employee(funcionario_id));
CREATE POLICY equipment_item_correction_insert ON public.rh_equipment_item_corrections
  FOR INSERT TO authenticated WITH CHECK (rh_internal.can_write() AND rh_internal.can_read_employee(funcionario_id) AND created_by=(SELECT auth.uid()));

CREATE FUNCTION rh_internal.equipment_item_correction_validate() RETURNS trigger
LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $$
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
END $$;
REVOKE ALL ON FUNCTION rh_internal.equipment_item_correction_validate() FROM PUBLIC,anon,authenticated;
CREATE TRIGGER equipment_item_correction_validate BEFORE INSERT ON public.rh_equipment_item_corrections
  FOR EACH ROW EXECUTE FUNCTION rh_internal.equipment_item_correction_validate();

CREATE OR REPLACE FUNCTION rh_internal.equipment_receipt_snapshot() RETURNS trigger
LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $$
BEGIN
  IF tg_op<>'INSERT' THEN RAISE EXCEPTION 'Documento emitido é imutável.'; END IF;
  NEW.created_by:=auth.uid(); NEW.created_at:=now();
  SELECT jsonb_build_object(
    'colaborador',jsonb_build_object('nome',e.nome,'cpf',e.cpf,'funcao',e.funcao,'setor',e.setor,'unidade',e.unidade,'admissao',e.admissao,'local_registro',e.local_registro),
    'empresa',coalesce((SELECT to_jsonb(x) FROM public.empresas x WHERE x.cnpj=CASE WHEN upper(e.local_registro) LIKE '%JEQUI%' THEN '52.522.019/0002-82' WHEN upper(e.local_registro) LIKE '%ILH%' THEN '52.522.019/0001-00' WHEN upper(e.local_registro) LIKE '%NUNES%' OR upper(e.local_registro) LIKE '%VIEIRA%' OR upper(e.local_registro) LIKE '%ITABUNA%' THEN '48.986.353/0001-39' END LIMIT 1),'{}'::jsonb),
    'categoria',NEW.categoria,'emitido_em',NEW.created_at,'operacao_id',NEW.id,
    'movimentos',coalesce((SELECT jsonb_agg(to_jsonb(m) ORDER BY m.data_movimento NULLS FIRST,m.created_at,m.id) FROM public.rh_equipment_movements m WHERE m.funcionario_id=e.id AND m.categoria=NEW.categoria),'[]'::jsonb),
    'verificacoes',coalesce((SELECT jsonb_agg(to_jsonb(v) ORDER BY v.data_verificacao,v.created_at,v.id) FROM public.rh_equipment_checks v WHERE v.funcionario_id=e.id AND v.categoria=NEW.categoria),'[]'::jsonb),
    'correcoes',coalesce((SELECT jsonb_agg(to_jsonb(c) ORDER BY c.created_at,c.id) FROM public.rh_equipment_item_corrections c WHERE c.funcionario_id=e.id AND c.categoria=NEW.categoria AND c.created_at<=NEW.created_at),'[]'::jsonb)
  ) INTO NEW.snapshot FROM public.funcionarios_epi e WHERE e.id=NEW.funcionario_id;
  IF NEW.snapshot IS NULL THEN RAISE EXCEPTION 'Colaborador indisponível.'; END IF;
  RETURN NEW;
END $$;

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
    SELECT string_agg(m.descricao||' ('||CASE WHEN m.ca<>'' THEN 'CA: '||m.ca||', ' ELSE '' END||CASE WHEN m.tamanho<>'' THEN 'Tamanho: '||m.tamanho||', ' ELSE '' END||'Qtd: '||s.saldo||CASE WHEN m.data_movimento IS NOT NULL THEN ' - '||coalesce((SELECT max(v.data_verificacao) FROM public.rh_equipment_checks v WHERE v.entrega_id=m.id),m.data_movimento)::text ELSE '' END||')','; ' ORDER BY m.data_movimento DESC NULLS LAST,m.id),max(coalesce((SELECT max(v.data_verificacao) FROM public.rh_equipment_checks v WHERE v.entrega_id=m.id),m.data_movimento))
    INTO texto,ultima FROM public.rh_equipment_movements m
    CROSS JOIN LATERAL(SELECT m.quantidade-coalesce(sum(r.quantidade),0) saldo FROM public.rh_equipment_movements r WHERE r.entrega_origem_id=m.id AND r.tipo IN ('devolucao','baixa'))s
    WHERE m.funcionario_id=p_funcionario AND m.categoria=p_categoria AND m.tipo='entrega' AND s.saldo>0;
    IF p_categoria='epi' THEN UPDATE public.funcionarios_epi SET epi_itens=coalesce(texto,''),epi_data=coalesce(to_char(ultima,'DD/MM/YYYY'),'') WHERE id=p_funcionario;
    ELSE UPDATE public.funcionarios_epi SET fardamento_itens=coalesce(texto,''),fardamento_data=coalesce(to_char(ultima,'DD/MM/YYYY'),'') WHERE id=p_funcionario; END IF;
  END IF;
  INSERT INTO public.rh_equipment_receipts(id,funcionario_id,categoria,snapshot) VALUES(p_operacao,p_funcionario,p_categoria,'{}') RETURNING * INTO receipt;
  RETURN to_jsonb(receipt);
END $$;
REVOKE ALL ON FUNCTION public.rh_registrar_equipamentos(uuid,text,uuid,jsonb,jsonb) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.rh_registrar_equipamentos(uuid,text,uuid,jsonb,jsonb) TO authenticated;

GRANT UPDATE(equipamento,complemento,descricao,ca,tamanho,quantidade,data_movimento,comprovante) ON public.rh_equipment_movements TO authenticated;
CREATE OR REPLACE FUNCTION rh_internal.equipment_validate()
RETURNS trigger LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $$
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
    IF NOT FOUND OR original.tipo<>'entrega' OR original.funcionario_id<>new.funcionario_id OR original.categoria<>new.categoria THEN RAISE EXCEPTION 'Entrega de origem inválida.'; END IF;
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
END $$;
REVOKE ALL ON FUNCTION rh_internal.equipment_validate() FROM PUBLIC,anon,authenticated;
NOTIFY pgrst,'reload schema';
