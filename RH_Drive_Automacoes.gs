/* Adicione como NOVO arquivo no mesmo projeto do google_apps_script_atualizado.js.
 * Usa as propriedades SUPABASE_URL / SUPABASE_KEY já configuradas. Não cole chaves no navegador.
 * Execute instalarAutomacaoDriveRH uma vez e autorize o Google Drive.
 */
function bancoDriveRH(resource,method,query,body) {
  const allowed=['rh_automation_settings','rh_drive_links','funcionarios_epi','rpc/rh_claim_drive','rpc/rh_finish_drive'];
  if(!allowed.includes(resource)) throw Error('Recurso não permitido');
  const props=PropertiesService.getScriptProperties();
  const url=props.getProperty('SUPABASE_URL'), key=props.getProperty('SUPABASE_KEY');
  if(!url || !/^https:\/\/[a-z0-9-]+\.supabase\.co\/?$/.test(url) || !key) throw Error('Configure as propriedades SUPABASE_URL e SUPABASE_KEY no Apps Script.');
  const options={method:method, muteHttpExceptions:true,headers:{apikey:key,Authorization:'Bearer '+key,'Content-Type':'application/json',Prefer:'return=representation'}};
  if(body!==undefined) options.payload=JSON.stringify(body);
  const r=UrlFetchApp.fetch(url.replace(/\/$/,'')+'/rest/v1/'+resource+(query?'?'+query:''),options);
  if(r.getResponseCode()<200 || r.getResponseCode()>=300) throw Error('Banco: HTTP '+r.getResponseCode()+' em '+resource);
  return r.getContentText()?JSON.parse(r.getContentText()):[];
}
function apiDriveRH(path,method,body,params) {
  const q=Object.entries(Object.assign({supportsAllDrives:true},params||{})).map(([k,v])=>encodeURIComponent(k)+'='+encodeURIComponent(v)).join('&');
  const options={method:method||'get',muteHttpExceptions:true,headers:{Authorization:'Bearer '+ScriptApp.getOAuthToken(),'Content-Type':'application/json'}};
  if(body!==undefined) options.payload=JSON.stringify(body);
  const r=UrlFetchApp.fetch('https://www.googleapis.com/drive/v3/'+path+'?'+q,options);
  if(r.getResponseCode()<200 || r.getResponseCode()>=300) throw Error(erroDriveRH(r));
  return r.getContentText()?JSON.parse(r.getContentText()):{};
}
function idDriveRH(id) { if(!/^[A-Za-z0-9_-]{10,200}$/.test(id||'')) throw Error('ID de pasta inválido'); return id; }
function listarDriveRH(query) {
  let token, rows=[];
  do { const r=apiDriveRH('files','get',undefined,{q:query+' and trashed=false',pageSize:1000,fields:'nextPageToken,files(id,name,mimeType,parents,appProperties)',includeItemsFromAllDrives:true,pageToken:token||''}); rows=rows.concat(r.files||[]);token=r.nextPageToken;}while(token);
  return rows;
}
function filhosDriveRH(id) { return listarDriveRH("'"+idDriveRH(id)+"' in parents"); }
function pastaDriveRH(id) {
 const f=apiDriveRH('files/'+idDriveRH(id),'get',undefined,{fields:'id,name,mimeType,parents,trashed,appProperties'});
 if(f.trashed || f.mimeType!=='application/vnd.google-apps.folder') throw Error('O ID informado não é uma pasta ativa.'); return f;
}
function nomeDriveRH(name) {return String(name||'').normalize('NFD').replace(/[\u0300-\u036f]/g,'').toUpperCase().replace(/[^A-Z0-9]+/g,' ').trim();}
function escolherPastaRH(folders,employee,linked) {
 if(linked) {const matches=folders.filter(f=>f.id===linked); if(matches.length!==1)throw Error('Pasta vinculada fora das raízes autorizadas.');return matches[0];}
 const cpf=String(employee.cpf||'').replace(/\D/g,'');
 const matches=folders.filter(f=>{
  const owner=(f.appProperties||{}).rh_employee_id;
  if(owner)return owner===employee.id;
  const ids=f.name.match(/(?<!\d)\d{3}\.?\d{3}\.?\d{3}-?\d{2}(?!\d)/g)||[];
  if(ids.length>1)throw Error('Pasta com múltiplos CPFs; vincule manualmente.');
  const folderCpf=ids.length?ids[0].replace(/\D/g,''):'';
  if(folderCpf && cpf && folderCpf!==cpf)return false;
  const name=ids.reduce((name,id)=>name.replace(id,''),f.name);
  return (cpf && cpf===folderCpf) || nomeDriveRH(name)===nomeDriveRH(employee.nome);
 });
 if(matches.length>1)throw Error('Pastas duplicadas/homônimas. Informe o ID correto no painel.');
 return matches[0]||null;
}
function validarRaizesDriveRH(s) {
 const ids=[s.active_folder_id,s.former_folder_id,s.template_folder_id];
 if(new Set(ids).size!==3)throw Error('As três pastas devem ser diferentes.');
 ids.forEach(id=>{
  let f=pastaDriveRH(id), seen=new Set([id]);
  while(f.parents && f.parents.length){
   const parent=f.parents[0];if(ids.includes(parent)||seen.has(parent))throw Error('As pastas configuradas não podem estar umas dentro das outras.');
   seen.add(parent);f=apiDriveRH('files/'+idDriveRH(parent),'get',undefined,{fields:'id,parents'});
  }
 });
}
function copiarModeloDriveRH(source,target,deadline) {
 const queue=[[source,target]];
 while(queue.length){
  if(Date.now()>deadline)throw Error('Cópia parcial preservada. Reprocesse a tarefa para continuar.');
  const [src,dst]=queue.shift(), children=filhosDriveRH(dst);
  for(const child of filhosDriveRH(src)){
   if(Date.now()>deadline)throw Error('Cópia parcial preservada. Reprocesse a tarefa para continuar.');
   const matches=children.filter(f=>(f.appProperties||{}).rh_source_id===child.id);
   if(matches.length>1)throw Error('Cópias duplicadas no modelo. Revise a pasta.');
   let copied=matches[0];
   if(!copied){
    const body={name:child.name,parents:[dst],appProperties:{rh_source_id:child.id}};
    if(child.mimeType==='application/vnd.google-apps.folder'){
     body.mimeType=child.mimeType;copied=apiDriveRH('files','post',body,{fields:'id'});
    }else{
     if(child.mimeType==='application/vnd.google-apps.shortcut')throw Error('Modelo contém atalho; revise antes de copiar.');
     copied=apiDriveRH('files/'+child.id+'/copy','post',body,{fields:'id'});
    }
   }
   if(child.mimeType==='application/vnd.google-apps.folder')queue.push([child.id,copied.id]);
  }
 }
}
function executarTarefaDriveRH(job,s,deadline) {
 const employees=bancoDriveRH('funcionarios_epi','get','id=eq.'+job.funcionario_id+'&select=id,nome,cpf,data_desligamento');
 if(employees.length!==1)throw Error('Colaborador indisponível');
 const e=employees[0], links=bancoDriveRH('rh_drive_links','get','funcionario_id=eq.'+e.id);
 const folders=filhosDriveRH(s.active_folder_id).concat(filhosDriveRH(s.former_folder_id)).filter(f=>f.mimeType==='application/vnd.google-apps.folder');
 let link=links[0], folder=escolherPastaRH(folders,e,link&&link.folder_id);
 const target=e.data_desligamento?s.former_folder_id:s.active_folder_id;
 if(!folder){
  if(e.data_desligamento)throw Error('Desligado sem pasta existente: vincule a pasta correta; nenhuma pasta vazia será criada.');
  folder=apiDriveRH('files','post',{name:e.nome,mimeType:'application/vnd.google-apps.folder',parents:[target],appProperties:{rh_employee_id:e.id,rh_new_template:'yes'}},{fields:'id,name,parents,appProperties'});
 }
 const owner=(folder.appProperties||{}).rh_employee_id;
 if(owner && owner!==e.id)throw Error('Pasta vinculada a outro colaborador.');
 if(!link){
  link={funcionario_id:e.id,folder_id:folder.id,template_pending:(folder.appProperties||{}).rh_new_template==='yes'};
  bancoDriveRH('rh_drive_links','post','',link);
 }
 if(link.template_pending){
  copiarModeloDriveRH(s.template_folder_id,folder.id,deadline);
  bancoDriveRH('rh_drive_links','patch','funcionario_id=eq.'+e.id,{template_pending:false,updated_at:new Date().toISOString()});
 }
 // Releitura evita mover usando um desligamento que mudou durante a cópia.
 const current=bancoDriveRH('funcionarios_epi','get','id=eq.'+e.id+'&select=data_desligamento')[0];
 const destination=current.data_desligamento?s.former_folder_id:s.active_folder_id;
 const fresh=pastaDriveRH(folder.id), parents=fresh.parents||[];
 if(parents.length!==1 || ![s.active_folder_id,s.former_folder_id].includes(parents[0]))throw Error('Pasta mudou de localização; revisão necessária.');
 apiDriveRH('files/'+folder.id,'patch',{appProperties:{rh_employee_id:e.id}},Object.assign({fields:'id,parents'},parents[0]===destination?{}:{addParents:destination,removeParents:parents[0]}));
 const verified=pastaDriveRH(folder.id);
 if(!(verified.parents||[]).includes(destination))throw Error('Destino não confirmado após movimentação.');
}
function processarFilaDriveRH() {
 const lock=LockService.getScriptLock();if(!lock.tryLock(1000))return;
 const deadline=Date.now()+240000;
 try{
  const settings=bancoDriveRH('rh_automation_settings','get','id=eq.true')[0];
  if(!settings)throw Error('Configuração indisponível');
  // Heartbeat inclusive quando pausado.
  bancoDriveRH('rh_automation_settings','patch','id=eq.true',{last_worker_at:new Date().toISOString()});
  if(!settings.drive_enabled)return;
  while(Date.now()<deadline-30000){
   const jobs=bancoDriveRH('rpc/rh_claim_drive','post','',{});if(!jobs.length)break;
   const job=jobs[0];let error=null;
   try{validarRaizesDriveRH(settings);executarTarefaDriveRH(job,settings,deadline);}catch(e){error=String(e.message).slice(0,500);}
   bancoDriveRH('rpc/rh_finish_drive','post','',{p_id:job.id,p_revision:job.claimed_revision,p_error:error});
  }
 }finally{lock.releaseLock();}
}
function instalarAutomacaoDriveRH() {
 // A referência explícita solicita o escopo do Drive durante a autorização inicial.
 DriveApp.getRootFolder().getId();
 const s=bancoDriveRH('rh_automation_settings','get','id=eq.true')[0];validarRaizesDriveRH(s);
 ScriptApp.getProjectTriggers().filter(t=>t.getHandlerFunction()==='processarFilaDriveRH').forEach(t=>ScriptApp.deleteTrigger(t));
 ScriptApp.newTrigger('processarFilaDriveRH').timeBased().everyMinutes(5).create();
 bancoDriveRH('rh_automation_settings','patch','id=eq.true',{last_worker_at:new Date().toISOString()});
}

// Diagnóstico sem criar, mover ou apagar arquivos.
function erroDriveRH(response) {
 let error={};try{error=JSON.parse(response.getContentText()).error||{};}catch(_){}
 const reasons=(error.errors||[]).map(e=>e.reason).concat((error.details||[]).map(e=>e.reason)).filter(Boolean);
 const reason=reasons.join(', ')||error.status||'motivo não informado';
 let hint='Confira a execução no Apps Script e o acesso da conta às pastas.';
 if(/accessNotConfigured|SERVICE_DISABLED/.test(reason))hint='Ative a Google Drive API no projeto Google Cloud vinculado ao Apps Script.';
 else if(/insufficientPermissions|ACCESS_TOKEN_SCOPE_INSUFFICIENT/.test(reason))hint='Execute instalarAutomacaoDriveRH novamente e autorize o acesso ao Drive. Confira os escopos explícitos do manifesto, se houver.';
 else if(/insufficientFilePermissions|teamDriveMembershipRequired/.test(reason))hint='A conta que criou o gatilho precisa de acesso às pastas e permissão para criar/copiar/mover os arquivos.';
 else if(/quota|limit|storage/i.test(reason))hint='Confira armazenamento e cotas do Google Drive antes de reprocessar.';
 return 'Drive: HTTP '+response.getResponseCode()+' ['+reason+']. '+hint;
}
function diagnosticarAutomacaoDriveRH() {
 DriveApp.getRootFolder().getId();
 const settings=bancoDriveRH('rh_automation_settings','get','id=eq.true')[0];
 if(!settings)throw Error('Configuração de pastas não encontrada.');
 validarRaizesDriveRH(settings);
 const result={};
 ['active_folder_id','former_folder_id','template_folder_id'].forEach(key=>{
  const folder=apiDriveRH('files/'+idDriveRH(settings[key]),'get',undefined,{fields:'id,name,capabilities(canAddChildren,canCopy,canEdit,canMoveChildrenWithinDrive)'});
  result[key]={nome:folder.name,permissoes:folder.capabilities||{}};
 });
 console.log(JSON.stringify(result));return result;
}
