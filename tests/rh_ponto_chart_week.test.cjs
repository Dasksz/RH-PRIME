const {test}=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs'),vm=require('node:vm'),P=require('../assets/js/rh-ponto-core.js');
class Element{constructor(tag){this.tag=tag;this.children=[];this.value='';this.style={};this.dataset={};this.classList={toggle(){},add(){},remove(){}};}append(...c){this.children.push(...c);}replaceChildren(...c){this.children=c;}setAttribute(k,v){this[k]=v;}getAttribute(k){return this[k];}querySelectorAll(){return [];}addEventListener(){}}
function harness(){const els=new Map(),calls=[],get=id=>{if(!els.has(id))els.set(id,new Element('div'));return els.get(id);};let fail=false;
 const client={from:table=>{const q={select(){return this;},gte(k,v){calls.push([table,'gte',k,v]);return this;},lt(){return this;},lte(){return this;},order(){return this;},range:async()=>({data:[]}),then(resolve){resolve({data:[]});}};return q;}};
 const context=vm.createContext({window:{supabase:{createClient:()=>client}},RHPonto:P,RHHolidays:{getHoliday:()=>null},RH:{today:()=> '2026-10-30',fetchAll:async(c,table)=>{if(fail)throw Error('Falha simulada');return table==='funcionarios_epi'?[{id:'a',nome:'Pessoa',setor:'ARMAZEM'}]:[];},result:async p=>(await p).data},document:{getElementById:get,createElement:tag=>new Element(tag),createTextNode:text=>({textContent:text}),querySelectorAll:()=>[]}});
 const src=fs.readFileSync(require.resolve('../assets/js/rh-ponto.js'),'utf8').replace(/action\(async\(\)=>\{profile=await RH.profile[\s\S]*$/,'');vm.runInContext(src,context);vm.runInContext("profile={status:'admin'};",context);get('start').value='2026-10-26';get('end').value='2026-11-25';get('search').value='';get('branch').value='';get('situation').value='all';return {context,get,calls,setFail:()=>fail=true};
}
test('semana anterior consulta histórico sem alterar fechamento; atual volta e próxima futura é bloqueada',async()=>{
 const {context,get,calls}=harness();await vm.runInContext('load()',context);assert.equal(get('chartNext').disabled,true);assert.equal(get('chartCurrent').disabled,true);
 await get('chartPrev').onclick();assert.equal(vm.runInContext('chartWeek',context),'2026-10-19');assert.equal(get('start').value,'2026-10-26');assert.equal(get('end').value,'2026-11-25');assert.match(get('distributionPeriod').textContent,/19\/10\/2026 a 25\/10\/2026/);assert.ok(calls.some(c=>c[0]==='rh_ponto_marcacoes'&&c[3]==='2026-10-19 00:00:00'));
 await get('chartCurrent').onclick();assert.equal(vm.runInContext('chartWeek',context),'2026-10-26');await get('chartNext').onclick();assert.equal(vm.runInContext('chartWeek',context),'2026-10-26');
 await vm.runInContext("changeChartWeek('2026-08-24')",context);assert.equal(vm.runInContext('chartWeek',context),'2026-10-26');
});
test('falha ao consultar semana restaura seleção anterior e mostra erro',async()=>{
 const {context,get,setFail}=harness();await vm.runInContext('load()',context);setFail();await get('chartPrev').onclick();assert.equal(vm.runInContext('chartWeek',context),'2026-10-26');assert.match(get('notice').textContent,/Falha simulada/);
});
test('cartão do dia contém todos os setores, total, data e suporte ao teclado sem title nativo',()=>{
 const {context,get}=harness();context.rows=[{employee:{id:'a',nome:'Ana',setor:'ARMAZEM'},days:[{date:'2026-10-26',delta:3600,warnings:[]}]},{employee:{id:'b',nome:'Bia',setor:'TRANSPORTE'},days:[{date:'2026-10-26',delta:0,warnings:[]}]}];vm.runInContext('period={start:"2026-10-26",end:"2026-11-25"};shown=rows;renderDistribution()',context);
 const column=get('distributionPlot').children[0],tip=column.children.at(-1);assert.equal(tip.role,'tooltip');assert.equal(column['aria-describedby'],tip.id);assert.equal(column.tabIndex,0);assert.match(tip.children[0].textContent,/Segunda-feira · 26\/10\/2026/);assert.equal(tip.children[2].children[1].textContent,'0h00');assert.equal(tip.children.at(-1).children[1].textContent,'+1h00');assert.equal(column.children[1].children[0].children[0].title,undefined);
});
