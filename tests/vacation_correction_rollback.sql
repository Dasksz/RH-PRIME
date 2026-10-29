-- Run after the migration inside BEGIN ... ROLLBACK. No fixtures persist.
do $test$
declare actor uuid; employee uuid:=gen_random_uuid();other_employee uuid:=gen_random_uuid();
 a uuid;b uuid;c uuid;other_period uuid;old_launch uuid;corrected uuid;extra uuid;doc uuid;
 stamp timestamptz; count_before integer; failed boolean;
begin
 select id into actor from public.profiles where status='admin' limit 1;
 if actor is null then raise exception 'Admin fixture unavailable';end if;
 perform set_config('request.jwt.claim.sub',actor::text,true);
 insert into public.funcionarios_epi(id,nome,admissao,cpf) values
  (employee,'TESTE TRANSACIONAL CORRECAO FERIAS','01/01/2024','00000000191'),
  (other_employee,'TESTE TRANSACIONAL OUTRO COLABORADOR','01/01/2024','00000000272');
 select id into a from public.rh_ferias_periodos where funcionario_id=employee and inicio='2024-01-01';
 if a is null then raise exception 'Employee synchronization did not create initial period';end if;
 b=rh_internal.rh_vacation_mutate('periodo',jsonb_build_object('funcionario_id',employee,'inicio','2025-01-01','fim','2025-12-31','direito',30,'observacao','Teste transacional sem persistência'));
 c=rh_internal.rh_vacation_mutate('periodo',jsonb_build_object('funcionario_id',employee,'inicio','2026-01-01','fim','2026-12-31','direito',30,'observacao','Teste transacional sem persistência'));
 other_period=rh_internal.rh_vacation_mutate('periodo',jsonb_build_object('funcionario_id',other_employee,'inicio','2025-01-01','fim','2025-12-31','direito',30,'observacao','Teste transacional sem persistência'));
 old_launch=rh_internal.rh_vacation_mutate('lancamento',jsonb_build_object('periodo_id',a,'inicio','2026-07-06','dias_gozo',30,'dias_abono',0,'status','concluido','observacao','Datas históricas de teste','concordancia',true));
 doc=rh_internal.rh_vacation_document('anexar',jsonb_build_object('periodo_id',a,'lancamento_id',old_launch,'tipo','AVISO DE FERIAS','link','https://example.invalid/rollback-only.pdf'));
 select updated_at into stamp from public.rh_ferias_lancamentos where id=old_launch;
 corrected=public.rh_vacation_correct(old_launch,stamp,'Corrigir o período aquisitivo de teste',jsonb_build_object('periodo_id',b,'inicio','2026-07-06','dias_gozo',30,'dias_abono',0,'status','concluido','observacao','Datas históricas de teste','concordancia',true));
 if not exists(select 1 from public.rh_ferias_lancamentos where id=old_launch and status='cancelado') then raise exception 'Original not preserved';end if;
 if not exists(select 1 from public.rh_ferias_lancamentos where id=corrected and periodo_id=b and status='concluido' and fim='2026-08-04') then raise exception 'Replacement invalid';end if;
 if (select coalesce(sum(dias_gozo),0) from public.rh_ferias_lancamentos where periodo_id=a and status<>'cancelado')<>0 or (select sum(dias_gozo) from public.rh_ferias_lancamentos where periodo_id=b and status<>'cancelado')<>30 then raise exception 'Balances invalid';end if;
 if not exists(select 1 from public.rh_ferias_documentos where id=doc and lancamento_id=old_launch and periodo_id=a) then raise exception 'Original document changed';end if;
 select updated_at into stamp from public.rh_ferias_lancamentos where id=corrected;
 select count(*) into count_before from public.rh_ferias_lancamentos where periodo_id in(a,b,c);
 failed=false;
 begin
  perform public.rh_vacation_correct(corrected,stamp,'Correção inválida excedendo saldo',jsonb_build_object('periodo_id',b,'inicio','2026-07-06','dias_gozo',31,'dias_abono',0,'status','concluido'));
 exception when others then if sqlerrm not like '%saldo%' then raise;end if;failed=true;end;
 if not failed or not exists(select 1 from public.rh_ferias_lancamentos where id=corrected and status='concluido' and updated_at=stamp) or (select count(*) from public.rh_ferias_lancamentos where periodo_id in(a,b,c))<>count_before then raise exception 'Failed correction did not roll back';end if;
 failed=false;
 begin
  perform public.rh_vacation_correct(corrected,stamp-interval '1 second','Tela desatualizada de teste',jsonb_build_object('periodo_id',b));
 exception when others then if sqlerrm not like '%atualize%' then raise;end if;failed=true;end;
 if not failed then raise exception 'Stale write accepted';end if;
 failed=false;
 begin
  perform public.rh_vacation_correct(corrected,stamp,'Troca indevida de colaborador',jsonb_build_object('periodo_id',other_period));
 exception when others then if sqlerrm not like '%mesmo colaborador%' then raise;end if;failed=true;end;
 if not failed then raise exception 'Cross-employee write accepted';end if;
 extra=rh_internal.rh_vacation_mutate('lancamento',jsonb_build_object('periodo_id',c,'inicio','2026-09-01','dias_gozo',30,'dias_abono',0,'status','concluido','concordancia',true,'antecipada',true));
 failed=false;
 begin
  perform public.rh_vacation_correct(corrected,stamp,'Datas sobrepostas ao outro lançamento',jsonb_build_object('periodo_id',b,'inicio','2026-09-14','dias_gozo',30,'dias_abono',0,'status','concluido'));
 exception when others then if sqlerrm not like '%sobrepostas%' then raise;end if;failed=true;end;
 if not failed or not exists(select 1 from public.rh_ferias_lancamentos where id=corrected and status='concluido' and inicio='2026-07-06') then raise exception 'Overlap changed original';end if;
 perform set_config('request.jwt.claim.sub','',true);
 failed=false;
 begin
  perform public.rh_vacation_correct(corrected,stamp,'Tentativa anônima de teste','{}'::jsonb);
 exception when others then if sqlerrm not like '%não autorizado%' then raise;end if;failed=true;end;
 if not failed then raise exception 'Anonymous write accepted';end if;
end $test$;
select 'PASS: correction, balance, history/documents, rollback, stale write, scope, overlap, anonymous access' as checks;
