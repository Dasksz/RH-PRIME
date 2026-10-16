/* Equipamentos: nomes livres, saldo por entrega e documentos com fotografia imutável. */
(function (global) {
 'use strict';
 const h=React.createElement;
 const icon=(name,size=18)=>h('svg',{width:size,height:size,viewBox:'0 0 24 24',fill:'none',stroke:'currentColor',strokeWidth:2,strokeLinecap:'round',strokeLinejoin:'round','aria-hidden':true},...(name==='add'?[h('path',{key:1,d:'M8 6h13M8 12h7M8 18h7M3 6h.01M3 12h.01M3 18h.01M19 15v6M16 18h6'})]:name==='shirt'?[h('path',{key:1,d:'m16 3 6 4-3 5-3-2v11H8V10l-3 2-3-5 6-4a4 4 0 0 0 8 0Z'})]:name==='calendar'?[h('rect',{key:1,x:3,y:5,width:18,height:16,rx:2}),h('path',{key:2,d:'M16 3v4M8 3v4M3 11h18'})]:name==='check'?[h('circle',{key:1,cx:12,cy:12,r:9}),h('path',{key:2,d:'m8 12 3 3 5-6'})]:[h('path',{key:1,d:'M12 3 3 7v6c0 5 9 9 9 9s9-4 9-9V7Z'})]));
 const esc=v=>String(v??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
 const date=v=>!v?'Não informada':String(v).includes('T')?new Date(v).toLocaleDateString('pt-BR',{timeZone:'America/Sao_Paulo'}):String(v).slice(0,10).split('-').reverse().join('/');
 function nameParts(v){const [base,...rest]=String(v).replace(/\s+-\s*$/,'').trim().split(/\s+-\s+/);return {equipamento:base.trim(),complemento:rest.join(' - ').trim()};}
 function balances(rows){return rows.filter(m=>m.tipo==='entrega').map(m=>({...m,saldo:m.quantidade-rows.filter(r=>r.entrega_origem_id===m.id&&r.tipo!=='entrega').reduce((n,r)=>n+r.quantidade,0)}));}
 function latestChecks(checks){return checks.reduce((map,c)=>{const old=map[c.entrega_id];if(!old||(c.data_verificacao+(c.created_at||''))>(old.data_verificacao+(old.created_at||'')))map[c.entrega_id]=c;return map;},{});}
 function latestCorrections(corrections){return corrections.reduce((map,c)=>{if(!map[c.entrega_id]||c.created_at>map[c.entrega_id].created_at)map[c.entrega_id]=c;return map;},{});}
 function needsReview(m,checks,today){const last=checks[m.id]?.data_verificacao||m.data_movimento;return m.saldo>0&&!!last&&(Date.parse(today)-Date.parse(last))/86400000>=180;}
 function documentRows(receipt,onlyOperation){
  const all=receipt.snapshot.movimentos,rows=[],verified=latestChecks(receipt.snapshot.verificacoes||[]);
  for(const m of all.filter(x=>x.tipo==='entrega')){
   const movements=all.filter(r=>r.entrega_origem_id===m.id&&r.tipo!=='entrega');
   const selected=onlyOperation?movements.filter(r=>r.operacao_id===receipt.id):movements;
   const origin=all.find(r=>r.id===m.entrega_origem_id);
   const check=verified[m.id];
   const description=esc(m.descricao)+(origin?'<br><small>Reposição referente à entrega de '+date(origin.data_movimento)+'</small>':'')+(check?'<br><small>Verificado em '+date(check.data_verificacao)+' — em boas condições</small>':'');
   for(const r of selected){
    const partial=r.quantidade<m.quantidade?' (devolução parcial: '+r.quantidade+' de '+m.quantidade+')':'';
    rows.push({nomeItem:description,ca:esc(m.ca),qtd:r.quantidade,dataEntrega:m.data_movimento,
     dataDevolucao:r.tipo==='devolucao'?r.data_movimento:null,
     motivoDevolucao:esc((r.tipo==='baixa'?'Baixa sem devolução física em '+date(r.data_movimento)+': ':'')+r.motivo+partial+(r.observacao?' — '+r.observacao:''))});
   }
   if(!onlyOperation||m.operacao_id===receipt.id){
    const remaining=m.quantidade-movements.reduce((n,r)=>n+r.quantidade,0);
    if(remaining>0)rows.push({nomeItem:description,ca:esc(m.ca),qtd:remaining,dataEntrega:m.data_movimento,dataDevolucao:null,motivoDevolucao:''});
   }
  }
  return rows;
 }
 function documentHtml(receipt,onlyOperation){
  const s=receipt.snapshot,e=s.colaborador,company=s.empresa||{};
  const relevant=onlyOperation?s.movimentos.filter(m=>m.operacao_id===receipt.id):s.movimentos;
  const employee=Object.fromEntries(Object.entries({...e,cargo:e.funcao}).map(([k,v])=>[k,esc(v)]));
  const empresa=Object.fromEntries(Object.entries({...company,nome:company.nome||e.local_registro}).map(([k,v])=>[k,esc(v)]));
  const current=s.movimentos.filter(m=>m.operacao_id===receipt.id);
  const currentChecks=(s.verificacoes||[]).filter(v=>v.operacao_id===receipt.id);
  const hasReturns=current.some(m=>m.tipo==='devolucao'),hasDeliveries=(current.length?current:currentChecks.length?[]:relevant).some(m=>m.tipo==='entrega');
  return RHFichaPadrao.render(employee,documentRows(receipt,onlyOperation),empresa,hasReturns,hasDeliveries);
 }
 async function pdf(receipt,onlyOperation){
  const container=document.createElement('div');container.className='rh-equipment-pdf-host';container.innerHTML=documentHtml(receipt,onlyOperation);document.body.appendChild(container);
  try{await html2pdf().set({margin:5,filename:(onlyOperation?'Movimentacao_':'Ficha_Equipamentos_')+receipt.id+'.pdf',image:{type:'jpeg',quality:0.98},html2canvas:{scale:2,scrollX:0,scrollY:0},jsPDF:{unit:'mm',format:'a4',orientation:'landscape'},pagebreak:{mode:['css','legacy'],avoid:['tr','.signatures']}}).from(container.firstElementChild).save();}finally{container.remove();}
 }
 function Control({client,employee,suggestions,onSaved,onVerificationChange}){
  const [tab,setTab]=React.useState('epi'),[rows,setRows]=React.useState([]),[receipts,setReceipts]=React.useState([]),[loading,setLoading]=React.useState(true),[busy,setBusy]=React.useState(false),[error,setError]=React.useState(''),[notice,setNotice]=React.useState('');
  const [deliveryOnly,setDeliveryOnly]=React.useState(false),[verifying,setVerifying]=React.useState(false),[returns,setReturns]=React.useState([]),[staged,setStaged]=React.useState([]),[checks,setChecks]=React.useState([]),[inspected,setInspected]=React.useState([]),[verificationDate,setVerificationDate]=React.useState(RH.today);
  const [corrections,setCorrections]=React.useState([]),[editingDate,setEditingDate]=React.useState(null),editRef=React.useRef(null);
  const empty=()=>({nome:'',ca:'',quantidade:1,data:RH.today(),comprovante:''});
  const [form,setForm]=React.useState(empty),[returning,setReturning]=React.useState(null),[substitute,setSubstitute]=React.useState(false),[reason,setReason]=React.useState('Defeito'),[other,setOther]=React.useState(''),[notes,setNotes]=React.useState(''),[returnedQty,setReturnedQty]=React.useState(1),[returnDate,setReturnDate]=React.useState(RH.today),[returnLink,setReturnLink]=React.useState('');
  const operation=React.useRef(null),mounted=React.useRef(true),loadSequence=React.useRef(0);
  function clearEditor(){setReturning(null);setSubstitute(false);setForm(empty());setReason('Defeito');setOther('');setNotes('');setReturnedQty(1);setReturnDate(RH.today());setReturnLink('');}
  function clearVerification(){setDeliveryOnly(false);operation.current=null;setStaged([]);setReturns([]);setInspected([]);setVerificationDate(RH.today());clearEditor();setVerifying(false);}
  async function load(){
   const sequence=++loadSequence.current;
   const readMovements=async()=>{const data=[];for(let offset=0;;offset+=1000){const page=await client.from('rh_equipment_movements').select('*').eq('funcionario_id',employee.id).eq('categoria',tab).order('id',{ascending:true}).range(offset,offset+999);if(page.error)throw page.error;data.push(...page.data);if(page.data.length<1000)return {data};}};
   const readChecks=async()=>{const data=[];for(let offset=0;;offset+=1000){const page=await client.from('rh_equipment_checks').select('*').eq('funcionario_id',employee.id).eq('categoria',tab).order('id',{ascending:true}).range(offset,offset+999);if(page.error)throw page.error;data.push(...page.data);if(page.data.length<1000)return data;}};
   const readCorrections=async()=>{const data=[];for(let offset=0;;offset+=1000){const page=await client.from('rh_equipment_date_corrections').select('*').eq('funcionario_id',employee.id).order('id',{ascending:true}).range(offset,offset+999);if(page.error)throw page.error;data.push(...page.data);if(page.data.length<1000)return data;}};
   const [mov,docs,verifiedRows,correctedRows]=await Promise.all([readMovements(),client.from('rh_equipment_receipts').select('id,created_at,categoria').eq('funcionario_id',employee.id).eq('categoria',tab).order('created_at',{ascending:false}).limit(30),readChecks(),readCorrections()]);
   if(docs.error)throw docs.error;
   if(mounted.current&&sequence===loadSequence.current){setRows(mov.data.sort((a,b)=>(a.data_movimento||'').localeCompare(b.data_movimento||'')||a.created_at.localeCompare(b.created_at)));setReceipts(docs.data);setChecks(verifiedRows);setCorrections(correctedRows);}
  }
  React.useEffect(()=>{mounted.current=true;setLoading(true);setError('');setNotice('');setEditingDate(null);clearVerification();load().catch(e=>{if(mounted.current)setError(e.message);}).finally(()=>{if(mounted.current)setLoading(false);});return()=>{mounted.current=false;};},[employee.id,tab]);
  React.useEffect(()=>{if(editingDate&&editRef.current){editRef.current.scrollIntoView({block:'center',behavior:'smooth'});editRef.current.querySelector('input')?.focus({preventScroll:true});}},[editingDate?.row.id]);
  React.useEffect(()=>{if(onVerificationChange)onVerificationChange(verifying);const warn=e=>{e.preventDefault();e.returnValue='';};if(verifying)window.addEventListener('beforeunload',warn);return()=>{window.removeEventListener('beforeunload',warn);if(onVerificationChange)onVerificationChange(false);};},[verifying]);
  const options=Array.from(new Set([...(suggestions(tab)||[]).map(x=>x==='BOTA MARLUVAS'?'BOTA':x),...rows.filter(x=>!x.legado).map(x=>x.equipamento)]));
  const items=balances(rows),current=items.filter(m=>m.saldo>0),verified=latestChecks(checks);
  const corrected=latestCorrections(corrections);
  function startDateEdit(m){if(staged.length||returns.length||inspected.length||returning||form.nome.trim()){setError('Conclua ou cancele os itens em preenchimento antes de editar uma data salva.');return;}clearVerification();setEditingDate({row:m,data:m.data_movimento||'',motivo:''});setError('');setNotice('');}
  async function saveDate(e){e.preventDefault();if(!editingDate)return;const edit=editingDate;setBusy(true);setError('');let saved=false;try{const result=await client.rpc('rh_corrigir_data_entrega',{p_entrega:edit.row.id,p_data:edit.data,p_data_anterior:edit.row.data_movimento,p_motivo:edit.motivo});if(result.error)throw result.error;if(result.data?.data_movimento!==edit.data)throw Error('A data retornada não corresponde à correção. Atualize a tela.');saved=true;setEditingDate(null);setNotice('Data da entrega salva: '+date(edit.data)+'. A correção ficou registrada no histórico; fichas já emitidas foram preservadas.');await load();if(onSaved)await onSaved();}catch(err){setError((saved?'Data salva; falha ao atualizar a tela: ':'Não foi possível corrigir a data: ')+err.message);}finally{setBusy(false);}}
  const auditLabel=m=>{const c=corrected[m.id];return h('div',{className:'rh-equip-authorship'},h('small',null,'Registrado por: '+(m.registrado_por||'Responsável não identificado')),
   c&&h('small',null,'Última edição por: '+(c.primeiro_nome||'Responsável não identificado')+' · '+new Date(c.created_at).toLocaleString('pt-BR',{timeZone:'America/Sao_Paulo',dateStyle:'short',timeStyle:'short'})),
   c&&h('small',null,'Data corrigida de '+date(c.data_anterior)+' para '+date(c.data_corrigida)+' · '+c.motivo));};
  const groups=Object.entries(items.reduce((g,m)=>{const key=m.data_movimento||'';(g[key]||(g[key]=[])).push(m);return g;},{})).sort(([a],[b])=>b.localeCompare(a));
  const field=(label,key,type='text',extra={})=>h('label',null,label,h('input',{type,value:form[key],onChange:e=>setForm({...form,[key]:e.target.value}),...extra}));
  const delivery=()=>({...nameParts(form.nome),ca:form.ca,quantidade:Number(form.quantidade),data:form.data,comprovante:form.comprovante});
  function add(e){e.preventDefault();if(!form.nome.trim())return;if(!verifying){setDeliveryOnly(true);setVerifying(true);}setStaged([...staged,delivery()]);setForm({...empty(),data:form.data});operation.current=null;setError('');}
  function openVerification(){setDeliveryOnly(false);setVerifying(true);setError('');setNotice('');}
  function cancelVerification(){if((staged.length||returns.length||inspected.length||returning||form.nome.trim())&&!window.confirm('Descartar as alterações desta verificação? Nenhuma movimentação foi salva.'))return;clearVerification();setError('');}
  function markVerified(m,checked){setInspected(checked?[...inspected.filter(v=>v.origem!==m.id),{origem:m.id,descricao:m.descricao,data:verificationDate}]:inspected.filter(v=>v.origem!==m.id));operation.current=null;}
  function startReturn(m){if(form.nome.trim()){setError('Inclua ou limpe o equipamento em preenchimento antes de preparar outra devolução.');return;}clearEditor();setReturning(m);setForm({...empty(),nome:(m.equipamento==='BOTA MARLUVAS'?'BOTA':m.equipamento)+(m.complemento?' - '+m.complemento:'')});setError('');}
  function stageReturn(e){
   e.preventDefault();const motivo=reason==='Outro'?other.trim():reason;
   if(!motivo){setError('Informe o motivo da devolução.');return;}
   const r={origem:returning.id,descricao:returning.descricao,tipo:reason==='Perda / extravio'?'baixa':'devolucao',quantidade:Number(returnedQty),data:returnDate,motivo,observacao:notes,comprovante:returnLink};
   setReturns([...returns,r]);setInspected(inspected.filter(v=>v.origem!==returning.id));if(substitute)setStaged([...staged,{...delivery(),origem:returning.id}]);operation.current=null;clearEditor();setError('');
  }
  function removeReturn(id){setReturns(returns.filter(r=>r.origem!==id));setStaged(staged.filter(i=>i.origem!==id));operation.current=null;}
  async function issue(onlyOperation,existing){
   setBusy(true);setError('');try{let receipt=existing;if(existing){const r=await client.from('rh_equipment_receipts').select('*').eq('id',existing.id).single();if(r.error)throw r.error;receipt=r.data;}else{const r=await client.rpc('rh_registrar_equipamentos',{p_funcionario:employee.id,p_categoria:tab,p_operacao:crypto.randomUUID(),p_itens:[],p_devolucao:null});if(r.error)throw r.error;receipt=r.data;await load();}await pdf(receipt,onlyOperation);}catch(e){setError('Não foi possível gerar o PDF: '+e.message);}finally{setBusy(false);}
  }
  async function finish(){
   if(returning||form.nome.trim()){setError('Inclua ou cancele o item em preenchimento antes de concluir a verificação.');return;}
   setBusy(true);setError('');setNotice('');let saved=false;
   try{
    operation.current=operation.current||crypto.randomUUID();
    if(!staged.length&&!returns.length&&!inspected.length)throw Error('Marque os itens conferidos ou inclua as devoluções e novas entregas antes de concluir.');
    const result=await client.rpc('rh_registrar_equipamentos',{p_funcionario:employee.id,p_categoria:tab,p_operacao:operation.current,p_itens:[...staged,...inspected.map(v=>({acao:'verificacao',origem:v.origem,data:v.data}))],p_devolucao:returns});
    if(result.error)throw result.error;saved=true;clearVerification();setNotice(deliveryOnly?'Entrega salva. A ficha está disponível em Documentos emitidos.':'Verificação concluída. As conferências, devoluções e entregas estão registradas na ficha. Você pode emiti-la novamente em Documentos emitidos.');
    await load();if(onSaved)await onSaved();
    try{await pdf(result.data,false);}catch(e){setError('Verificação salva. O PDF falhou: '+e.message+'. Gere novamente em Documentos emitidos.');}
   }catch(e){setError((saved?'Verificação salva; atualização da tela falhou: ':'')+e.message);}finally{setBusy(false);}
  }
  const equipmentFields=h('div',{className:'rh-equip-fields'},field('Item entregue','nome','text',{required:true,list:'rh-equipment-options',maxLength:500,placeholder:'Selecione ou digite o item e seu complemento',onBlur:()=>{if(options.includes(form.nome))setForm({...form,nome:form.nome+' - '});}}),h('datalist',{id:'rh-equipment-options'},options.map(x=>h('option',{key:x,value:x}))),field('C.A. (opcional)','ca','text',{maxLength:80}),field('Qtd.','quantidade','number',{min:1,max:10000,required:true}),field('Data da entrega','data','date',{required:true,max:RH.today(),min:returning?returnDate:undefined}),field('Link comprovante','comprovante','url',{placeholder:'Opcional…'}));
  const returnForm=returning&&h('section',{className:'rh-equip-card',role:'region','aria-label':'Preparar devolução ou troca'},h('h3',null,'Devolver / Trocar — '+returning.descricao),h('p',null,'Entrega original: '+date(returning.data_movimento)+' · Em posse: '+returning.saldo),h('form',{onSubmit:stageReturn},h('fieldset',{disabled:busy},h('div',{className:'rh-equip-fields'},
   h('label',null,'Quantidade devolvida / baixada',h('input',{type:'number',min:1,max:returning.saldo,required:true,value:returnedQty,onChange:e=>setReturnedQty(e.target.value)})),
   h('label',null,'Data da devolução / baixa',h('input',{type:'date',required:true,min:returning.data_movimento||undefined,max:RH.today(),value:returnDate,onChange:e=>setReturnDate(e.target.value)})),
   h('label',null,'Motivo',h('select',{value:reason,onChange:e=>setReason(e.target.value)},['Defeito','Rasgo','Desgaste','Tamanho inadequado','Desligamento','Perda / extravio','Outro'].map(x=>h('option',{key:x},x)))),
   reason==='Outro'&&h('label',null,'Informe o motivo',h('input',{required:true,maxLength:300,value:other,onChange:e=>setOther(e.target.value)})),
   h('label',null,'Link da evidência (opcional)',h('input',{type:'url',value:returnLink,onChange:e=>setReturnLink(e.target.value)}))),
   h('label',null,'Observações',h('textarea',{value:notes,maxLength:2000,onChange:e=>setNotes(e.target.value)})),reason==='Perda / extravio'&&h('p',null,'Será registrada uma baixa sem devolução física.'),
   h('label',{className:'rh-equip-check'},h('input',{type:'checkbox',checked:substitute,onChange:e=>setSubstitute(e.target.checked)}),'Entregar um substituto'),substitute&&equipmentFields,
   h('div',{className:'rh-equip-actions'},h('button',{type:'submit'},substitute?'Incluir devolução e substituto na verificação':'Incluir devolução na verificação'),h('button',{type:'button',onClick:clearEditor},'Cancelar este item')))));
  const summary=h('section',{className:'rh-equip-card','aria-label':deliveryOnly?'Prontos para salvar':'Resumo da verificação'},h('h3',null,deliveryOnly?'Prontos para salvar ('+staged.length+')':'Resumo da verificação'),
     !returns.length&&!staged.length&&!inspected.length&&h('p',null,'Marque os itens em boas condições ou inclua as devoluções e novas entregas.'),
     inspected.map(v=>h('div',{key:v.origem,className:'rh-equip-item'},h('strong',null,'Verificado: '+v.descricao),h('p',null,date(v.data)+' — em boas condições'),h('button',{className:'rh-equip-action',disabled:busy,onClick:()=>{setInspected(inspected.filter(x=>x.origem!==v.origem));operation.current=null;}},'Desmarcar verificação'))),
     returns.map(r=>h('div',{key:r.origem,className:'rh-equip-item'},h('strong',null,(r.tipo==='baixa'?'Baixa sem devolução: ':'Devolver: ')+r.descricao),h('p',null,'Qtd. '+r.quantidade+' · '+date(r.data)+' · '+r.motivo+(r.observacao?' — '+r.observacao:'')),h('button',{className:'rh-equip-action',disabled:busy,onClick:()=>removeReturn(r.origem),'aria-label':'Remover devolução de '+r.descricao},'Remover devolução e substituto'))),
     staged.map((i,index)=>h('div',{key:index,className:'rh-equip-item'},h('strong',null,(i.origem?'Substituto: ':'Nova entrega: ')+i.equipamento+(i.complemento?' - '+i.complemento:'')),h('p',null,'Qtd. '+i.quantidade+' · CA: '+(i.ca||'—')+' · '+date(i.data)),!i.origem&&h('button',{className:'rh-equip-action',disabled:busy||!!form.nome.trim(),onClick:()=>{setForm({nome:i.equipamento+(i.complemento?' - '+i.complemento:''),ca:i.ca,quantidade:i.quantidade,data:i.data,comprovante:i.comprovante});setStaged(staged.filter((_,j)=>j!==index));operation.current=null;}},'Editar'),h('button',{className:'rh-equip-action',disabled:busy,onClick:()=>{setStaged(staged.filter((_,j)=>j!==index));operation.current=null;},'aria-label':'Remover nova entrega de '+i.equipamento},'Remover'))),
     h('div',{className:'rh-equip-actions rh-equip-finish'},h('button',{className:'rh-equip-primary',disabled:busy||!!returning||(!returns.length&&!staged.length&&!inspected.length),onClick:finish},busy?'Salvando…':deliveryOnly?'Salvar e gerar ficha':'Concluir verificação e gerar ficha'),deliveryOnly&&h('button',{className:'rh-equip-action',disabled:busy,onClick:cancelVerification},'Cancelar entrega')));
  const historyCards=groups.map(([when,list],index)=>{const expired=list.some(m=>needsReview(m,verified,RH.today()));return h('section',{className:'rh-equip-card rh-equip-history-group'+(expired?' rh-equip-expired':''),key:when},
   h('div',{className:'rh-equip-history-heading'},h('span',{className:'rh-equip-history-status'},icon('check',16)),h('div',null,h('h4',null,index===0?'Última Entrega':'Entrega Anterior'),h('p',null,icon('calendar',12),date(when)),expired&&h('span',{className:'rh-equip-expired-label'},'Verificação pendente · 180 dias'))),h('strong',{className:'rh-equip-items-label'},'Itens:'),
   h('ul',null,list.map(m=>h('li',{key:m.id},
    h('span',null,m.descricao+(m.ca?' (CA: '+m.ca+')':'')+' — Qtd: '+m.quantidade+(m.saldo!==m.quantidade?' · Em posse: '+m.saldo:'')),
    h('button',{type:'button',className:'rh-equip-action rh-equip-date-edit',disabled:busy||!!editingDate,onClick:()=>startDateEdit(m),'aria-label':'Editar data da entrega de '+m.descricao},'Editar data'),auditLabel(m),
    needsReview(m,verified,RH.today())&&h('small',{className:'rh-equip-review-note'},'Este item em posse completou 180 dias desde a entrega ou última conferência. Verifique suas condições.'),
    checks.filter(v=>v.entrega_id===m.id).sort((a,b)=>b.data_verificacao.localeCompare(a.data_verificacao)).map(v=>h('small',{key:v.id,className:'rh-equip-verified'},'Verificado em '+date(v.data_verificacao)+' — em boas condições')),
    m.entrega_origem_id&&h('small',null,'Reposição vinculada à entrega original'),
    rows.filter(r=>r.entrega_origem_id===m.id&&r.tipo!=='entrega').map(r=>h('small',{key:r.id},(r.tipo==='baixa'?'Baixa sem devolução':'Devolução')+': '+date(r.data_movimento)+' · Qtd. '+r.quantidade+' · '+r.motivo+(r.observacao?' — '+r.observacao:''))),
    m.comprovante&&/^https?:\/\//i.test(m.comprovante)&&h('a',{href:m.comprovante,target:'_blank',rel:'noopener noreferrer'},'Ver comprovante')
   )))
  );});
  if(loading)return h('div',{className:'rh-equip'},'Carregando equipamentos…');
  return h('section',{className:'rh-equip','aria-label':'Controle de equipamentos'},
   h('div',{className:'rh-equip-tabs'},['epi','fardamento'].map(t=>h('button',{key:t,disabled:busy||verifying,onClick:()=>setTab(t),'aria-pressed':tab===t},icon(t==='epi'?'shield':'shirt'),t==='epi'?'EPIs':'Fardas'))),
   error&&h('p',{role:'alert',className:'rh-equip-error'},error),notice&&h('p',{role:'status',className:'rh-equip-notice'},notice),
   editingDate&&h('section',{ref:editRef,className:'rh-equip-card rh-equip-date-form','aria-label':'Corrigir data de entrega'},h('h3',null,'Editar data — '+editingDate.row.descricao),h('p',null,'Data atual: '+date(editingDate.row.data_movimento)),h('form',{onSubmit:saveDate},h('fieldset',{disabled:busy},h('label',null,'Data da entrega',h('input',{type:'date',required:true,max:RH.today(),value:editingDate.data,onChange:e=>setEditingDate({...editingDate,data:e.target.value})})),h('label',null,'Motivo da correção',h('textarea',{required:true,minLength:3,maxLength:500,value:editingDate.motivo,onChange:e=>setEditingDate({...editingDate,motivo:e.target.value}),placeholder:'Ex.: data digitada incorretamente no cadastro anterior'})),h('p',{className:'rh-equip-date-note'},'A nova data será usada no histórico e nas próximas fichas. Os documentos já emitidos continuam preservados.'),h('div',{className:'rh-equip-actions'},h('button',{type:'submit',disabled:editingDate.data===editingDate.row.data_movimento},busy?'Salvando…':'Salvar data'),h('button',{type:'button',className:'rh-equip-action',onClick:()=>setEditingDate(null)},'Cancelar'))))),
   !returning&&!editingDate&&h('section',{className:'rh-equip-card rh-equip-add'},h('h3',null,icon('add'),'Adicionar '+(tab==='epi'?'EPI':'Fardamento')),h('form',{onSubmit:add},h('fieldset',{disabled:busy,className:'rh-equip-add-fields'},equipmentFields,h('button',{type:'submit'},'＋ Incluir'))),deliveryOnly&&summary),
   verifying&&!deliveryOnly&&h('section',{className:'rh-equip-verification','aria-label':'Verificação em andamento'},
    h('div',{className:'rh-equip-actions'},h('h3',null,deliveryOnly?'Nova entrega':'Verificação em andamento'),h('button',{className:'rh-equip-action',disabled:busy,onClick:cancelVerification},deliveryOnly?'Cancelar entrega':'Cancelar verificação')),
    !deliveryOnly&&h('p',null,'Confira os itens em posse. Marque os que estão em boas condições ou prepare as devoluções e substituições. Tudo será salvo ao concluir.'),
    !deliveryOnly&&h('label',{className:'rh-equip-check-date'},'Data da verificação',h('input',{type:'date',required:true,max:RH.today(),value:verificationDate,onChange:e=>setVerificationDate(e.target.value),disabled:busy})),
    !deliveryOnly&&h('section',{className:'rh-equip-card'},h('h3',null,'Itens em posse'),!current.length&&h('p',null,'Nenhum item em posse nesta categoria.'),current.map(m=>{const prepared=returns.find(r=>r.origem===m.id),checked=inspected.find(v=>v.origem===m.id),last=verified[m.id];return h('article',{key:m.id,className:'rh-equip-item'},h('div',{className:'rh-equip-item-heading'},h('strong',null,m.descricao),prepared?h('span',{className:'rh-equip-prepared'},'Devolução preparada'):h('button',{className:'rh-equip-action rh-equip-return',disabled:busy||!!returning,onClick:()=>startReturn(m),'aria-label':'Devolver ou trocar '+m.descricao},'Devolver / Trocar')),h('p',null,'Entrega: '+date(m.data_movimento)+' · CA: '+(m.ca||'—')+' · Em posse: '+m.saldo),h('button',{type:'button',className:'rh-equip-action rh-equip-date-edit',disabled:busy,onClick:()=>startDateEdit(m)},'Editar data'),auditLabel(m),last&&h('small',{className:'rh-equip-verified'},'Última verificação: '+date(last.data_verificacao)+' — em boas condições'),!prepared&&h('label',{className:'rh-equip-check'},h('input',{type:'checkbox',checked:!!checked,disabled:busy||!!returning||!verificationDate||!!(m.data_movimento&&verificationDate<m.data_movimento),onChange:e=>markVerified(m,e.target.checked),'aria-label':'Marcar como verificado '+m.descricao}),checked?'Verificado em '+date(checked.data)+' — em boas condições':'Marcar como verificado — em boas condições'));})),
    returnForm,
    summary),
   h('section',{className:'rh-equip-history'},h('div',{className:'rh-equip-actions'},h('h3',null,'Histórico Salvo'),
    h('button',{className:'rh-equip-action rh-equip-document',disabled:busy||verifying||!rows.length,onClick:()=>issue(false)},'Gerar Ficha (PDF)'),
    (!verifying||deliveryOnly)&&h('button',{className:'rh-equip-action rh-equip-open',disabled:busy,onClick:openVerification},'Abrir verificação')),
    !groups.length&&h('div',{className:'rh-equip-empty'},'Nenhum registro encontrado.'),
    h('div',{className:'rh-equip-history-grid'},historyCards)),
   receipts.length>0&&h('section',{className:'rh-equip-card'},h('h3',null,'Documentos emitidos'),receipts.map(r=>h('div',{className:'rh-equip-actions',key:r.id},h('span',null,date(r.created_at)+' · '+r.id.slice(0,8)),h('button',{className:'rh-equip-action',disabled:busy||verifying,onClick:()=>issue(false,r)},'Ficha desta emissão'),rows.some(m=>m.operacao_id===r.id)&&h('button',{className:'rh-equip-action',disabled:busy||verifying,onClick:()=>issue(true,r)},'Comprovante da movimentação'))))
  );
 }

 global.RHEquipment={Control,nameParts,balances,latestChecks,latestCorrections,needsReview,documentRows,documentHtml};
})(window);
