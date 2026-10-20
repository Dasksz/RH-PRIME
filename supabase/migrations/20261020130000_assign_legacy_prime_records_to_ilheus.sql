UPDATE public.funcionarios_epi AS f
SET empresa_id = e.id
FROM public.empresas AS e
WHERE regexp_replace(coalesce(e.cnpj, ''), '\D', '', 'g') = '52522019000100'
  AND upper(trim(coalesce(f.local_registro, ''))) = upper(trim(e.nome))
  AND f.empresa_id IS NULL;
