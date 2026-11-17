-- Destino por movimento físico. Devoluções antigas seguem na área separada.
CREATE TABLE public.rh_equipment_return_routes (
  movimento_id uuid PRIMARY KEY REFERENCES public.rh_equipment_movements(id),
  destino text NOT NULL CHECK (destino IN ('estoque','desgaste'))
);
ALTER TABLE public.rh_equipment_return_routes ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.rh_equipment_return_routes FROM PUBLIC, anon, authenticated;
GRANT SELECT ON public.rh_equipment_return_routes TO authenticated, service_role;
CREATE POLICY return_routes_read ON public.rh_equipment_return_routes FOR SELECT TO authenticated
USING (EXISTS (SELECT 1 FROM public.rh_equipment_movements m WHERE m.id = movimento_id));

CREATE OR REPLACE VIEW public.rh_returned_items WITH (security_invoker = true) AS
SELECT m.id,m.produto_id,m.funcionario_id,e.nome AS funcionario_nome,m.categoria,m.equipamento,m.descricao,
 m.estoque_filial AS filial,m.tamanho,m.quantidade,m.data_movimento,m.motivo,m.observacao,m.comprovante,m.created_at,m.registrado_por
FROM public.rh_equipment_current m
JOIN public.funcionarios_epi e ON e.id=m.funcionario_id
LEFT JOIN public.rh_equipment_return_routes r ON r.movimento_id=m.id
WHERE m.tipo='devolucao' AND r.destino IS DISTINCT FROM 'estoque';

CREATE FUNCTION rh_internal.pending_return_items(p_id integer) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
DECLARE pend public.devolucoes_pendentes; resultado jsonb;
BEGIN
 IF auth.uid() IS NULL OR rh_internal.can_write() IS DISTINCT FROM true THEN
  RAISE EXCEPTION 'Sem permissão para registrar devoluções.';
 END IF;
 SELECT * INTO pend FROM public.devolucoes_pendentes WHERE id=p_id AND status='pendente';
 IF pend.funcionario_id IS NULL OR rh_internal.can_read_employee(pend.funcionario_id) IS DISTINCT FROM true THEN
  RAISE EXCEPTION 'Pendência indisponível ou sem vínculo com o cadastro do colaborador.';
 END IF;
 SELECT coalesce(jsonb_agg(jsonb_build_object(
   'id',m.id,'categoria',m.categoria,'descricao',m.descricao,'tamanho',sz.tamanho,'ca',m.ca,
   'data_entrega',m.data_movimento,'filial',m.estoque_filial,'saldo',s.saldo,
   'pode_reintegrar',coalesce(p.ativo AND m.estoque_filial IN ('FILIAL 5','FILIAL 8') AND sz.tamanho=ANY(p.tamanhos),false),
   'conflito_tamanho',EXISTS(
     SELECT 1 FROM regexp_split_to_table(CASE m.categoria WHEN 'epi' THEN pend.epi_itens ELSE pend.fardamento_itens END,';') AS linha(txt)
     CROSS JOIN LATERAL regexp_match(linha.txt,'^\s*(.*?)\s*\(.*Tamanho:\s*([^,()]+).*?\s-\s(\d{4}-\d{2}-\d{2}|\d{2}/\d{2}/\d{4})\)\s*$','i') AS partes
     WHERE rh_internal.product_key(partes[1]) IN (rh_internal.product_key(m.descricao),rh_internal.product_key(original.descricao))
       AND partes[3] IN (m.data_movimento::text,to_char(m.data_movimento,'DD/MM/YYYY'))
       AND upper(trim(partes[2]))<>upper(sz.tamanho)
   )
 ) ORDER BY m.categoria,m.data_movimento,m.id),'[]') INTO resultado
 FROM public.rh_equipment_current m
 JOIN public.rh_equipment_movements original ON original.id=m.id
 LEFT JOIN public.rh_equipment_products b ON b.movimento_id=m.id
 LEFT JOIN public.rh_products p ON p.id=b.produto_id
 CROSS JOIN LATERAL (SELECT coalesce(nullif(b.tamanho,''),nullif(m.tamanho,''),'ÚNICO') tamanho) sz
 CROSS JOIN LATERAL (SELECT m.quantidade-coalesce(sum(r.quantidade),0) saldo
   FROM public.rh_equipment_movements r WHERE r.entrega_origem_id=m.id AND r.tipo IN ('devolucao','baixa')) s
 WHERE m.funcionario_id=pend.funcionario_id AND m.tipo='entrega' AND s.saldo>0;
 RETURN resultado;
END $$;

CREATE FUNCTION rh_internal.route_pending_returns(p_id integer,p_operacao uuid,p_itens jsonb) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE pend public.devolucoes_pendentes; execucao rh_internal.stock_operations; payload jsonb;
        linhas jsonb; linha jsonb; it jsonb; destino text; qty integer; devolvido uuid;
        original public.rh_equipment_current; b public.rh_equipment_products; resultado jsonb; restante bigint;
        efetuados jsonb:='[]'; hoje date:=(now() AT TIME ZONE 'America/Sao_Paulo')::date;
BEGIN
 IF auth.uid() IS NULL OR rh_internal.can_write() IS DISTINCT FROM true THEN
  RAISE EXCEPTION 'Sem permissão para registrar devoluções.';
 END IF;
 IF p_operacao IS NULL OR p_id IS NULL OR jsonb_typeof(p_itens) IS DISTINCT FROM 'array' THEN
  RAISE EXCEPTION 'Informe os itens devolvidos.';
 END IF;
 IF jsonb_array_length(p_itens) NOT BETWEEN 1 AND 100 THEN RAISE EXCEPTION 'Informe de 1 a 100 entregas por operação.'; END IF;
 PERFORM pg_advisory_xact_lock(73411928);
 SELECT * INTO execucao FROM rh_internal.stock_operations WHERE id=p_operacao;
 IF FOUND THEN
  IF execucao.payload->>'acao' IS DISTINCT FROM 'devolucao_desligamento'
     OR execucao.payload->>'autor' IS DISTINCT FROM auth.uid()::text
     OR execucao.payload->>'pendencia' IS DISTINCT FROM p_id::text
     OR execucao.payload->'itens' IS DISTINCT FROM p_itens
     OR rh_internal.can_read_employee((execucao.payload->>'funcionario')::uuid) IS DISTINCT FROM true THEN
    RAISE EXCEPTION 'Identificador já usado por outra operação.';
  END IF;
  RETURN execucao.result;
 END IF;
 SELECT * INTO pend FROM public.devolucoes_pendentes WHERE id=p_id AND status='pendente' FOR UPDATE;
 IF pend.funcionario_id IS NULL OR rh_internal.can_read_employee(pend.funcionario_id) IS DISTINCT FROM true THEN
  RAISE EXCEPTION 'Pendência indisponível ou sem vínculo com o cadastro do colaborador.';
 END IF;
 PERFORM 1 FROM public.funcionarios_epi WHERE id=pend.funcionario_id
   AND data_desligamento IS NOT NULL FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'Desligamento não encontrado para esta pendência.'; END IF;
 linhas:=rh_internal.pending_return_items(p_id);
 IF (SELECT count(DISTINCT x->>'id') FROM jsonb_array_elements(p_itens) x)<>jsonb_array_length(p_itens) THEN
  RAISE EXCEPTION 'Selecione cada entrega apenas uma vez.';
 END IF;
 FOR it IN SELECT * FROM jsonb_array_elements(p_itens) LOOP
  IF jsonb_typeof(it)<>'object' OR coalesce(it->>'estoque','') !~ '^\d{1,5}$'
     OR coalesce(it->>'desgaste','') !~ '^\d{1,5}$' THEN RAISE EXCEPTION 'Quantidade inválida.'; END IF;
  SELECT x INTO linha FROM jsonb_array_elements(linhas) x WHERE x->>'id'=it->>'id';
  qty:=(it->>'estoque')::integer+(it->>'desgaste')::integer;
  IF linha IS NULL OR it->>'tamanho' IS DISTINCT FROM linha->>'tamanho'
     OR qty NOT BETWEEN 1 AND (linha->>'saldo')::integer THEN
    RAISE EXCEPTION 'O tamanho ou a quantidade em posse mudou. Reabra a janela para atualizar os itens.';
  END IF;
  IF (linha->>'conflito_tamanho')::boolean THEN
    RAISE EXCEPTION 'Há uma divergência de tamanho entre a ficha e a entrega. Corrija o histórico antes de devolver este item.';
  END IF;
  IF (it->>'estoque')::integer>0 AND NOT (linha->>'pode_reintegrar')::boolean THEN
    RAISE EXCEPTION 'Este item não tem cadastro, tamanho ou filial válidos para voltar ao estoque.';
  END IF;
  SELECT * INTO original FROM public.rh_equipment_current WHERE id=(linha->>'id')::uuid;
  SELECT * INTO b FROM public.rh_equipment_products WHERE movimento_id=original.id;
  FOREACH destino IN ARRAY ARRAY['estoque','desgaste'] LOOP
   qty:=(it->>destino)::integer;
   IF qty=0 THEN CONTINUE; END IF;
   INSERT INTO public.rh_equipment_movements(
     funcionario_id,operacao_id,categoria,tipo,equipamento,descricao,quantidade,data_movimento,entrega_origem_id,motivo,observacao
   ) VALUES (
     pend.funcionario_id,p_operacao,original.categoria,'devolucao','','',qty,hoje,original.id,'Desligamento',
     CASE destino WHEN 'estoque' THEN 'Conferido em boas condições; reintegrado ao estoque.' ELSE 'Com desgaste ou avaria; separado do saldo disponível.' END
   ) RETURNING id INTO devolvido;
   INSERT INTO public.rh_equipment_return_routes VALUES(devolvido,destino);
   IF destino='estoque' THEN
    PERFORM rh_internal.stock_delta(b.produto_id,b.filial,b.tamanho,qty,p_operacao,'Devolução conferida em boas condições',devolvido);
   END IF;
   efetuados:=efetuados||jsonb_build_array(linha||jsonb_build_object('quantidade',qty,'destino',destino));
  END LOOP;
 END LOOP;
 SELECT coalesce(sum((x->>'saldo')::bigint),0) INTO restante FROM jsonb_array_elements(rh_internal.pending_return_items(p_id)) x;
 resultado:=jsonb_build_object('concluida',restante=0,'restante',restante,'itens',efetuados,'data',hoje);
 INSERT INTO public.sistema_logs(tabela_afetada,tipo_operacao,descricao,dados_anteriores,dados_novos)
 VALUES ('devolucoes_pendentes','UPDATE',
   CASE WHEN restante=0 THEN 'Devolução concluída com destinação de itens' ELSE 'Devolução parcial com destinação de itens' END,to_jsonb(pend),resultado);
 IF restante=0 THEN DELETE FROM public.devolucoes_pendentes WHERE id=p_id; END IF;
 payload:=jsonb_build_object('acao','devolucao_desligamento','autor',auth.uid(),'pendencia',p_id,'funcionario',pend.funcionario_id,'itens',p_itens);
 INSERT INTO rh_internal.stock_operations VALUES(p_operacao,payload,resultado);
 RETURN resultado;
END $$;

CREATE FUNCTION public.rh_itens_devolucao_pendente(p_id integer) RETURNS jsonb
LANGUAGE sql STABLE SECURITY INVOKER SET search_path='' AS $$ SELECT rh_internal.pending_return_items(p_id) $$;
CREATE FUNCTION public.rh_destinar_devolucao(p_id integer,p_operacao uuid,p_itens jsonb) RETURNS jsonb
LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$ SELECT rh_internal.route_pending_returns(p_id,p_operacao,p_itens) $$;
REVOKE ALL ON FUNCTION rh_internal.pending_return_items(integer),rh_internal.route_pending_returns(integer,uuid,jsonb),
  public.rh_itens_devolucao_pendente(integer),public.rh_destinar_devolucao(integer,uuid,jsonb) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION rh_internal.pending_return_items(integer),rh_internal.route_pending_returns(integer,uuid,jsonb),
  public.rh_itens_devolucao_pendente(integer),public.rh_destinar_devolucao(integer,uuid,jsonb) TO authenticated;
NOTIFY pgrst,'reload schema';
