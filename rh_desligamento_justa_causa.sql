ALTER TABLE public.rh_movimentacoes DROP CONSTRAINT rh_movimentacoes_motivo_saida_check;
ALTER TABLE public.rh_movimentacoes ADD CONSTRAINT rh_movimentacoes_motivo_saida_check CHECK (motivo_saida IN ('voluntario', 'involuntario', 'involuntario_justa_causa', 'entrada', ''));
