const {test}=require('node:test'),assert=require('node:assert/strict'),vm=require('node:vm'),fs=require('node:fs');
const F=require('../assets/js/rh-ponto-fichas-core.js');
class Element{
 constructor(tag){this.tag=tag;this.children=[];this.value='';this.hidden=true;this.disabled=false;this.classList={toggle(){}};}
 append(...items){this.children.push(...items);}replaceChildren(...items){this.children=items;}
 showModal(){this.open=true;}close(){this.open=false;}setAttribute(){}querySelectorAll(){return [];}remove(){}click(){this.clicked=true;}
}
function harness(){
 const els=new Map(),get=id=>{if(!els.has(id))els.set(id,new Element('div'));return els.get(id);};
 const db={funcionarios_epi:[{id:'a',nome:'Nome inicial',funcao:'PROMOTOR',cpf:'00124876510',empresa_id:4,admissao:'2025-01-01'},{id:'b',nome:'Outra empresa',funcao:'MOTORISTA',cpf:'04342870592',empresa_id:5,admissao:'2025-01-01'}],empresas:[{id:4,nome:'Nunes',cnpj:'48.986.353/0001-39'},{id:5,nome:'Prime',cnpj:'52.522.019/0001-00'}],rh_ponto_fichas_destinatarios:[]};
 const calls=[],downloads=[];const client={from(name){let op='read',record,match;return {
  select(){return this;},order(){return this;},range(){return this;},upsert(r){op='upsert';record=r;return this;},delete(){op='delete';return this;},eq(k,v){match=[k,v];return this;},
  then(resolve){calls.push({name,op,record});let rows=db[name];if(op==='upsert'){const old=rows.find(r=>r.funcionario_id===record.funcionario_id);if(old)Object.assign(old,record);else rows.push({...record});rows=[record];}else if(op==='delete'){rows=rows.filter(r=>r[match[0]]===match[1]);db[name]=db[name].filter(r=>r[match[0]]!==match[1]);}return Promise.resolve({data:rows.map(r=>({...r}))}).then(resolve);}
 };}};
 const root={RHPontoFichasCore:{...F,pdf(args){downloads.push(args);return F.pdf(args);}},RHHolidays:{getHoliday:()=>null}};
 const context=vm.createContext({window:root,document:{getElementById:get,createElement:tag=>new Element(tag),body:new Element('body')},RH:{today:()=> '2026-11-04',fetchAll:async(c,t)=>db[t].map(r=>({...r})),result:async p=>(await p).data},URL:{createObjectURL:()=> 'blob:test',revokeObjectURL(){}},Blob,setTimeout(){}});
 vm.runInContext(fs.readFileSync(require.resolve('../assets/js/rh-ponto-fichas.js'),'utf8'),context);
 return {get,db,calls,downloads,client,init:profile=>root.RHPontoFichas.init({supabase:client,profile})};
}
test('lista salva, cidade, geração com cadastro atual, filtro e remoção',async()=>{
 const h=harness(),{get,db}=h;await h.init({status:'aprovado'});assert.equal(get('openManualSheets').hidden,true);assert.equal(h.calls.length,0);
 await h.init({status:'admin'});assert.equal(get('openManualSheets').hidden,false);assert.equal(get('sheetMonth').value,'2026-11');
 assert.ok(!get('manualSheetPanel').open);get('openManualSheets').onclick();assert.equal(get('manualSheetPanel').open,true);get('closeManualSheets').onclick();assert.equal(get('manualSheetPanel').open,false);
 get('sheetEmployee').value='a';await get('sheetAdd').onclick();assert.equal(db.rh_ponto_fichas_destinatarios.length,1);
 let row=get('sheetRecipients').children[0];row.children[1].children[0].value='Ilhéus';await row.children[2].onclick();assert.equal(db.rh_ponto_fichas_destinatarios[0].cidade_trabalho,'Ilhéus');
 get('sheetEmployee').value='b';await get('sheetAdd').onclick();assert.equal(db.rh_ponto_fichas_destinatarios.length,2);
 db.funcionarios_epi[0].nome='Nome atualizado';db.funcionarios_epi[0].funcao='PROMOTOR ATUALIZADO';
 await get('sheetGenerate').onclick();assert.equal(h.downloads[0].sheets.length,2);assert.equal(h.downloads[0].sheets[0].employee.nome,'Nome atualizado');assert.equal(h.downloads[0].sheets[0].employee.funcao,'PROMOTOR ATUALIZADO');assert.equal(h.downloads[0].sheets[0].city,'Ilhéus');
 get('sheetCompany').value='5';get('sheetCompany').onchange();assert.equal(get('sheetRecipients').children.length,1);
 await get('sheetBlank').onclick();assert.equal(h.downloads.at(-1).sheets.length,1);assert.equal(h.downloads.at(-1).sheets[0].company.id,5);assert.equal(h.downloads.at(-1).sheets[0].employee,undefined);
 await get('sheetRecipients').children[0].children[3].onclick();assert.equal(db.rh_ponto_fichas_destinatarios.length,1);assert.equal(db.funcionarios_epi.length,2);
 get('sheetMonth').value='';get('sheetMonth').onchange();assert.equal(get('sheetGenerate').disabled,true);
});
