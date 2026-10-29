const test=require('node:test'),assert=require('node:assert/strict'),vm=require('node:vm'),fs=require('node:fs'),P=require('../assets/js/rh-ponto-core.js');
class Element{
 constructor(tag){this.tag=tag;this.children=[];this.value='';this.checked=false;this.files=[];this.classList={toggle(){}};}
 append(...nodes){this.children.push(...nodes);}replaceChildren(...nodes){this.children=nodes;}setAttribute(k,v){this[k]=v;}querySelectorAll(){return [];}addEventListener(){}showModal(){this.open=true;}close(){this.open=false;}
}
function harness(client={}){
 const elements=new Map(),get=id=>{if(!elements.has(id))elements.set(id,new Element('div'));return elements.get(id);};
 const context=vm.createContext({window:{supabase:{createClient:()=>client}},RHPonto:P,RH:{today:()=> '2026-10-29',result:async p=>{const r=await p;if(r.error)throw r.error;return r.data;}},document:{getElementById:get,createElement:tag=>new Element(tag),querySelectorAll:()=>[]},crypto:{randomUUID:()=> '00000000-0000-4000-8000-000000000001'}});
 const source=fs.readFileSync(require.resolve('../assets/js/rh-ponto.js'),'utf8').replace(/action\(async\(\)=>\{profile=await RH.profile[\s\S]*$/,'');vm.runInContext(source,context);
 vm.runInContext("profile={status:'admin'};period={start:'2026-10-26',end:'2026-11-25'};summaries=[P.summarize({id:'employee-a',nome:'Ana'},[],[{inicio:'2026-10-26',fim:'2026-10-29',sucesso:true}],{...period,today:'2026-10-29',availableFrom:'2026-10-26'})];shown=summaries;absenceKind='injustificada';",context);
 return {context,get};
}
test('KPI → data → colaborador abre a classificação vinculada ao dia e à pessoa corretos',async()=>{
 const {context,get}=harness();vm.runInContext('renderAbsences()',context);
 const dateList=get('absenceContent').children[0];assert.equal(dateList.children.length,3);dateList.children[0].onclick();
 const personRow=get('absenceContent').children[1];assert.equal(personRow.children[0].children[0].textContent,'Ana');personRow.children[1].onclick();
 assert.equal(get('occurrence').open,true);assert.equal(get('occurrenceDate').textContent,'28/10/2026');assert.equal(get('occurrenceTitle').textContent,'Classificar dia · Ana');
 assert.equal(vm.runInContext('occurrenceEmployee',context),'employee-a');assert.equal(vm.runInContext('occurrenceDay',context),'2026-10-28');assert.equal(vm.runInContext('selected',context),null);
 assert.equal(get('occurrenceClass').value,'justificada');assert.equal(get('occurrenceCredit').checked,true);
 await new Promise(resolve=>setImmediate(resolve));
});
test('validação aceita somente comprovantes limitados e rejeita formatos executáveis',()=>{
 const {context}=harness();context.files=[{size:100,type:'image/jpeg'}];assert.doesNotThrow(()=>vm.runInContext('validateFiles(files)',context));
 for(const files of [[{size:100,type:'text/html'}],[{size:10485761,type:'application/pdf'}],Array(6).fill({size:1,type:'image/png'})]){context.files=files;assert.throws(()=>vm.runInContext('validateFiles(files)',context));}
});
test('justificar sem observação salva motivo padrão e atualiza a tela sem exigir comprovante',async()=>{
 let saved;const client={from:()=>({upsert:row=>{saved=row;return {select:async()=>({data:[{...row,id:'occurrence'}]})};}})};
 const {context,get}=harness(client);vm.runInContext("load=async()=>{};openOccurrence(summaries[0].days[0], 'employee-a')",context);await new Promise(resolve=>setImmediate(resolve));
 get('occurrenceReason').value='';get('occurrenceClass').value='justificada';get('occurrenceCredit').checked=true;get('occurrenceForm').onsubmit({preventDefault(){}});await new Promise(resolve=>setImmediate(resolve));
 assert.equal(saved.funcionario_id,'employee-a');assert.equal(saved.dia,'2026-10-26');assert.equal(saved.motivo,'Falta justificada pelo RH.');assert.equal(saved.abonar,true);assert.equal(get('occurrence').open,false);assert.match(get('notice').textContent,/Classificação salva/);
});
test('upload privado usa vínculo e metadados e remove upload órfão se o vínculo falhar',async()=>{
 const calls=[],client={storage:{from:bucket=>({upload:async(path,file,options)=>{calls.push({bucket,path,options});return {};},remove:async paths=>{calls.push({cleanup:paths});return {};}})},from:()=>({insert:row=>{calls.push({row});return {select:async()=>({error:Error('falha teste')})};}})};
 const {context}=harness(client);context.files=[{name:'atestado.png',size:120,type:'image/png'}];context.occurrence={id:'occurrence',funcionario_id:'employee-a',dia:'2026-10-28'};
 await assert.rejects(vm.runInContext('saveAttachments(occurrence,files)',context),/vincular/);
 assert.equal(calls[0].bucket,'rh-ponto-comprovantes');assert.equal(calls[0].options.upsert,false);assert.match(calls[0].path,/^employee-a\/2026-10-28\/.+\.png$/);assert.equal(calls[1].row.ocorrencia_id,'occurrence');assert.equal(calls[2].cleanup[0],calls[0].path);
});
