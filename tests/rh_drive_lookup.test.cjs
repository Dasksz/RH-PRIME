const test=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs'),vm=require('node:vm'),path=require('node:path');
const employee={id:'11111111-1111-1111-1111-111111111111',nome:'José da Silva',cpf:'12345678901'},userId='22222222-2222-2222-2222-222222222222';
const query={employee_id:employee.id,access_token:'eyJ.test.signature'};
function env({admin=true,authenticated=true,folders=[],linked}={}){
 const calls=[],c=vm.createContext({propriedadesRH:()=>({getProperty:k=>({SUPABASE_URL:'https://example.supabase.co',SUPABASE_KEY:'sb_secret_test_only'})[k]}),UrlFetchApp:{fetch:(url,options)=>{calls.push({url,options});return {getResponseCode:()=>url.includes('/auth/')&&!authenticated?401:200,getContentText:()=>JSON.stringify(url.includes('/auth/')?{id:userId}:[{status:admin?'admin':'aprovado'}])};}}});
 vm.runInContext(fs.readFileSync(path.join(__dirname,'../RH_Drive_Automacoes.gs'),'utf8'),c);
 vm.runInContext(fs.readFileSync(path.join(__dirname,'../RH_Drive_Busca.gs'),'utf8'),c);
 c.bancoDriveRH=(resource,method)=>{assert.equal(method,'get');calls.push({resource});if(resource==='funcionarios_epi')return [employee];if(resource==='rh_automation_settings')return [{active_folder_id:'active-root',former_folder_id:'former-root'}];if(resource==='rh_drive_links')return linked?[{folder_id:linked}]:[];throw Error('Mutação inesperada');};
 c.filhosDriveRH=id=>{calls.push({root:id});return folders.filter(f=>f.parents.includes(id));};
 return {c,calls};
}
const folder=(id,name='JOSE DA SILVA',owner)=>({id,name,mimeType:'application/vnd.google-apps.folder',parents:['active-root'],appProperties:owner?{rh_employee_id:owner}:{}});
test('busca pasta existente por nome normalizado, sem escrita',()=>{
 const {c,calls}=env({folders:[folder('folder-auto-1')]});const r=c.buscarPastaColaboradorRH(query);assert.equal(r.folders.length,1);assert.equal(r.folders[0].id,'folder-auto-1');assert.equal(r.employee_id,employee.id);assert.ok(calls.filter(x=>x.options).every(x=>!x.options.method||x.options.method==='get'));
});
test('retorna todas as homônimas para escolha, sem selecionar a primeira',()=>{const {c}=env({folders:[folder('folder-auto-1'),folder('folder-auto-2')]});assert.equal(c.buscarPastaColaboradorRH(query).folders.length,2);});
test('nenhuma correspondência não cria pasta',()=>{const {c}=env();assert.equal(c.buscarPastaColaboradorRH(query).folders.length,0);});
test('CPF divergente e vínculo a outro colaborador não são candidatos',()=>{const {c}=env({folders:[folder('folder-auto-1','JOSE DA SILVA 999.999.999-99'),folder('folder-auto-2','JOSE DA SILVA','outro')]});assert.equal(c.buscarPastaColaboradorRH(query).folders.length,0);});
test('pasta vinculada válida tem prioridade',()=>{const {c}=env({folders:[folder('folder-auto-1','Nome antigo'),folder('folder-auto-2')],linked:'folder-auto-1'});const r=c.buscarPastaColaboradorRH(query);assert.equal(r.folders.length,1);assert.equal(r.folders[0].id,'folder-auto-1');assert.equal(r.folders[0].linked,true);});
test('usuário não administrador não chega ao banco de colaboradores ou Drive',()=>{const {c,calls}=env({admin:false});assert.throws(()=>c.buscarPastaColaboradorRH(query),/administrador/);assert.ok(calls.every(x=>!x.resource&&!x.root));});
test('sessão inválida bloqueia antes de consultar perfil ou Drive',()=>{const {c,calls}=env({authenticated:false});assert.throws(()=>c.buscarPastaColaboradorRH(query),/Sessão inválida/);assert.equal(calls.length,1);});
