const {test}=require('node:test'),assert=require('node:assert/strict'),vm=require('node:vm'),fs=require('node:fs');
class Element{
 constructor(tag='div'){this.tag=tag;this.children=[];this.value='';this.checked=false;this.dataset={};}
 append(...children){this.children.push(...children);}replaceChildren(...children){this.children=children;}
 get cells(){return this.children;}querySelectorAll(){return [];}addEventListener(){}
}
async function harness(){
 const elements=new Map(),get=id=>{if(!elements.has(id))elements.set(id,new Element());return elements.get(id);};
 const products=[{id:'boot',nome:'BOTA',categoria:'epi',ativo:true,tamanhos:['37','38'],funcoes:[]},{id:'special',nome:'BOTA ESPECIAL',categoria:'epi',ativo:true,tamanhos:['37'],funcoes:[]},{id:'shirt',nome:'CAMISA',categoria:'fardamento',ativo:true,tamanhos:['M','G'],funcoes:[]}];
 const stock=[{produto_id:'boot',filial:'FILIAL 5',tamanho:'37',quantidade:12},{produto_id:'boot',filial:'FILIAL 6',tamanho:'37',quantidade:4},{produto_id:'special',filial:'FILIAL 5',tamanho:'37',quantidade:5},{produto_id:'shirt',filial:'FILIAL 5',tamanho:'M',quantidade:6},{produto_id:'shirt',filial:'FILIAL 6',tamanho:'M',quantidade:2},{produto_id:'shirt',filial:'FILIAL 8',tamanho:'G',quantidade:1}];
 const document={getElementById:get,createElement:tag=>new Element(tag),querySelectorAll:()=>[]};
 const window={supabase:{createClient:()=>({})}};
 vm.runInNewContext(fs.readFileSync(require.resolve('../assets/js/rh-estoque.js'),'utf8'),{window,document,RHTableSort:{refresh(){}},RH:{profile:async()=>({status:'aprovado'}),fetchAll:async(c,t)=>t==='rh_products'?products:stock}});
 await new Promise(setImmediate);
 return {get,change(id,value){get(id).value=value;get(id).onchange();}};
}
test('seleção exata atualiza saldos e indicadores sem somar itens com nomes parecidos',async()=>{
 const {get,change}=await harness();assert.equal(get('total').textContent,'30');assert.equal(get('count').textContent,3);
 change('search','boot');assert.equal(get('total').textContent,'16');assert.equal(get('count').textContent,1);
 assert.equal(get('balances').children.length,6);assert.ok(get('balances').children.every(row=>row.children[0].textContent==='BOTA'));
 change('branch','FILIAL 5');assert.equal(get('total').textContent,'12');assert.equal(get('balances').children.length,2);
 change('branch','FILIAL 8');assert.equal(get('total').textContent,'0');assert.equal(get('empty').textContent,2);
 change('search','');assert.equal(get('total').textContent,'1');assert.equal(get('count').textContent,3);
});
test('tipo restringe as opções e limpa somente uma seleção incompatível',async()=>{
 const {get,change}=await harness();change('search','boot');change('branch','FILIAL 5');change('group','fardamento');
 assert.equal(get('search').value,'');assert.equal(get('total').textContent,'6');assert.equal(get('search').children.length,2);assert.equal(get('search').children[1].value,'shirt');
 change('search','shirt');change('branch','');assert.equal(get('total').textContent,'9');
 change('group','');assert.equal(get('search').value,'shirt');assert.equal(get('total').textContent,'9');
 change('search','');assert.equal(get('total').textContent,'30');assert.equal(get('count').textContent,3);
});
