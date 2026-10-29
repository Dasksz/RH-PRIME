-- A correction is one transaction: the old version remains cancelled in history,
-- and the replacement goes through the same validations as a normal launch.
create function rh_internal.rh_vacation_correct(
 p_id uuid,p_expected_updated_at timestamptz,p_reason text,p_payload jsonb
) returns uuid language plpgsql security definer set search_path='' as $$
declare original public.rh_ferias_lancamentos; source_employee uuid; target_employee uuid;
 replacement uuid; reason text:=trim(coalesce(p_reason,'')); payload jsonb;
begin
 if auth.uid() is null or not rh_internal.can_write() then
  raise exception 'Acesso de edição não autorizado';
 end if;
 if length(reason)<10 or length(reason)>1000 then
  raise exception 'Informe o motivo da correção com 10 a 1000 caracteres';
 end if;
 select * into original from public.rh_ferias_lancamentos where id=p_id;
 if original.id is null then raise exception 'Lançamento não encontrado';end if;
 select funcionario_id into source_employee from public.rh_ferias_periodos where id=original.periodo_id;
 if not rh_internal.can_read_employee(source_employee) then
  raise exception 'Colaborador fora da área autorizada';
 end if;
 -- Serialize corrections for this employee, including concurrent duplicate submits.
 perform pg_advisory_xact_lock(hashtext(source_employee::text));
 select * into original from public.rh_ferias_lancamentos where id=p_id for update;
 if original.status='cancelado' then raise exception 'Lançamento já cancelado ou corrigido; atualize a tela';end if;
 if p_expected_updated_at is null or original.updated_at is distinct from p_expected_updated_at then
  raise exception 'Este lançamento foi alterado; atualize a tela antes de corrigir';
 end if;
 if nullif(p_payload->>'periodo_id','') is not null then
  select funcionario_id into target_employee from public.rh_ferias_periodos where id=(p_payload->>'periodo_id')::uuid;
 else
  target_employee=(p_payload->'novo_periodo'->>'funcionario_id')::uuid;
 end if;
 if target_employee is distinct from source_employee then
  raise exception 'O período corrigido deve pertencer ao mesmo colaborador';
 end if;
 if p_payload->>'status' not in ('programado','concluido') or p_payload->>'status' is null
  or p_payload->>'dias_gozo' is null or p_payload->>'dias_abono' is null then
  raise exception 'Informe a situação e os dias do lançamento corrigido';
 end if;
 payload=p_payload||jsonb_build_object('observacao',concat(
  nullif(p_payload->>'observacao',''),E'\nCorreção do lançamento ',p_id::text,'. Motivo: ',reason));
 if length(payload->>'observacao')>2000 then raise exception 'Observação e motivo excedem 2000 caracteres';end if;
 perform rh_internal.rh_vacation_mutate('cancelar',jsonb_build_object(
  'id',p_id,'observacao','Substituído por correção. Motivo: '||reason));
 replacement=rh_internal.rh_vacation_mutate('lancamento',payload);
 -- No files or delivery permissions are changed: documents remain on the original
 -- version and its period, available in history for the RH to review/reissue.
 return replacement;
end $$;
revoke all on function rh_internal.rh_vacation_correct(uuid,timestamptz,text,jsonb) from public,anon,authenticated;
create function public.rh_vacation_correct(
 p_id uuid,p_expected_updated_at timestamptz,p_reason text,p_payload jsonb
) returns uuid language sql security invoker set search_path='' as $$
 select rh_internal.rh_vacation_correct(p_id,p_expected_updated_at,p_reason,p_payload);
$$;
revoke all on function public.rh_vacation_correct(uuid,timestamptz,text,jsonb) from public,anon;
grant execute on function public.rh_vacation_correct(uuid,timestamptz,text,jsonb) to authenticated;
grant execute on function rh_internal.rh_vacation_correct(uuid,timestamptz,text,jsonb) to authenticated;
notify pgrst,'reload schema';
