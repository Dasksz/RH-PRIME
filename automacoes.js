'use strict';
const client=window.supabase.createClient('https://gcksbfstheavpfgcdndb.supabase.co','sb_publishable_UrTJ8_SyM3n800C4LZQWpw_5Ah8Ko98');
const el=id=>document.getElementById(id);let employees=[],links=[],settings,pendingJobs=[],driveJobs=[];
RHFolderChoice.start(client);
const labels={awaiting_choice:'Aguardando escolha da pasta',waiting:'Aguardando',processing:'Processando',done:'Concluído',failed:'Falha',prepared:'Preparado',sent_manual:'Envio manual',signed_manual:'Assinatura manual'};
const name=id=>(employees.find(e=>e.id===id)||{}).nome||'Cadastro indisponível';
function notify(text,error=false){el('message').textContent=text;el('message').classList.toggle('error',error);}
async function action(fn){document.querySelectorAll('button').forEach(b=>b.disabled=true);try{await fn();}catch(e){notify(e.message||String(e),true);}finally{document.querySelectorAll('button').forEach(b=>b.disabled=false);}}
function cell(row,text,label){const td=document.createElement('td');td.textContent=text||'—';if(label)td.setAttribute('data-label',label);row.append(td);return td;}
function renderRows(id,data,render){el(id).replaceChildren();if(!data.length){const tr=document.createElement('tr');cell(tr,'Nenhum registro.');el(id).append(tr);}data.forEach(d=>{const row=document.createElement('tr');render(row,d);el(id).append(row);});}
function folderPreview(){const id=el('folder').value.trim(),valid=/^[A-Za-z0-9_-]{10,200}$/.test(id),a=el('folderPreview');a.hidden=!valid;el('bind').hidden=!valid||links.some(l=>l.funcionario_id===el('employee').value&&l.folder_id===id);if(valid){a.href='https://drive.google.com/drive/folders/'+encodeURIComponent(id);a.textContent='Abrir e conferir pasta no Drive · '+id;}else a.removeAttribute('href');}
function selected(){const e=employees.find(e=>e.id===el('employee').value);if(!e)return;el('folder').value=(links.find(l=>l.funcionario_id===e.id)||{}).folder_id||'';el('folderSearchStatus').textContent=el('folder').value?'Pasta já vinculada. Você pode abrir para conferir ou informar outro ID manualmente.':'';el('folderResults').replaceChildren();el('manualFolder').open=false;folderPreview();el('destination').textContent=e.nome+' → '+(e.data_desligamento?'Ex-funcionários (desligado)':'Funcionários ativos')+'.';}
function renderMessage(){let text=el('messageTemplate').value;const fields={nome:name(el('docEmployee').value),tipo:el('type').value,competencia:el('period').value,link:el('url').value};if(/\{([^{}]+)\}/g.test(text)){text=text.replace(/\{([^{}]+)\}/g,(_,k)=>{if(!(k in fields))throw Error('Variável desconhecida: '+k);return fields[k];});}el('preview').textContent=text;return text;}
function recognitionCandidates(){return employees.filter(e=>!e.data_desligamento&&!links.some(l=>l.funcionario_id===e.id)&&!pendingJobs.some(j=>j.funcionario_id===e.id));}
function recognitionSummary(){const active=employees.filter(e=>!e.data_desligamento),linked=active.filter(e=>links.some(l=>l.funcionario_id===e.id)),queued=active.filter(e=>!links.some(l=>l.funcionario_id===e.id)&&pendingJobs.some(j=>j.funcionario_id===e.id)),review=active.filter(e=>driveJobs.some(j=>j.funcionario_id===e.id&&['failed','awaiting_choice'].includes(j.status)));el('withFolder').textContent=linked.length;el('withoutFolder').textContent=active.length-linked.length;el('reviewFolders').textContent=review.length;el('recognitionStatus').textContent=active.length+' colaboradores ativos. '+recognitionCandidates().length+' disponíveis para vinculação em lote; '+queued.length+' com solicitação em andamento. Revisões podem incluir pessoas com ou sem pasta.';}
function requireRecognitionWorker(){if(!settings.drive_enabled)throw Error('Ative a automação nas configurações de pastas primeiro.');if(!['existing-link-v1','folder-choice-v1'].includes(settings.drive_worker_version))throw Error('Atualize o processador de pastas no Apps Script antes de reconhecer pastas existentes.');}
let folderFilter='without';
function folderPeople(filter){return employees.filter(e=>!e.data_desligamento).filter(e=>{const linked=links.some(l=>l.funcionario_id===e.id),job=driveJobs.find(j=>j.funcionario_id===e.id);return filter==='with'?linked:filter==='without'?!linked:filter==='pending'?job&&['waiting','processing'].includes(job.status):job&&['failed','awaiting_choice'].includes(job.status);});}
function renderFolderPeople(){
 const titles={with:'Colaboradores com pasta',without:'Colaboradores sem pasta',review:'Colaboradores que precisam de revisão',pending:'Solicitações em andamento'};
 const people=folderPeople(folderFilter);el('folderPeopleTitle').textContent=titles[folderFilter]+' · '+people.length;
 renderRows('folderPeopleRows',people,(r,e)=>{
  const link=links.find(l=>l.funcionario_id===e.id),job=driveJobs.find(j=>j.funcionario_id===e.id);
  cell(r,e.nome,'Colaborador');cell(r,job?labels[job.status]||job.status:link?'Com pasta':'Sem solicitação','Situação');cell(r,job?.error|| (job?.status==='waiting'?'Na fila, aguardando a próxima execução.':job?.status==='processing'?'Busca iniciada.':job?.status==='awaiting_choice'?'Escolha a pasta correta para continuar.':link?'Pasta vinculada.':'Disponível para busca automática.'),'Detalhes');
  const td=cell(r,'','Ações'),b=document.createElement('button');b.type='button';b.className='secondary';b.textContent='Buscar / revisar pasta';b.onclick=()=>{el('folderPeopleDialog').close();el('employee').value=e.id;selected();el('employee').focus();el('employee').scrollIntoView({block:'center'});el('findFolder').click();};td.replaceChildren(b);
  if(!link&&!pendingJobs.some(j=>j.funcionario_id===e.id)){const auto=document.createElement('button');auto.type='button';auto.textContent='Solicitar vínculo automático';auto.onclick=()=>{el('employee').value=e.id;selected();el('recognizeOne').click();};td.append(auto);}
  if(link){const a=document.createElement('a');a.href='https://drive.google.com/drive/folders/'+encodeURIComponent(link.folder_id);a.target='_blank';a.rel='noopener noreferrer';a.textContent='Abrir pasta';td.append(a);}
 });
}
['with','without','review','pending'].forEach(filter=>{el('showFolders-'+filter).onclick=()=>action(async()=>{await refresh();folderFilter=filter;renderFolderPeople();el('folderPeopleDialog').showModal();});});
el('closeFolderPeople').onclick=()=>el('folderPeopleDialog').close();
async function refresh(resetSelection=false){
 [links,driveJobs]=await Promise.all([RH.fetchAll(client,'rh_drive_links','*','funcionario_id'),RH.fetchAll(client,'rh_drive_jobs','funcionario_id,status,error,updated_at','id')]);
 pendingJobs=driveJobs.filter(j=>['waiting','processing','awaiting_choice'].includes(j.status));
 const [jobs,events,docs]=await Promise.all([RH.result(client.from('rh_drive_jobs').select('*').order('updated_at',{ascending:false}).limit(100)),RH.result(client.from('rh_drive_events').select('*').order('id',{ascending:false}).limit(30)),RH.result(client.from('rh_document_registry').select('*').order('created_at',{ascending:false}).limit(100))]);
 settings=await RH.result(client.from('rh_automation_settings').select('*').eq('id',true).single(),true);
 const age=settings.last_worker_at?Date.now()-new Date(settings.last_worker_at).getTime():Infinity;
 el('worker').textContent=!settings.last_worker_at?'Processador ainda não conectado. Instale o novo arquivo no Apps Script e execute instalarAutomacaoDriveRH.':(age>15*60000?'Processador sem contato recente. Confira as Execuções do Apps Script.':'Processador conectado.')+' Último contato: '+new Date(settings.last_worker_at).toLocaleString('pt-BR')+(settings.drive_enabled?' · Automação ativa.':' · Automação pausada.');
 renderRows('jobs',jobs,(r,j)=>{cell(r,name(j.funcionario_id),'Colaborador');cell(r,labels[j.status],'Situação');cell(r,new Date(j.updated_at).toLocaleString('pt-BR'),'Atualização');cell(r,(j.link_only?'Vincular pasta existente':'Criar ou organizar pasta')+(j.error?' · '+j.error:''),'Detalhes');});
 el('events').replaceChildren();events.forEach(e=>{const p=document.createElement('p');p.textContent=new Date(e.created_at).toLocaleString('pt-BR')+' · '+name(e.funcionario_id)+' · '+labels[e.status]+(e.detail?' · '+e.detail:'');el('events').append(p);});
 renderRows('documents',docs,(r,d)=>{cell(r,name(d.funcionario_id),'Colaborador');cell(r,d.document_type,'Documento');cell(r,d.period,'Competência');cell(r,labels[d.status],'Situação manual');const td=cell(r,'','Arquivo');try{const url=new URL(d.url);if(url.protocol==='https:'){const a=document.createElement('a');a.href=url.href;a.target='_blank';a.rel='noopener noreferrer';a.textContent='Abrir';td.replaceChildren(a);}}catch(_){}});
 recognitionSummary();el('pendingFolders').textContent=folderPeople('pending').length;if(el('folderPeopleDialog').open)renderFolderPeople();if(resetSelection)selected();
}
function showDriveSettings(open){el('driveSettings').hidden=!open;el('toggleDriveSettings').setAttribute('aria-expanded',String(open));if(open){el('driveSettingsTitle').focus();el('driveSettings').scrollIntoView({block:'start'});}else el('toggleDriveSettings').focus();}
el('toggleDriveSettings').onclick=e=>{e.preventDefault();if(!el('content').hidden)showDriveSettings(el('driveSettings').hidden);};
el('closeDriveSettings').onclick=()=>showDriveSettings(false);
el('employee').onchange=selected;
el('folder').addEventListener('input',folderPreview);
el('findFolder').onclick=()=>action(async()=>{
 const id=el('employee').value,original=el('folder').value;
 if(!id)throw Error('Escolha um colaborador.');
 el('folderResults').replaceChildren();el('folderSearchStatus').textContent='Buscando nas pastas de ativos e ex-funcionários…';
 try{
  const {data,error}=await client.functions.invoke('drive-folder-lookup',{body:{employeeId:id}});
  if(error){let message=error.message;try{const body=await error.context.json();message=body.error||message;}catch(_){}throw Error(message||'Não foi possível buscar a pasta.');}
  if(id!==el('employee').value)return;
  if(!data||data.employee_id!==id||!Array.isArray(data.folders))throw Error('Resposta da busca inválida.');
  const folders=data.folders.filter(f=>/^[A-Za-z0-9_-]{10,200}$/.test(f.id||''));
  if(!folders.length){el('folderSearchStatus').textContent='Nenhuma pasta compatível foi encontrada. Abra Vínculo manual para informar o ID.';return;}
  const choose=f=>{el('folder').value=f.id;folderPreview();el('folderSearchStatus').textContent='Confira a pasta no Drive e clique em “Vincular pasta selecionada” para registrá-la.';};
  if(folders.length===1&&el('folder').value===original){choose(folders[0]);return;}
  el('folderSearchStatus').textContent=folders.length>1?'Encontramos mais de uma pasta. Abra para conferir e selecione a correta.':'Pasta encontrada. Seu preenchimento manual foi preservado; selecione a pasta se desejar.';
  folders.forEach(f=>{const row=document.createElement('div');row.className='folder-result';const b=document.createElement('button');b.type='button';b.className='secondary';b.textContent='Selecionar: '+f.name+' · '+f.location;b.onclick=()=>choose(f);const a=document.createElement('a');a.href='https://drive.google.com/drive/folders/'+encodeURIComponent(f.id);a.target='_blank';a.rel='noopener noreferrer';a.textContent='Abrir no Drive';row.append(b,a);el('folderResults').append(row);});
 }catch(e){if(id!==el('employee').value)return;el('folderSearchStatus').textContent=(e.message||String(e))+' Abra Vínculo manual para informar o ID.';throw e;}
});
el('recognizeOne').onclick=()=>action(async()=>{
 await refresh();requireRecognitionWorker();const id=el('employee').value,e=employees.find(e=>e.id===id);
 if(!e||e.data_desligamento)throw Error('Escolha um colaborador ativo. Para desligados, use a busca e confira o vínculo individual.');
 if(links.some(l=>l.funcionario_id===id))throw Error('Já existe um vínculo. Use Buscar pasta deste colaborador para conferir a pasta atual.');
 if(pendingJobs.some(j=>j.funcionario_id===id))throw Error('Este colaborador já tem uma tarefa pendente. Confira a fila e as escolhas de pasta.');
 if(!confirm('Reconhecer e vincular uma pasta existente de '+e.nome+' pelo nome/CPF? Pastas ambíguas exigirão revisão.'))return;
 await RH.result(client.rpc('rh_link_existing_drive',{p_employee:id}));await refresh();notify('Reconhecimento colocado na fila. O processador verifica a fila a cada 5 minutos. Consulte o nome e a situação nos indicadores ou atualize o acompanhamento.');
});
el('recognizeAll').onclick=()=>action(async()=>{
 await refresh();requireRecognitionWorker();const candidates=recognitionCandidates();
 if(!candidates.length){notify('Todos os colaboradores ativos já têm vínculo ou uma tarefa pendente.');return;}
 if(!confirm('Reconhecer e vincular pastas existentes para '+candidates.length+' colaboradores ativos sem vínculo? A busca usa nome/CPF nas pastas de ativos e ex-funcionários. Não cria, move ou renomeia pastas nem envia mensagens. Correspondências ambíguas exigirão revisão individual.'))return;
 let count=0,failure;
 try{for(const e of candidates){await RH.result(client.rpc('rh_link_existing_drive',{p_employee:e.id}));count++;el('recognitionStatus').textContent='Registrando reconhecimento: '+count+' de '+candidates.length+'…';}}catch(e){failure=e;}
 await refresh();notify(count+' reconhecimento(s) colocado(s) na fila. O processador verifica a fila a cada 5 minutos; a duração da busca depende do Drive e da fila. Consulte os nomes nos indicadores.'+(failure?' Registro interrompido: '+(failure.message||String(failure))+'. Tente novamente para incluir os restantes.':''),!!failure);
});
el('saveSettings').onclick=()=>action(async()=>{
 const ids=['active','former','template'].map(id=>el(id).value.trim());if(ids.some(id=>!/^[A-Za-z0-9_-]{10,200}$/.test(id))||new Set(ids).size!==3)throw Error('Informe três IDs de pastas válidos e diferentes.');
 await RH.result(client.from('rh_automation_settings').update({drive_enabled:el('enabled').checked,active_folder_id:ids[0],former_folder_id:ids[1],template_folder_id:ids[2]}).eq('id',true).select(),true);await refresh();notify('Configuração salva. Cadastros anteriores não são movimentados em massa.');
});
el('bind').onclick=()=>action(async()=>{
 const folder=el('folder').value.trim(),id=el('employee').value;if(!id||!/^[A-Za-z0-9_-]{10,200}$/.test(folder))throw Error('Escolha o colaborador e informe um ID válido.');
 if(!confirm('Vincular esta pasta a '+name(id)+'? Confira o ID. O processador validará a localização antes de movimentar.'))return;
 if(links.some(l=>l.folder_id===folder&&l.funcionario_id!==id))throw Error('Esta pasta já está vinculada a outro colaborador. Confira o vínculo antes de salvar.');
 await RH.result(client.from('rh_drive_links').upsert({funcionario_id:id,folder_id:folder,template_pending:false,updated_at:new Date().toISOString()},{onConflict:'funcionario_id'}).select(),true);await refresh(true);notify('Vínculo salvo. Nenhuma pasta foi movimentada por esta ação.');
});
el('enqueue').onclick=()=>action(async()=>{const id=el('employee').value;if(!id)throw Error('Escolha um colaborador.');if(!confirm('Criar ou organizar a pasta de '+name(id)+'?\nEsta ação pode criar uma pasta com o modelo ou mover a pasta vinculada para '+(employees.find(e=>e.id===id)?.data_desligamento?'Ex-funcionários':'Funcionários ativos')+'. Pastas existentes sem vínculo exigirão sua escolha.\nConfirmar criação ou organização?'))return;await RH.result(client.rpc('rh_enqueue_drive',{p_employee:id}));await refresh();notify('Tarefa registrada. Será executada quando o processador estiver conectado e a automação estiver ativa.');});
el('refresh').onclick=()=>action(async()=>{await refresh();notify('Acompanhamento atualizado.');});
el('saveTemplate').onclick=()=>action(async()=>{renderMessage();const text=el('messageTemplate').value.trim();if(!text||text.length>8000)throw Error('Modelo vazio ou longo demais.');await RH.result(client.from('rh_automation_settings').update({message_template:text}).eq('id',true).select(),true);notify('Modelo salvo. Nenhuma mensagem enviada.');});
el('copy').onclick=()=>action(async()=>{await navigator.clipboard.writeText(renderMessage());notify('Mensagem copiada. O envio é manual.');});
el('saveDocument').onclick=()=>action(async()=>{const url=new URL(el('url').value);if(url.protocol!=='https:')throw Error('Use um link HTTPS.');await RH.result(client.from('rh_document_registry').insert({funcionario_id:el('docEmployee').value,document_type:el('type').value.trim(),period:el('period').value.trim(),url:url.href,status:el('docStatus').value,notes:el('notes').value}).select(),true);await refresh();notify('Documento registrado. Nenhum arquivo foi enviado ou compartilhado.');});
['messageTemplate','docEmployee','type','period','url'].forEach(id=>el(id).addEventListener('input',()=>{try{renderMessage();}catch(e){el('preview').textContent=e.message;}}));
action(async()=>{const p=await RH.profile(client);if(p.status!=='admin')throw Error('Esta área exige acesso de administrador.');employees=await RH.fetchAll(client,'funcionarios_epi','id,nome,cpf,data_desligamento');employees.sort((a,b)=>a.nome.localeCompare(b.nome,'pt-BR'));['employee','docEmployee'].forEach(id=>employees.forEach(e=>{const o=document.createElement('option');o.value=e.id;o.textContent=e.nome+(e.data_desligamento?' · desligado':'');el(id).append(o);}));await refresh(true);el('active').value=settings.active_folder_id;el('former').value=settings.former_folder_id;el('template').value=settings.template_folder_id;el('enabled').checked=settings.drive_enabled;el('messageTemplate').value=settings.message_template;renderMessage();el('content').hidden=false;el('toggleDriveSettings').hidden=false;notify('Área administrativa conectada.');});
