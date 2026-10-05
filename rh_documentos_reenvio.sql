-- Recupera somente falhas comprovadas antes da chamada HTTP ao n8n.
create or replace function rh_internal.rh_prepare_delivery_retry(p_id uuid)
returns void language plpgsql security definer set search_path='' as $$
declare d public.rh_delivery_documents; e public.funcionarios_epi;
begin
 if auth.uid() is null or not rh_internal.is_admin() then raise exception 'Acesso restrito'; end if;
 select * into d from public.rh_delivery_documents where id=p_id for update;
 if not found then raise exception 'Documento não encontrado'; end if;
 if d.status not in ('uncertain','failed') or d.error is null or d.error not in (
  'Configure webhook HTTPS e token de autenticação nas propriedades do Apps Script',
  'N8N_CONFIG_MISSING: Configure webhook HTTPS e token de autenticação nas propriedades do Apps Script'
 ) then raise exception 'Esta situação exige conferência no n8n antes de qualquer reenvio'; end if;
 select * into e from public.funcionarios_epi where id=d.funcionario_id;
 if not found or e.data_desligamento is not null then raise exception 'Colaborador indisponível ou desligado'; end if;
 if d.link is null or d.link !~ '^https://' or (d.source='upload' and d.drive_file_id is null) then raise exception 'Confira primeiro o arquivo e o link do documento'; end if;
 -- O gatilho de auditoria conserva a falha anterior e registra a retomada.
 update public.rh_delivery_documents set status='ready',error=null,approved_by=null,approved_at=null,phone=null,message_text=null,updated_at=now() where id=p_id;
end $$;
revoke all on function rh_internal.rh_prepare_delivery_retry(uuid) from public,anon;
grant execute on function rh_internal.rh_prepare_delivery_retry(uuid) to authenticated;
create or replace function public.rh_prepare_delivery_retry(p_id uuid)
returns void language sql security invoker set search_path='' as $$
 select rh_internal.rh_prepare_delivery_retry(p_id);
$$;
revoke all on function public.rh_prepare_delivery_retry(uuid) from public,anon;
grant execute on function public.rh_prepare_delivery_retry(uuid) to authenticated;
