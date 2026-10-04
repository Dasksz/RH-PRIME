// Sem chamadas de rede: simula Sheets, PropertiesService e a API REST.
const fs = require('node:fs');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const source = fs.readFileSync(process.argv[2] || 'google_apps_script_atualizado.js','utf8');
let checks = 0;
function test(name, fn) { fn(); checks++; console.log('OK ' + name); }
function environment() {
  const db = {}, sheets = {}, requests = [];
  const props = { SUPABASE_URL: 'https://example.supabase.co', SUPABASE_KEY: 'test-only', SPREADSHEET_ID: 'test-sheet' };
  const ss = { getId: ()=>'test-sheet', getSheetByName: name=>sheets[name], toast:()=>{} };
  class Sheet {
    constructor(name, rows) { this.name=name; this.rows=rows.map(r=>r.slice()); sheets[name]=this; this.maxColumns=40; }
    getName(){return this.name;} getParent(){return ss;}
    getLastRow(){return this.rows.length;}
    getLastColumn(){return Math.max(1,...this.rows.map(r=>r.length));}
    getMaxColumns(){return this.maxColumns;}
    insertColumnsAfter(n,count){this.maxColumns+=count;}
    getRange(row,col,n=1,m=1){
      const self=this;
      return {
        getValues:()=>Array.from({length:n},(_,i)=>Array.from({length:m},(_,j)=>self.rows[row+i-1]?.[col+j-1] ?? '')),
        setValue(value){self.rows[row-1] ??=[]; self.rows[row-1][col-1]=value; return this;},
        setValues(values){values.forEach((items,i)=>items.forEach((v,j)=>{self.rows[row+i-1] ??=[];self.rows[row+i-1][col+j-1]=v;}));return this;},
        setNumberFormat(){return this;}
      };
    }
    deleteRow(row){this.rows.splice(row-1,1);}
  }
  const ctx={
    console:{error:()=>{}},
    PropertiesService:{getScriptProperties:()=>({getProperty:k=>props[k],setProperty:(k,v)=>props[k]=v})},
    SpreadsheetApp:{openById:()=>ss},
    LockService:{getScriptLock:()=>({tryLock:()=>true,releaseLock:()=>{}})},
    Utilities:{formatDate:(d,tz,fmt)=>d.toISOString().slice(0,10)},
    ContentService:{MimeType:{JSON:'json'},createTextOutput:t=>({setMimeType:()=>JSON.parse(t)})},
    UrlFetchApp:{fetch:(url,options)=>{
      requests.push({url,options});
      const parsed = new URL(url), table=parsed.pathname.split('/').pop();
      const filter=[...parsed.searchParams].find(([k,v])=>v.startsWith('eq.'));
      const found=(db[table] || []).filter(r=>!filter || String(r[filter[0]]) === filter[1].slice(3));
      let result;
      if(options.method==='get') result=found;
      else if(options.method==='patch'){const payload=JSON.parse(options.payload);found.forEach(r=>Object.assign(r,payload));result=found;}
      else if(options.method==='post'){result=JSON.parse(options.payload).map((r,i)=>({...r,id:100+i}));db[table] ??=[];db[table].push(...result);}
      else throw new Error('Operação inesperada');
      return {getResponseCode:()=>200,getContentText:()=>JSON.stringify(result)};
    }}
  };
  vm.createContext(ctx); vm.runInContext(source,ctx);
  const config=vm.runInContext('SHEET_CONFIG',ctx);
  return {ctx,config,db,sheets,requests,Sheet,props};
}
test('horas manuais permanecem 2h',()=>{
  const {ctx}=environment();
  assert.equal(ctx.buildPayload('absenteismo',[9,'TESTE','2026-10-01','2026-10-01',220,2,'Consulta','12345678901',220]).horas_perdidas,2);
});
test('zero informado permanece zero',()=>{
  const {ctx}=environment();
  assert.equal(ctx.buildPayload('absenteismo',[9,'TESTE','2026-10-01','2026-10-01',220,0,'Consulta','12345678901',220]).horas_perdidas,0);
});
test('horas em branco recebem estimativa',()=>{
  const {ctx}=environment();
  assert.equal(ctx.buildPayload('absenteismo',[9,'TESTE','2026-10-01','2026-10-01',220,'','Consulta','12345678901',220]).horas_perdidas,8);
});
test('limpeza do desligamento envia null',()=>{
  const {ctx}=environment();assert.equal(ctx.buildPayload('movimentacoes',['TESTE','2025-01-01','','','12345678901']).data_desligamento,null);
});
test('CPF inválido não segue para banco',()=>{
  const {ctx}=environment();assert.throws(()=>ctx.buildPayload('ferias',['TESTE','2025-01-01','2025-12-31','2026-11-30',30,0,'pendente',0,30]),/CPF/);
});
test('datas inexistentes são rejeitadas',()=>{
  const {ctx}=environment();assert.throws(()=>ctx.formatarData('31/02/2026'),/inexistente/);assert.equal(ctx.formatarData('29/02/2024'),'2024-02-29');
});
test('intervalo invertido é rejeitado',()=>{
  const {ctx}=environment();assert.throws(()=>ctx.buildPayload('absenteismo',[9,'TESTE','2026-10-02','2026-10-01',220,2,'Consulta','12345678901',220]),/anterior/);
});
test('horas proporcionais consideram carga de 110h',()=>{
  const {ctx}=environment();assert.equal(ctx.calcularHorasUteis('2026-10-01','2026-10-03',110),10);
});
test('dias_saldo e histórico não são enviados para escrita',()=>{
  const {ctx}=environment();const p=ctx.buildPayload('ferias',{funcionario_nome:'TESTE',cpf:'12345678901',dias_saldo:30,historico_periodos:'[]'});assert.equal('dias_saldo' in p,false);assert.equal('historico_periodos' in p,false);
});
test('segundo cabeçalho de EPI é reconhecido',()=>{
  const {ctx,config,Sheet}=environment();const sheet=new Sheet('epi_funcao',[['','EPI'],['Função','CAPACETE'],['MOTORISTA','SIM']]);const map=ctx.layoutRH(sheet,config.epi_funcao,false);assert.equal(map.funcao,1);assert.equal(map.capacete,2);assert.throws(()=>ctx.buildPayload('epi_funcao',['Função','CAPACETE']),/EPI deve ser|cabeçalho/);
});
function webhook(env,event){return env.ctx.doPost({postData:{contents:JSON.stringify({...event,schema:'public'})},parameter:{}});}
test('DELETE de falta usa id do old_record e preserva outra falta',()=>{
  const env=environment();const c=env.config.absenteismo;
  const headers=c.fields.concat(c.extra);const sheet=new env.Sheet('absenteismo',[headers,[1,'TESTE','2026-10-01','2026-10-01',220,2,'Consulta','12345678901',220],[2,'TESTE','2026-10-02','2026-10-02',220,4,'Consulta','12345678901',220]]);
  env.db.rh_absenteismo=[{id:1}];
  const r=webhook(env,{type:'DELETE',table:'rh_absenteismo',record:null,old_record:{id:2,funcionario_nome:'TESTE'}});
  assert.equal(r.action,'deleted');assert.equal(sheet.rows.length,2);assert.equal(sheet.rows[1][0],1);
});
test('DELETE de EPI remove a linha pelo old_record',()=>{
  const env=environment();const headers=env.config['Controle EPI e Fardamento'].fields.slice();headers[23]='id';const row=[];row[1]='TESTE';row[2]='12345678901';row[23]='uuid-1';const sheet=new env.Sheet('Controle EPI e Fardamento',[headers,row]);
  const r=webhook(env,{type:'DELETE',table:'funcionarios_epi',record:null,old_record:{id:'uuid-1',nome:'TESTE',cpf:'12345678901'}});
  assert.equal(r.action,'deleted');assert.equal(sheet.rows.length,1);
});
test('rename usa id e não acrescenta linha',()=>{
  const env=environment();const sheet=new env.Sheet('movimentacoes',[env.config.movimentacoes.fields.concat(['id']),['ANTIGO','2025-01-01','','','12345678901',7]]);
  env.db.rh_movimentacoes=[{id:7,funcionario_nome:'NOVO',cpf:'12345678901'}];
  const r=webhook(env,{type:'UPDATE',table:'rh_movimentacoes',record:{id:7,funcionario_nome:'NOVO'},old_record:{id:7,funcionario_nome:'ANTIGO'}});
  assert.equal(r.action,'updated');assert.equal(sheet.rows.length,2);assert.equal(sheet.rows[1][0],'NOVO');
});
test('evento atrasado recebe estado mais recente do banco',()=>{
  const env=environment();const sheet=new env.Sheet('movimentacoes',[env.config.movimentacoes.fields.concat(['id']),['TESTE','2025-01-01','','','12345678901',7]]);env.db.rh_movimentacoes=[{id:7,funcionario_nome:'ATUAL',cpf:'12345678901'}];
  webhook(env,{type:'UPDATE',table:'rh_movimentacoes',record:{id:7,funcionario_nome:'ANTIGO'},old_record:{id:7}});assert.equal(sheet.rows[1][0],'ATUAL');
});
test('nova linha de EPI e CNPJ ficam na mesma linha',()=>{
  const env=environment();const headers=env.config['Controle EPI e Fardamento'].fields.slice();headers[23]='id';const sheet=new env.Sheet('Controle EPI e Fardamento',[headers]);env.db.funcionarios_epi=[{id:'uuid-1',cpf:'12345678901',nome:'TESTE',local_registro:'NUNES & VIEIRA LOGISTICA LTDA'}];
  webhook(env,{type:'INSERT',table:'funcionarios_epi',record:{id:'uuid-1'}});assert.equal(sheet.rows.length,2);assert.equal(sheet.rows[1][1],'TESTE');assert.equal(sheet.rows[1][22],'48.986.353/0001-39');
});
test('CPF em texto preserva zero inicial',()=>{
  const {ctx}=environment();assert.equal(ctx.formatoCpfRH('00138376565'),'00138376565');
});
test('patch sem mudanças não dispara novo webhook',()=>{
  const env=environment();env.db.rh_movimentacoes=[{id:7,funcionario_nome:'TESTE',cpf:'12345678901'}];env.ctx.upsertRecord('rh_movimentacoes','funcionario_nome',{id:7,funcionario_nome:'TESTE',cpf:'12345678901'});assert.equal(env.requests.filter(r=>r.options.method==='patch').length,0);
});
test('identidade ambígua não sobrescreve primeira ocorrência',()=>{
  const env=environment();env.db.rh_movimentacoes=[{id:1,funcionario_nome:'TESTE'},{id:2,funcionario_nome:'TESTE'}];assert.throws(()=>env.ctx.upsertRecord('rh_movimentacoes','funcionario_nome',{funcionario_nome:'TESTE'}),/Mais de um/);
});
test('registro excluído não é recriado por planilha desatualizada',()=>{
  const env=environment();assert.throws(()=>env.ctx.upsertRecord('rh_movimentacoes','funcionario_nome',{id:7,funcionario_nome:'TESTE'}),/não encontrado/);assert.equal(env.requests.filter(r=>r.options.method==='post').length,0);
});
test('colagem em duas linhas grava ambas',()=>{
  const env=environment();const sheet=new env.Sheet('movimentacoes',[env.config.movimentacoes.fields.concat(['id']),['UM','2025-01-01','','','12345678901',7],['DOIS','2025-01-01','','','10987654321',8]]);env.db.rh_movimentacoes=[{id:7,funcionario_nome:'UM ANTIGO',cpf:'12345678901'},{id:8,funcionario_nome:'DOIS ANTIGO',cpf:'10987654321'}];
  env.ctx.syncToSupabaseOnEdit({range:{getSheet:()=>sheet,getRow:()=>2,getLastRow:()=>3,getColumn:()=>1,getLastColumn:()=>1}});
  assert.equal(env.db.rh_movimentacoes[0].funcionario_nome,'UM');assert.equal(env.db.rh_movimentacoes[1].funcionario_nome,'DOIS');
});
test('token configurado rejeita webhook sem autenticação',()=>{
  const env=environment();env.props.WEBHOOK_TOKEN='test-token';assert.equal(webhook(env,{type:'INSERT',table:'empresas',record:{id:1}}).status,'error');assert.equal(env.requests.length,0);
});
test('colunas auxiliares permanecem intactas',()=>{
  const env=environment();const headers=env.config.movimentacoes.fields.concat(['id','FÓRMULA']);const sheet=new env.Sheet('movimentacoes',[headers,['TESTE','','','','12345678901',7,'=1+1']]);const map=env.ctx.layoutRH(sheet,env.config.movimentacoes,false);env.ctx.escreverRegistroRH(sheet,env.config.movimentacoes,map,2,{id:7,funcionario_nome:'NOVO'});assert.equal(sheet.rows[1][6],'=1+1');
});
test('erros HTTP não viram sucesso silencioso',()=>{
  const env=environment();env.ctx.UrlFetchApp.fetch=()=>({getResponseCode:()=>403,getContentText:()=>'{"message":"permission denied"}'});assert.throws(()=>env.ctx.requestRH('empresas','get',''),/HTTP 403/);
});
console.log(checks + ' verificações concluídas.');
