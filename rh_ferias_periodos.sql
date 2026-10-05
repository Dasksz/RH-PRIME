-- Histórico normalizado; preserva rh_ferias e as informações recebidas da planilha.
create table public.rh_ferias_periodos (
 id uuid primary key default gen_random_uuid(),funcionario_id uuid not null references public.funcionarios_epi(id) on delete restrict,
 inicio date not null,fim date not null,prazo_concessivo date not null,prazo_legado date,
 direito integer not null default 30 check(direito between 0 and 30),gozo_base integer not null default 0 check(gozo_base>=0),abono_base integer not null default 0 check(abono_base>=0),
 origem text not null default 'rh' check(origem in('rh','legado')),legacy_id integer references public.rh_ferias(id) on delete restrict,legacy_snapshot jsonb,
 controlado boolean not null default false,observacao text not null default '',created_at timestamptz not null default now(),updated_at timestamptz not null default now(),
 unique(funcionario_id,inicio),check(fim>=inicio),check(prazo_concessivo>fim),check(gozo_base+abono_base<=direito)
);
create table public.rh_ferias_lancamentos (
 id uuid primary key default gen_random_uuid(),periodo_id uuid not null references public.rh_ferias_periodos(id) on delete restrict,
 inicio date,fim date,dias_gozo integer not null default 0 check(dias_gozo>=0),dias_abono integer not null default 0 check(dias_abono>=0),
 status text not null check(status in('programado','concluido','cancelado')),observacao text not null default '',concordancia boolean not null default false,
 origem text not null default 'rh',created_by uuid references auth.users(id),created_at timestamptz not null default now(),updated_at timestamptz not null default now(),
 check(dias_gozo+dias_abono>0),check((dias_gozo=0 and inicio is null and fim is null) or (dias_gozo>0 and inicio is not null and fim=inicio+dias_gozo-1))
);
create index rh_ferias_lanc_periodo on public.rh_ferias_lancamentos(periodo_id,status);
create table public.rh_ferias_documentos (
 id uuid primary key default gen_random_uuid(),periodo_id uuid not null references public.rh_ferias_periodos(id) on delete restrict,lancamento_id uuid references public.rh_ferias_lancamentos(id),
 tipo text not null check(tipo in('AVISO DE FERIAS','RECIBO DE FERIAS','COMPROVANTE ASSINADO')),link text not null check(link ~ '^https://'),
 assinatura_status text not null default 'pendente' check(assinatura_status in('pendente','recebido_assinado')),signed_link text,provider text not null default 'manual',provider_reference text,
 delivery_id uuid unique references public.rh_delivery_documents(id),observacao text not null default '',created_at timestamptz not null default now(),updated_at timestamptz not null default now(),
 unique(periodo_id,tipo,link)
);
create table public.rh_ferias_eventos(id bigint generated always as identity primary key,tabela text not null,registro_id uuid not null,actor_id uuid,acao text not null,antes jsonb,depois jsonb,created_at timestamptz not null default now());
alter table public.rh_ferias_periodos enable row level security;
alter table public.rh_ferias_lancamentos enable row level security;
alter table public.rh_ferias_documentos enable row level security;
alter table public.rh_ferias_eventos enable row level security;
revoke all on public.rh_ferias_periodos,public.rh_ferias_lancamentos,public.rh_ferias_documentos,public.rh_ferias_eventos from anon,authenticated;
grant select on public.rh_ferias_periodos,public.rh_ferias_lancamentos,public.rh_ferias_documentos,public.rh_ferias_eventos to authenticated;
grant all on public.rh_ferias_periodos,public.rh_ferias_lancamentos,public.rh_ferias_documentos,public.rh_ferias_eventos to service_role;
grant usage,select on sequence public.rh_ferias_eventos_id_seq to service_role;
create policy ferias_periodos_read on public.rh_ferias_periodos for select to authenticated using((select rh_internal.is_approved()));
create policy ferias_lancamentos_read on public.rh_ferias_lancamentos for select to authenticated using((select rh_internal.is_approved()));
create policy ferias_documentos_read on public.rh_ferias_documentos for select to authenticated using((select rh_internal.is_approved()));
create policy ferias_eventos_read on public.rh_ferias_eventos for select to authenticated using((select rh_internal.is_approved()));
create function rh_internal.ferias_audit() returns trigger language plpgsql security definer set search_path='' as $$ begin
 insert into public.rh_ferias_eventos(tabela,registro_id,actor_id,acao,antes,depois) values(tg_table_name,new.id,auth.uid(),tg_op,case when tg_op='UPDATE' then to_jsonb(old) else null end,to_jsonb(new));return new;end $$;
revoke all on function rh_internal.ferias_audit() from public,anon,authenticated;
create trigger ferias_periodos_audit after insert or update on public.rh_ferias_periodos for each row execute function rh_internal.ferias_audit();
create trigger ferias_lanc_audit after insert or update on public.rh_ferias_lancamentos for each row execute function rh_internal.ferias_audit();
create trigger ferias_docs_audit after insert or update on public.rh_ferias_documentos for each row execute function rh_internal.ferias_audit();
-- O legado informa totais; não inventar datas de gozo inexistentes.
insert into public.rh_ferias_periodos(funcionario_id,inicio,fim,prazo_concessivo,prazo_legado,direito,gozo_base,abono_base,origem,legacy_id,legacy_snapshot,observacao)
 select funcionario_id,data_inicio_aquisitivo,data_fim_aquisitivo,(data_inicio_aquisitivo+interval '2 years')::date-1,data_vencimento,coalesce(dias_direito,30),coalesce(dias_gozados,0),coalesce(dias_abonados,0),'legado',id,to_jsonb(f),'Totais importados do resumo anterior; datas de gozo anteriores não comprovadas neste cadastro.'
 from public.rh_ferias f where funcionario_id is not null and data_inicio_aquisitivo is not null and data_fim_aquisitivo>=data_inicio_aquisitivo and data_fim_aquisitivo<(data_inicio_aquisitivo+interval '2 years')::date-1
 on conflict(funcionario_id,inicio) do nothing;
insert into public.rh_ferias_lancamentos(periodo_id,inicio,fim,dias_gozo,dias_abono,status,origem,observacao)
 select p.id,f.data_inicio_programada,f.data_inicio_programada+f.dias_programados-1,f.dias_programados,0,'programado','legado','Programação anterior importada; abono já incluído no total legado. Conferir antes de concluir.'
 from public.rh_ferias f join public.rh_ferias_periodos p on p.legacy_id=f.id
 where f.status='programadas' and f.dias_programados>0 and f.data_inicio_programada is not null;
create function rh_internal.ferias_sync_legacy(p_id uuid) returns void language plpgsql security definer set search_path='' as $$
declare p public.rh_ferias_periodos;used integer;sold integer;scheduled public.rh_ferias_lancamentos;begin
 select * into p from public.rh_ferias_periodos where id=p_id;if p.legacy_id is null then return;end if;
 select p.gozo_base+coalesce(sum(dias_gozo) filter(where status='concluido'),0),p.abono_base+coalesce(sum(dias_abono) filter(where status='concluido'),0) into used,sold from public.rh_ferias_lancamentos where periodo_id=p_id;
 select * into scheduled from public.rh_ferias_lancamentos where periodo_id=p_id and status='programado' order by inicio nulls last limit 1;
 perform set_config('rh.vacation_projection','on',true);
 update public.rh_ferias set dias_direito=p.direito,dias_gozados=used,dias_abonados=sold,status=case when scheduled.id is not null then 'programadas' when used+sold=p.direito then 'concluidas' else 'pendente' end,data_inicio_programada=scheduled.inicio,data_fim_programada=scheduled.fim,dias_programados=scheduled.dias_gozo,data_retorno=scheduled.fim+1 where id=p.legacy_id and data_inicio_aquisitivo=p.inicio;
 perform set_config('rh.vacation_projection','off',true);
end $$;
revoke all on function rh_internal.ferias_sync_legacy(uuid) from public,anon,authenticated;
create function rh_internal.ferias_legacy_guard() returns trigger language plpgsql set search_path='' as $$ begin
 if coalesce(current_setting('rh.vacation_projection',true),'off')<>'on' and exists(select 1 from public.rh_ferias_periodos where legacy_id=old.id and controlado) and
 (to_jsonb(new)-array['cpf','funcionario_nome','funcionario_id','created_at','historico_periodos','dias_saldo']) is distinct from (to_jsonb(old)-array['cpf','funcionario_nome','funcionario_id','created_at','historico_periodos','dias_saldo']) then
 raise exception 'Férias controladas por períodos: registre os lançamentos no RH PRIME; o resumo da planilha não pode sobrescrever o histórico.';end if;return new;end $$;
revoke all on function rh_internal.ferias_legacy_guard() from public,anon,authenticated;
create trigger ferias_normalized_guard before update on public.rh_ferias for each row execute function rh_internal.ferias_legacy_guard();
create function rh_internal.rh_vacation_mutate(p_action text,p_payload jsonb) returns uuid language plpgsql security definer set search_path='' as $$
declare p public.rh_ferias_periodos;l public.rh_ferias_lancamentos;e public.funcionarios_epi;pid uuid;lid uuid;st text;start_date date;end_date date;days integer;sold integer;consumed integer;abono_sum integer;parts integer;largest integer;obs text;today date:=(now() at time zone 'America/Sao_Paulo')::date;begin
 if auth.uid() is null or not rh_internal.is_approved() then raise exception 'Acesso RH não aprovado';end if;
 obs=coalesce(p_payload->>'observacao','');if length(obs)>2000 then raise exception 'Observação longa';end if;
 if p_action='periodo' then
  select * into e from public.funcionarios_epi where id=(p_payload->>'funcionario_id')::uuid;if e.id is null then raise exception 'Colaborador não encontrado';end if;
  start_date=(p_payload->>'inicio')::date;end_date=(p_payload->>'fim')::date;days=(p_payload->>'direito')::integer;
  if days not in(0,12,18,24,30) then raise exception 'Confirme o direito: 0, 12, 18, 24 ou 30 dias';end if;
  if end_date<>(start_date+interval '1 year')::date-1 and length(trim(obs))<10 then raise exception 'Período excepcional exige justificativa';end if;
  perform pg_advisory_xact_lock(hashtext(e.id::text));
  if exists(select 1 from public.rh_ferias_periodos where funcionario_id=e.id and inicio<=end_date and fim>=start_date) then raise exception 'Já existe período que se sobrepõe às datas';end if;
  insert into public.rh_ferias_periodos(funcionario_id,inicio,fim,prazo_concessivo,direito,controlado,observacao) values(e.id,start_date,end_date,(end_date+interval '1 year')::date,days,true,obs) returning id into pid;return pid;
 end if;
 if p_action in('concluir','cancelar') then
  select * into l from public.rh_ferias_lancamentos where id=(p_payload->>'id')::uuid;pid=l.periodo_id;
 else
  pid=nullif(p_payload->>'periodo_id','')::uuid;
  if pid is null and p_action='lancamento' and p_payload ? 'novo_periodo' then
   pid=rh_internal.rh_vacation_mutate('periodo',p_payload->'novo_periodo');
  end if;
 end if;
 select * into p from public.rh_ferias_periodos where id=pid for update;if p.id is null then raise exception 'Período não encontrado';end if;
 perform pg_advisory_xact_lock(hashtext(p.funcionario_id::text));
 if p_action='ajustar' then
  if length(trim(obs))<10 then raise exception 'Justifique o ajuste do resumo anterior';end if;
  days=(p_payload->>'direito')::integer;consumed=(p_payload->>'gozo_base')::integer;sold=(p_payload->>'abono_base')::integer;
  if days not in(0,12,18,24,30) or consumed<0 or sold<0 or sold>days/3 then raise exception 'Totais inválidos';end if;
  if sold+(select coalesce(sum(dias_abono),0) from public.rh_ferias_lancamentos where periodo_id=pid and status<>'cancelado')>days/3 then raise exception 'Abono acumulado excede um terço do direito';end if;
  if consumed+sold+(select coalesce(sum(dias_gozo+dias_abono),0) from public.rh_ferias_lancamentos where periodo_id=pid and status<>'cancelado')>days then raise exception 'O ajuste excede o direito ou reservas existentes';end if;
  update public.rh_ferias_periodos set direito=days,gozo_base=consumed,abono_base=sold,observacao=obs,controlado=true,updated_at=now() where id=pid;
 elsif p_action in('concluir','cancelar') then
  lid=l.id;select * into l from public.rh_ferias_lancamentos where id=lid for update;
  if p_action='concluir' and l.status<>'programado' then raise exception 'Somente uma programação pode ser concluída';end if;
  if p_action='concluir' and l.fim>=today then raise exception 'Confirme o gozo somente após a data final';end if;
  if p_action='cancelar' and (l.status='cancelado' or length(trim(obs))<10) then raise exception 'Informe motivo para estornar/cancelar o lançamento';end if;
  update public.rh_ferias_lancamentos set status=case when p_action='concluir' then 'concluido' else 'cancelado' end,observacao=concat(observacao,E'\n',obs),updated_at=now() where id=l.id;
 elsif p_action='lancamento' then
  st=p_payload->>'status';days=(p_payload->>'dias_gozo')::integer;sold=(p_payload->>'dias_abono')::integer;start_date=nullif(p_payload->>'inicio','')::date;end_date=case when days>0 then start_date+days-1 else null end;
  if st not in('programado','concluido') or days<0 or sold<0 or days+sold=0 or (days>0 and start_date is null) then raise exception 'Lançamento inválido';end if;
  if days=0 then start_date=null;end if;
  select * into e from public.funcionarios_epi where id=p.funcionario_id;
  if st='programado' and e.data_desligamento is not null then raise exception 'Programação bloqueada para desligado';end if;
  if days>0 and start_date<=p.fim then raise exception 'Gozo anterior à aquisição completa: revise o período; antecipação exige tratamento específico pelo DP';end if;
  if st='concluido' and days>0 and end_date>=today then raise exception 'Registre como programação e confirme o gozo após o término';end if;
  select p.gozo_base+p.abono_base+coalesce(sum(dias_gozo+dias_abono),0),p.abono_base+coalesce(sum(dias_abono),0),count(*) filter(where dias_gozo>0),coalesce(max(dias_gozo),0) into consumed,abono_sum,parts,largest from public.rh_ferias_lancamentos where periodo_id=pid and status<>'cancelado';
  if consumed+days+sold>p.direito then raise exception 'Lançamento excede saldo disponível, incluindo reservas';end if;
  if abono_sum+sold>p.direito/3 then raise exception 'Abono excede um terço do direito';end if;
  if days>0 and (days<5 or parts>=3) and (st='programado' or length(trim(obs))<10) then raise exception 'Fracionamento fora do padrão exige justificativa de registro histórico/DP';end if;
  if days>0 and (parts>0 or days<p.direito-sold) and not coalesce((p_payload->>'concordancia')::boolean,false) then raise exception 'Confirme a concordância do colaborador no fracionamento';end if;
  if parts>0 and consumed+days+sold=p.direito and greatest(largest,days)<14 and p.direito>=14 and p.gozo_base=0 and (st='programado' or length(trim(obs))<10) then raise exception 'Um dos períodos de gozo deve ter ao menos 14 dias; exceção histórica exige justificativa';end if;
  if days>0 and exists(select 1 from public.rh_ferias_lancamentos x join public.rh_ferias_periodos y on y.id=x.periodo_id where y.funcionario_id=p.funcionario_id and x.status<>'cancelado' and x.inicio<=end_date and x.fim>=start_date) then raise exception 'Datas sobrepostas a outro lançamento do colaborador';end if;
  insert into public.rh_ferias_lancamentos(periodo_id,inicio,fim,dias_gozo,dias_abono,status,observacao,concordancia,created_by) values(pid,start_date,end_date,days,sold,st,obs,coalesce((p_payload->>'concordancia')::boolean,false),auth.uid()) returning id into lid;
 else raise exception 'Ação inválida';end if;
 update public.rh_ferias_periodos set controlado=true,updated_at=now() where id=pid;perform rh_internal.ferias_sync_legacy(pid);return coalesce(lid,l.id,pid);
end $$;
create function public.rh_vacation_mutate(p_action text,p_payload jsonb) returns uuid language sql security invoker set search_path='' as $$ select rh_internal.rh_vacation_mutate(p_action,p_payload);$$;
revoke all on function rh_internal.rh_vacation_mutate(text,jsonb),public.rh_vacation_mutate(text,jsonb) from public,anon;
grant execute on function rh_internal.rh_vacation_mutate(text,jsonb),public.rh_vacation_mutate(text,jsonb) to authenticated;
create function rh_internal.ferias_import_legacy() returns trigger language plpgsql security definer set search_path='' as $$ declare p public.rh_ferias_periodos;begin
 if new.funcionario_id is null or new.data_inicio_aquisitivo is null or new.data_fim_aquisitivo is null or new.data_fim_aquisitivo<new.data_inicio_aquisitivo then return new;end if;
 insert into public.rh_ferias_periodos(funcionario_id,inicio,fim,prazo_concessivo,prazo_legado,direito,gozo_base,abono_base,origem,legacy_id,legacy_snapshot,observacao)
 values(new.funcionario_id,new.data_inicio_aquisitivo,new.data_fim_aquisitivo,(new.data_inicio_aquisitivo+interval '2 years')::date-1,new.data_vencimento,coalesce(new.dias_direito,30),coalesce(new.dias_gozados,0),coalesce(new.dias_abonados,0),'legado',new.id,to_jsonb(new),'Resumo recebido da sincronização; datas anteriores dependem de conferência.')
 on conflict(funcionario_id,inicio) do update set fim=excluded.fim,prazo_legado=excluded.prazo_legado,direito=excluded.direito,gozo_base=excluded.gozo_base,abono_base=excluded.abono_base,legacy_snapshot=excluded.legacy_snapshot,updated_at=now() where not rh_ferias_periodos.controlado;
 select * into p from public.rh_ferias_periodos where funcionario_id=new.funcionario_id and inicio=new.data_inicio_aquisitivo;
 if not p.controlado then
  if not exists(select 1 from public.rh_ferias_lancamentos where periodo_id=p.id and status='programado' and origem='legado' and new.status='programadas' and inicio=new.data_inicio_programada and dias_gozo=new.dias_programados) then
   update public.rh_ferias_lancamentos set status='cancelado',observacao=observacao||E'\nProgramação do resumo substituída pela sincronização.',updated_at=now() where periodo_id=p.id and origem='legado' and status='programado';
   if new.status='programadas' and new.dias_programados>0 and new.data_inicio_programada is not null then
    insert into public.rh_ferias_lancamentos(periodo_id,inicio,fim,dias_gozo,status,origem,observacao) values(p.id,new.data_inicio_programada,new.data_inicio_programada+new.dias_programados-1,new.dias_programados,'programado','legado','Programação recebida da planilha; conferir antes de concluir.');
   end if;
  end if;
 end if;
 return new;end $$;
revoke all on function rh_internal.ferias_import_legacy() from public,anon,authenticated;
create trigger ferias_normalized_import after insert or update on public.rh_ferias for each row execute function rh_internal.ferias_import_legacy();
alter table public.rh_delivery_documents add column source text not null default 'upload' check(source in('upload','link'));
alter table public.rh_delivery_documents add column vacation_period_id uuid references public.rh_ferias_periodos(id) on delete restrict;
alter table public.rh_delivery_documents add column vacation_launch_id uuid references public.rh_ferias_lancamentos(id) on delete restrict;
create function rh_internal.ferias_delivery_guard() returns trigger language plpgsql security invoker set search_path='' as $$ begin
 if current_user='authenticated' and new.source<>'upload' then raise exception 'Links externos exigem preparação pelo RH';end if;
 if new.vacation_period_id is not null and not exists(select 1 from public.rh_ferias_periodos where id=new.vacation_period_id and funcionario_id=new.funcionario_id) then raise exception 'Documento pertence a outro colaborador/período';end if;
 if new.vacation_period_id is not null and new.document_type not in('AVISO DE FERIAS','RECIBO DE FERIAS','COMPROVANTE ASSINADO') then raise exception 'Tipo de documento de férias inválido';end if;
 if new.vacation_launch_id is not null and not exists(select 1 from public.rh_ferias_lancamentos where id=new.vacation_launch_id and periodo_id=new.vacation_period_id) then raise exception 'Lançamento e período incompatíveis';end if;return new;end $$;
revoke all on function rh_internal.ferias_delivery_guard() from public,anon,authenticated;
create trigger ferias_delivery_guard before insert or update on public.rh_delivery_documents for each row execute function rh_internal.ferias_delivery_guard();
create function rh_internal.rh_vacation_document(p_action text,p_payload jsonb) returns uuid language plpgsql security definer set search_path='' as $$
declare p public.rh_ferias_periodos;d public.rh_ferias_documentos;did uuid;delivery uuid;url text;kind text;begin
 if auth.uid() is null or not rh_internal.is_approved() then raise exception 'Acesso RH não aprovado';end if;
 if p_action='anexar' then
  select * into p from public.rh_ferias_periodos where id=(p_payload->>'periodo_id')::uuid;if p.id is null then raise exception 'Período inexistente';end if;
  url=p_payload->>'link';kind=p_payload->>'tipo';if url is null or url !~ '^https://[^[:space:]]+$' or length(url)>2000 or kind not in('AVISO DE FERIAS','RECIBO DE FERIAS','COMPROVANTE ASSINADO') then raise exception 'Informe tipo e link HTTPS válidos';end if;
  if nullif(p_payload->>'lancamento_id','') is not null and not exists(select 1 from public.rh_ferias_lancamentos where id=(p_payload->>'lancamento_id')::uuid and periodo_id=p.id) then raise exception 'Lançamento não pertence ao período';end if;
  insert into public.rh_ferias_documentos(periodo_id,lancamento_id,tipo,link,observacao,assinatura_status,signed_link) values(p.id,nullif(p_payload->>'lancamento_id','')::uuid,kind,url,left(coalesce(p_payload->>'observacao',''),2000),case when kind='COMPROVANTE ASSINADO' then 'recebido_assinado' else 'pendente' end,case when kind='COMPROVANTE ASSINADO' then url else null end) returning id into did;return did;
 end if;
 select * into d from public.rh_ferias_documentos where id=(p_payload->>'id')::uuid for update;if d.id is null then raise exception 'Documento não encontrado';end if;
 if p_action='assinado' then
  url=p_payload->>'signed_link';if url is null or url !~ '^https://[^[:space:]]+$' or length(url)>2000 then raise exception 'Informe o link do arquivo devolvido assinado';end if;
  update public.rh_ferias_documentos set assinatura_status='recebido_assinado',signed_link=url,updated_at=now() where id=d.id;return d.id;
 elsif p_action='preparar_envio' then
  if not rh_internal.is_admin() then raise exception 'Somente administrador pode preparar envio';end if;
  if d.delivery_id is not null then return d.delivery_id;end if;
  if d.tipo='COMPROVANTE ASSINADO' then raise exception 'Prepare o aviso/recibo original para envio';end if;
  select * into p from public.rh_ferias_periodos where id=d.periodo_id;
  if exists(select 1 from public.funcionarios_epi where id=p.funcionario_id and data_desligamento is not null) then raise exception 'Envio bloqueado para desligado';end if;
  delivery=gen_random_uuid();
  insert into public.rh_delivery_documents(id,funcionario_id,document_type,period,filename,sha256,storage_path,status,link,source,vacation_period_id,vacation_launch_id)
   values(delivery,p.funcionario_id,d.tipo,p.inicio::text||' a '||p.fim::text,d.tipo||'.pdf',encode(sha256(convert_to(d.id::text||d.link,'UTF8')),'hex'),delivery::text||'.pdf','ready',d.link,'link',p.id,d.lancamento_id);
  update public.rh_ferias_documentos set delivery_id=delivery,updated_at=now() where id=d.id;return delivery;
 end if;raise exception 'Ação inválida';end $$;
create function public.rh_vacation_document(p_action text,p_payload jsonb) returns uuid language sql security invoker set search_path='' as $$select rh_internal.rh_vacation_document(p_action,p_payload);$$;
revoke all on function rh_internal.rh_vacation_document(text,jsonb),public.rh_vacation_document(text,jsonb) from public,anon;
grant execute on function rh_internal.rh_vacation_document(text,jsonb),public.rh_vacation_document(text,jsonb) to authenticated;
comment on table public.rh_ferias_documentos is 'Links de documentos conferidos pelo RH. Recebimento de assinatura manual não equivale a assinatura certificada. Campos provider/reference reservados para integração futura.';
notify pgrst,'reload schema';

create function rh_internal.ferias_delivery_link() returns trigger language plpgsql security definer set search_path='' as $$ begin
 if new.status='ready' and new.vacation_period_id is not null and new.link is not null then
  insert into public.rh_ferias_documentos(periodo_id,lancamento_id,tipo,link,delivery_id,assinatura_status,signed_link,observacao)
   values(new.vacation_period_id,new.vacation_launch_id,new.document_type,new.link,new.id,case when new.document_type='COMPROVANTE ASSINADO' then 'recebido_assinado' else 'pendente' end,case when new.document_type='COMPROVANTE ASSINADO' then new.link else null end,'PDF importado pela fila privada de documentos.')
   on conflict(periodo_id,tipo,link) do update set delivery_id=coalesce(rh_ferias_documentos.delivery_id,excluded.delivery_id),updated_at=now();
 end if;return new;end $$;
revoke all on function rh_internal.ferias_delivery_link() from public,anon,authenticated;
create trigger ferias_delivery_link after update on public.rh_delivery_documents for each row execute function rh_internal.ferias_delivery_link();
