const test=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs'),vm=require('node:vm'),path=require('node:path');
class Element{
 constructor(tag='div'){this.tag=tag;this.children=[];this.dataset={};this.style={};this.files=[];this.checked=false;this.value='';}
 append(...items){this.children.push(...items);}
 replaceChildren(...items){this.children=items;}
 click(){}
}
function setup(){
 const elements=new Map(),el=id=>{if(!elements.has(id))elements.set(id,new Element());return elements.get(id);};
 const calls=[],downloads=[],zipFiles={};
 let exported=[];
 class FakeZip{file(name,content){zipFiles[name]=content;}async generateAsync(){return new Blob(['zip']);}}
 const JSZip=process.env.JSZIP_PATH?require(process.env.JSZIP_PATH):FakeZip;
 const employee={id:'11111111-1111-4111-8111-111111111111',nome:'ANA SILVA',cpf:'01234567890'};
 const selected={id:'local-1',selected:true,error:'',employee,filename:'01234567890-HOLERITE - ANA SILVA 09-2026.pdf',kind:'HOLERITE',period:'09/2026',bytes:new Uint8Array([37,80,68,70]),sha256:'a'.repeat(64)};
 const context=vm.createContext({JSZip,Blob,crypto:require('node:crypto').webcrypto,setTimeout:()=>{},URL:{createObjectURL:blob=>{downloads.push(blob);return 'blob:test';},revokeObjectURL:()=>{}},document:{createElement:tag=>new Element(tag),createTextNode:s=>s},el,localDocs:[selected,{...selected,id:'local-2',selected:false},{...selected,id:'local-3',error:'CPF inválido'}],client:{rpc:(name,args)=>{calls.push({name,args});if(name==='rh_register_signature_export'){exported=[{id:args.p_id,documents:args.p_documents,created_at:'2026-10-29'}];context.batches=[{id:args.p_id,name:'Lote',document_type:'HOLERITE',period:'09/2026'}];context.queueDocs=[{id:'notice',batch_id:args.p_id,funcionario_id:employee.id,status:'ready'}];}return {data:name==='rh_confirm_signature_export'?1:args.p_id};}},RH:{result:async x=>x.data,fetchAll:async()=>exported},settings:null,batches:[],queueDocs:[],employee:()=>employee,labels:{ready:'Pronto'},action:async fn=>fn(),notice:()=>{},confirm:()=>true,refresh:async()=>{}});
 vm.runInContext(fs.readFileSync(path.join(__dirname,'../rh-signature-export.js'),'utf8'),context);
 return {context,el,calls,downloads,zipFiles,JSZip,selected};
}
test('exporta somente a seleção elegível e registra apenas metadados, sem upload ou envio',async()=>{
 const s=setup();await s.el('upload').onclick();
 assert.equal(s.calls.length,1);assert.equal(s.calls[0].name,'rh_register_signature_export');
 assert.equal(s.calls[0].args.p_documents.length,1);
 assert.equal(s.calls[0].args.p_documents[0].filename,s.selected.filename);
 assert.deepEqual(Object.keys(s.calls[0].args.p_documents[0]).sort(),['employee_id','filename','sha256']);
 assert.equal(s.downloads.length,1);
 if(process.env.JSZIP_PATH){const zip=await s.JSZip.loadAsync(await s.downloads[0].arrayBuffer());assert.deepEqual([...await zip.file(s.selected.filename).async('uint8array')],[37,80,68,70]);const manifest=JSON.parse(await zip.file('_controle_do_lote/manifest.json').async('string'));assert.equal(manifest.documents.length,1);assert.equal(manifest.id,s.calls[0].args.p_id);}
 else assert.ok(s.zipFiles[s.selected.filename]);
});
test('repetir download preserva identidade do lote para deduplicar o registro',async()=>{
 const s=setup();await s.el('upload').onclick();await s.el('upload').onclick();assert.equal(s.calls[0].args.p_id,s.calls[1].args.p_id);
});
test('aviso exige confirmação de disponibilidade e ação explícita posterior ao download',async()=>{
 const s=setup();await s.el('upload').onclick();const card=s.el('signatureBatches').children[0];
 const button=card.children.at(-1),check=card.children.at(-2).children[0];
 assert.equal(button.disabled,true);await assert.rejects(button.onclick(),/Confirme/);assert.equal(s.calls.length,1);
 check.checked=true;check.onchange();assert.equal(button.disabled,false);await button.onclick();
 assert.equal(s.calls.at(-1).name,'rh_confirm_signature_export');assert.equal(s.calls.at(-1).args.p_confirmed,true);
});
