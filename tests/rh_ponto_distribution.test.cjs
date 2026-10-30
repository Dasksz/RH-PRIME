const {test}=require('node:test'),assert=require('node:assert/strict'),P=require('../assets/js/rh-ponto-core.js');
const day=(date,delta,extra={})=>({date,delta,warnings:[],...extra});
test('gráfico soma por setor e dia da semana sem misturar débito ou dias sem confirmação',()=>{
 const rows=[{employee:{setor:'ARMAZEM'},days:[day('2026-10-26',3600),day('2026-10-27',-1800),day('2026-10-28',null),day('2026-10-29',900,{warnings:['Entrada incompleta']}),day('2026-10-30',900,{partial:true}),day('2026-10-31',900,{future:true})]},{employee:{setor:'TRANSPORTE'},days:[day('2026-10-26',1800),day('2026-10-27',7200)]}];
 const d=P.distribution(rows);assert.equal(d.total,12600);assert.equal(d.dates,2);assert.equal(d.maximum,7200);assert.equal(d.buckets[0].total,5400);assert.deepEqual(d.buckets[0].sectors,{ARMAZEM:3600,TRANSPORTE:1800});assert.equal(d.buckets[1].total,7200);assert.equal(d.buckets[5].total,0);
 assert.equal(P.distribution(rows.slice(0,1)).total,3600);
});
test('dias repetidos de semanas diferentes somam no gráfico, mas contam datas distintas',()=>{
 const d=P.distribution([{employee:{},days:[day('2026-10-26',60),day('2026-11-02',120),day('2026-11-01',180)]}]);
 assert.equal(d.dates,3);assert.equal(d.buckets[0].total,180);assert.equal(d.buckets[6].total,180);assert.equal(d.total,360);assert.equal(d.buckets[0].sectors['Sem setor'],180);
});
test('sem valores confirmados o gráfico retorna sete grupos zerados',()=>{const d=P.distribution([]);assert.equal(d.total,0);assert.equal(d.maximum,0);assert.equal(d.buckets.length,7);});
