create function rh_internal.rh_approve_delivery(p_id uuid,p_link text,p_message text) returns void language plpgsql security definer set search_path='' as $$
declare e public.funcionarios_epi; d public.rh_delivery_documents; destination_phone text; begin
 if auth.uid() is null or not rh_internal.is_admin() then raise exception 'Acesso restrito'; end if;
 select * into d from public.rh_delivery_documents where id=p_id for update;
 if d.status<>'ready' then raise exception 'Documento ainda não pronto para aprovação'; end if;
 select * into e from public.funcionarios_epi where id=d.funcionario_id;
 if e.data_desligamento is not null then raise exception 'Envio automático bloqueado para desligado'; end if;
 destination_phone=regexp_replace(coalesce(e.whatsapp,''),'[^0-9]','','g');if length(destination_phone) in(10,11) then destination_phone='55'||destination_phone;end if;
 if destination_phone !~ '^55[1-9][0-9][0-9]{8,9}$' then raise exception 'WhatsApp inválido'; end if;
 if p_link !~ '^https://' or length(p_message) not between 1 and 8000 or position(p_link in p_message)=0 then raise exception 'Informe mensagem e link HTTPS válidos'; end if;
 update public.rh_delivery_documents set link=p_link,message_text=p_message,phone=destination_phone,approved_by=auth.uid(),approved_at=now(),status='queued',updated_at=now() where id=p_id;
end $$;
create function rh_internal.rh_cancel_delivery(p_id uuid) returns void language plpgsql security definer set search_path='' as $$ begin
 if auth.uid() is null or not rh_internal.is_admin() then raise exception 'Acesso restrito'; end if;
 update public.rh_delivery_documents set status='cancelled',updated_at=now() where id=p_id and status in('prepared','ready','queued','failed');
 if not found then raise exception 'Não é possível cancelar esta situação'; end if;
end $$;
revoke all on function rh_internal.rh_approve_delivery(uuid,text,text),rh_internal.rh_cancel_delivery(uuid) from public,anon;
grant execute on function rh_internal.rh_approve_delivery(uuid,text,text),rh_internal.rh_cancel_delivery(uuid) to authenticated;
create or replace function public.rh_approve_delivery(p_id uuid,p_link text,p_message text) returns void language sql security invoker set search_path='' as $$ select rh_internal.rh_approve_delivery(p_id,p_link,p_message); $$;
create or replace function public.rh_cancel_delivery(p_id uuid) returns void language sql security invoker set search_path='' as $$ select rh_internal.rh_cancel_delivery(p_id); $$;
revoke all on function public.rh_approve_delivery(uuid,text,text),public.rh_cancel_delivery(uuid) from public,anon;
grant execute on function public.rh_approve_delivery(uuid,text,text),public.rh_cancel_delivery(uuid) to authenticated;
