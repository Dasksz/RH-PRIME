-- Complemento: unificação explícita de cadastros antigos e integração das entregas.
CREATE FUNCTION rh_internal.product_merge(source_id uuid,target_id uuid) RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE source public.rh_products; target public.rh_products; s public.rh_stock; emp uuid; op uuid:=gen_random_uuid();
BEGIN
 IF auth.uid() IS NULL OR NOT rh_internal.is_admin() THEN RAISE EXCEPTION 'Somente administradores podem unificar cadastros.'; END IF;
 PERFORM pg_advisory_xact_lock(73411928);
 SELECT * INTO source FROM public.rh_products WHERE id=source_id;
 SELECT * INTO target FROM public.rh_products WHERE id=target_id;
 IF source_id=target_id OR source.id IS NULL OR target.id IS NULL OR source.categoria<>target.categoria OR NOT target.ativo THEN RAISE EXCEPTION 'Selecione dois cadastros distintos da mesma categoria, com destino ativo.'; END IF;
 IF NOT EXISTS(SELECT 1 FROM public.rh_product_aliases WHERE produto_id=source_id) THEN RETURN; END IF;
 UPDATE public.rh_products SET tamanhos=ARRAY(SELECT DISTINCT unnest(source.tamanhos||target.tamanhos)),versao=versao+1,updated_at=now() WHERE id=target_id;
 FOR s IN SELECT * FROM public.rh_stock WHERE produto_id=source_id AND quantidade>0 ORDER BY filial,tamanho LOOP
  PERFORM rh_internal.stock_delta(source_id,s.filial,s.tamanho,-s.quantidade,op,'Unificação em '||target.nome);
  PERFORM rh_internal.stock_delta(target_id,s.filial,s.tamanho,s.quantidade,op,'Unificação de '||source.nome);
 END LOOP;
 UPDATE public.rh_equipment_products SET produto_id=target_id WHERE produto_id=source_id;
 UPDATE public.rh_product_aliases SET produto_id=target_id WHERE produto_id=source_id;
 UPDATE public.rh_products SET ativo=false,versao=versao+1,updated_at=now() WHERE id=source_id;
 INSERT INTO public.rh_product_events(produto_id,antes,depois,created_by) VALUES(source_id,to_jsonb(source),jsonb_build_object('unificado_em',target_id,'nome',target.nome),auth.uid());
 FOR emp IN SELECT DISTINCT m.funcionario_id FROM public.rh_equipment_products b JOIN public.rh_equipment_movements m ON m.id=b.movimento_id WHERE b.produto_id=target_id ORDER BY m.funcionario_id LOOP
  PERFORM rh_internal.stock_refresh_employee(emp);
 END LOOP;
END $$;
REVOKE ALL ON FUNCTION rh_internal.product_merge(uuid,uuid) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION rh_internal.product_merge(uuid,uuid) TO authenticated;
CREATE FUNCTION public.rh_merge_products(source_id uuid,target_id uuid) RETURNS void LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$ SELECT rh_internal.product_merge(source_id,target_id) $$;
REVOKE ALL ON FUNCTION public.rh_merge_products(uuid,uuid) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.rh_merge_products(uuid,uuid) TO authenticated;
REVOKE ALL ON rh_internal.stock_operations FROM PUBLIC,anon,authenticated;

-- A trava precede a trava do colaborador. O resumo sempre usa o nome atual do catálogo.
DO $$ DECLARE definition text; BEGIN
 SELECT pg_get_functiondef('public.rh_registrar_equipamentos(uuid,text,uuid,jsonb,jsonb)'::regprocedure) INTO definition;
 definition:=replace(definition,E'BEGIN\n',E'BEGIN\n  PERFORM pg_advisory_xact_lock(73411928);\n');
 definition:=replace(definition,'INTO texto,ultima FROM public.rh_equipment_movements movement','INTO texto,ultima FROM public.rh_equipment_current movement');
 EXECUTE definition;
END $$;
NOTIFY pgrst,'reload schema';

