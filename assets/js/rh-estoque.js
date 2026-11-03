(function(){
 'use strict';
 const client=window.supabase.createClient('https://gcksbfstheavpfgcdndb.supabase.co','sb_publishable_UrTJ8_SyM3n800C4LZQWpw_5Ah8Ko98');
 window.RHNavigationClient=client;
 const $=id=>document.getElementById(id),branches=['FILIAL 5','FILIAL 8'],labels={epi:'EPI',fardamento:'Fardamento'};
 let products=[],stock=[],events=[],roles=[],names={},admin=false,editing=null,counting=null,busy=false,operation=null;
 const n=(tag,text,cls)=>{const e=document.createElement(tag);if(text!==undefined)e.textContent=text;if(cls)e.className=cls;return e;};
 function notice(text,error=false){$('notice').textContent=text;$('notice').className=error?'error':'';}
 async function action(fn,errorId){if(busy)return;busy=true;document.querySelectorAll('button').forEach(b=>b.disabled=true);document.querySelectorAll('dialog fieldset').forEach(e=>e.disabled=true);try{await fn();}catch(e){if(errorId)$(errorId).textContent=e.message;else notice(e.message,true);}finally{busy=false;document.querySelectorAll('button').forEach(b=>b.disabled=false);document.querySelectorAll('dialog fieldset').forEach(e=>e.disabled=false);$('productCategory').disabled=!!editing;$('roles').disabled=$('allRoles').checked;}}
 async function load(){
  [products,stock]=await Promise.all([RH.fetchAll(client,'rh_products'),RH.fetchAll(client,'rh_stock','*','produto_id')]);
  if(admin){const result=await client.from('rh_stock_events').select('*').order('created_at',{ascending:false}).limit(100);if(result.error)throw result.error;events=result.data;}
  render();
 }
 function selected(){const query=$('search').value.trim().toLocaleUpperCase('pt-BR');return products.filter(p=>($('includeInactive').checked||p.ativo)&&(!$('group').value||p.categoria===$('group').value)&&(!query||[p.nome,...p.tamanhos].some(x=>x.toLocaleUpperCase('pt-BR').includes(query)))).sort((a,b)=>a.nome.localeCompare(b.nome,'pt-BR'));}
 function render(){
  const chosen=selected(),filiais=$('branch').value?[$('branch').value]:branches;let total=0,empty=0;
  $('balances').replaceChildren();$('products').replaceChildren();
  for(const p of chosen){
   for(const filial of filiais)for(const tamanho of [...new Set([...p.tamanhos,...stock.filter(s=>s.produto_id===p.id).map(s=>s.tamanho)])]){
    const s=stock.find(s=>s.produto_id===p.id&&s.filial===filial&&s.tamanho===tamanho),qty=s?.quantidade||0;total+=qty;if(!qty)empty++;
    const tr=n('tr'),name=n('td',p.nome);name.append(n('small',labels[p.categoria]));tr.append(name,n('td',filial),n('td',tamanho),n('td',String(qty),'qty'));
    const status=n('td');status.append(n('span',!p.ativo?'Inativo':qty?'Disponível':'Informar entrada','badge'+(!p.ativo?' inactive':qty?'':' empty')));tr.append(status);
    const cell=n('td');if(admin&&p.tamanhos.includes(tamanho)){const b=n('button','Informar quantidade','secondary');b.onclick=()=>openStock(p,filial,tamanho,s);cell.append(b);}tr.append(cell);$('balances').append(tr);
   }
   const tr=n('tr'),name=n('td',p.nome);if(!p.ativo)name.append(n('small','Inativo'));tr.append(name,n('td',labels[p.categoria]),n('td',p.tamanhos.join(', ')),n('td',p.todas_funcoes?'Todas as funções':p.funcoes.length?p.funcoes.join(', '):'Selecione as funções para liberar entregas'));
   const td=n('td');if(admin){const b=n('button','Editar / renomear','secondary');b.onclick=()=>openProduct(p);td.append(b);}tr.append(td);$('products').append(tr);
  }
  $('total').textContent=total.toLocaleString('pt-BR');$('count').textContent=chosen.length;$('empty').textContent=empty;
  for(const id of ['balances','products'])if(!$(id).children.length){const tr=n('tr'),td=n('td','Nenhum item encontrado.');td.colSpan=6;tr.append(td);$(id).append(tr);}
  $('history').replaceChildren();for(const e of events.filter(e=>(!$('branch').value||e.filial===$('branch').value)&&chosen.some(p=>p.id===e.produto_id))){const tr=n('tr');for(const value of [new Date(e.created_at).toLocaleString('pt-BR',{timeZone:'America/Sao_Paulo'}),products.find(p=>p.id===e.produto_id)?.nome||'Item',e.filial+' · '+e.tamanho,(e.diferenca>0?'+':'')+e.diferenca,e.saldo,e.motivo,names[e.created_by]||'RH'])tr.append(n('td',String(value)));$('history').append(tr);}
 }
 function openProduct(p){editing=p||null;$('productError').textContent='';$('productTitle').textContent=p?'Editar / renomear item':'Cadastrar item';$('productName').value=p?.nome||'';$('productCategory').value=p?.categoria||'epi';$('productCategory').disabled=!!p;$('productSizes').value=(p?.tamanhos||[]).join(', ');$('allRoles').checked=p?.todas_funcoes||false;$('productActive').checked=p?.ativo??true;
  $('roleOptions').replaceChildren();for(const role of [...new Set([...roles,...(p?.funcoes||[])])].sort()){const label=n('label'),input=n('input');input.type='checkbox';input.value=role;input.checked=p?.funcoes.includes(role)||false;label.append(input,document.createTextNode(role));$('roleOptions').append(label);}$('roles').disabled=$('allRoles').checked;
  $('mergeBox').hidden=!p;$('mergeBox').open=false;$('mergeTarget').replaceChildren();const placeholder=n('option','Selecione o cadastro de destino');placeholder.value='';$('mergeTarget').append(placeholder);for(const target of products.filter(t=>t.id!==p?.id&&t.ativo&&t.categoria===p?.categoria)){const o=n('option',target.nome);o.value=target.id;$('mergeTarget').append(o);}
  $('productDialog').showModal();$('productName').focus();
 }
 function openStock(p,filial,tamanho,s){counting={produto_id:p.id,filial,tamanho,versao:s?.versao||0};operation=crypto.randomUUID();$('stockError').textContent='';$('stockIdentity').textContent=p.nome+' · '+filial+' · '+tamanho;$('stockBefore').textContent='Saldo atual: '+(s?.quantidade||0);$('stockQuantity').value=s?.quantidade||0;$('stockReason').value='';$('stockDialog').showModal();$('stockQuantity').focus();}
 $('productForm').onsubmit=e=>{e.preventDefault();action(async()=>{const payload={id:editing?.id||null,versao:editing?.versao||null,nome:$('productName').value,categoria:$('productCategory').value,grupo:$('productCategory').value==='fardamento'?'fardamento':'equipamento',tamanhos:$('productSizes').value.split(',').map(s=>s.trim().toUpperCase()).filter(Boolean),funcoes:[...$('roleOptions').querySelectorAll('input:checked')].map(x=>x.value),todas_funcoes:$('allRoles').checked,ativo:$('productActive').checked};await RH.result(client.rpc('rh_save_product',{payload}));$('productDialog').close();notice('Cadastro salvo. O nome padrão já está disponível no histórico e nas novas entregas.');await load();},'productError');};
 $('stockForm').onsubmit=e=>{e.preventDefault();action(async()=>{const payload={...counting,operacao_id:operation,quantidade:Number($('stockQuantity').value),motivo:$('stockReason').value};await RH.result(client.rpc('rh_set_stock',{payload}));$('stockDialog').close();notice('Quantidade salva e movimentação registrada.');await load();},'stockError');};
 $('allRoles').onchange=()=>{$('roles').disabled=$('allRoles').checked;};
 $('mergeProduct').onclick=()=>{const target=products.find(p=>p.id===$('mergeTarget').value);if(!target){$('productError').textContent='Selecione o cadastro que será mantido.';return;}if(!confirm('Unificar '+editing.nome+' em '+target.nome+'? As entregas usarão '+target.nome+' e os saldos serão somados por filial e tamanho.'))return;action(async()=>{await RH.result(client.rpc('rh_merge_products',{source_id:editing.id,target_id:target.id}));$('productDialog').close();notice('Cadastros unificados. As entregas e saldos já usam '+target.nome+'.');await load();},'productError');};

 document.querySelectorAll('[data-close]').forEach(b=>b.onclick=()=>$(b.dataset.close).close());document.querySelectorAll('dialog').forEach(d=>d.addEventListener('cancel',e=>{if(busy)e.preventDefault();}));
 $('newProduct').onclick=()=>openProduct();$('refresh').onclick=()=>action(load);for(const id of ['branch','group','includeInactive'])$(id).onchange=render;$('search').oninput=render;
 (async()=>{try{const p=await RH.profile(client);admin=p.status==='admin';if(admin){const [people,rules,profiles]=await Promise.all([RH.fetchAll(client,'funcionarios_epi','id,funcao'),RH.fetchAll(client,'epi_funcao','funcao','funcao'),RH.fetchAll(client,'profiles','id,name')]);roles=[...new Set([...people,...rules].map(x=>x.funcao).filter(Boolean))];names=Object.fromEntries(profiles.map(p=>[p.id,p.name]));}$('newProduct').hidden=!admin;$('historyPanel').hidden=!admin;await load();$('app').hidden=false;notice(admin?'Cadastre os itens e informe o saldo físico de cada filial e tamanho.':'Consulta de estoque. Ajustes e cadastros são feitos por administradores.');}catch(e){notice(e.message,true);}})();
})();
