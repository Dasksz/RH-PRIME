CREATE FUNCTION rh_internal.asset_rename_variant(p_id uuid, p_previous text, p_name text)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE
  item public.rh_asset_variants%ROWTYPE;
  type_id uuid;
  detail text;
  name text := upper(regexp_replace(btrim(coalesce(p_name,'')), '[[:space:]]+', ' ', 'g'));
BEGIN
  IF auth.uid() IS NULL OR NOT rh_internal.can_manage_stock() THEN
    RAISE EXCEPTION 'Sem permissão para editar modelos de equipamento.';
  END IF;
  SELECT tipo_id INTO type_id FROM public.rh_asset_variants WHERE id=p_id;
  SELECT detalhe INTO detail FROM public.rh_asset_types WHERE id=type_id FOR UPDATE;
  SELECT * INTO item FROM public.rh_asset_variants WHERE id=p_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Modelo ou versão não encontrado. Atualize a lista.'; END IF;
  IF length(name) NOT BETWEEN 1 AND 120 OR (detail='ano' AND name !~ '^[1-9][0-9]{3}$') THEN
    RAISE EXCEPTION 'Informe um modelo, ano ou descrição válido.';
  END IF;
  IF name=item.variante THEN RETURN item.id; END IF;
  IF item.variante IS DISTINCT FROM p_previous THEN
    RAISE EXCEPTION 'O nome foi alterado. Atualize a lista e tente novamente.';
  END IF;
  IF EXISTS (SELECT 1 FROM public.rh_asset_variants WHERE tipo_id=type_id AND variante=name) THEN
    RAISE EXCEPTION 'Já existe outro modelo ou versão com esse nome neste tipo.';
  END IF;
  UPDATE public.rh_asset_variants SET variante=name WHERE id=item.id;
  UPDATE public.rh_asset_stock SET variante=name WHERE tipo_id=type_id AND variante=item.variante;
  RETURN item.id;
END $$;
CREATE FUNCTION public.rh_asset_rename_variant(p_id uuid, p_previous text, p_name text)
RETURNS uuid LANGUAGE sql SECURITY INVOKER SET search_path = '' AS $$
  SELECT rh_internal.asset_rename_variant(p_id,p_previous,p_name)
$$;
REVOKE ALL ON FUNCTION rh_internal.asset_rename_variant(uuid,text,text),
  public.rh_asset_rename_variant(uuid,text,text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION rh_internal.asset_rename_variant(uuid,text,text),
  public.rh_asset_rename_variant(uuid,text,text) TO authenticated;
