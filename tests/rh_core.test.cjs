const fs=require('node:fs'),vm=require('node:vm'),assert=require('node:assert/strict');
const ctx={window:{},Intl,Date,console,setTimeout,clearTimeout};vm.createContext(ctx);vm.runInContext(fs.readFileSync(process.argv[2]||'rh-core.js','utf8'),ctx);const RH=ctx.window.RH;
const split=RH.absByMonth([{data_inicio:'2026-09-30',data_fim:'2026-10-01',horas_perdidas:2}]);assert.equal(split.length,2);assert.equal(split[0].mes_ref,'09/2026');assert.equal(split[1].mes_ref,'10/2026');assert.equal(split.reduce((s,r)=>s+r.horas_perdidas,0),2);
assert.equal(RH.absByMonth([{data_inicio:'2026-10-04',data_fim:'2026-10-04',horas_perdidas:1}])[0].horas_perdidas,1);
assert.equal(RH.archivePeriod({data_inicio_aquisitivo:'2025-01-01',dias_gozados:10,historico_periodos:[{id:1}]},{dias_gozados:30})[1].dias_gozados,30);
(async()=>{await assert.rejects(RH.result(Promise.resolve({error:new Error('negado')})),/negado/);await assert.rejects(RH.result(Promise.resolve({data:[]}),true),/Nenhum registro/);assert.equal(await RH.result(Promise.resolve({data:[{id:1}]}),true).then(x=>x[0].id),1);console.log('6 verificações de horas, histórico e confirmação de gravação passaram.');})();
