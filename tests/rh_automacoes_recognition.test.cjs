const test=require('node:test'),assert=require('node:assert/strict'),vm=require('node:vm'),fs=require('node:fs');
const source=fs.readFileSync(require.resolve('../automacoes.js'),'utf8');
function env({disabled=false,reject=false,failAt=0}={}){
 const nodes=new Map(),calls=[];
 const node=id=>{if(!nodes.has(id))nodes.set(id,{value:'',textContent:'',hidden:false,classList:{toggle(){}},replaceChildren(){},append(){},addEventListener(){},removeAttribute(){},setAttribute(){},focus(){},scrollIntoView(){}});return nodes.get(id);};
 const settings={drive_enabled:!disabled,drive_worker_version:'folder-choice-v1',last_worker_at:new Date().toISOString()};
 const employees=[{id:'linked',nome:'A'},{id:'queued',nome:'B'},{id:'choice',nome:'C'},{id:'former',nome:'D',data_desligamento:'2026-01-01'},{id:'fresh',nome:'E'},{id:'retry',nome:'F'}];
 const links=[{funcionario_id:'linked',folder_id:'folder12345'}],jobs=[{funcionario_id:'queued',status:'processing'},{funcionario_id:'choice',status:'awaiting_choice'},{funcionario_id:'retry',status:'failed'}];
 const client={from:table=>{const q={select(){return q},order(){return q},limit(){return q},eq(){return q},single(){return q},then(resolve){resolve({data:table==='rh_automation_settings'?settings:[]})}};return q},rpc:async(_,args)=>{calls.push(args.p_employee);return failAt===calls.length?{error:Error('Falha simulada')}:{data:null}}};
 const ctx=vm.createContext({window:{supabase:{createClient:()=>client}},document:{getElementById:node,querySelectorAll:()=>[],createElement:()=>node('new-'+Math.random())},RHFolderChoice:{start(){}},RH:{profile:()=>new Promise(()=>{}),fetchAll:async(_,table)=>table==='rh_drive_links'?links:jobs,result:async promise=>{const r=await promise;if(r.error)throw r.error;return r.data}},confirm:()=>!reject,Date,URL,console});
 vm.runInContext(source,ctx);ctx.fixture={employees,links,settings};vm.runInContext('employees=fixture.employees;links=fixture.links;settings=fixture.settings;',ctx);
 return {ctx,node,calls};
}
test('lote exclui vinculados, desligados e pendências; retoma somente falhas',async()=>{const e=env();await e.node('recognizeAll').onclick();assert.deepEqual(e.calls,['fresh','retry']);});
test('cancelar lote e automação pausada não criam tarefas',async()=>{for(const options of [{reject:true},{disabled:true}]){const e=env(options);await e.node('recognizeAll').onclick();assert.equal(e.calls.length,0);}});
test('falha parcial informa quantas tarefas foram registradas',async()=>{const e=env({failAt:2});await e.node('recognizeAll').onclick();assert.match(e.node('message').textContent,/1 reconhecimento/);assert.match(e.node('message').textContent,/Falha simulada/);});
test('atualização preserva ID manual enquanto renova o acompanhamento',async()=>{const e=env();e.node('folder').value='manual-folder123';await e.ctx.refresh();assert.equal(e.node('folder').value,'manual-folder123');});
test('reconhecimento individual respeita tarefa em escolha',async()=>{const e=env();e.node('employee').value='choice';await e.node('recognizeOne').onclick();assert.equal(e.calls.length,0);assert.match(e.node('message').textContent,/tarefa pendente/);});
test('indicadores listam nomes por vínculo, revisão e processamento sem incluir desligados',async()=>{
 const e=env();await e.ctx.refresh();
 const ids=filter=>Array.from(e.ctx.folderPeople(filter),person=>person.id);
 assert.deepEqual(ids('with'),['linked']);
 assert.deepEqual(ids('without'),['queued','choice','fresh','retry']);
 assert.deepEqual(ids('review'),['choice','retry']);
 assert.deepEqual(ids('pending'),['queued']);
 assert.equal(e.node('pendingFolders').textContent,1);
});
test('revisão pode incluir pessoa com pasta e espera continua visível em andamento',async()=>{
 const e=env();await e.ctx.refresh();
 vm.runInContext("driveJobs.push({funcionario_id:'linked',status:'failed'},{funcionario_id:'fresh',status:'waiting'});",e.ctx);
 assert.deepEqual(Array.from(e.ctx.folderPeople('review'),p=>p.id),['linked','choice','retry']);
 assert.deepEqual(Array.from(e.ctx.folderPeople('pending'),p=>p.id),['queued','fresh']);
});
