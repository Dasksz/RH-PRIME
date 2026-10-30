const {test}=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs'),vm=require('node:vm');
const P=require('../assets/js/rh-ponto-core.js');
const source=fs.readFileSync(require.resolve('../assets/js/rh-ponto.js'),'utf8').replace(/action\(async\(\)=>\{profile=await RH.profile[\s\S]*$/,'');
function setup(run,load=async()=>{}){
 const elements=new Map();const get=id=>{if(!elements.has(id))elements.set(id,{value:'',hidden:false,children:[],classList:{toggle(){},add(){},remove(){}},replaceChildren(...c){this.children=c;},setAttribute(k,v){this[k]=v;},getAttribute(k){return this[k];},querySelectorAll(){return [];},addEventListener(){}});return elements.get(id);};
 const context=vm.createContext({window:{supabase:{createClient:()=>({})}},RHPonto:P,RHPontoSync:{run},RH:{today:()=> '2026-10-30'},document:{getElementById:get,querySelectorAll:()=>[],createElement:()=>({})}});
 vm.runInContext(source,context);context.mockLoad=load;
 vm.runInContext("profile={status:'admin'};period={start:'2026-10-26',end:'2026-11-25'};shown=[{employee:{id:'a',nome:'Ana'}}];load=mockLoad;",context);
 get('start').value='2026-10-26';get('end').value='2026-11-25';return {get,context};
}
test('progresso compacto só permite fechar após recarga; nova execução reabre',async()=>{
 let done;const {get}=setup(async({onProgress})=>{onProgress({total:1,done:0,failed:0});return {total:1,done:1,failed:0,issues:[]};},()=>new Promise(r=>done=r));
 const running=get('sync').onclick();await new Promise(r=>setImmediate(r));
 assert.equal(get('syncPercent').textContent,'100%');assert.equal(get('syncTitle').textContent,'Finalizando…');assert.equal(get('syncClose').hidden,true);
 get('syncClose').onclick();assert.equal(get('syncPanel').hidden,false);
 done();await running;assert.equal(get('syncClose').hidden,false);assert.equal(get('syncDetails').hidden,true);assert.equal(get('notice').hidden,true);
 get('syncClose').onclick();assert.equal(get('syncPanel').hidden,true);
 const again=get('sync').onclick();await new Promise(r=>setImmediate(r));assert.equal(get('syncPanel').hidden,false);assert.equal(get('syncClose').hidden,true);done();await again;
});
test('falha parcial e interrupção mantêm detalhes recolhidos e permitem fechar',async()=>{
 for(const result of [{total:2,done:2,failed:1,issues:[{id:'a',message:'Falhou'}]},{total:2,done:1,failed:0,error:'Servidor indisponível',issues:[]}]){
  const {get}=setup(async()=>result);await get('sync').onclick();assert.equal(get('syncDetails').hidden,false);assert.equal(get('syncDetails').open,false);assert.equal(get('syncClose').hidden,false);assert.equal(get('syncPercent').textContent,result.done===2?'100%':'50%');get('syncClose').onclick();assert.equal(get('syncPanel').hidden,true);
 }
});
test('erro ao recarregar e exceção inesperada continuam visíveis nos detalhes',async()=>{
 for(const scenario of ['reload','throw']){
  const {get}=setup(async()=>{if(scenario==='throw')throw Error('Erro inesperado');return {total:1,done:1,failed:0,issues:[]};},async()=>{throw Error('Erro de recarga');});
  await get('sync').onclick();assert.equal(get('syncClose').hidden,false);assert.equal(get('syncDetails').hidden,false);assert.match(get('syncStatus').textContent,/Erro/);
 }
});

