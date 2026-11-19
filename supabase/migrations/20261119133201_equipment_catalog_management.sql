CREATE TABLE public.rh_asset_variants (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tipo_id uuid NOT NULL REFERENCES public.rh_asset_types ON DELETE CASCADE,
  variante text NOT NULL CHECK (length(variante)<=120),
  UNIQUE (tipo_id,variante)
);
INSERT INTO public.rh_asset_variants (tipo_id,variante)
  SELECT DISTINCT tipo_id,variante FROM public.rh_asset_stock WHERE variante<>'';
ALTER TABLE public.rh_asset_variants ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.rh_asset_variants FROM PUBLIC, anon, authenticated;
GRANT SELECT ON public.rh_asset_variants TO authenticated;
CREATE POLICY asset_variants_read ON public.rh_asset_variants FOR SELECT TO authenticated
  USING ((SELECT rh_internal.can_manage_stock()));

CREATE FUNCTION rh_internal.asset_manage_type(p_id uuid, p_name text, p_detail text, p_delete boolean)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE
  item public.rh_asset_types%ROWTYPE;
BEGIN
  IF auth.uid() IS NULL OR NOT rh_internal.can_manage_stock() THEN
    RAISE EXCEPTION 'Sem permissão para administrar os tipos de equipamento.';
  END IF;
  SELECT * INTO item FROM public.rh_asset_types WHERE id=p_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Tipo de equipamento não encontrado. Atualize a lista.'; END IF;
  IF p_delete OR p_detail IS DISTINCT FROM item.detalhe THEN
    IF EXISTS (SELECT 1 FROM public.rh_asset_stock WHERE tipo_id=p_id) THEN
      RAISE EXCEPTION 'Este tipo já está vinculado ao estoque. Você pode editar o nome.';
    END IF;
  END IF;
  IF NOT p_delete AND p_detail IS DISTINCT FROM item.detalhe
    AND EXISTS (SELECT 1 FROM public.rh_asset_variants WHERE tipo_id=p_id) THEN
    RAISE EXCEPTION 'Este tipo já tem modelos ou versões cadastrados. Você pode editar o nome.';
  END IF;
  IF p_delete THEN
    DELETE FROM public.rh_asset_types WHERE id=p_id;
  ELSE
    UPDATE public.rh_asset_types SET nome=btrim(p_name), detalhe=p_detail WHERE id=p_id;
  END IF;
  RETURN p_id;
END $$;

CREATE FUNCTION public.rh_asset_manage_type(p_id uuid, p_name text, p_detail text, p_delete boolean)
RETURNS uuid LANGUAGE sql SECURITY INVOKER SET search_path = '' AS $$
  SELECT rh_internal.asset_manage_type(p_id,p_name,p_detail,p_delete)
$$;
REVOKE ALL ON FUNCTION rh_internal.asset_manage_type(uuid,text,text,boolean),
  public.rh_asset_manage_type(uuid,text,text,boolean) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION rh_internal.asset_manage_type(uuid,text,text,boolean),
  public.rh_asset_manage_type(uuid,text,text,boolean) TO authenticated;

-- Revalida o complemento após sincronizar a entrada com uma edição concorrente do tipo.
CREATE FUNCTION rh_internal.asset_validate_stock_variant() RETURNS trigger
LANGUAGE plpgsql SECURITY INVOKER SET search_path = '' AS $$
DECLARE
  detail text;
BEGIN
  SELECT detalhe INTO detail FROM public.rh_asset_types WHERE id=NEW.tipo_id FOR SHARE;
  IF (detail='ano' AND NEW.variante !~ '^[1-9][0-9]{3}$')
    OR (detail IN ('modelo','descricao') AND btrim(NEW.variante)='')
    OR (detail='nenhum' AND NEW.variante<>'') THEN
    RAISE EXCEPTION 'O tipo de equipamento mudou. Atualize a tela e confira o ano, modelo ou descrição.';
  END IF;
  IF NEW.variante<>'' THEN
    INSERT INTO public.rh_asset_variants (tipo_id,variante) VALUES (NEW.tipo_id,NEW.variante)
    ON CONFLICT DO NOTHING;
  END IF;
  RETURN NEW;
END $$;
REVOKE ALL ON FUNCTION rh_internal.asset_validate_stock_variant() FROM PUBLIC, anon, authenticated;
CREATE TRIGGER asset_validate_stock_variant BEFORE INSERT OR UPDATE OF tipo_id,variante
ON public.rh_asset_stock FOR EACH ROW EXECUTE FUNCTION rh_internal.asset_validate_stock_variant();

CREATE FUNCTION rh_internal.asset_register_variant(p_id uuid, p jsonb)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE
  item public.rh_asset_types%ROWTYPE;
  variant text := upper(regexp_replace(btrim(coalesce(p->>'variante','')), '[[:space:]]+', ' ', 'g'));
  qty integer := coalesce((p->>'quantidade')::integer,0);
BEGIN
  IF auth.uid() IS NULL OR NOT rh_internal.can_manage_stock() THEN RAISE EXCEPTION 'Sem permissão para cadastrar equipamentos.'; END IF;
  IF qty NOT BETWEEN 0 AND 10000 THEN RAISE EXCEPTION 'Confira a quantidade.'; END IF;
  SELECT * INTO item FROM public.rh_asset_types WHERE id=(p->>'tipo_id')::uuid FOR SHARE;
  IF item.id IS NULL OR item.detalhe='nenhum' OR length(variant) NOT BETWEEN 1 AND 120
    OR (item.detalhe='ano' AND variant !~ '^[1-9][0-9]{3}$') THEN
    RAISE EXCEPTION 'Confira o tipo e o ano, modelo ou descrição.';
  END IF;
  IF qty>0 THEN
    RETURN rh_internal.asset_event(p_id,p || jsonb_build_object('acao','entrada','variante',variant));
  END IF;
  INSERT INTO public.rh_asset_variants (tipo_id,variante) VALUES (item.id,variant) ON CONFLICT DO NOTHING;
  RETURN p_id;
END $$;
CREATE FUNCTION public.rh_asset_register_variant(p_id uuid, p jsonb)
RETURNS uuid LANGUAGE sql SECURITY INVOKER SET search_path = '' AS $$
  SELECT rh_internal.asset_register_variant(p_id,p)
$$;
REVOKE ALL ON FUNCTION rh_internal.asset_register_variant(uuid,jsonb),
  public.rh_asset_register_variant(uuid,jsonb) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION rh_internal.asset_register_variant(uuid,jsonb),
  public.rh_asset_register_variant(uuid,jsonb) TO authenticated;
