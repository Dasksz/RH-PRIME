/* Equipamentos: nomes livres, saldo por entrega e documentos com fotografia imutável. */
(function (global) {
 'use strict';
 const h=React.createElement;
 const esc=v=>String(v??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
 const date=v=>!v?'Não informada':String(v).includes('T')?new Date(v).toLocaleDateString('pt-BR',{timeZone:'America/Sao_Paulo'}):String(v).slice(0,10).split('-').reverse().join('/');
 function nameParts(v){const [base,...rest]=String(v).replace(/\s+-\s*$/,'').trim().split(/\s+-\s+/);return {equipamento:base.trim(),complemento:rest.join(' - ').trim()};}
 function balances(rows){return rows.filter(m=>m.tipo==='entrega').map(m=>({...m,saldo:m.quantidade-rows.filter(r=>r.entrega_origem_id===m.id&&r.tipo!=='entrega').reduce((n,r)=>n+r.quantidade,0)}));}
 function documentHtml(receipt,onlyOperation){
  const s=receipt.snapshot,e=s.colaborador,company=s.empresa||{},all=s.movimentos;
  const selected=onlyOperation?all.filter(m=>m.operacao_id===receipt.id):all;
  const rows=selected.map(m=>{
   const origin=all.find(x=>x.id===m.entrega_origem_id);
   const balance=balances(all).find(x=>x.id===m.id);
   return `<tr><td>${date(m.data_movimento)}</td><td>${m.tipo==='entrega'?'Entrega':m.tipo==='baixa'?'Baixa sem devolução':'Devolução'}</td><td>${esc(m.descricao)}${m.legado?'<br><small>Registro importado do histórico anterior</small>':''}</td><td>${esc(m.ca)}</td><td>${m.quantidade}</td><td>${esc(m.motivo)}${m.observacao?'<br>'+esc(m.observacao):''}${origin?'<br>Ref. entrega '+esc(origin.id.slice(0,8))+' de '+date(origin.data_movimento):''}</td><td>${m.tipo==='entrega'?'Em posse: '+balance.saldo:'Ref.: '+esc(m.entrega_origem_id.slice(0,8))}</td></tr>`;
  }).join('');
  return `<article class="rh-equipment-pdf"><h1>${onlyOperation?'COMPROVANTE DE MOVIMENTAÇÃO / TROCA':'FICHA COMPLETA DE EQUIPAMENTOS'}</h1><p><b>${esc(company.nome||e.local_registro)}</b>${company.cnpj?' · CNPJ: '+esc(company.cnpj):''}</p><p><b>${esc(e.nome)}</b> · CPF: ${esc(e.cpf)}<br>Função: ${esc(e.funcao)} · Setor: ${esc(e.setor)} · Unidade: ${esc(e.unidade)}</p><p>Categoria: ${s.categoria==='epi'?'EPI':'Fardamento'} · Documento: ${esc(receipt.id)}<br>Emitido em: ${esc(new Date(receipt.created_at).toLocaleString('pt-BR',{timeZone:'America/Sao_Paulo'}))}</p><table><thead><tr><th>Data</th><th>Movimentação</th><th>Equipamento / complemento</th><th>CA</th><th>Qtd.</th><th>Motivo / observações</th><th>Situação nesta emissão</th></tr></thead><tbody>${rows}</tbody></table><p>${onlyOperation?'Declaro o recebimento e/ou a devolução dos itens expressamente relacionados acima, conforme os tipos de movimentação e as observações registrados. Baixa sem devolução não representa entrega física do item à empresa.':'Esta ficha apresenta o histórico registrado até a emissão. Não substitui os comprovantes de cada movimentação.'}</p>${onlyOperation?'<div class="signatures"><span>Colaborador: _________________________</span><span>Responsável pela entrega / recebimento: _________________________</span></div>':''}<p class="foot">Entregas anteriores permanecem no histórico. Datas não informadas no legado não foram presumidas.</p></article>`;
 }
 async function pdf(receipt,onlyOperation){
  const container=document.createElement('div');container.className='rh-equipment-pdf-host';container.innerHTML=documentHtml(receipt,onlyOperation);document.body.appendChild(container);
  try{await html2pdf().set({margin:10,filename:(onlyOperation?'Movimentacao_':'Ficha_Equipamentos_')+receipt.id+'.pdf',image:{type:'jpeg',quality:0.98},html2canvas:{scale:2,scrollX:0,scrollY:0},jsPDF:{unit:'mm',format:'a4',orientation:'landscape'},pagebreak:{mode:['css','legacy'],avoid:['tr','.signatures']}}).from(container.firstChild).save();}finally{container.remove();}
 }
 function Control({client,employee,suggestions,onSaved}){
  const [tab,setTab]=React.useState('epi'),[rows,setRows]=React.useState([]),[receipts,setReceipts]=React.useState([]),[loading,setLoading]=React.useState(true),[busy,setBusy]=React.useState(false),[error,setError]=React.useState(''),[notice,setNotice]=React.useState('');
  const empty=()=>({nome:'',ca:'',quantidade:1,data:RH.today(),comprovante:''});
  const [form,setForm]=React.useState(empty),[staged,setStaged]=React.useState([]),[returning,setReturning]=React.useState(null),[substitute,setSubstitute]=React.useState(false),[reason,setReason]=React.useState('Defeito'),[other,setOther]=React.useState(''),[notes,setNotes]=React.useState(''),[returnedQty,setReturnedQty]=React.useState(1),[returnDate,setReturnDate]=React.useState(RH.today),[returnLink,setReturnLink]=React.useState('');
  const operation=React.useRef(null),mounted=React.useRef(true),loadSequence=React.useRef(0);
  const blankOperation=()=>{operation.current=null;setStaged([]);setReturning(null);setSubstitute(false);setForm(empty());setReason('Defeito');setOther('');setNotes('');setReturnedQty(1);setReturnDate(RH.today());setReturnLink('');};
  async function load(){
   const sequence=++loadSequence.current;
   const readMovements=async()=>{const data=[];for(let offset=0;;offset+=1000){const page=await client.from('rh_equipment_movements').select('*').eq('funcionario_id',employee.id).eq('categoria',tab).order('id',{ascending:true}).range(offset,offset+999);if(page.error)throw page.error;data.push(...page.data);if(page.data.length<1000)return {data,error:null};}};
   const [mov,docs]=await Promise.all([readMovements(),client.from('rh_equipment_receipts').select('id,created_at,categoria').eq('funcionario_id',employee.id).eq('categoria',tab).order('created_at',{ascending:false}).limit(30)]);
   if(mov.error)throw mov.error;if(docs.error)throw docs.error;
   if(mounted.current&&sequence===loadSequence.current){setRows(mov.data.sort((a,b)=>(a.data_movimento||'').localeCompare(b.data_movimento||'')||a.created_at.localeCompare(b.created_at)));setReceipts(docs.data);}
  }
  React.useEffect(()=>{mounted.current=true;setLoading(true);setError('');setNotice('');blankOperation();load().catch(e=>{if(mounted.current)setError(e.message);}).finally(()=>{if(mounted.current)setLoading(false);});return()=>{mounted.current=false;};},[employee.id,tab]);
  const options=Array.from(new Set([...(suggestions(tab)||[]).map(x=>x==='BOTA MARLUVAS'?'BOTA':x),...rows.filter(x=>!x.legado).map(x=>x.equipamento)]));
  const items=balances(rows);
  const field=(label,key,type='text',extra={})=>h('label',null,label,h('input',{type,value:form[key],onChange:e=>setForm({...form,[key]:e.target.value}),...extra}));
  function add(e){e.preventDefault();if(!form.nome.trim())return;setStaged([...staged,{...nameParts(form.nome),ca:form.ca,quantidade:Number(form.quantidade),data:form.data,comprovante:form.comprovante}]);setForm({...empty(),data:form.data});operation.current=null;}
  async function issue(onlyOperation,existing){
   setBusy(true);setError('');
   try{
    let receipt=existing;
    if(existing){const r=await client.from('rh_equipment_receipts').select('*').eq('id',existing.id).single();if(r.error)throw r.error;receipt=r.data;}
    else{const r=await client.rpc('rh_registrar_equipamentos',{p_funcionario:employee.id,p_categoria:tab,p_operacao:crypto.randomUUID(),p_itens:[],p_devolucao:null});if(r.error)throw r.error;receipt=r.data;await load();}
    await pdf(receipt,onlyOperation);
   }catch(e){setError('Não foi possível gerar o PDF: '+e.message);}finally{setBusy(false);}
  }
  async function save(e){
   e.preventDefault();setBusy(true);setError('');setNotice('');
   let saved=false;
   try{
    const pending=returning?(substitute?[{...nameParts(form.nome),ca:form.ca,quantidade:Number(form.quantidade),data:form.data,comprovante:form.comprovante}]:[]):staged;
    const motivo=reason==='Outro'?other.trim():reason;
    if(returning&&!motivo)throw Error('Informe o motivo da devolução.');
    if(!pending.length&&!returning)throw Error('Inclua pelo menos um equipamento.');
    operation.current=operation.current||crypto.randomUUID();
    const result=await client.rpc('rh_registrar_equipamentos',{p_funcionario:employee.id,p_categoria:tab,p_operacao:operation.current,p_itens:pending,p_devolucao:returning?{origem:returning.id,tipo:reason==='Perda / extravio'?'baixa':'devolucao',quantidade:Number(returnedQty),data:returnDate,motivo,observacao:notes,comprovante:returnLink}:null});
    if(result.error)throw result.error;
    saved=true;blankOperation();setNotice('Movimentação salva. O comprovante pode ser emitido novamente em Documentos emitidos.');
    await load();if(onSaved)await onSaved();
    try{await pdf(result.data,true);}catch(e){setError('Registro salvo. O PDF falhou: '+e.message+'. Gere novamente em Documentos emitidos.');}
   }catch(e){setError((saved?'Registro salvo; atualização da tela falhou: ':'')+e.message);}finally{setBusy(false);}
  }
  function startReturn(m){blankOperation();setReturning(m);setForm({...empty(),nome:(m.equipamento==='BOTA MARLUVAS'?'BOTA':m.equipamento)+(m.complemento?' - '+m.complemento:'')});setNotice('');setError('');}
  const equipmentFields=h('div',{className:'rh-equip-fields'},field('Item entregue','nome','text',{required:true,list:'rh-equipment-options',maxLength:500,placeholder:'Selecione ou digite: BOTA - marca - tamanho 42',onBlur:()=>{if(options.includes(form.nome))setForm({...form,nome:form.nome+' - '});}}),h('datalist',{id:'rh-equipment-options'},options.map(x=>h('option',{key:x,value:x}))),field('CA (opcional)','ca','text',{maxLength:80}),field('Quantidade','quantidade','number',{min:1,max:10000,required:true}),field('Data da entrega','data','date',{required:true,max:RH.today(),min:returning?returnDate:undefined}),field('Link do comprovante (opcional)','comprovante','url',{placeholder:'https://'}));
  if(loading)return h('div',{className:'rh-equip'},'Carregando equipamentos…');
  return h('section',{className:'rh-equip','aria-label':'Controle de equipamentos'},
   h('div',{className:'rh-equip-tabs'},['epi','fardamento'].map(t=>h('button',{key:t,disabled:busy,onClick:()=>setTab(t),'aria-pressed':tab===t},t==='epi'?'EPIs':'Fardamento'))),
   error&&h('p',{role:'alert',className:'rh-equip-error'},error),notice&&h('p',{role:'status',className:'rh-equip-notice'},notice),
   !returning?h('section',{className:'rh-equip-card'},h('h3',null,'Adicionar equipamento'),h('p',null,'Escolha uma sugestão ou escreva um item. Use “ - ” para complementar com marca, tamanho ou modelo.'),h('form',{onSubmit:add},h('fieldset',{disabled:busy},equipmentFields,h('button',{type:'submit'},'Incluir na entrega'))),staged.length>0&&h('div',null,h('ul',null,staged.map((x,i)=>h('li',{key:i},x.equipamento+(x.complemento?' - '+x.complemento:'')+' · Qtd. '+x.quantidade+' · '+date(x.data),h('button',{disabled:busy,onClick:()=>{setStaged(staged.filter((_,j)=>i!==j));operation.current=null;}},'Remover')))),h('button',{disabled:busy,onClick:save},busy?'Salvando…':'Salvar entrega e gerar comprovante'))):
   h('section',{className:'rh-equip-card',role:'region','aria-label':'Registrar devolução ou troca'},h('h3',null,'Devolver / Trocar — '+returning.descricao),h('p',null,'Entrega original: '+date(returning.data_movimento)+' · Em posse: '+returning.saldo),h('form',{onSubmit:save},h('fieldset',{disabled:busy},h('div',{className:'rh-equip-fields'},
    h('label',null,'Quantidade devolvida / baixada',h('input',{type:'number',min:1,max:returning.saldo,required:true,value:returnedQty,onChange:e=>setReturnedQty(e.target.value)})),
    h('label',null,'Data da devolução / baixa',h('input',{type:'date',required:true,min:returning.data_movimento||undefined,max:RH.today(),value:returnDate,onChange:e=>setReturnDate(e.target.value)})),
    h('label',null,'Motivo',h('select',{value:reason,onChange:e=>setReason(e.target.value)},['Defeito','Rasgo','Desgaste','Tamanho inadequado','Desligamento','Perda / extravio','Outro'].map(x=>h('option',{key:x},x)))),
    reason==='Outro'&&h('label',null,'Informe o motivo',h('input',{required:true,maxLength:300,value:other,onChange:e=>setOther(e.target.value)})),
    h('label',null,'Link da evidência (opcional)',h('input',{type:'url',value:returnLink,onChange:e=>setReturnLink(e.target.value)}))),
    h('label',null,'Observações',h('textarea',{value:notes,maxLength:2000,onChange:e=>setNotes(e.target.value)})),
    reason==='Perda / extravio'&&h('p',null,'Será registrada uma baixa sem devolução física.'),
    h('label',{className:'rh-equip-check'},h('input',{type:'checkbox',checked:substitute,onChange:e=>setSubstitute(e.target.checked)}),'Entregar um substituto'),
    substitute&&equipmentFields,h('div',{className:'rh-equip-actions'},h('button',{type:'submit'},busy?'Salvando…':substitute?'Salvar devolução e nova entrega':'Salvar devolução / baixa'),h('button',{type:'button',onClick:blankOperation},'Cancelar'))))),
   h('section',{className:'rh-equip-card'},h('div',{className:'rh-equip-actions'},h('h3',null,'Histórico de equipamentos'),h('button',{disabled:busy||!rows.length,onClick:()=>issue(false)},'Gerar ficha completa (PDF)')),
    !items.length&&h('p',null,'Nenhuma entrega registrada.'),
    items.slice().reverse().map(m=>h('article',{key:m.id,className:'rh-equip-item'},h('strong',null,m.descricao),h('p',null,'Entrega: '+date(m.data_movimento)+' · CA: '+(m.ca||'—')+' · Entregues: '+m.quantidade+' · Em posse: '+m.saldo),m.legado&&h('small',null,'Importado do histórico anterior'),m.entrega_origem_id&&h('p',null,'Substitui a entrega '+m.entrega_origem_id.slice(0,8)),
     rows.filter(r=>r.entrega_origem_id===m.id&&r.tipo!=='entrega').map(r=>h('p',{key:r.id},(r.tipo==='baixa'?'Baixa sem devolução':'Devolução')+': '+date(r.data_movimento)+' · Qtd. '+r.quantidade+' · '+r.motivo+(r.observacao?' — '+r.observacao:''))),
     m.saldo>0&&h('button',{disabled:busy,onClick:()=>startReturn(m)},'Devolver / Trocar')))),
   receipts.length>0&&h('section',{className:'rh-equip-card'},h('h3',null,'Documentos emitidos'),receipts.map(r=>h('div',{className:'rh-equip-actions',key:r.id},h('span',null,date(r.created_at)+' · '+r.id.slice(0,8)),h('button',{disabled:busy,onClick:()=>issue(false,r)},'Ficha desta emissão'),rows.some(m=>m.operacao_id===r.id)&&h('button',{disabled:busy,onClick:()=>issue(true,r)},'Comprovante da movimentação'))))
  );
 }
 global.RHEquipment={Control,nameParts,balances,documentHtml};
})(window);
