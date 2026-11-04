-- Lista compartilhada pelo RH para emissão recorrente de fichas manuais.
-- Não altera cadastro, batidas ou apuração de jornada.
begin;
create table public.rh_ponto_fichas_destinatarios (
 funcionario_id uuid primary key references public.funcionarios_epi(id) on delete cascade,
 cidade_trabalho text not null default '' check (length(cidade_trabalho) <= 120),
 criado_em timestamptz not null default now()
);
alter table public.rh_ponto_fichas_destinatarios enable row level security;
revoke all on public.rh_ponto_fichas_destinatarios from anon, authenticated;
grant select, insert, update, delete on public.rh_ponto_fichas_destinatarios to authenticated;
create policy fichas_admin_select on public.rh_ponto_fichas_destinatarios
 for select to authenticated using ((select rh_internal.is_admin()));
create policy fichas_admin_insert on public.rh_ponto_fichas_destinatarios
 for insert to authenticated with check ((select rh_internal.is_admin()));
create policy fichas_admin_update on public.rh_ponto_fichas_destinatarios
 for update to authenticated using ((select rh_internal.is_admin()))
 with check ((select rh_internal.is_admin()));
create policy fichas_admin_delete on public.rh_ponto_fichas_destinatarios
 for delete to authenticated using ((select rh_internal.is_admin()));
commit;
