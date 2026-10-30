const {test}=require('node:test'),assert=require('node:assert/strict'),P=require('../assets/js/rh-ponto-core.js');
test('verificação tira alerta da contagem e reabre se ponto ou jornada mudar',()=>{
 const day={date:'2026-10-26',punches:[{data_hora:'2026-10-26 08:00:00',entrada_saida:'E',situacao:'Aprovado (Auto)'}],expected:31680,worked:0,delta:null,covered:true,credit:0,status:'Conferir',warnings:['Entrada sem saída; jornada incompleta'],employed:true};
 const s={employee:{id:'a'},days:[day]},record={funcionario_id:'a',dia:day.date,assinatura:P.reviewSignature(day),verificado_em:'2026-10-30T12:00:00Z',responsavel:'RH'};
 P.applyVerifications(s,[record]);assert.equal(s.reviewCount,0);assert.equal(day.verification.responsavel,'RH');
 day.punches[0].data_hora='2026-10-26 08:05:00';P.applyVerifications(s,[record]);assert.equal(s.reviewCount,1);assert.equal(day.verification,null);
 day.punches[0].data_hora='2026-10-26 08:00:00';day.expected=30000;P.applyVerifications(s,[record]);assert.equal(s.reviewCount,1);
});
