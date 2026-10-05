-- Processadores anteriores não podem obter tarefas do modo vínculo sem mutação.
create or replace function public.rh_claim_drive() returns setof public.rh_drive_jobs language plpgsql security invoker set search_path='' as $$ begin
 update public.rh_automation_settings set last_worker_at=now() where id;
 if not (select drive_enabled from public.rh_automation_settings where id) then return;end if;
 update public.rh_drive_jobs set status='waiting',error='Retomando execução interrompida',updated_at=now() where status='processing' and updated_at<now()-interval '15 minutes';
 return query update public.rh_drive_jobs set status='processing',claimed_revision=revision,updated_at=now() where id=(select id from public.rh_drive_jobs where status='waiting' and not link_only order by updated_at for update skip locked limit 1) returning *;
end $$;
create function public.rh_claim_existing_drive() returns setof public.rh_drive_jobs language plpgsql security invoker set search_path='' as $$ begin
 if not (select drive_enabled from public.rh_automation_settings where id) then return;end if;
 update public.rh_drive_jobs set status='waiting',error='Retomando vínculo interrompido',updated_at=now() where status='processing' and link_only and updated_at<now()-interval '15 minutes';
 return query update public.rh_drive_jobs set status='processing',claimed_revision=revision,updated_at=now() where id=(select id from public.rh_drive_jobs where status='waiting' and link_only order by updated_at for update skip locked limit 1) returning *;
end $$;
revoke all on function public.rh_claim_drive(),public.rh_claim_existing_drive() from public,anon,authenticated;
grant execute on function public.rh_claim_drive(),public.rh_claim_existing_drive() to service_role;
notify pgrst,'reload schema';
