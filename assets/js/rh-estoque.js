(function(){
 'use strict';
 const client=window.supabase.createClient('https://gcksbfstheavpfgcdndb.supabase.co','sb_publishable_UrTJ8_SyM3n800C4LZQWpw_5Ah8Ko98');
 window.RHNavigationClient=client;
 const $=id=>document.getElementById(id),branches=['FILIAL 5','FILIAL 6','FILIAL 8'],labels={epi:'EPI',fardamento:'Fardamento'};
 let products=[],stock=[],events=[],roles=[],names={},admin=false,editing=null,counting=null,busy=false,operation=null,transferRequest=null;
 const n=(tag,text,cls)=>{const e=document.createElement(tag);if(text!==undefined)e.textContent=text;if(cls)e.className=cls;return e;};
 function notice(text,error=false){$('notice').textContent=text;$('notice').className=error?'error':'';}
 async function action(fn,errorId){if(busy)return;busy=true;document.querySelectorAll('button').forEach(b=>b.disabled=true);document.querySelectorAll('dialog fieldset').forEach(e=>e.disabled=true);try{await fn();}catch(e){if(errorId)$(errorId).textContent=e.message;else notice(e.message,true);}finally{busy=false;document.querySelectorAll('button').forEach(b=>b.disabled=false);document.querySelectorAll('dialog fieldset').forEach(e=>e.disabled=false);$('productCategory').disabled=!!editing;$('roles').disabled=$('allRoles').checked;if($('transferDialog').open)previewTransfer();}}
 async function load(){
  [products,stock]=await Promise.all([RH.fetchAll(client,'rh_products'),RH.fetchAll(client,'rh_stock','*','produto_id')]);
  if(admin){const result=await client.from('rh_stock_events').select('*').order('created_at',{ascending:false}).limit(100);if(result.error)throw result.error;events=result.data;}
  render();
 }
 function availableProducts(){return products.filter(p=>($('includeInactive').checked||p.ativo)&&(!$('group').value||p.categoria===$('group').value)).sort((a,b)=>a.nome.localeCompare(b.nome,'pt-BR')||a.categoria.localeCompare(b.categoria));}
 function refreshItemFilter(){
  const available=availableProducts(),previous=$('search').value,all=n('option','Todos os itens');all.value='';
  $('search').replaceChildren(all,...available.map(p=>{const o=n('option',p.nome+' · '+labels[p.categoria]+(p.ativo?'':' · Inativo'));o.value=p.id;return o;}));
  $('search').value=available.some(p=>p.id===previous)?previous:'';
 }
 function selected(){return availableProducts().filter(p=>!$('search').value||p.id===$('search').value);}
 function render(){
  refreshItemFilter();
  const chosen=selected(),filiais=$('branch').value?[$('branch').value]:branches;let total=0,empty=0;
  $('balances').replaceChildren();$('products').replaceChildren();
  for(const p of chosen){
   for(const filial of filiais)for(const tamanho of [...new Set([...p.tamanhos,...stock.filter(s=>s.produto_id===p.id).map(s=>s.tamanho)])]){
    const s=stock.find(s=>s.produto_id===p.id&&s.filial===filial&&s.tamanho===tamanho),qty=s?.quantidade||0;total+=qty;if(!qty)empty++;
    const tr=n('tr'),name=n('td',p.nome);name.append(n('small',labels[p.categoria]));tr.append(name,n('td',filial),n('td',tamanho),n('td',String(qty),'qty'));
    const status=n('td');status.append(n('span',!p.ativo?'Inativo':qty?'Disponível':'Informar entrada','badge'+(!p.ativo?' inactive':qty?'':' empty')));tr.append(status);
    const cell=n('td');if(admin&&p.tamanhos.includes(tamanho)){const b=n('button','Informar quantidade','secondary');b.onclick=()=>openStock(p,filial,tamanho,s);cell.append(b);if(p.ativo&&qty>0){const t=n('button','Transferir','secondary');t.type='button';t.onclick=()=>action(async()=>{await load();openTransfer(p,filial,tamanho);});cell.append(t);}cell.className='balance-actions';}tr.append(cell);$('balances').append(tr);
   }
   const tr=n('tr'),name=n('td',p.nome);if(!p.ativo)name.append(n('small','Inativo'));tr.append(name,n('td',labels[p.categoria]),n('td',p.tamanhos.join(', ')),n('td',p.todas_funcoes?'Todas as funções':p.funcoes.length?p.funcoes.join(', '):'Selecione as funções para liberar entregas'));
   const td=n('td');if(admin){const b=n('button','Editar / renomear','secondary');b.onclick=()=>openProduct(p);td.append(b);}tr.append(td);$('products').append(tr);
  }
  $('total').textContent=total.toLocaleString('pt-BR');$('count').textContent=chosen.length;$('empty').textContent=empty;
  for(const id of ['balances','products'])if(!$(id).children.length){const tr=n('tr'),td=n('td','Nenhum item encontrado.');td.colSpan=6;tr.append(td);$(id).append(tr);}
  $('history').replaceChildren();for(const e of events.filter(e=>(!$('branch').value||e.filial===$('branch').value)&&chosen.some(p=>p.id===e.produto_id))){const tr=n('tr');for(const value of [new Date(e.created_at).toLocaleString('pt-BR',{timeZone:'America/Sao_Paulo'}),products.find(p=>p.id===e.produto_id)?.nome||'Item',e.filial+' · '+e.tamanho,(e.diferenca>0?'+':'')+e.diferenca,e.saldo,e.motivo,names[e.created_by]||'RH'])tr.append(n('td',String(value)));tr.cells[0].dataset.sortValue=e.created_at;$('history').append(tr);}
  RHTableSort.refresh();
 }
 function openProduct(p){editing=p||null;$('productError').textContent='';$('productTitle').textContent=p?'Editar / renomear item':'Cadastrar item';$('productName').value=p?.nome||'';$('productCategory').value=p?.categoria||'epi';$('productCategory').disabled=!!p;$('productSizes').value=(p?.tamanhos||[]).join(', ');$('allRoles').checked=p?.todas_funcoes||false;$('productActive').checked=p?.ativo??true;
  $('roleOptions').replaceChildren();for(const role of [...new Set([...roles,...(p?.funcoes||[])])].sort()){const label=n('label'),input=n('input');input.type='checkbox';input.value=role;input.checked=p?.funcoes.includes(role)||false;label.append(input,document.createTextNode(role));$('roleOptions').append(label);}$('roles').disabled=$('allRoles').checked;
  $('mergeBox').hidden=!p;$('mergeBox').open=false;$('mergeTarget').replaceChildren();const placeholder=n('option','Selecione o cadastro de destino');placeholder.value='';$('mergeTarget').append(placeholder);for(const target of products.filter(t=>t.id!==p?.id&&t.ativo&&t.categoria===p?.categoria)){const o=n('option',target.nome);o.value=target.id;$('mergeTarget').append(o);}
  $('productDialog').showModal();$('productName').focus();
 }
 function openStock(p,filial,tamanho,s){counting={produto_id:p.id,filial,tamanho,versao:s?.versao||0};operation=crypto.randomUUID();$('stockError').textContent='';$('stockIdentity').textContent=p.nome+' · '+filial+' · '+tamanho;$('stockBefore').textContent='Saldo atual: '+(s?.quantidade||0);$('stockQuantity').value=s?.quantidade||0;$('stockReason').value='';$('stockDialog').showModal();$('stockQuantity').focus();}
 function transferBalance(filial){return stock.find(s=>s.produto_id===$('transferProduct').value&&s.filial===filial&&s.tamanho===$('transferSize').value);}
 function transferSizes(preferred){
  const p=products.find(p=>p.id===$('transferProduct').value),old=preferred||$('transferSize').value;
  $('transferSize').replaceChildren();for(const size of p?.tamanhos||[]){const o=n('option',size);o.value=size;$('transferSize').append(o);}
  if(p?.tamanhos.includes(old))$('transferSize').value=old;
 }
 function transferDestinations(preferred){
  const old=preferred||$('transferDestination').value;$('transferDestination').replaceChildren();
  for(const branch of branches.filter(b=>b!==$('transferOrigin').value)){const o=n('option',branch);o.value=branch;$('transferDestination').append(o);}
  if(branches.includes(old)&&old!==$('transferOrigin').value)$('transferDestination').value=old;
 }
 function previewTransfer(){
  const origin=transferBalance($('transferOrigin').value),destination=transferBalance($('transferDestination').value),qty=Number($('transferQuantity').value);
  const selected=!!$('transferProduct').value&&!!$('transferSize').value;
  const valid=selected&&Number.isInteger(qty)&&qty>0&&qty<=1000000&&qty<=(origin?.quantidade||0)&&$('transferOrigin').value!==$('transferDestination').value;
  $('transferQuantity').max=Math.min(1000000,origin?.quantidade||0);
  $('confirmTransfer').disabled=busy||!valid;
  $('transferPreview').replaceChildren();
  if(!selected){$('transferPreview').append(n('p','Selecione o item e o tamanho para consultar os saldos.'));return;}
  for(const [label,row,change] of [[$('transferOrigin').value,origin,-qty],[$('transferDestination').value,destination,qty]]){
   const box=n('div');box.append(n('span',label),n('strong',(row?.quantidade||0)+' un.'),n('small',valid?'Após transferir: '+((row?.quantidade||0)+change)+' un.':'Saldo disponível'));$('transferPreview').append(box);
  }
  if(!origin?.quantidade)$('transferPreview').append(n('p','Sem saldo na origem para este item e tamanho.','transfer-hint'));
  else if(!valid)$('transferPreview').append(n('p','Informe uma quantidade inteira de 1 a '+Math.min(1000000,origin.quantidade)+' para transferir.','transfer-hint'));
 }
 function openTransfer(p,filial,tamanho){
  transferRequest=null;$('transferError').textContent='';$('transferReason').value='';$('transferQuantity').value='1';
  const placeholder=n('option','Selecione um item');placeholder.value='';$('transferProduct').replaceChildren(placeholder);
  for(const item of products.filter(p=>p.ativo).sort((a,b)=>a.nome.localeCompare(b.nome,'pt-BR'))){const o=n('option',item.nome+' · '+labels[item.categoria]);o.value=item.id;$('transferProduct').append(o);}
  $('transferProduct').value=p?.id||'';$('transferOrigin').replaceChildren(...branches.map(b=>{const o=n('option',b);o.value=b;return o;}));
  $('transferOrigin').value=filial||$('branch').value||branches[0];transferDestinations();transferSizes(tamanho);previewTransfer();$('transferDialog').showModal();$('transferProduct').focus();
 }
 for(const id of ['transferProduct','transferOrigin','transferDestination','transferSize'])$(id).onchange=()=>{if(id==='transferProduct')transferSizes();if(id==='transferOrigin')transferDestinations();$('transferError').textContent='';previewTransfer();};
 $('transferQuantity').oninput=previewTransfer;
 $('reloadTransfer').onclick=()=>action(async()=>{await load();$('transferError').textContent='';previewTransfer();},'transferError');
 $('newTransfer').onclick=()=>action(async()=>{await load();openTransfer();});
 $('transferForm').onsubmit=e=>{e.preventDefault();if($('confirmTransfer').disabled)return;action(async()=>{
  const values={produto_id:$('transferProduct').value,origem:$('transferOrigin').value,destino:$('transferDestination').value,tamanho:$('transferSize').value,quantidade:Number($('transferQuantity').value),motivo:$('transferReason').value.trim()};
  // Uma nova tentativa conserva o mesmo pedido e a mesma versão, inclusive após falha de rede.
  if(!transferRequest||Object.entries(values).some(([k,v])=>transferRequest[k]!==v))transferRequest={...values,operacao_id:crypto.randomUUID(),versao_origem:transferBalance(values.origem)?.versao||0};
  let result;try{result=await RH.result(client.rpc('rh_transfer_stock',{payload:transferRequest}));}catch(error){
   if(/^(O saldo da origem mudou|Estoque insuficiente)/.test(error.message)){transferRequest=null;try{await load();}catch(_){}previewTransfer();}
   throw error;
  }
  if(!result?.operacao_id)throw Error('A transferência não foi confirmada. Tente novamente com os mesmos dados.');
  $('transferDialog').close();transferRequest=null;notice('Transferência concluída: '+result.quantidade+' un. de '+result.origem+' para '+result.destino+'.');
  try{await load();}catch(error){notice('Transferência concluída. Não foi possível atualizar a lista; clique em Atualizar. '+error.message,true);}
 },'transferError');};
 $('productForm').onsubmit=e=>{e.preventDefault();action(async()=>{const payload={id:editing?.id||null,versao:editing?.versao||null,nome:$('productName').value,categoria:$('productCategory').value,grupo:$('productCategory').value==='fardamento'?'fardamento':'equipamento',tamanhos:$('productSizes').value.split(',').map(s=>s.trim().toUpperCase()).filter(Boolean),funcoes:[...$('roleOptions').querySelectorAll('input:checked')].map(x=>x.value),todas_funcoes:$('allRoles').checked,ativo:$('productActive').checked};await RH.result(client.rpc('rh_save_product',{payload}));$('productDialog').close();notice('Cadastro salvo. O nome padrão já está disponível no histórico e nas novas entregas.');await load();},'productError');};
 $('stockForm').onsubmit=e=>{e.preventDefault();action(async()=>{const payload={...counting,operacao_id:operation,quantidade:Number($('stockQuantity').value),motivo:$('stockReason').value};await RH.result(client.rpc('rh_set_stock',{payload}));$('stockDialog').close();notice('Quantidade salva e movimentação registrada.');await load();},'stockError');};
 $('allRoles').onchange=()=>{$('roles').disabled=$('allRoles').checked;};
 $('mergeProduct').onclick=()=>{const target=products.find(p=>p.id===$('mergeTarget').value);if(!target){$('productError').textContent='Selecione o cadastro que será mantido.';return;}if(!confirm('Unificar '+editing.nome+' em '+target.nome+'? As entregas usarão '+target.nome+' e os saldos serão somados por filial e tamanho.'))return;action(async()=>{await RH.result(client.rpc('rh_merge_products',{source_id:editing.id,target_id:target.id}));$('productDialog').close();notice('Cadastros unificados. As entregas e saldos já usam '+target.nome+'.');await load();},'productError');};

 document.querySelectorAll('[data-close]').forEach(b=>b.onclick=()=>$(b.dataset.close).close());document.querySelectorAll('dialog').forEach(d=>d.addEventListener('cancel',e=>{if(busy)e.preventDefault();}));
 $('newProduct').onclick=()=>openProduct();$('refresh').onclick=()=>action(load);for(const id of ['branch','group','includeInactive'])$(id).onchange=render;$('search').onchange=render;
 (async()=>{try{const p=await RH.profile(client);admin=p.status==='admin';if(admin){const [people,rules,profiles]=await Promise.all([RH.fetchAll(client,'funcionarios_epi','id,funcao'),RH.fetchAll(client,'epi_funcao','funcao','funcao'),RH.fetchAll(client,'profiles','id,name')]);roles=[...new Set([...people,...rules].map(x=>x.funcao).filter(Boolean))];names=Object.fromEntries(profiles.map(p=>[p.id,p.name]));}$('newProduct').hidden=!admin;$('newTransfer').hidden=!admin;$('historyPanel').hidden=!admin;await load();$('app').hidden=false;notice(admin?'Cadastre os itens e informe o saldo físico de cada filial e tamanho.':'Consulta de estoque. Ajustes e cadastros são feitos por administradores.');}catch(e){notice(e.message,true);}})();
})();
