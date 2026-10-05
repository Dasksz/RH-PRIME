const test=require('node:test'),assert=require('node:assert/strict'),vm=require('node:vm'),fs=require('node:fs');
const employee={id:'employee1',nome:'ANA MARIA SILVA',cpf:'52998224725'};
const settings={active_folder_id:'active',former_folder_id:'former',template_folder_id:'template'};
function setup(folders,job={}){
 const calls=[],ctx=vm.createContext({});vm.runInContext(fs.readFileSync(require.resolve('../RH_Drive_Automacoes.gs'),'utf8'),ctx);
 const full={id:'job1',funcionario_id:employee.id,revision:1,claimed_revision:1,...job};
 ctx.bancoDriveRH=(r,m,q,b)=>{calls.push({r,m,b});if(r==='funcionarios_epi')return [employee];if(r==='rpc/rh_request_folder_choice')return true;return [];};
 ctx.filhosDriveRH=id=>id==='active'?folders:[];
 ctx.apiDriveRH=(p,m,b)=>{calls.push({p,m,b});if(p==='files')return {id:'newfolder1',name:b.name,parents:['active'],appProperties:b.appProperties};return {};};
 ctx.copiarModeloDriveRH=()=>calls.push({copy:true});ctx.pastaDriveRH=id=>({id,parents:['active']});
 return {calls,run:()=>ctx.executarTarefaDriveRH(full,settings,Date.now()+10000)};
}
const folder={id:'oldfolder1',name:'ANA MARIA SILVA',mimeType:'application/vnd.google-apps.folder',parents:['active']};
test('pasta compatível aguarda decisão sem criar, vincular ou mover',()=>{const {run,calls}=setup([folder]);run();assert(calls.some(c=>c.r==='rpc/rh_request_folder_choice'));assert(!calls.some(c=>c.p||c.r==='rh_drive_links'&&c.m==='post'));});
test('homônimos são apresentados para escolha',()=>{const {run,calls}=setup([folder,{...folder,id:'otherfolder1'}]);run();assert.equal(calls.find(c=>c.r==='rpc/rh_request_folder_choice').b.p_candidates.length,2);});
test('escolha de usar conserva a pasta e não copia o modelo',()=>{const {run,calls}=setup([folder],{folder_choice:folder.id,choice_revision:1,folder_employee:employee});run();assert.equal(calls.find(c=>c.r==='rh_drive_links'&&c.m==='post').b.folder_id,folder.id);assert(!calls.some(c=>c.copy||c.p==='files'));});
test('criar outra preserva a antiga e copia o modelo para nova',()=>{const {run,calls}=setup([folder],{folder_choice:'new',choice_revision:1,folder_employee:employee});run();assert(calls.some(c=>c.p==='files'&&c.m==='post'));assert(calls.some(c=>c.copy));assert(!calls.some(c=>c.p==='files/'+folder.id));});
test('pasta selecionada removida não gera substituta',()=>{const {run,calls}=setup([],{folder_choice:folder.id,choice_revision:1,folder_employee:employee});assert.throws(run,/Pasta escolhida mudou/);assert(!calls.some(c=>c.p));});
test('nome alterado invalida a escolha antes de mutação',()=>{const {run,calls}=setup([folder],{folder_choice:folder.id,choice_revision:1,folder_employee:{...employee,nome:'OUTRA PESSOA'}});assert.throws(run,/Nome ou CPF mudou/);assert(!calls.some(c=>c.p));});
test('retomada de nova pasta usa marcador e não duplica',()=>{const recovered={...folder,id:'newfolder1',appProperties:{rh_employee_id:employee.id,rh_new_template:'yes',rh_choice_job:'job1',rh_choice_revision:'1'}};const {run,calls}=setup([folder,recovered],{folder_choice:'new',choice_revision:1,folder_employee:employee});run();assert(!calls.some(c=>c.p==='files'));assert.equal(calls.find(c=>c.r==='rh_drive_links'&&c.m==='post').b.folder_id,'newfolder1');});
