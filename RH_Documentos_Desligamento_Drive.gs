/* Depende de RH_Drive_Automacoes.gs e RH_Atestados_Drive.gs no mesmo projeto. */
function bancoDocumentoDesligamentoRH(resource,method,query,body){
 const allowed=['rh_automation_settings','funcionarios_epi','rpc/rh_claim_scheduled_notice_drive','rpc/rh_finish_scheduled_notice_drive'];
 if(!allowed.includes(resource))throw Error('Recurso não permitido');
 const props=PropertiesService.getScriptProperties(),base=props.getProperty('SUPABASE_URL'),key=props.getProperty('SUPABASE_KEY');
 if(!base||!base.startsWith('https://')||!base.slice(8).replace(new RegExp('/+$'),'').endsWith('.supabase.co')||!key)throw Error('Confira SUPABASE_URL e SUPABASE_KEY nas propriedades do Apps Script');
 const options={method:method,muteHttpExceptions:true,headers:Object.assign({apikey:key,'Content-Type':'application/json',Prefer:'return=representation'},key.startsWith('sb_secret_')?{}:{Authorization:'Bearer '+key})};
 if(body!==undefined)options.payload=JSON.stringify(body);
 const response=UrlFetchApp.fetch(base.replace(new RegExp('/+$'),'')+'/rest/v1/'+resource+(query?'?'+query:''),options);
 if(response.getResponseCode()<200||response.getResponseCode()>=300)throw Error('Documentos de desligamento: banco HTTP '+response.getResponseCode());
 return response.getContentText()?JSON.parse(response.getContentText()):[];
}
function importarDocumentoDesligamentoDriveRH(job,settings){
 const pathParts=String(job.storage_path||'').split('/');
 if(!['aviso_previo','rescisao'].includes(job.document_kind)||pathParts.length!==2||!/^[0-9a-f-]{36}$/.test(pathParts[0])||!/^[0-9a-f-]{36}[.](pdf|jpg|png)$/.test(pathParts[1])||!['application/pdf','image/jpeg','image/png'].includes(job.mime)||!/^.{1,255}$/.test(job.filename||''))throw Error('Identificação ou formato do documento inválido');
 const employee=bancoDocumentoDesligamentoRH('funcionarios_epi','get','id=eq.'+job.id+'&select=id,nome,cpf,data_desligamento,data_desligamento_programada,aviso_previo_path,aviso_previo_nome,rescisao_path,rescisao_nome')[0];
 if(!employee)throw Error('Colaborador não encontrado');
 const currentPath=job.document_kind==='aviso_previo'?employee.aviso_previo_path:employee.rescisao_path;
 const currentName=job.document_kind==='aviso_previo'?employee.aviso_previo_nome:employee.rescisao_nome;
 if(currentPath!==job.storage_path||currentName!==job.filename)throw Error('O documento mudou enquanto aguardava a sincronização; será processada a versão mais recente');
 const employeeFolder=pastaColaboradorAtestadoRH(employee,settings);
 const rescissionFolders=filhosDriveRH(employeeFolder.id).filter(f=>f.mimeType==='application/vnd.google-apps.folder'&&nomeDriveRH(f.name)==='RESCISAO');
 if(rescissionFolders.length!==1)throw Error(rescissionFolders.length?'Há mais de uma pasta RESCISÃO/RESCISAO. Confira o Drive antes de tentar novamente':'A pasta RESCISÃO/RESCISAO não existe na pasta do colaborador.');
 const destination=rescissionFolders[0];
 if(!(destination.parents||[]).includes(employeeFolder.id)||nomeDriveRH(destination.name)!=='RESCISAO')throw Error('A pasta de rescisão não pertence ao colaborador selecionado');
 permissoesAtestadoRH(destination.id);
 const props=PropertiesService.getScriptProperties(),base=props.getProperty('SUPABASE_URL'),key=props.getProperty('SUPABASE_KEY');
 const encoded=job.storage_path.split('/').map(encodeURIComponent).join('/');
 const response=UrlFetchApp.fetch(base.replace(new RegExp('/+$'),'')+'/storage/v1/object/authenticated/rh-documentos-desligamento/'+encoded,{headers:Object.assign({apikey:key},key.startsWith('sb_secret_')?{}:{Authorization:'Bearer '+key}),muteHttpExceptions:true});
 if(response.getResponseCode()!==200)throw Error('Documento privado indisponível no armazenamento');
 const bytes=response.getBlob().getBytes();if(bytes.length!==Number(job.size)||bytes.length<1||bytes.length>10485760)throw Error('Tamanho do documento não confere');
 validarBytesAtestadoRH(bytes,job.mime);
 const digest=hashAtestadoRH(bytes),sourceKey='rh_termination_document_source';
 const matches=listarDriveRH("appProperties has { key='"+sourceKey+"' and value='"+job.storage_path+"' }");
 if(matches.length>1)throw Error('O mesmo documento foi encontrado mais de uma vez no Drive; confira a pasta antes de tentar novamente');
 let file=matches[0];
 if(!file){
  const init=UrlFetchApp.fetch('https://www.googleapis.com/upload/drive/v3/files?uploadType=resumable&supportsAllDrives=true',{method:'post',headers:{Authorization:'Bearer '+ScriptApp.getOAuthToken(),'Content-Type':'application/json','X-Upload-Content-Type':job.mime},payload:JSON.stringify({name:job.filename,parents:[destination.id],appProperties:{[sourceKey]:job.storage_path,rh_employee_id:employee.id,rh_termination_document_kind:job.document_kind,rh_termination_sha256:digest}}),muteHttpExceptions:true});
  if(init.getResponseCode()<200||init.getResponseCode()>=300)throw Error('Não foi possível iniciar o envio do documento ao Drive');
  const uploadUrl=init.getAllHeaders().Location||init.getAllHeaders().location;
  if(typeof uploadUrl!=='string'||!uploadUrl.startsWith('https://www.googleapis.com/'))throw Error('Destino de upload inválido');
  const uploaded=UrlFetchApp.fetch(uploadUrl,{method:'put',headers:{Authorization:'Bearer '+ScriptApp.getOAuthToken()},contentType:job.mime,payload:bytes,muteHttpExceptions:true});
  if(uploaded.getResponseCode()<200||uploaded.getResponseCode()>=300)throw Error('Drive não confirmou o recebimento do documento');
  file=JSON.parse(uploaded.getContentText());
 }
 const verified=apiDriveRH('files/'+idDriveRH(file.id),'get',undefined,{fields:'id,name,mimeType,size,parents,trashed,appProperties'});
 if(verified.trashed||verified.mimeType!==job.mime||Number(verified.size)!==bytes.length||verified.appProperties?.[sourceKey]!==job.storage_path||verified.appProperties?.rh_employee_id!==employee.id)throw Error('Arquivo do Drive não corresponde ao documento enviado');
 const readback=UrlFetchApp.fetch('https://www.googleapis.com/drive/v3/files/'+idDriveRH(file.id)+'?alt=media&supportsAllDrives=true',{headers:{Authorization:'Bearer '+ScriptApp.getOAuthToken()},muteHttpExceptions:true});
 if(readback.getResponseCode()!==200||hashAtestadoRH(readback.getBlob().getBytes())!==digest)throw Error('O conteúdo gravado no Drive difere do documento enviado');
 if(verified.name!==job.filename||!(verified.parents||[]).includes(destination.id)){
  const params={fields:'id,name,parents'};
  if(!(verified.parents||[]).includes(destination.id)){
   const parents=verified.parents||[];
   if(parents.length!==1)throw Error('Localização anterior do documento exige revisão');
   const previous=pastaDriveRH(parents[0]);
   if(!(previous.parents||[]).includes(employeeFolder.id)||nomeDriveRH(previous.name)!=='RESCISAO')throw Error('Documento encontrado fora da pasta RESCISÃO deste colaborador');
   params.addParents=destination.id;params.removeParents=parents[0];
  }
  apiDriveRH('files/'+file.id,'patch',{name:job.filename},params);
 }
 const final=apiDriveRH('files/'+file.id,'get',undefined,{fields:'id,name,parents'});
 if(final.name!==job.filename||!(final.parents||[]).includes(destination.id))throw Error('Drive não confirmou o nome e a pasta do documento');
 permissoesAtestadoRH(file.id);
 return {fileId:file.id,sha256:digest};
}
function processarDocumentosDesligamentoDriveRH(){
 const lock=LockService.getScriptLock();if(!lock.tryLock(1000))return;
 try{
  const settings=bancoDocumentoDesligamentoRH('rh_automation_settings','get','id=eq.true')[0];if(!settings)throw Error('Configuração das pastas do Drive indisponível');
  for(let count=0;count<8;count++){
   const jobs=bancoDocumentoDesligamentoRH('rpc/rh_claim_scheduled_notice_drive','post','',{});if(!jobs.length)break;
   const job=jobs[0];let result,error;
   try{result=importarDocumentoDesligamentoDriveRH(job,settings);}catch(e){error=String(e.message).slice(0,500);}
   bancoDocumentoDesligamentoRH('rpc/rh_finish_scheduled_notice_drive','post','',{p_id:job.id,p_kind:job.document_kind,p_revision:job.revision,p_file_id:result?.fileId||null,p_sha256:result?.sha256||null,p_error:error||null});
   if(error)break;
  }
 }finally{lock.releaseLock();}
}
function instalarDocumentosDesligamentoDriveRH(){
 if(typeof apiDriveRH!=='function'||typeof pastaColaboradorAtestadoRH!=='function'||typeof permissoesAtestadoRH!=='function')throw Error('Instale RH_Drive_Automacoes e RH_Atestados_Drive no mesmo projeto');
 DriveApp.getRootFolder().getId();
 ScriptApp.getProjectTriggers().filter(t=>t.getHandlerFunction()==='processarDocumentosDesligamentoDriveRH').forEach(t=>ScriptApp.deleteTrigger(t));
 ScriptApp.newTrigger('processarDocumentosDesligamentoDriveRH').timeBased().everyMinutes(1).create();
 processarDocumentosDesligamentoDriveRH();
 console.log('Envio privado de avisos prévios e documentos de rescisão habilitado.');
}
