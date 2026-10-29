const test=require('node:test'),assert=require('node:assert/strict'),S=require('../assets/js/rh-ponto-sync.js');
const windows=[{start:'2026-10-26',end:'2026-10-29'}];
const success=body=>({data:{resultados:body.funcionarios.map(funcionario_id=>({funcionario_id,sucesso:true,quantidade:4}))}});
test('progresso só avança depois da resposta confirmada e consulta em lotes de três',async()=>{
 const events=[],calls=[];const state=await S.run({ids:['a','b','c','d'],windows,invoke:async body=>{calls.push(body);return success(body);},onProgress:p=>events.push({...p})});
 assert.equal(events[0].done,0);assert.deepEqual(events.filter(e=>e.phase==='querying').map(e=>e.done),[0,3]);assert.deepEqual(events.filter(e=>e.phase==='received').map(e=>e.done),[3,4]);assert.deepEqual(calls.map(c=>c.funcionarios.length),[3,1]);assert.equal(state.success,4);assert.equal(state.done,state.total);
});
test('falha de colaborador é listada sem impedir os próximos lotes',async()=>{
 const state=await S.run({ids:['a','b','c','d'],windows,invoke:async body=>{const response=success(body);if(body.funcionarios.includes('b'))response.data.resultados[1]={funcionario_id:'b',sucesso:false,erro:'Fornecedor indisponível'};return response;}});
 assert.equal(state.success,3);assert.equal(state.failed,1);assert.equal(state.done,4);assert.equal(state.issues[0].id,'b');assert.equal(state.error,undefined);
});
test('falha da chamada interrompe com contagens parciais sem repetir automaticamente',async()=>{
 let calls=0;const state=await S.run({ids:['a','b','c','d','e','f','g'],windows,invoke:async body=>{if(++calls===2)throw Error('Sem conexão');return success(body);}});
 assert.equal(calls,2);assert.equal(state.done,3);assert.equal(state.success,3);assert.equal(state.total-state.done,4);assert.match(state.error,/Sem conexão/);
});
test('tempo limite informa resultado ainda incerto e não chama os próximos colaboradores',async()=>{
 let calls=0;const state=await S.run({ids:['a','b','c','d'],windows,timeoutMs:10,invoke:()=>{calls++;return new Promise(()=>{});}});
 assert.equal(calls,1);assert.equal(state.done,0);assert.match(state.error,/pode ainda concluir no banco/);
});
test('resposta incompleta não contabiliza como sucesso e duração é legível',async()=>{
 const state=await S.run({ids:['a','b'],windows,invoke:async()=>success({funcionarios:['a']})});assert.equal(state.done,0);assert.match(state.error,/não confirmou todos/);assert.equal(S.duration(125),'2min 05s');
});
