const {test}=require('node:test'),assert=require('node:assert/strict'),F=require('../assets/js/rh-ponto-fichas-core.js'),fs=require('node:fs'),vm=require('node:vm');
test('anexo usa o mesmo PDF do painel, sem senha e sem URL pública',async()=>{
 const {sheetFile,holiday}=await import('../supabase/functions/admin-notifications/sheet-file.mjs');
 const sheet={month:'2026-12',employee:{nome:'Teste da Silva',funcao:'Promotor',cpf:'00124876510'},company:{nome:'Empresa de teste',cnpj:'52522019000100'},city:'Jequié'};
 const file=sheetFile(sheet),bytes=Buffer.from(file.data,'base64');
 assert.equal(file.mimetype,'application/pdf');assert.equal(file.url,undefined);assert.equal(file.filename,'Ficha_Ponto_2026-12.pdf');
 assert.deepEqual(bytes,Buffer.from(F.pdf({month:sheet.month,sheets:[sheet],holiday})));
 assert.ok(!bytes.includes(Buffer.from('/Encrypt')));assert.ok(bytes.includes(Buffer.from('/Count 1')));
});
test('calendário do servidor corresponde ao painel por vários anos',async()=>{
 const root={},doc={readyState:'loading',addEventListener(){}};
 vm.runInNewContext(fs.readFileSync(require.resolve('../assets/js/rh-holidays.js'),'utf8'),{window:root,document:doc,Date});
 const {holiday}=await import('../supabase/functions/admin-notifications/sheet-file.mjs');
 for(let y=2026;y<=2032;y++)for(let d=new Date(Date.UTC(y,0,1));d.getUTCFullYear()===y;d.setUTCDate(d.getUTCDate()+1)){
  const date=d.toISOString().slice(0,10),ui=root.RHHolidays.getHoliday(date);
  assert.equal(holiday(date)?.name,ui?.scope==='facultativo'?undefined:ui?.name,date);
 }
});
test('fluxo valida capacidade antes do WhatsApp e separa anexos de lembretes',()=>{
 const flow=require('../n8n/ponto-fichas.json');assert.deepEqual(flow.pinData,{});
 assert.equal(flow.connections['Obter evento autorizado'].main[0][0].node,'Consultar autorização');
 assert.equal(flow.connections['Consultar autorização'].main[0][0].node,'Ler resposta do administrador');
 assert.equal(flow.connections['Consultar autorização'].main[1][0].node,'Tem ficha PDF');
 const gate=flow.connections['Tem ficha PDF'].main;assert.equal(gate[0][0].node,'Enviar ficha PDF');assert.equal(gate[1][0].node,'Enviar lembrete');
 for(const name of ['Enviar ficha PDF','Enviar lembrete'])assert.equal(flow.connections[name].main[0][0].node,'Registrar resultado');
 assert.equal(flow.settings.saveDataSuccessExecution,'none');
 assert.ok(flow.nodes.find(n=>n.name==='Registrar resultado').parameters.jsonBody.includes('uncertain'));
});
