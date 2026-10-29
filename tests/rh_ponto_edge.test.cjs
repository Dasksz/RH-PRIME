const test=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs'),vm=require('node:vm'),{stripTypeScriptTypes}=require('node:module');
const source=stripTypeScriptTypes(fs.readFileSync(require('node:path').join(__dirname,'../supabase/functions/ponto-sync/index.ts'),'utf8'));
const employee='11111111-1111-4111-8111-111111111111',user='22222222-2222-4222-8222-222222222222';
function env({admin=true,response=[],providerStatus=200}={}){
 let handler;const calls=[],saved=[];
 const context=vm.createContext({Deno:{env:{get:key=>({SUPABASE_URL:'https://test.supabase.co',SUPABASE_PUBLISHABLE_KEYS:'{"default":"sb_publishable_test"}',SUPABASE_SECRET_KEYS:'{"default":"sb_secret_test"}'}[key])},serve:fn=>handler=fn},Request,Response,AbortSignal,URLSearchParams,Intl,Date,fetch:async(url,opts={})=>{
  calls.push(String(url));
  if(url.includes('/auth/v1/user'))return Response.json({id:user});
  if(url.includes('/profiles?'))return Response.json([{status:admin?'admin':'aprovado'}]);
  if(url.includes('funcionarios_epi?'))return Response.json([{id:employee,cpf:'012.345.678-90'}]);
  if(url.endsWith('rpc/rh_ponto_segredos'))return Response.json({rh_facilita_empresa:'000000',rh_facilita_senha_sha1:'fake-private-value'});
  if(url.includes('api.facilitaponto.com.br'))return new Response(JSON.stringify(response),{status:providerStatus});
  if(url.endsWith('rpc/rh_ponto_salvar_consulta')){saved.push(JSON.parse(opts.body));return Response.json(1);}
  throw Error('URL inesperada');
 }});vm.runInContext(source,context);
 const request=(body={inicio:'2020-01-01',fim:'2020-01-02',funcionarios:[employee]},authorization=true)=>new Request('https://test/edge',{method:'POST',headers:{'Content-Type':'application/json',...(authorization?{Authorization:'Bearer eyJfake.fake.fake'}:{})},body:JSON.stringify(body)});
 return {handler:()=>handler,calls,saved,request};
}
test('sem sessão ou sem administrador não lê credenciais nem chama fornecedor',async()=>{
 const a=env();assert.equal((await a.handler()(a.request(undefined,false))).status,401);assert.equal(a.calls.length,0);
 const b=env({admin:false});assert.equal((await b.handler()(b.request())).status,403);assert.equal(b.calls.some(u=>u.includes('segredos')||u.includes('facilitaponto')),false);
});
test('retorna apenas resumo e persiste marcações no banco com CPF de 11 dígitos',async()=>{
 const e=env({response:[{data_hora:'2020-01-01 08:00:00',entrada_saida:'E',tipo_registro:'A',situacao:'Aprovado (Auto)',obs:null}]});
 const r=await e.handler()(e.request()),body=await r.text();assert.equal(r.status,200);assert.equal(e.saved.length,1);assert.equal(e.saved[0].p_registros.length,1);
 assert.ok(e.calls.find(u=>u.includes('facilitaponto')).includes('matricula=01234567890'));assert.doesNotMatch(body,/fake-private-value|senha_integracao|data_hora|01234567890/);
});
test('resposta fora do contrato registra erro e não substitui dados anteriores',async()=>{
 const e=env({response:[{data_hora:'2020-01-01 08:00:00',entrada_saida:'E',tipo_registro:'A',situacao:'Desconhecido'}]});await e.handler()(e.request());assert.equal(e.saved[0].p_registros,null);assert.match(e.saved[0].p_erro,/contrato/);
});
test('falha HTTP do fornecedor registra consulta sem apagar dados',async()=>{
 const e=env({providerStatus:401});await e.handler()(e.request());assert.equal(e.saved[0].p_registros,null);assert.match(e.saved[0].p_erro,/HTTP 401/);
});
test('bloqueia períodos e IDs inválidos antes de ler credenciais',async()=>{
 const e=env();const r=await e.handler()(e.request({inicio:'2020-02-31',fim:'2020-03-02',funcionarios:[employee]}));assert.equal(r.status,400);assert.equal(e.calls.some(u=>u.includes('segredos')),false);
});
