/* Adicione como NOVO arquivo RH_Atestados_Drive no projeto RH PRIME.
 * Depende de RH_Drive_Automacoes, já usado pelas pastas dos colaboradores.
 * Usa SUPABASE_URL / SUPABASE_KEY existentes. Execute instalarAtestadosDriveRH.
 * Guarda em colaborador / ATESTADOS / AAAA. Não cria pastas de mês.
 */
function bancoAtestadosRH(resource,method,query,body){
 const allowed=['rh_automation_settings','rh_drive_links','funcionarios_epi','rpc/rh_claim_absence_drive','rpc/rh_finish_absence_drive'];
 if(!allowed.includes(resource))throw Error('Recurso não permitido');
 const props=PropertiesService.getScriptProperties(),base=props.getProperty('SUPABASE_URL'),key=props.getProperty('SUPABASE_KEY');
 if(!/^https:\/\/[a-z0-9-]+\.supabase\.co\/?$/.test(base||'')||!key)throw Error('Confira SUPABASE_URL e SUPABASE_KEY nas propriedades do script');
 const options={method:method,muteHttpExceptions:true,headers:Object.assign({apikey:key,'Content-Type':'application/json',Prefer:'return=representation'},key.startsWith('sb_secret_')?{}:{Authorization:'Bearer '+key})};
 if(body!==undefined)options.payload=JSON.stringify(body);
 const response=UrlFetchApp.fetch(base.replace(/\/$/,'')+'/rest/v1/'+resource+(query?'?'+query:''),options);
 if(response.getResponseCode()<200||response.getResponseCode()>=300)throw Error('Atestados: banco HTTP '+response.getResponseCode());
 return response.getContentText()?JSON.parse(response.getContentText()):[];
}
function subpastaAtestadoRH(parent,name){
 const matches=filhosDriveRH(parent).filter(f=>f.mimeType==='application/vnd.google-apps.folder'&&nomeDriveRH(f.name)===nomeDriveRH(name));
 if(matches.length>1)throw Error('Há pastas duplicadas de '+name+'. Confira no Drive antes de tentar novamente');
 return matches[0]||apiDriveRH('files','post',{name:name,mimeType:'application/vnd.google-apps.folder',parents:[parent]},{fields:'id,name'});
}
function permissoesAtestadoRH(fileId){
 let token,permissions=[];
 do{
  const page=apiDriveRH('files/'+idDriveRH(fileId)+'/permissions','get',undefined,{pageSize:100,fields:'nextPageToken,permissions(type,role)',pageToken:token||''});
  permissions=permissions.concat(page.permissions||[]);token=page.nextPageToken;
 }while(token);
 if(permissions.some(p=>p.type==='anyone'||p.type==='domain'))throw Error('A pasta/arquivo de atestados tem compartilhamento público ou por domínio. Restrinja esse acesso no Drive e tente novamente');
}
function hashAtestadoRH(bytes){return Utilities.computeDigest(Utilities.DigestAlgorithm.SHA_256,bytes).map(b=>('0'+((b+256)%256).toString(16)).slice(-2)).join('');}
function validarBytesAtestadoRH(bytes,mime){
 const h=bytes.slice(0,8).map(b=>(b+256)%256);
 const valid=mime==='application/pdf'?h.length>=5&&[37,80,68,70,45].every((v,i)=>h[i]===v)
 :mime==='image/jpeg'?h.length>=3&&[255,216,255].every((v,i)=>h[i]===v)
 :mime==='image/png'?h.length===8&&[137,80,78,71,13,10,26,10].every((v,i)=>h[i]===v):false;
 if(!valid)throw Error('O conteúdo do atestado não corresponde a PDF, JPG ou PNG');
}
function pastaColaboradorAtestadoRH(employee,settings){
 let link=bancoAtestadosRH('rh_drive_links','get','funcionario_id=eq.'+employee.id)[0];
 let folder;
 if(link){
  if(link.template_pending)throw Error('A pasta do colaborador ainda está sendo preparada. Conclua o processamento nas automações');
  folder=pastaDriveRH(link.folder_id);
 }else{
  const folders=filhosDriveRH(settings.active_folder_id).concat(filhosDriveRH(settings.former_folder_id)).filter(f=>f.mimeType==='application/vnd.google-apps.folder');
  const candidates=candidatasPastaRH(folders,employee);
  if(candidates.length!==1)throw Error(candidates.length?'Há mais de uma pasta compatível. Vincule a pasta correta nas automações':'Pasta do colaborador não encontrada. Vincule ou processe a pasta nas automações');
  folder=pastaDriveRH(candidates[0].id);
 }
 if(!(folder.parents||[]).some(id=>id===settings.active_folder_id||id===settings.former_folder_id))throw Error('Pasta fora das raízes autorizadas de colaboradores');
 if(folder.appProperties?.rh_employee_id&&folder.appProperties.rh_employee_id!==employee.id)throw Error('Pasta vinculada a outro colaborador');
 if(!link)bancoAtestadosRH('rh_drive_links','post','',{funcionario_id:employee.id,folder_id:folder.id,template_pending:false,updated_at:new Date().toISOString()});
 return folder;
}
function importarAtestadoDriveRH(job,settings){
 if(!/^[0-9a-f-]{36}\/[0-9a-f-]{36}\.(pdf|jpg|png)$/.test(job.storage_path||'')||!/^\d{4}$/.test(job.year||''))throw Error('Identificação do atestado inválida');
 const employee=bancoAtestadosRH('funcionarios_epi','get','id=eq.'+job.funcionario_id+'&select=id,nome,cpf,data_desligamento')[0];
 if(!employee)throw Error('Colaborador não encontrado');
 const folder=pastaColaboradorAtestadoRH(employee,settings);
 const atestados=subpastaAtestadoRH(folder.id,'ATESTADOS');
 const year=subpastaAtestadoRH(atestados.id,job.year);
 permissoesAtestadoRH(year.id);
 const props=PropertiesService.getScriptProperties(),base=props.getProperty('SUPABASE_URL'),key=props.getProperty('SUPABASE_KEY');
 const response=UrlFetchApp.fetch(base.replace(/\/$/,'')+'/storage/v1/object/authenticated/rh-atestados/'+job.storage_path.split('/').map(encodeURIComponent).join('/'),{headers:Object.assign({apikey:key},key.startsWith('sb_secret_')?{}:{Authorization:'Bearer '+key}),muteHttpExceptions:true});
 if(response.getResponseCode()!==200)throw Error('Atestado privado indisponível. Confira se o anexo ainda existe no registro');
 const bytes=response.getBlob().getBytes();
 if(bytes.length!==Number(job.size)||bytes.length<1||bytes.length>10485760)throw Error('Tamanho do atestado não confere');
 validarBytesAtestadoRH(bytes,job.mime);
 const digest=hashAtestadoRH(bytes);
 const matches=listarDriveRH("appProperties has { key='rh_absence_source' and value='"+job.storage_path+"' }");
 if(matches.length>1)throw Error('O mesmo anexo foi encontrado mais de uma vez no Drive. Confira antes de tentar novamente');
 let file=matches[0];
 if(!file){
  const init=UrlFetchApp.fetch('https://www.googleapis.com/upload/drive/v3/files?uploadType=resumable&supportsAllDrives=true',{method:'post',headers:{Authorization:'Bearer '+ScriptApp.getOAuthToken(),'Content-Type':'application/json','X-Upload-Content-Type':job.mime},payload:JSON.stringify({name:job.filename,parents:[year.id],appProperties:{rh_absence_source:job.storage_path,rh_absence_sha256:digest,rh_employee_id:employee.id}}),muteHttpExceptions:true});
  if(init.getResponseCode()<200||init.getResponseCode()>=300)throw Error('Não foi possível iniciar o envio do atestado ao Drive');
  const uploadUrl=init.getAllHeaders().Location||init.getAllHeaders().location;
  if(typeof uploadUrl!=='string'||!uploadUrl.startsWith('https://www.googleapis.com/'))throw Error('Destino de upload inválido');
  const uploaded=UrlFetchApp.fetch(uploadUrl,{method:'put',headers:{Authorization:'Bearer '+ScriptApp.getOAuthToken()},contentType:job.mime,payload:bytes,muteHttpExceptions:true});
  if(uploaded.getResponseCode()<200||uploaded.getResponseCode()>=300)throw Error('Drive não confirmou o recebimento do atestado');
  file=JSON.parse(uploaded.getContentText());
 }
 const verified=apiDriveRH('files/'+idDriveRH(file.id),'get',undefined,{fields:'id,name,mimeType,size,parents,trashed,appProperties'});
 if(verified.trashed||verified.mimeType!==job.mime||Number(verified.size)!==bytes.length||verified.appProperties?.rh_absence_source!==job.storage_path||verified.appProperties?.rh_employee_id!==employee.id)throw Error('Arquivo do Drive não corresponde ao atestado enviado');
 const readback=UrlFetchApp.fetch('https://www.googleapis.com/drive/v3/files/'+idDriveRH(file.id)+'?alt=media&supportsAllDrives=true',{headers:{Authorization:'Bearer '+ScriptApp.getOAuthToken()},muteHttpExceptions:true});
 if(readback.getResponseCode()!==200||hashAtestadoRH(readback.getBlob().getBytes())!==digest)throw Error('O conteúdo gravado no Drive difere do atestado. Nenhum arquivo foi substituído');
 if(verified.name!==job.filename||!(verified.parents||[]).includes(year.id)){
  const params={fields:'id,name,parents'};
  if(!(verified.parents||[]).includes(year.id)){
   const previous=verified.parents||[];
   if(previous.length!==1)throw Error('Destino anterior do atestado exige revisão');
   const previousYear=pastaDriveRH(previous[0]);
   if(!(previousYear.parents||[]).includes(atestados.id))throw Error('Atestado encontrado fora da pasta ATESTADOS deste colaborador');
   params.addParents=year.id;params.removeParents=previous[0];
  }
  apiDriveRH('files/'+file.id,'patch',{name:job.filename},params);
 }
 const final=apiDriveRH('files/'+file.id,'get',undefined,{fields:'id,name,parents'});
 if(final.name!==job.filename||!(final.parents||[]).includes(year.id))throw Error('Drive não confirmou nome e destino do atestado');
 permissoesAtestadoRH(file.id);
 return {fileId:file.id,sha256:digest};
}
function processarAtestadosDriveRH(){
 const lock=LockService.getScriptLock();if(!lock.tryLock(1000))return;
 try{
  const settings=bancoAtestadosRH('rh_automation_settings','get','id=eq.true')[0];
  if(!settings)throw Error('Configuração das pastas indisponível');
  const deadline=Date.now()+240000;
  for(let count=0;count<10&&Date.now()<deadline-45000;count++){
   const jobs=bancoAtestadosRH('rpc/rh_claim_absence_drive','post','',{});if(!jobs.length)break;
   const job=jobs[0];let result,error;
   try{result=importarAtestadoDriveRH(job,settings);}catch(e){error=String(e.message).slice(0,500);}
   bancoAtestadosRH('rpc/rh_finish_absence_drive','post','',{p_id:job.id,p_revision:job.revision,p_file_id:result?.fileId||null,p_sha256:result?.sha256||null,p_error:error||null});
   if(error)break;
  }
 }finally{lock.releaseLock();}
}
function instalarAtestadosDriveRH(){
 if(typeof apiDriveRH!=='function'||typeof candidatasPastaRH!=='function')throw Error('Instale primeiro RH_Drive_Automacoes no mesmo projeto');
 DriveApp.getRootFolder().getId();
 const settings=bancoAtestadosRH('rh_automation_settings','get','id=eq.true')[0];validarRaizesDriveRH(settings);
 ScriptApp.getProjectTriggers().filter(t=>t.getHandlerFunction()==='processarAtestadosDriveRH').forEach(t=>ScriptApp.deleteTrigger(t));
 ScriptApp.newTrigger('processarAtestadosDriveRH').timeBased().everyMinutes(1).create();
 processarAtestadosDriveRH();
 console.log('Processador de atestados instalado: ATESTADOS / ano, sem mês.');
}
