const test=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs'),vm=require('node:vm'),path=require('node:path');
const root=path.join(__dirname,'..');
for(const [file,fn,resource] of [['google_apps_script_atualizado.js','requestRH','funcionarios_epi'],['RH_Drive_Automacoes.gs','bancoDriveRH','rh_automation_settings'],['RH_Documentos_N8N.gs','bancoDocumentosRH','rh_delivery_documents']]){
 test(file+' envia chave moderna apenas em apikey, sem Bearer inválido',()=>{
  const requests=[],props={SUPABASE_KEY:'sb_secret_test_only',SUPABASE_URL:'https://example.supabase.co'};
  const c=vm.createContext({PropertiesService:{getScriptProperties:()=>({getProperty:k=>props[k],setProperty:(k,v)=>props[k]=v})},UrlFetchApp:{fetch:(url,options)=>{requests.push({url,options});return {getResponseCode:()=>200,getContentText:()=>'[]'};}}});
  vm.runInContext(fs.readFileSync(path.join(root,file),'utf8'),c);
  c[fn](resource,'get','select=id&limit=0');
  assert.equal(requests.length,1);assert.equal(requests[0].options.headers.apikey,props.SUPABASE_KEY);assert.equal(requests[0].options.headers.Authorization,undefined);
  props.SUPABASE_KEY='legacy-test-only';c[fn](resource,'get','select=id&limit=0');
  assert.equal(requests[1].options.headers.Authorization,'Bearer legacy-test-only');
 });
}
test('bootstrap nunca restaura chave privilegiada removida',()=>{
 const props={},c=vm.createContext({PropertiesService:{getScriptProperties:()=>({getProperty:k=>props[k],setProperty:(k,v)=>props[k]=v})}});
 vm.runInContext(fs.readFileSync(path.join(root,'google_apps_script_atualizado.js'),'utf8'),c);c.configurarCredenciaisRH();
 assert.equal(props.SUPABASE_KEY,undefined);assert.throws(()=>c.verificarConexaoSupabaseRH(),/sb_secret_/);
});
test('nenhum consumidor público usa a anon legado',()=>{
 for(const file of ['index.html','admin.html','colaboradores.html','login.html','indicadores.html','detalhes_absenteismo.html','automacoes.js','documentos-web.js','ferias.js','desktop/rhprime/config.py','admin-notifications.ts']){
  const s=fs.readFileSync(path.join(root,file),'utf8');assert.match(s,/sb_publishable_/);assert.doesNotMatch(s,/eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+/);assert.doesNotMatch(s,/SUPABASE_ANON_KEY|sb_secret_[A-Za-z0-9]{20}/);
 }
});
