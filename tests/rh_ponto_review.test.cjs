const {test}=require('node:test'),assert=require('node:assert/strict'),P=require('../assets/js/rh-ponto-core.js');
const employee={id:'pessoa',nome:'Pessoa',admissao:'2025-01-01',carga_horaria_semanal:44,jornada_diaria_minutos:528,dias_trabalho_semana:5};
const options={start:'2026-10-26',end:'2026-11-01',today:'2026-11-02',availableFrom:'2026-10-26'};
const coverage=[{inicio:'2026-10-26',fim:'2026-11-01',sucesso:true}];
function punches(date,times,types){return times.map((t,i)=>({data_hora:date+' '+t,entrada_saida:types?.[i]||(i%2?'S':'E'),situacao:'Aprovado (Auto)'}));}
function full(date,minutes){const remaining=minutes-240,end=13*60+remaining;return punches(date,['08:00:00','12:00:00','13:00:00',String(Math.floor(end/60)).padStart(2,'0')+':'+String(end%60).padStart(2,'0')+':00']);}
const first=r=>r.days[0];
test('6h, 9h30 e 10h recebem alerta em relação a 8h48; limite é 30 minutos inclusive',()=>{
 for(const [minutes,type] of [[360,'below'],[570,'above'],[600,'above'],[498,'below'],[558,'above']]){const day=first(P.summarize(employee,full('2026-10-26',minutes),coverage,options));assert.ok(day.alerts.some(a=>a.type===type));assert.equal(day.pending,false);assert.equal(day.delta,(minutes-528)*60);}
 for(const minutes of [499,527,528,529,557]){assert.equal(first(P.summarize(employee,full('2026-10-26',minutes),coverage,options)).alerts.length,0);}
});
test('três registros sinalizam sequência incompleta sem inventar qual horário foi esquecido',()=>{
 for(const [times,types] of [[['08:00:00','12:00:00','13:00:00'],['E','S','E']],[['08:00:00','12:00:00','18:00:00'],['E','S','S']],[['08:00:00','13:00:00','18:00:00'],['E','E','S']]]){
  const day=first(P.summarize(employee,punches('2026-10-26',times,types),coverage,options));assert.equal(day.delta,null);assert.ok(day.alerts.some(a=>a.type==='missing'&&a.message.includes('3 registro')));assert.ok(!day.alerts.some(a=>['above','below'].includes(a.type)));
 }
});
test('alertas operacionais não impedem compensação semanal: 6h e 11h36 se compensam',()=>{
 const marks=[...full('2026-10-26',360),...full('2026-10-27',696),...full('2026-10-28',528),...full('2026-10-29',528),...full('2026-10-30',528)];const r=P.summarize(employee,marks,coverage,options);
 assert.equal(r.reviewCount,2);assert.equal(r.reviewCounts.below,1);assert.equal(r.reviewCounts.above,1);assert.equal(r.pending,0);assert.equal(r.weeks[0].delta,0);assert.equal(r.extra,0);assert.equal(r.negative,0);
});
test('hoje, futuro e vínculo encerrado não geram alerta prematuro',()=>{
 for(const today of ['2026-10-26','2026-10-25']){const r=P.summarize(employee,full('2026-10-26',600),coverage,{...options,today});assert.equal(first(r).alerts.length,0);}
 assert.equal(first(P.summarize({...employee,data_desligamento:'2026-10-25'},full('2026-10-26',600),coverage,options)).alerts.length,0);
});
test('abono válido evita alerta de horas baixas; dia sem consulta não é rotulado como falta confirmada',()=>{
 const r=P.summarize(employee,full('2026-10-26',360),coverage,{...options,occurrences:[{dia:'2026-10-26',classificacao:'justificada',abonar:true}]});assert.equal(first(r).delta,0);assert.equal(first(r).alerts.length,0);
 const unknown=first(P.summarize(employee,[],[],options));assert.ok(unknown.alerts.some(a=>a.type==='data'));assert.ok(!unknown.alerts.some(a=>a.type==='no_record'));
 const absent=first(P.summarize(employee,[],coverage,options));assert.ok(absent.alerts.some(a=>a.type==='no_record'));assert.ok(!absent.alerts.some(a=>a.type==='below'));
});
