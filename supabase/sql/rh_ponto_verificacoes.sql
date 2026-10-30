create table public.rh_ponto_verificacoes (
 id bigint generated always as identity primary key,
 funcionario_id uuid not null references public.funcionarios_epi(id),
 dia date not null,
 assinatura text not null check(length(assinatura) between 2 and 50000),
 verificado_por uuid not null default auth.uid() references auth.users(id),
 responsavel text not null default '',
 verificado_em timestamptz not null default now()
);
create index on public.rh_ponto_verificacoes(funcionario_id,dia);
alter table public.rh_ponto_verificacoes enable row level security;
create policy verificacao_read on public.rh_ponto_verificacoes for select to authenticated using (rh_internal.can_read_employee(funcionario_id));
create policy verificacao_insert on public.rh_ponto_verificacoes for insert to authenticated with check ((select rh_internal.is_admin()) and verificado_por=(select auth.uid()));
grant select,insert on public.rh_ponto_verificacoes to authenticated;
grant usage,select on sequence public.rh_ponto_verificacoes_id_seq to authenticated;
create function public.rh_ponto_verificacao_autoria() returns trigger language plpgsql security invoker set search_path='' as $$
begin
 new.verificado_por:=auth.uid();new.verificado_em:=clock_timestamp();
 select coalesce(nullif(name,''),email,'RH') into new.responsavel from public.profiles where id=auth.uid();
 new.responsavel:=coalesce(new.responsavel,'RH');
 return new;
end $$;
create trigger verificacao_autoria before insert on public.rh_ponto_verificacoes for each row execute function public.rh_ponto_verificacao_autoria();
revoke all on function public.rh_ponto_verificacao_autoria() from public;
