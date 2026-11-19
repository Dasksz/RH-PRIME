CREATE FUNCTION public.rh_asset_offboarding() RETURNS jsonb
LANGUAGE sql STABLE SECURITY INVOKER SET search_path = '' AS $$
  SELECT coalesce(jsonb_agg(to_jsonb(p) ORDER BY p.data_desligamento DESC,p.funcionario_nome), '[]'::jsonb)
  FROM (
    SELECT f.id AS funcionario_id, f.nome AS funcionario_nome, f.cpf, f.funcao, f.setor, f.unidade,
      f.local_registro, f.admissao AS data_admissao, f.data_desligamento, f.empresa_id,
      sum(d.quantidade - coalesce(r.quantidade,0)) AS equipamentos_pendentes
    FROM public.funcionarios_epi f
    JOIN public.rh_asset_events d ON d.funcionario_id=f.id AND d.acao='entrega'
      AND d.data<=timezone('America/Sao_Paulo',now())::date
    LEFT JOIN LATERAL (
      SELECT sum(e.quantidade) AS quantidade FROM public.rh_asset_events e WHERE e.entrega_id=d.id
    ) r ON true
    WHERE f.data_desligamento IS NOT NULL
    GROUP BY f.id
  ) p
$$;
REVOKE ALL ON FUNCTION public.rh_asset_offboarding() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.rh_asset_offboarding() TO authenticated;
