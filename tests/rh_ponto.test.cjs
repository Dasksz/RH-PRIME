const test=require('node:test'),assert=require('node:assert/strict'),P=require('../assets/js/rh-ponto-core.js');
const person={id:'person',nome:'Teste',admissao:'01/01/2020',carga_horaria_semanal:44,jornada_diaria_minutos:528,dias_trabalho_semana:5};
const coverage=[{inicio:'2026-10-26',fim:'2026-11-01',sucesso:true}];
const options={start:'2026-10-26',end:'2026-11-25',today:'2026-11-02',availableFrom:'2026-10-26'};
function punches(durations=[468,588,528,528,528]){return durations.flatMap((minutes,i)=>{const date=P.add('2026-10-26',i),end=9*60+minutes;return [{data_hora:date+' 09:00:00',entrada_saida:'E',tipo_registro:'A',situacao:'Aprovado (Auto)'},{data_hora:date+' '+String(Math.floor(end/60)).padStart(2,'0')+':'+String(end%60).padStart(2,'0')+':00',entrada_saida:'S',tipo_registro:'A',situacao:'Aprovado (Auto)'}];});}
test('ciclo 26 a 25 inclui virada de ano e abre novo ciclo após dia 25',()=>{
 assert.deepEqual(P.cycle('2026-10-25'),{start:'2026-09-26',end:'2026-10-25'});
 assert.deepEqual(P.cycle('2026-10-29'),{start:'2026-10-26',end:'2026-11-25'});
 assert.deepEqual(P.cycleMonth('2027-01'),{start:'2026-12-26',end:'2027-01-25'});
});
test('menos uma hora num dia e mais uma em outro fecha 44h sem extra ou débito',()=>{
 const result=P.summarize(person,punches(),coverage,options),week=result.weeks[0];
 assert.equal(result.days[0].delta,-3600);assert.equal(result.days[1].delta,3600);
 assert.equal(week.worked,44*3600);assert.equal(week.delta,0);assert.equal(result.extra,0);assert.equal(result.negative,0);
});
test('saldo semanal só contabiliza o excedente após compensação',()=>{
 const result=P.summarize(person,punches([468,588,528,528,648]),coverage,options);assert.equal(result.extra,7200);assert.equal(result.negative,0);
});
test('semana em andamento e dia atual não são fechados como débito',()=>{
 const result=P.summarize(person,punches([468]),[{inicio:'2026-10-26',fim:'2026-10-26',sucesso:true}],{...options,today:'2026-10-26'});
 assert.equal(result.weeks[0].delta,null);assert.equal(result.negative,0);assert.equal(result.days[0].delta,null);
});
test('entrada sem saída ou marcação rejeitada deixa semana para conferência',()=>{
 const marks=punches();marks.pop();const result=P.summarize(person,marks,coverage,options);assert.equal(result.weeks[0].delta,null);
 const other=punches();other[1].situacao='Rejeitado (Auto)';assert.equal(P.summarize(person,other,coverage,options).weeks[0].delta,null);
});
test('ausência de sincronização e histórico anterior à disponibilidade não viram faltas',()=>{
 const result=P.summarize(person,[],[],options);assert.equal(result.possibleAbsences,0);assert.equal(result.negative,0);
 const earlier=P.summarize(person,[],coverage,{...options,availableFrom:'2026-11-01'});assert.equal(earlier.unjustified,0);assert.ok(earlier.justified>0);
});
test('dia de trabalho consultado sem ponto é possível falta, preservando folgas',()=>{
 const observed=[{data_hora:'2026-10-23 09:00:00',entrada_saida:'E',tipo_registro:'A',situacao:'Aprovado (Auto)'}];
 const result=P.summarize(person,observed,coverage,options);assert.equal(result.possibleAbsences,5);assert.equal(result.weeks[0].delta,-44*3600);
 assert.equal(result.days[5].status,'Folga');
});
test('feriado ajusta meta da semana e ponto facultativo não é folga automática',()=>{
 const marks=punches([528,528,528,528,528]).filter(m=>!m.data_hora.startsWith('2026-10-28'));
 const result=P.summarize(person,marks,coverage,{...options,holiday:d=>d==='2026-10-28'?{scope:'brasil',name:'Feriado teste'}:null});
 assert.equal(result.weeks[0].expected,4*528*60);assert.equal(result.weeks[0].delta,0);
 const facultativo=P.summarize(person,marks,coverage,{...options,holiday:d=>d==='2026-10-28'?{scope:'facultativo',name:'Facultativo'}:null});assert.equal(facultativo.weeks[0].expected,44*3600);
});
test('semana que cruza o corte usa dias de contexto e não soma saldo duas vezes',()=>{
 const r=P.summarize(person,punches(),coverage,{...options,start:'2026-10-27'});assert.equal(r.days[0].date,'2026-10-27');assert.equal(r.weeks[0].delta,0);assert.equal(r.weeks[0].worked,44*3600);
 const previous=P.summarize(person,punches(),coverage,{...options,start:'2026-09-26',end:'2026-10-25'});assert.equal(previous.weeks.some(w=>w.end==='2026-11-01'),false);
});
test('a jornada individual prevalece sobre o padrão de 44h',()=>{
 const r=P.summarize(person,punches([480,480,480,480,480]),coverage,{...options,override:{minutos_dia:480,minutos_semana:2400,dias:[1,2,3,4,5]}});assert.equal(r.weeks[0].delta,0);
});

test('dias anteriores ao corte sem marcação ficam justificados e não geram débito',()=>{
 const r=P.summarize(person,[],[],{...options,start:'2026-09-26',end:'2026-10-25'});
 assert.ok(r.justified>0);assert.equal(r.unjustified,0);assert.equal(r.negative,0);
 assert.equal(r.days.find(d=>d.date==='2026-10-01').historical,true);
});
test('justificativa com abono retira o débito semanal e mantém histórico de ponto',()=>{
 const marks=punches([528,528,528,528,528]).filter(m=>!m.data_hora.startsWith('2026-10-28'));
 const r=P.summarize(person,marks,coverage,{...options,occurrences:[{dia:'2026-10-28',classificacao:'justificada',abonar:true,motivo:'Atestado'}]});
 assert.equal(r.justified,1);assert.equal(r.unjustified,0);assert.equal(r.weeks[0].delta,0);assert.equal(r.weeks[0].expected,4*528*60);
});
test('justificativa sem abono não elimina horas negativas e hoje não vira falta',()=>{
 const marks=punches([528,528,528,528,528]).filter(m=>!m.data_hora.startsWith('2026-10-28'));
 const r=P.summarize(person,marks,coverage,{...options,occurrences:[{dia:'2026-10-28',classificacao:'justificada',abonar:false,motivo:'Justificada sem abono'}]});
 assert.equal(r.justified,1);assert.equal(r.weeks[0].delta,-528*60);
 assert.equal(P.summarize(person,[],coverage,{...options,today:'2026-10-26'}).unjustified,0);
});
