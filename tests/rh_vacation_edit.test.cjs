const test=require('node:test'),assert=require('node:assert/strict'),vm=require('node:vm'),fs=require('node:fs');
const V=require('../assets/js/rh-ferias-core.js'),source=fs.readFileSync(require.resolve('../assets/js/ferias.js'),'utf8');
function fixture(){
 const fields={},nodes={formFields:{append(){}},completedPeriodDialog:{open:true,close(){this.open=false;}}},calls=[];
 const employee={id:'employee',admissao:'06/01/2025'};
 const periods=[{id:'old-period',inicio:'2025-01-06',fim:'2026-01-05',direito:30,phase:'adquirido',gozo_base:0,abono_base:0},{id:'new-period',inicio:'2026-01-06',fim:'2027-01-05',direito:30,phase:'em_formacao',gozo_base:0,abono_base:0}];
 const entry={id:'launch',periodo_id:'old-period',inicio:'2026-07-06',fim:'2026-08-04',dias_gozo:30,dias_abono:0,status:'concluido',observacao:'Registro original',concordancia:true,antecipada:false,updated_at:'2026-10-23T12:00:00.123456+00:00'};
 let submit,title,saved;
 const ctx={V,currentEmployee:employee,launches:[entry],state:()=>({line:periods}),RH:{today:()=> '2026-10-27',result:async p=>p},client:{rpc:async(name,args)=>{calls.push({name,args});return 'replacement';}},mutate:async(...args)=>calls.push({mutate:args}),saved:async text=>{saved=text;},$:id=>nodes[id],form:(t,fn)=>{title=t;submit=fn;},field:(name,label,type,value)=>{const f={name,label,type,value:String(value??''),checked:type==='checkbox'&&!!value,listeners:{},addEventListener(k,fn){this.listeners[k]=fn;},closest(){return this.container;},container:{hidden:false}};fields[name]=f;nodes['field-'+name]=f;return f;},make:()=>({hidden:false}),note(){},values:()=>Object.fromEntries(Object.entries(fields).map(([name,f])=>[name,f.value]))};
 vm.createContext(ctx);vm.runInContext(source.slice(source.indexOf('function launchForm('),source.indexOf('function adjustForm(')),ctx);
 return {ctx,fields,nodes,calls,periods,entry,get title(){return title;},get saved(){return saved;},submit:()=>submit()};
}
test('edição preenche o lançamento existente e devolve sua capacidade no formulário',()=>{
 const f=fixture();f.ctx.launchForm(f.periods[0],f.entry);
 assert.equal(f.title,'Editar férias lançadas');assert.equal(f.fields.inicio.value,'2026-07-06');assert.equal(f.fields.dias_gozo.value,'30');assert.equal(f.fields.observacao.value,'Registro original');assert.equal(f.fields.concordancia.checked,true);assert.equal(f.fields.motivo.required,true);
});
test('correção troca período e datas em uma única chamada com controle de versão',async()=>{
 const f=fixture();f.ctx.launchForm(f.periods[0],f.entry);f.fields.periodo.value=f.periods[1].inicio;f.fields.periodo.listeners.change();f.fields.antecipada.checked=true;f.fields.motivo.value='Período aquisitivo selecionado incorretamente';await f.submit();
 assert.equal(f.calls.length,1);const c=f.calls[0];assert.equal(c.name,'rh_vacation_correct');assert.equal(c.args.p_id,'launch');assert.equal(c.args.p_expected_updated_at,f.entry.updated_at);assert.equal(c.args.p_payload.periodo_id,'new-period');assert.equal(c.args.p_payload.inicio,'2026-07-06');assert.equal(c.args.p_payload.status,'concluido');assert.equal(c.args.p_payload.antecipada,true);assert.equal(f.nodes.completedPeriodDialog.open,false);assert.match(f.saved,/corrigidas/);
});
test('não grava edição sem justificativa nem sem concordância na antecipação',async()=>{
 const f=fixture();f.ctx.launchForm(f.periods[0],f.entry);await assert.rejects(f.submit(),/motivo/);assert.equal(f.calls.length,0);
 f.fields.periodo.value=f.periods[1].inicio;f.fields.periodo.listeners.change();f.fields.motivo.value='Corrigindo o período de origem';await assert.rejects(f.submit(),/antecipação/);assert.equal(f.calls.length,0);
});
test('novo lançamento continua usando o fluxo existente',async()=>{
 const f=fixture();f.ctx.launchForm(f.periods[0]);f.fields.inicio.value='2026-09-01';await f.submit();assert.equal(f.title,'Registrar férias por período aquisitivo');assert.equal(f.fields.motivo,undefined);assert.equal(f.calls[0].mutate[0],'lancamento');
});
