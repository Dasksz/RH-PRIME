const test=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs'),vm=require('node:vm'),core=require('../rh-documentos-core');
const people=[{id:'a',nome:'ANA MARIA SILVA',cpf:'52998224725',whatsapp:'11999999999'},{id:'b',nome:'BRUNO JOSE SANTOS',cpf:'11144477735',whatsapp:'21999999999'}];
test('identifica CPF com pontuacao',()=>assert.equal(core.identify('CPF 529.982.247-25',people).id,'a'));
test('nome sem CPF e unico',()=>assert.equal(core.identify('Ana Maria Silva',people).id,'a'));
test('CPF desconhecido nao usa nome como fallback',()=>assert.throws(()=>core.identify('ANA MARIA SILVA 123.456.789-09',people)));
test('bloqueia documento com dois CPFs',()=>assert.throws(()=>core.identify('52998224725 11144477735',people)));
test('bloqueia desligado',()=>assert.throws(()=>core.identify('ANA MARIA SILVA',[{...people[0],data_desligamento:'2026-01-01'}])));
test('bloqueia nomes duplicados',()=>assert.throws(()=>core.identify('ANA MARIA SILVA',[people[0],{...people[0],id:'c'}])));
test('telefone nao inventa digitos',()=>assert.equal(core.phone('11 99999-9999'),'5511999999999'));
test('telefone invalido bloqueado',()=>assert.throws(()=>core.phone('123')));
test('modelo nao executa campos desconhecidos',()=>assert.throws(()=>core.message('Olá {senha}',{})));
const ctx=vm.createContext({});vm.runInContext(fs.readFileSync(require('node:path').join(__dirname,'../RH_Documentos_N8N.gs'),'utf8'),ctx);
test('intervalo normal 15 a 25 segundos',()=>{assert.equal(ctx.intervaloMensagemRH(1,()=>0),15);assert.equal(ctx.intervaloMensagemRH(4,()=>.999),25);});
test('pausa apos cinco mensagens 45 a 90 segundos',()=>{assert.equal(ctx.intervaloMensagemRH(5,()=>0),45);assert.equal(ctx.intervaloMensagemRH(10,()=>.999),90);});
test('lista inclui somente falha conhecida e registros legados',()=>{
 const error='Configure webhook HTTPS e token de autenticação nas propriedades do Apps Script';
 assert.equal(core.retryableDelivery({status:'uncertain',error}),true);
 assert.equal(core.retryableDelivery({status:'failed',error:'N8N_CONFIG_MISSING: '+error}),true);
 for(const status of ['ready','queued','sending','accepted','cancelled'])assert.equal(core.retryableDelivery({status,error}),false);
 for(const error of [null,'Sem confirmação do n8n. Confira a execução antes de reenviar.','n8n não confirmou o documento (HTTP 500). Confira a execução.'])assert.equal(core.retryableDelivery({status:'uncertain',error}),false);
});
function sendingEnvironment(props,fetch){
 const updates=[],c=vm.createContext({PropertiesService:{getScriptProperties:()=>({getProperty:k=>props[k]})},UrlFetchApp:{fetch},LockService:{getScriptLock:()=>({tryLock:()=>true,releaseLock:()=>{}})}});
 vm.runInContext(fs.readFileSync(require('node:path').join(__dirname,'../RH_Documentos_N8N.gs'),'utf8'),c);
 c.bancoDocumentosRH=(resource)=>resource==='funcionarios_epi'?[{whatsapp:'11999999999'}]:[];
 c.atualizarDocumentoRH=(_,change)=>updates.push(change);
 return {c,updates};
}
const approved={id:'test',phone:'5511999999999',approved_at:'2026-10-05',message_text:'PDF https://example.com',link:'https://example.com'};
test('configuracao invalida nunca chama o webhook',()=>{
 for(const props of [{},{N8N_RH_WEBHOOK_URL:'http://private/webhook/rh',N8N_RH_TOKEN:'token'},{N8N_RH_WEBHOOK_URL:'https://example.com/webhook/rh',N8N_RH_TOKEN:' '}]){
  let called=false;const {c}=sendingEnvironment(props,()=>{called=true;});
  assert.throws(()=>c.enviarDocumentoN8NRH(approved),e=>e.code==='N8N_CONFIG_MISSING');assert.equal(called,false);
 }
});
test('timeout continua incerto e nao entra na lista',()=>{
 const {c,updates}=sendingEnvironment({N8N_RH_WEBHOOK_URL:'https://example.com/webhook/rh',N8N_RH_TOKEN:'token'},()=>{throw Error('timeout');});
 assert.equal(c.enviarDocumentoN8NRH(approved),false);assert.equal(updates[0].status,'uncertain');assert.equal(core.retryableDelivery(updates[0]),false);
});
test('processador pausa envio apos primeira falha de configuracao',()=>{
 const {c,updates}=sendingEnvironment({},()=>{throw Error('Não deveria chamar');});let claims=0,paused=false;
 c.validarRaizesDriveRH=()=>{};c.limparCopiasConfirmadasRH=()=>{};
 c.bancoDocumentosRH=(resource,method,query,body)=>{
  if(resource==='funcionarios_epi')return [{whatsapp:'11999999999'}];
  if(resource==='rh_automation_settings'){if(method==='patch'&&body.n8n_enabled===false)paused=true;return [{documents_enabled:true,n8n_enabled:true,messages_count:0}];}
  if(resource==='rpc/rh_claim_document'&&body.p_send){claims++;return [approved];}return [];
 };
 c.processarDocumentosWebRH();assert.equal(claims,1);assert.equal(paused,true);assert.equal(updates[0].status,'failed');assert.equal(core.retryableDelivery(updates[0]),true);
});
