(function(){
 'use strict';
 const client=window.supabase.createClient('https://gcksbfstheavpfgcdndb.supabase.co','sb_publishable_UrTJ8_SyM3n800C4LZQWpw_5Ah8Ko98');
 window.RHNavigationClient=client;
 const $=id=>document.getElementById(id),branches=['FILIAL 5','FILIAL 8'],labels={epi:'EPI',fardamento:'Fardamento'};
 let products=[],stock=[],returned=[],events=[],roles=[],names={},managesStock=false,editing=null,counting=null,busy=false,operation=null,transferRequest=null,classificationSource=null,classificationRequest=null;
 const n=(tag,text,cls)=>{const e=document.createElement(tag);if(text!==undefined)e.textContent=text;if(cls)e.className=cls;return e;};
 function notice(text,error=false){$('notice').textContent=text;$('notice').className=error?'error':'';}
 async function action(fn,errorId){if(busy)return;busy=true;document.querySelectorAll('button').forEach(b=>b.disabled=true);document.querySelectorAll('dialog fieldset').forEach(e=>e.disabled=true);try{await fn();}catch(e){if(errorId)$(errorId).textContent=e.message;else notice(e.message,true);}finally{busy=false;document.querySelectorAll('button').forEach(b=>b.disabled=false);document.querySelectorAll('dialog fieldset').forEach(e=>e.disabled=false);$('productCategory').disabled=false;$('roles').disabled=$('allRoles').checked;if($('transferDialog').open)previewTransfer();if($('classificationDialog').open)previewClassification();}}
 async function load(){
  [products,stock,returned]=await Promise.all([RH.fetchAll(client,'rh_products'),RH.fetchAll(client,'rh_stock','*','produto_id'),RH.fetchAll(client,'rh_returned_items','*','id')]);
  if(managesStock){const result=await client.from('rh_stock_events').select('*').order('created_at',{ascending:false}).limit(100);if(result.error)throw result.error;events=result.data;}
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
    const cell=n('td');if(managesStock&&p.tamanhos.includes(tamanho)){const b=n('button','Informar quantidade','secondary');b.onclick=()=>openStock(p,filial,tamanho,s);cell.append(b);if(p.ativo&&qty>0){const t=n('button','Transferir','secondary');t.type='button';t.onclick=()=>action(async()=>{await load();openTransfer(p,filial,tamanho);});cell.append(t);}cell.className='balance-actions';}tr.append(cell);$('balances').append(tr);
   }
   const tr=n('tr'),name=n('td',p.nome);if(!p.ativo)name.append(n('small','Inativo'));tr.append(name,n('td',labels[p.categoria]),n('td',p.tamanhos.join(', ')),n('td',p.todas_funcoes?'Todas as funções':p.funcoes.length?p.funcoes.join(', '):'Selecione as funções para liberar entregas'));
   const td=n('td');if(managesStock){const b=n('button','Editar / renomear','secondary');b.onclick=()=>openProduct(p);td.append(b);}tr.append(td);$('products').append(tr);
  }
  $('total').textContent=total.toLocaleString('pt-BR');$('count').textContent=chosen.length;$('empty').textContent=empty;
  for(const id of ['balances','products'])if(!$(id).children.length){const tr=n('tr'),td=n('td','Nenhum item encontrado.');td.colSpan=6;tr.append(td);$(id).append(tr);}
  $('history').replaceChildren();for(const e of events.filter(e=>(!$('branch').value||e.filial===$('branch').value)&&chosen.some(p=>p.id===e.produto_id))){const tr=n('tr');for(const value of [new Date(e.created_at).toLocaleString('pt-BR',{timeZone:'America/Sao_Paulo'}),products.find(p=>p.id===e.produto_id)?.nome||'Item',e.filial+' · '+e.tamanho,(e.diferenca>0?'+':'')+e.diferenca,e.saldo,e.motivo,names[e.created_by]||'RH'])tr.append(n('td',String(value)));tr.cells[0].dataset.sortValue=e.created_at;$('history').append(tr);}
  renderReturned(chosen);
  RHTableSort.refresh();
 }
 const shortDate=value=>value?String(value).slice(0,10).split('-').reverse().join('/'):'Data não informada';
 function renderReturned(chosen){
  const rows=returned.filter(r=>(!$('branch').value||r.filial===$('branch').value)&&chosen.some(p=>p.id===r.produto_id)).sort((a,b)=>(b.data_movimento||'').localeCompare(a.data_movimento||'')||(b.created_at||'').localeCompare(a.created_at||''));
  $('returnedCount').textContent=rows.reduce((sum,r)=>sum+r.quantidade,0)+' un.';$('returnedRows').replaceChildren();
  for(const r of rows){const tr=n('tr'),item=n('td');item.append(n('strong',r.equipamento),n('small',[r.filial,r.tamanho?'Tam. '+r.tamanho:'',shortDate(r.data_movimento)].filter(Boolean).join(' · ')));const detail=n('td'),button=n('button','Ver detalhes','secondary returned-detail');button.type='button';button.onclick=()=>openReturned(r);detail.append(button);tr.append(item,n('td',String(r.quantidade)),n('td',r.motivo||'Não informado'),detail);$('returnedRows').append(tr);}
  if(!rows.length){const tr=n('tr'),td=n('td','Nenhuma devolução nos filtros selecionados.');td.colSpan=4;tr.append(td);$('returnedRows').append(tr);}
 }
 function openReturned(r){
  $('returnedTitle').textContent=r.equipamento+' · devolução';$('returnedDetails').replaceChildren();
  const grid=n('div',undefined,'returned-details-grid');for(const [label,value] of [['Tipo',labels[r.categoria]],['Filial',r.filial],['Tamanho',r.tamanho||'Não informado'],['Quantidade',r.quantidade],['Colaborador',r.funcionario_nome||'Não informado'],['Data da devolução',shortDate(r.data_movimento)],['Motivo / condição informada',r.motivo||'Não informado'],['Registrado por',r.registrado_por||'RH']]){const cell=n('div');cell.append(n('small',label),n('strong',String(value||'Não informado')));grid.append(cell);}
  $('returnedDetails').append(grid,n('h3','Observações'),n('p',r.observacao||'Nenhuma observação registrada.','returned-observation'));
  if(r.comprovante){if(/^https?:\/\//i.test(r.comprovante)){const a=n('a','Abrir comprovante');a.href=r.comprovante;a.target='_blank';a.rel='noopener';$('returnedDetails').append(a);}else $('returnedDetails').append(n('p',r.comprovante));}
  $('returnedDialog').showModal();
 }
 function hasProductChanges(){
  if(!editing)return false;const norm=v=>String(v||'').trim().replace(/\s+/g,' ').toLocaleUpperCase('pt-BR'),sorted=a=>JSON.stringify([...new Set(a)].sort());
  return norm($('productName').value)!==norm(editing.nome)||sorted($('productSizes').value.split(',').map(norm).filter(Boolean))!==sorted(editing.tamanhos.map(norm))||$('allRoles').checked!==editing.todas_funcoes||$('productActive').checked!==editing.ativo||sorted([...$('roleOptions').querySelectorAll('input:checked')].map(x=>x.value))!==sorted(editing.funcoes);
 }
 function classificationTargets(){
  const old=$('classificationTarget').value,cat=$('classificationCategory').value,placeholder=n('option','Selecione o substituto');placeholder.value='';$('classificationTarget').replaceChildren(placeholder);
  for(const p of products.filter(p=>p.id!==classificationSource.id&&p.ativo&&p.categoria===cat).sort((a,b)=>a.nome.localeCompare(b.nome,'pt-BR'))){const o=n('option',p.nome+' · '+labels[p.categoria]);o.value=p.id;$('classificationTarget').append(o);}
  if(products.some(p=>p.id===old&&p.ativo&&p.categoria===cat))$('classificationTarget').value=old;
 }
 function previewClassification(){
  const cat=$('classificationCategory').value,merge=$('classificationMode').value==='merge',target=products.find(p=>p.id===$('classificationTarget').value),norm=v=>v.trim().replace(/\s+/g,' ').toLocaleUpperCase('pt-BR');
  const duplicate=products.find(p=>p.id!==classificationSource.id&&p.categoria===cat&&norm(p.nome)===norm(classificationSource.nome));
  $('classificationTargetLabel').hidden=!merge;$('classificationTarget').required=merge;
  let text=merge?target?'As entregas e os saldos de '+classificationSource.nome+' serão unificados em '+target.nome+' ('+labels[cat]+'). O cadastro de origem ficará inativo. As regras por função do destino serão mantidas.':'Escolha um substituto do tipo '+labels[cat]+'.':'O item '+classificationSource.nome+' passará de '+labels[classificationSource.categoria]+' para '+labels[cat]+', mantendo este cadastro e seus saldos.';
  if(!merge&&duplicate)text='Já existe '+duplicate.nome+' em '+labels[cat]+'. Escolha usar esse cadastro como substituto ou renomeie o item antes de mudar o tipo.';
  $('classificationPreview').textContent=text;$('classificationSubmit').disabled=busy||cat===classificationSource.categoria||(merge?!target:!!duplicate);
 }
 function openClassification(p,category){
  classificationSource=p;classificationRequest=null;$('classificationError').textContent='';$('classificationIdentity').textContent=p.nome+' · tipo atual: '+labels[p.categoria];$('classificationCategory').value=category;$('classificationMode').value='keep';classificationTargets();previewClassification();$('productDialog').close();$('classificationDialog').showModal();
 }
 $('productCategory').onchange=()=>{if(!editing)return;const category=$('productCategory').value;$('productCategory').value=editing.categoria;if(category===editing.categoria)return;if(hasProductChanges()){$('productError').textContent='Salve as alterações de nome, tamanhos e regras antes de mudar o tipo.';return;}openClassification(editing,category);};
 $('classificationCategory').onchange=()=>{classificationTargets();previewClassification();};$('classificationMode').onchange=previewClassification;$('classificationTarget').onchange=previewClassification;
 $('classificationForm').onsubmit=e=>{e.preventDefault();if($('classificationSubmit').disabled)return;action(async()=>{
  const target=$('classificationMode').value==='merge'?products.find(p=>p.id===$('classificationTarget').value):null;
  const values={id:classificationSource.id,versao:classificationSource.versao,categoria:$('classificationCategory').value,substituto_id:target?.id||null,versao_substituto:target?.versao||null};
  if(!classificationRequest||Object.entries(values).some(([k,v])=>classificationRequest[k]!==v))classificationRequest={...values,operacao_id:crypto.randomUUID()};
  const result=await RH.result(client.rpc('rh_reclassify_product',{payload:classificationRequest}));if(!result?.operacao_id)throw Error('A alteração não foi confirmada. Tente novamente sem alterar os dados.');
  $('classificationDialog').close();$('group').value=result.categoria;$('search').value=result.id;editing=null;classificationRequest=null;notice('Tipo atualizado para '+labels[result.categoria]+'. As entregas vinculadas já usam a identificação corrigida.');
  try{await load();}catch(error){notice('Tipo atualizado. Clique em Atualizar para recarregar a lista. '+error.message,true);}
 },'classificationError');};
 function openProduct(p){editing=p||null;$('productError').textContent='';$('productTitle').textContent=p?'Editar / renomear item':'Cadastrar item';$('productName').value=p?.nome||'';$('productCategory').value=p?.categoria||'epi';$('productCategory').disabled=false;$('productTypeHelp').hidden=!p;$('productSizes').value=(p?.tamanhos||[]).join(', ');$('allRoles').checked=p?.todas_funcoes||false;$('productActive').checked=p?.ativo??true;
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
 (async()=>{
  try{
   await RH.profile(client);
   const catalogRoles=await RH.result(client.rpc('rh_stock_catalog_roles'));
   managesStock=Array.isArray(catalogRoles);
   if(managesStock){
    roles=catalogRoles;
    const profiles=await RH.fetchAll(client,'profiles','id,name');
    names=Object.fromEntries(profiles.map(p=>[p.id,p.name]));
   }
   $('newProduct').hidden=!managesStock;
   $('newTransfer').hidden=!managesStock;
   $('historyPanel').hidden=!managesStock;
   await load();
   $('app').hidden=false;
   notice(managesStock?'Cadastre os itens e informe o saldo físico de cada filial e tamanho.':'Consulta de estoque. Ajustes e cadastros exigem permissão para administrar o estoque.');
  }catch(e){notice(e.message,true);}
 })();
})();
