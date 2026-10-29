ALTER TABLE public.funcionarios_epi
  ADD COLUMN IF NOT EXISTS empresa_id integer REFERENCES public.empresas(id);

UPDATE public.funcionarios_epi AS f
SET empresa_id = e.id
FROM public.empresas AS e
WHERE regexp_replace(coalesce(e.cnpj, ''), '\D', '', 'g') = '48986353000139'
  AND upper(trim(coalesce(f.local_registro, ''))) = upper(trim(e.nome))
  AND f.empresa_id IS NULL;

UPDATE public.funcionarios_epi AS f
SET empresa_id = e.id
FROM public.empresas AS e
WHERE regexp_replace(coalesce(e.cnpj, ''), '\D', '', 'g') = '52522019000100'
  AND translate(upper(trim(coalesce(f.local_registro, ''))), 'ÁÀÂÃÉÊÍÓÔÕÚÜÇ', 'AAAAEEIOOOUUC') LIKE '%ILHEUS%'
  AND f.empresa_id IS NULL;

UPDATE public.funcionarios_epi AS f
SET empresa_id = e.id
FROM public.empresas AS e
WHERE regexp_replace(coalesce(e.cnpj, ''), '\D', '', 'g') = '52522019000282'
  AND translate(upper(trim(coalesce(f.local_registro, ''))), 'ÁÀÂÃÉÊÍÓÔÕÚÜÇ', 'AAAAEEIOOOUUC') LIKE '%JEQUIE%'
  AND f.empresa_id IS NULL;

UPDATE public.funcionarios_epi AS f
SET empresa_id = e.id
FROM public.empresas AS e
WHERE regexp_replace(coalesce(e.cnpj, ''), '\D', '', 'g') = '52522019000282'
  AND regexp_replace(coalesce(f.cpf, ''), '\D', '', 'g') = '07543150530'
  AND f.empresa_id IS NULL;
