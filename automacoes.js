'use strict';
const client=window.supabase.createClient('https://gcksbfstheavpfgcdndb.supabase.co','sb_publishable_UrTJ8_SyM3n800C4LZQWpw_5Ah8Ko98');
const el=id=>document.getElementById(id);let employees=[],links=[],settings;
RHFolderChoice.start(client);
const labels={awaiting_choice:'Aguardando escolha da pasta',waiting:'Aguardando',processing:'Processando',done:'Concluído',failed:'Falha',prepared:'Preparado',sent_manual:'Envio manual',signed_manual:'Assinatura manual'};
const name=id=>(employees.find(e=>e.id===id)||{}).nome||'Cadastro indisponível';
function notify(text,error=false){el('message').textContent=text;el('message').classList.toggle('error',error);}
async function action(fn){document.querySelectorAll('button').forEach(b=>b.disabled=true);try{await fn();}catch(e){notify(e.message||String(e),true);}finally{document.querySelectorAll('button').forEach(b=>b.disabled=false);}}
function cell(row,text){const td=document.createElement('td');td.textContent=text||'—';row.append(td);return td;}
function renderRows(id,data,render){el(id).replaceChildren();if(!data.length){const tr=document.createElement('tr');cell(tr,'Nenhum registro.');el(id).append(tr);}data.forEach(d=>{const row=document.createElement('tr');render(row,d);el(id).append(row);});}
function folderPreview(){const id=el('folder').value.trim(),valid=/^[A-Za-z0-9_-]{10,200}$/.test(id),a=el('folderPreview');a.hidden=!valid;if(valid){a.href='https://drive.google.com/drive/folders/'+encodeURIComponent(id);a.textContent='Abrir e conferir pasta no Drive · '+id;}else a.removeAttribute('href');}
function selected(){const e=employees.find(e=>e.id===el('employee').value);if(!e)return;el('folder').value=(links.find(l=>l.funcionario_id===e.id)||{}).folder_id||'';el('folderSearchStatus').textContent=el('folder').value?'Pasta já vinculada. Você pode abrir para conferir ou informar outro ID manualmente.':'';el('folderResults').replaceChildren();folderPreview();el('destination').textContent=e.nome+' → '+(e.data_desligamento?'Ex-funcionários (desligado)':'Funcionários ativos')+'. A tarefa procura uma pasta existente e pede sua confirmação antes de reutilizar.';}
function renderMessage(){let text=el('messageTemplate').value;const fields={nome:name(el('docEmployee').value),tipo:el('type').value,competencia:el('period').value,link:el('url').value};if(/\{([^{}]+)\}/g.test(text)){text=text.replace(/\{([^{}]+)\}/g,(_,k)=>{if(!(k in fields))throw Error('Variável desconhecida: '+k);return fields[k];});}el('preview').textContent=text;return text;}
async function refresh(){
 [links]=await Promise.all([RH.fetchAll(client,'rh_drive_links','*','funcionario_id')]);
 const [jobs,events,docs]=await Promise.all([RH.result(client.from('rh_drive_jobs').select('*').order('updated_at',{ascending:false}).limit(100)),RH.result(client.from('rh_drive_events').select('*').order('id',{ascending:false}).limit(30)),RH.result(client.from('rh_document_registry').select('*').order('created_at',{ascending:false}).limit(100))]);
 settings=await RH.result(client.from('rh_automation_settings').select('*').eq('id',true).single(),true);
 const age=settings.last_worker_at?Date.now()-new Date(settings.last_worker_at).getTime():Infinity;
 el('worker').textContent=!settings.last_worker_at?'Processador ainda não conectado. Instale o novo arquivo no Apps Script e execute instalarAutomacaoDriveRH.':(age>15*60000?'Processador sem contato recente. Confira as Execuções do Apps Script.':'Processador conectado.')+' Último contato: '+new Date(settings.last_worker_at).toLocaleString('pt-BR')+(settings.drive_enabled?' · Automação ativa.':' · Automação pausada.');
 renderRows('jobs',jobs,(r,j)=>{cell(r,name(j.funcionario_id));cell(r,labels[j.status]);cell(r,new Date(j.updated_at).toLocaleString('pt-BR'));cell(r,j.error);});
 el('events').replaceChildren();events.forEach(e=>{const p=document.createElement('p');p.textContent=new Date(e.created_at).toLocaleString('pt-BR')+' · '+name(e.funcionario_id)+' · '+labels[e.status]+(e.detail?' · '+e.detail:'');el('events').append(p);});
 renderRows('documents',docs,(r,d)=>{cell(r,name(d.funcionario_id));cell(r,d.document_type);cell(r,d.period);cell(r,labels[d.status]);const td=cell(r,'');try{const url=new URL(d.url);if(url.protocol==='https:'){const a=document.createElement('a');a.href=url.href;a.target='_blank';a.rel='noopener noreferrer';a.textContent='Abrir';td.replaceChildren(a);}}catch(_){}});
 selected();
}
function showDriveSettings(open){el('driveSettings').hidden=!open;el('toggleDriveSettings').setAttribute('aria-expanded',String(open));if(open){el('driveSettingsTitle').focus();el('driveSettings').scrollIntoView({block:'start'});}else el('toggleDriveSettings').focus();}
el('toggleDriveSettings').onclick=e=>{e.preventDefault();if(!el('content').hidden)showDriveSettings(el('driveSettings').hidden);};
el('closeDriveSettings').onclick=()=>showDriveSettings(false);
el('employee').onchange=selected;
el('folder').addEventListener('input',folderPreview);
el('findFolder').onclick=()=>action(async()=>{
 const id=el('employee').value,original=el('folder').value;
 if(!id)throw Error('Escolha um colaborador.');
 if(links.some(l=>l.funcionario_id===id&&l.folder_id)){selected();notify('Este colaborador já possui uma pasta vinculada. Abra o link para conferir.');return;}
 el('folderResults').replaceChildren();el('folderSearchStatus').textContent='Buscando nas pastas de ativos e ex-funcionários…';
 try{
  const {data,error}=await client.functions.invoke('drive-folder-lookup',{body:{employeeId:id}});
  if(error){let message=error.message;try{const body=await error.context.json();message=body.error||message;}catch(_){}throw Error(message||'Não foi possível buscar a pasta.');}
  if(id!==el('employee').value)return;
  if(!data||data.employee_id!==id||!Array.isArray(data.folders))throw Error('Resposta da busca inválida.');
  const folders=data.folders.filter(f=>/^[A-Za-z0-9_-]{10,200}$/.test(f.id||''));
  if(!folders.length){el('folderSearchStatus').textContent='Nenhuma pasta compatível foi encontrada. Você pode informar o ID manualmente.';return;}
  const choose=f=>{el('folder').value=f.id;folderPreview();el('folderSearchStatus').textContent='Confira a pasta no Drive e clique em “Salvar vínculo” para registrá-la.';};
  if(folders.length===1&&el('folder').value===original){choose(folders[0]);return;}
  el('folderSearchStatus').textContent=folders.length>1?'Encontramos mais de uma pasta. Abra para conferir e selecione a correta.':'Pasta encontrada. Seu preenchimento manual foi preservado; selecione a pasta se desejar.';
  folders.forEach(f=>{const row=document.createElement('div');row.className='folder-result';const b=document.createElement('button');b.type='button';b.className='secondary';b.textContent='Selecionar: '+f.name+' · '+f.location;b.onclick=()=>choose(f);const a=document.createElement('a');a.href='https://drive.google.com/drive/folders/'+encodeURIComponent(f.id);a.target='_blank';a.rel='noopener noreferrer';a.textContent='Abrir no Drive';row.append(b,a);el('folderResults').append(row);});
 }catch(e){if(id!==el('employee').value)return;el('folderSearchStatus').textContent=(e.message||String(e))+' Você pode informar o ID manualmente.';throw e;}
});
el('saveSettings').onclick=()=>action(async()=>{
 const ids=['active','former','template'].map(id=>el(id).value.trim());if(ids.some(id=>!/^[A-Za-z0-9_-]{10,200}$/.test(id))||new Set(ids).size!==3)throw Error('Informe três IDs de pastas válidos e diferentes.');
 await RH.result(client.from('rh_automation_settings').update({drive_enabled:el('enabled').checked,active_folder_id:ids[0],former_folder_id:ids[1],template_folder_id:ids[2]}).eq('id',true).select(),true);await refresh();notify('Configuração salva. Cadastros anteriores não são movimentados em massa.');
});
el('bind').onclick=()=>action(async()=>{
 const folder=el('folder').value.trim(),id=el('employee').value;if(!id||!/^[A-Za-z0-9_-]{10,200}$/.test(folder))throw Error('Escolha o colaborador e informe um ID válido.');
 if(!confirm('Vincular esta pasta a '+name(id)+'? Confira o ID. O processador validará a localização antes de movimentar.'))return;
 await RH.result(client.from('rh_drive_links').upsert({funcionario_id:id,folder_id:folder,template_pending:false,updated_at:new Date().toISOString()},{onConflict:'funcionario_id'}).select(),true);await refresh();notify('Vínculo salvo. Nenhuma pasta foi movimentada por esta ação.');
});
el('enqueue').onclick=()=>action(async()=>{const id=el('employee').value;if(!id)throw Error('Escolha um colaborador.');if(!confirm(el('destination').textContent+'\nConfirmar inclusão na fila?'))return;await RH.result(client.rpc('rh_enqueue_drive',{p_employee:id}));await refresh();notify('Tarefa registrada. Será executada quando o processador estiver conectado e a automação estiver ativa.');});
el('refresh').onclick=()=>action(async()=>{await refresh();notify('Acompanhamento atualizado.');});
el('saveTemplate').onclick=()=>action(async()=>{renderMessage();const text=el('messageTemplate').value.trim();if(!text||text.length>8000)throw Error('Modelo vazio ou longo demais.');await RH.result(client.from('rh_automation_settings').update({message_template:text}).eq('id',true).select(),true);notify('Modelo salvo. Nenhuma mensagem enviada.');});
el('copy').onclick=()=>action(async()=>{await navigator.clipboard.writeText(renderMessage());notify('Mensagem copiada. O envio é manual.');});
el('saveDocument').onclick=()=>action(async()=>{const url=new URL(el('url').value);if(url.protocol!=='https:')throw Error('Use um link HTTPS.');await RH.result(client.from('rh_document_registry').insert({funcionario_id:el('docEmployee').value,document_type:el('type').value.trim(),period:el('period').value.trim(),url:url.href,status:el('docStatus').value,notes:el('notes').value}).select(),true);await refresh();notify('Documento registrado. Nenhum arquivo foi enviado ou compartilhado.');});
['messageTemplate','docEmployee','type','period','url'].forEach(id=>el(id).addEventListener('input',()=>{try{renderMessage();}catch(e){el('preview').textContent=e.message;}}));
action(async()=>{const p=await RH.profile(client);if(p.status!=='admin')throw Error('Esta área exige acesso de administrador.');employees=await RH.fetchAll(client,'funcionarios_epi','id,nome,cpf,data_desligamento');employees.sort((a,b)=>a.nome.localeCompare(b.nome,'pt-BR'));['employee','docEmployee'].forEach(id=>employees.forEach(e=>{const o=document.createElement('option');o.value=e.id;o.textContent=e.nome+(e.data_desligamento?' · desligado':'');el(id).append(o);}));await refresh();el('active').value=settings.active_folder_id;el('former').value=settings.former_folder_id;el('template').value=settings.template_folder_id;el('enabled').checked=settings.drive_enabled;el('messageTemplate').value=settings.message_template;renderMessage();el('content').hidden=false;el('toggleDriveSettings').hidden=false;notify('Área administrativa conectada.');});
