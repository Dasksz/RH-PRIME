/* Treinamentos RH PRIME. Usa as propriedades e os escopos já existentes.
 * A rota training_upload deve ser despachada pelo doPost principal antes do webhook.
 */
function bancoTreinamentoRH(resource,body){
 if(!['rh_begin_training_upload','rh_finish_training_upload'].includes(resource))throw Error('Recurso de treinamento inválido');
 const props=propriedadesRH(),base=props.getProperty('SUPABASE_URL'),key=props.getProperty('SUPABASE_KEY');
 if(!/^https:\/\/[a-z0-9-]+\.supabase\.co\/?$/.test(base||'')||!key)throw Error('Configuração Supabase indisponível');
 const response=UrlFetchApp.fetch(base.replace(/\/$/,'')+'/rest/v1/rpc/'+resource,{method:'post',contentType:'application/json',headers:Object.assign({apikey:key},key.startsWith('sb_secret_')?{}:{Authorization:'Bearer '+key}),payload:JSON.stringify(resource==='rh_finish_training_upload'?{payload:body}:body),muteHttpExceptions:true});
 if(response.getResponseCode()<200||response.getResponseCode()>=300)throw Error('Não foi possível confirmar o registro do comprovante');
 return JSON.parse(response.getContentText());
}
function autorizarTreinamentoRH(jwt){
 if(typeof jwt!=='string'||jwt.length>10000||!/^eyJ[A-Za-z0-9_.-]+$/.test(jwt))throw Error('Sessão inválida');
 const p=propriedadesRH(),base=p.getProperty('SUPABASE_URL'),key=p.getProperty('SUPABASE_KEY');
 const headers={apikey:key,Authorization:'Bearer '+jwt};
 const auth=UrlFetchApp.fetch(base.replace(/\/$/,'')+'/auth/v1/user',{headers:headers,muteHttpExceptions:true});
 if(auth.getResponseCode()!==200)throw Error('Entre novamente no sistema');
 const user=JSON.parse(auth.getContentText());
 if(!/^[a-f0-9-]{36}$/i.test(user.id||''))throw Error('Sessão inválida');
 const profile=UrlFetchApp.fetch(base.replace(/\/$/,'')+'/rest/v1/profiles?id=eq.'+user.id+'&select=status',{headers:headers,muteHttpExceptions:true});
 if(profile.getResponseCode()!==200||JSON.parse(profile.getContentText())[0]?.status!=='admin')throw Error('Somente administradores podem anexar comprovantes');
 return user.id;
}
function subpastaTreinamentoRH(parent,name){
 const matches=filhosDriveRH(parent).filter(f=>f.mimeType==='application/vnd.google-apps.folder'&&f.name===name);
 if(matches.length>1)throw Error('Há pastas duplicadas de '+name+'. Confira no Drive');
 return matches[0]||apiDriveRH('files','post',{name:name,mimeType:'application/vnd.google-apps.folder',parents:[parent]},{fields:'id,name'});
}
function bytesTreinamentoValidosRH(bytes,mime){
 const b=bytes.slice(0,12).map(v=>(v+256)%256),prefix=values=>values.every((v,i)=>b[i]===v);
 if(mime==='application/pdf')return prefix([37,80,68,70,45]);
 if(mime==='image/jpeg')return prefix([255,216,255]);
 if(mime==='image/png')return prefix([137,80,78,71,13,10,26,10]);
 if(mime==='image/webp')return prefix([82,73,70,70])&&[87,69,66,80].every((v,i)=>b[i+8]===v);
 if(['application/vnd.openxmlformats-officedocument.wordprocessingml.document','application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'].includes(mime))return prefix([80,75,3,4]);
 return mime==='text/plain';
}
function salvarComprovanteTreinamentoRH(data){
 autorizarTreinamentoRH(data.access_token);
 if(!/^[a-f0-9-]{36}$/i.test(data.file_id||'')||typeof data.base64!=='string'||data.base64.length>13982000)throw Error('Arquivo inválido ou maior que 10 MB');
 const lock=LockService.getScriptLock();if(!lock.tryLock(30000))throw Error('Há outro envio em andamento. Tente novamente');
 let job;
 try{
  job=bancoTreinamentoRH('rh_begin_training_upload',{file_id:data.file_id});const f=job.arquivo,t=job.treinamento;
  if(f.status==='arquivado')return {status:'success',arquivo:f};
  const bytes=Utilities.base64Decode(data.base64),sha=hashAtestadoRH(bytes);
  if(bytes.length!==f.tamanho||sha!==f.sha256||!bytesTreinamentoValidosRH(bytes,f.mime))throw Error('O conteúdo do arquivo não corresponde ao comprovante informado');
  const root='1BIlpnhv9m7LJrW-XtpJaZo2NLY7loSi2';pastaDriveRH(root);
  const year=t.data_realizacao.slice(0,4),month=t.data_realizacao.slice(5,7),months=['Janeiro','Fevereiro','Março','Abril','Maio','Junho','Julho','Agosto','Setembro','Outubro','Novembro','Dezembro'];
  const y=subpastaTreinamentoRH(root,year),m=subpastaTreinamentoRH(y.id,month+' - '+months[Number(month)-1]);
  let folder;
  if(t.drive_folder_id){folder=pastaDriveRH(t.drive_folder_id);if(!(folder.parents||[]).includes(m.id))throw Error('A pasta do treinamento mudou de local. Confira antes de reenviar');}
  else{
   const found=filhosDriveRH(m.id).filter(x=>x.mimeType==='application/vnd.google-apps.folder'&&x.appProperties?.rh_training_id===t.id);
   if(found.length>1)throw Error('Há mais de uma pasta para o treinamento');
   folder=found[0]||apiDriveRH('files','post',{name:t.nome.replace(/[\x00-\x1f/\\]/g,' ').slice(0,180),mimeType:'application/vnd.google-apps.folder',parents:[m.id],appProperties:{rh_training_id:t.id}},{fields:'id,name,parents,appProperties'});
  }
  const foundFiles=filhosDriveRH(folder.id).filter(x=>x.appProperties?.rh_training_file===f.id);
  if(foundFiles.length>1)throw Error('Comprovante duplicado no Drive');
  let file=foundFiles[0];
  if(!file){
   const init=UrlFetchApp.fetch('https://www.googleapis.com/upload/drive/v3/files?uploadType=resumable&supportsAllDrives=true',{method:'post',headers:{Authorization:'Bearer '+ScriptApp.getOAuthToken(),'Content-Type':'application/json','X-Upload-Content-Type':f.mime},payload:JSON.stringify({name:f.nome,parents:[folder.id],appProperties:{rh_training_id:t.id,rh_training_file:f.id,rh_training_sha256:sha}}),muteHttpExceptions:true});
   const location=init.getHeaders().Location||init.getHeaders().location;if(init.getResponseCode()!==200||!location)throw Error('Drive não iniciou o envio');
   const sent=UrlFetchApp.fetch(location,{method:'put',contentType:f.mime,payload:bytes,headers:{Authorization:'Bearer '+ScriptApp.getOAuthToken()},muteHttpExceptions:true});
   if(![200,201].includes(sent.getResponseCode()))throw Error('Drive não confirmou o envio');file=JSON.parse(sent.getContentText());
  }
  const verified=apiDriveRH('files/'+idDriveRH(file.id),'get',undefined,{fields:'id,name,mimeType,size,parents,trashed,appProperties,md5Checksum,webViewLink'});
  const md5=Utilities.computeDigest(Utilities.DigestAlgorithm.MD5,bytes).map(b=>('0'+((b+256)%256).toString(16)).slice(-2)).join('');
  if(verified.trashed||Number(verified.size)!==bytes.length||verified.mimeType!==f.mime||verified.md5Checksum!==md5||verified.appProperties?.rh_training_file!==f.id||!(verified.parents||[]).includes(folder.id)||!verified.webViewLink)throw Error('A verificação do comprovante no Drive falhou');
  const saved=bancoTreinamentoRH('rh_finish_training_upload',{id:f.id,sha256:sha,drive_file_id:verified.id,drive_url:verified.webViewLink,folder_id:folder.id});
  return {status:'success',arquivo:saved};
 }catch(e){if(job?.arquivo&&job.arquivo.status!=='arquivado'){try{bancoTreinamentoRH('rh_finish_training_upload',{id:job.arquivo.id,erro:String(e.message).slice(0,500)});}catch(_) {}}throw e;}
 finally{lock.releaseLock();}
}
