/* PDFs ficam no computador; somente manifesto e avisos são registrados. */
(function(){
 'use strict';
 const portal='https://sistema.facilitaponto.com.br/portal';
 const exportIds=new Map();let exports=[];
 function download(blob,name){const url=URL.createObjectURL(blob),a=document.createElement('a');a.href=url;a.download=name;a.click();setTimeout(()=>URL.revokeObjectURL(url),60000);}
 function message(name,kind,period){const assunto=kind.trim().toUpperCase()==='FOLHA DE PONTO'?'Sua folha de ponto, referente a '+period+', está disponível':'Seus documentos de '+kind+', referentes a '+period+', estão disponíveis';return 'Olá, '+name+'!\n\nAqui é do RH. '+assunto+' no Facilita Ponto para visualização e assinatura.\n\nAcesse o Portal do Colaborador:\n'+portal+'\n\nFaça login com seu CPF (somente números) e o código da empresa: 032612.\nApós entrar, abra os documentos disponíveis e conclua a assinatura.\n\nEm caso de dificuldade, procure o RH.';}
 async function register(manifest){
  if(manifest?.format!=='rh-facilita-export-v1'||!Array.isArray(manifest.documents)||!manifest.documents.length)throw Error('Arquivo de controle de lote inválido.');
  return RH.result(client.rpc('rh_register_signature_export',{p_id:manifest.id,p_name:manifest.name,p_type:manifest.kind,p_period:manifest.period,p_documents:manifest.documents}));
 }
 el('upload').textContent='Baixar selecionados em ZIP para o Facilita Ponto';
 el('upload').onclick=()=>action(async()=>{
  const selected=localDocs.filter(d=>d.selected&&!d.error);
  if(!selected.length)throw Error('Selecione os PDFs que deseja baixar.');
  const kind=selected[0].kind,period=selected[0].period;
  if(selected.some(d=>d.kind!==kind||d.period!==period))throw Error('Exporte cada tipo e competência em seu próprio lote.');
  const key=JSON.stringify(selected.map(d=>[d.id,d.sha256]).sort());
  if(!exportIds.has(key))exportIds.set(key,crypto.randomUUID());
  const id=exportIds.get(key),name=el('batchName').value.trim()||kind+' · '+period;
  const manifest={format:'rh-facilita-export-v1',id,name,kind,period,documents:selected.map(d=>({employee_id:d.employee.id,filename:d.filename,sha256:d.sha256}))};
  const zip=new JSZip();selected.forEach(d=>zip.file(d.filename,d.bytes));
  zip.file('_controle_do_lote/manifest.json',JSON.stringify(manifest,null,2));
  const blob=await zip.generateAsync({type:'blob',compression:'STORE'});
  download(blob,'Facilita-Ponto-'+period.replace('/','-')+'-'+id.slice(0,8)+'.zip');
  try{await register(manifest);await refresh();notice('Download iniciado: '+selected.length+' PDFs. Extraia o ZIP e carregue os PDFs no Facilita Ponto. Depois confirme a disponibilidade no lote abaixo para autorizar os avisos. Nenhum PDF foi enviado ao Drive e nenhum aviso foi autorizado.');}
  catch(error){throw Error('O ZIP foi gerado, mas o registro do lote falhou. Guarde o ZIP e use Importar controle do lote com o manifest.json da pasta _controle_do_lote. '+error.message);}
 });
 el('importSignatureManifest').onchange=()=>action(async()=>{
  const file=el('importSignatureManifest').files[0];if(!file)return;
  if(file.size>2097152)throw Error('Arquivo de controle maior que 2 MB.');
  await register(JSON.parse(await file.text()));await refresh();notice('Lote registrado. Confirme a disponibilidade no Facilita Ponto antes de autorizar os avisos.');
 });
 async function renderExports(){
  exports=await RH.fetchAll(client,'rh_signature_exports');
  const container=el('signatureBatches');container.replaceChildren();
  exports.sort((a,b)=>b.created_at.localeCompare(a.created_at)).forEach(x=>{
   const batch=batches.find(b=>b.id===x.id);if(!batch)return;
   const docs=queueDocs.filter(d=>d.batch_id===x.id),card=document.createElement('article');card.className='batch-card';
   const h=document.createElement('h3');h.textContent=batch.name;
   const summary=document.createElement('p');summary.textContent=x.documents.length+' PDFs · '+docs.length+' colaboradores · '+docs.filter(d=>d.status==='accepted').length+' avisos aceitos pelo n8n';
   const status=document.createElement('p');status.textContent=x.confirmed_at?'Disponibilidade confirmada por um administrador em '+new Date(x.confirmed_at).toLocaleString('pt-BR'):'Aguardando você carregar e disponibilizar os PDFs no Facilita Ponto.';
   const details=document.createElement('details'),title=document.createElement('summary');title.textContent='Conferir colaboradores e mensagens';details.append(title);
   docs.forEach(d=>{const e=employee(d.funcionario_id),p=document.createElement('p');p.textContent=(e?.nome||'Cadastro indisponível')+' · '+(d.error==='SIGNATURE_PHONE_INVALID'?'Revise o telefone ou situação no cadastro':labels[d.status]||d.status);details.append(p);});
   const preview=document.createElement('pre');preview.style.whiteSpace='pre-wrap';preview.textContent=message('NOME DO COLABORADOR',batch.document_type,batch.period);details.append(preview);
   const checkLabel=document.createElement('label'),check=document.createElement('input');check.type='checkbox';checkLabel.append(check,document.createTextNode(' Já carreguei e disponibilizei TODOS os PDFs deste lote para assinatura no Facilita Ponto.'));
   const button=document.createElement('button');button.textContent='Confirmar disponibilidade e autorizar avisos';button.disabled=true;button.dataset.signatureReady='false';
   const eligible=docs.some(d=>d.status==='ready'||d.status==='failed'&&d.error==='SIGNATURE_PHONE_INVALID'&&!d.approved_at);
   check.onchange=()=>{button.disabled=!check.checked||!eligible;button.dataset.signatureReady=String(!button.disabled);};
   button.onclick=()=>action(async()=>{
    if(!check.checked)throw Error('Confirme a disponibilidade dos documentos.');
    if(!confirm('Autorizar um aviso por colaborador elegível deste lote? A mensagem contém somente o portal do Facilita Ponto e as instruções de login.'))return;
    const count=await RH.result(client.rpc('rh_confirm_signature_export',{p_id:x.id,p_confirmed:true}));await refresh();
    notice(count+' aviso(s) autorizado(s). Telefones inválidos ficam para revisão. Confira o acompanhamento: aceito pelo n8n não comprova entrega nem assinatura.');
   });
   card.append(h,summary,status,details,checkLabel,button);container.append(card);
  });
  if(!exports.length)container.textContent='Nenhum lote exportado ainda.';
 }
 const originalRefresh=refresh;
 refresh=async()=>{await originalRefresh();await renderExports();};
 el('refreshSignature').onclick=()=>action(refresh);
 // A inicialização original pode já ter concluído durante o carregamento deste arquivo.
 if(settings)action(renderExports);
})();
