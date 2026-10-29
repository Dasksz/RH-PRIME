const test=require('node:test'),assert=require('node:assert/strict'),P=require('../assets/js/rh-ponto-core.js');
const options={start:'2026-10-26',end:'2026-11-25',today:'2026-10-29',availableFrom:'2026-10-26'};
const coverage=[{inicio:'2026-10-26',fim:'2026-10-29',sucesso:true}];
function summary(id,nome,occurrences=[]){return P.summarize({id,nome,admissao:'2020-01-01'},[],coverage,{...options,occurrences});}
test('KPI agrupa ausências por data e mostra cada colaborador uma vez no dia',()=>{
 const groups=P.absenceGroups([summary('a','Zelia'),summary('b','Ana')],'injustificada');
 assert.equal(groups.length,3);assert.equal(groups.reduce((n,g)=>n+g.items.length,0),6);
 assert.deepEqual(groups.map(g=>g.date),['2026-10-28','2026-10-27','2026-10-26']);
 assert.deepEqual(groups[0].items.map(i=>i.employee.nome),['Ana','Zelia']);
 assert.equal(groups.some(g=>g.date==='2026-10-29'),false);
});
test('justificar transfere apenas o colaborador e o dia correspondente entre KPIs',()=>{
 const people=[summary('a','Ana',[{dia:'2026-10-27',classificacao:'justificada',motivo:'Falta justificada pelo RH.',abonar:true}]),summary('b','Bia')];
 assert.equal(P.absenceGroups(people,'injustificada').reduce((n,g)=>n+g.items.length,0),5);
 const justified=P.absenceGroups(people,'justificada');assert.equal(justified.length,1);assert.equal(justified[0].date,'2026-10-27');assert.equal(justified[0].items[0].employee.id,'a');
});
test('agrupamento respeita os colaboradores fornecidos pelos filtros e o estado vazio',()=>{
 assert.equal(P.absenceGroups([summary('b','Bia')],'injustificada')[0].items.length,1);
 assert.deepEqual(P.absenceGroups([],'justificada'),[]);
 const s=P.summarize({id:'a',nome:'Ana'},[],[],options);assert.deepEqual(P.absenceGroups([s],'injustificada'),[]);
});
