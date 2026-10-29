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
    'movimentos',coalesce((SELECT jsonb_agg(to_jsonb(m) ORDER BY m.data_movimento NULLS FIRST,m.created_at,m.id) FROM public.rh_equipment_movements m WHERE m.funcionario_id=e.id AND m.categoria=NEW.categoria),'[]'::jsonb),
    'verificacoes',coalesce((SELECT jsonb_agg(to_jsonb(v) ORDER BY v.data_verificacao,v.created_at,v.id) FROM public.rh_equipment_checks v WHERE v.funcionario_id=e.id AND v.categoria=NEW.categoria),'[]'::jsonb),
    'correcoes',coalesce((SELECT jsonb_agg(to_jsonb(c) ORDER BY c.created_at,c.id) FROM public.rh_equipment_item_corrections c WHERE c.funcionario_id=e.id AND c.categoria=NEW.categoria AND c.created_at<=NEW.created_at),'[]'::jsonb)
  ) INTO NEW.snapshot FROM public.funcionarios_epi e WHERE e.id=NEW.funcionario_id;
  IF NEW.snapshot IS NULL THEN RAISE EXCEPTION 'Colaborador indisponível.'; END IF;
  RETURN NEW;
END $function$;
