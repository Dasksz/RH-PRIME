/* Novo arquivo NO MESMO Apps Script dos sincronizadores e de RH_Drive_Automacoes.
 * Propriedades necessárias: N8N_RH_WEBHOOK_URL (HTTPS público), N8N_RH_TOKEN (Header Auth X-RH-Token).
 * Não usa endpoint MCP; libera PDFs individuais para leitura por link antes do envio. Execução depende de confirmação no painel.
 */
function bancoDocumentosRH(resource,method,query,body) {
 const allowed=['rh_delivery_documents','rh_automation_settings','rh_drive_links','funcionarios_epi','rpc/rh_claim_document'];
 if(!allowed.includes(resource))throw Error('Recurso não permitido');
 const props=PropertiesService.getScriptProperties(),url=props.getProperty('SUPABASE_URL'),key=props.getProperty('SUPABASE_KEY');
 if(!/^https:\/\/[a-z0-9-]+\.supabase\.co\/?$/.test(url||'')||!key)throw Error('Propriedades Supabase ausentes');
 const options={method:method,muteHttpExceptions:true,headers:{apikey:key,Authorization:'Bearer '+key,'Content-Type':'application/json',Prefer:'return=representation'}};
 if(body!==undefined)options.payload=JSON.stringify(body);
 const r=UrlFetchApp.fetch(url.replace(/\/$/,'')+'/rest/v1/'+resource+(query?'?'+query:''),options);
 if(r.getResponseCode()<200||r.getResponseCode()>=300)throw Error('Banco: HTTP '+r.getResponseCode()+' em '+resource);
 return r.getContentText()?JSON.parse(r.getContentText()):[];
}
function atualizarDocumentoRH(d,changes){return bancoDocumentosRH('rh_delivery_documents','patch','id=eq.'+d.id,Object.assign({updated_at:new Date().toISOString()},changes));}
function subpastaDocumentoRH(parent,name){
 const matches=filhosDriveRH(parent).filter(f=>f.mimeType==='application/vnd.google-apps.folder'&&f.name===name);
 if(matches.length>1)throw Error('Subpastas duplicadas: '+name);
 return matches[0]||apiDriveRH('files','post',{name:name,mimeType:'application/vnd.google-apps.folder',parents:[parent]},{fields:'id'});
}
function hashDocumentoRH(bytes){
 return Utilities.computeDigest(Utilities.DigestAlgorithm.SHA_256,bytes).map(b=>('0'+((b+256)%256).toString(16)).slice(-2)).join('');
}
function limparCopiaTemporariaDocumentoRH(d){
 if(d.source!=='upload'||d.storage_deleted_at)return;
 if(!d.drive_file_id||!d.storage_path||d.storage_path!==d.id+'.pdf'||!/^[a-f0-9]{64}$/.test(d.sha256||''))throw Error('Identificação insuficiente para limpar cópia temporária');
 const fileId=idDriveRH(d.drive_file_id);
 const metadata=apiDriveRH('files/'+fileId,'get',undefined,{fields:'id,mimeType,size,trashed,appProperties'});
 if(metadata.id!==fileId||metadata.trashed||metadata.mimeType!=='application/pdf'||metadata.appProperties?.rh_delivery_id!==d.id||!(Number(metadata.size)>0&&Number(metadata.size)<=10485760))throw Error('Arquivo do Drive não confirmado para limpeza');
 const drive=UrlFetchApp.fetch('https://www.googleapis.com/drive/v3/files/'+fileId+'?alt=media&supportsAllDrives=true',{headers:{Authorization:'Bearer '+ScriptApp.getOAuthToken()},muteHttpExceptions:true});
 if(drive.getResponseCode()!==200)throw Error('Não foi possível verificar o PDF no Drive');
 const bytes=drive.getBlob().getBytes();
 if(bytes.length!==Number(metadata.size)||hashDocumentoRH(bytes)!==d.sha256)throw Error('Conteúdo do Drive difere do PDF importado; cópia temporária preservada');
 const verified=new Date().toISOString();
 atualizarDocumentoRH(d,{drive_verified_at:verified,storage_cleanup_error:null});
 const props=PropertiesService.getScriptProperties(),base=props.getProperty('SUPABASE_URL'),key=props.getProperty('SUPABASE_KEY');
 if(!/^https:\/\/[a-z0-9-]+\.supabase\.co\/?$/.test(base||'')||!key)throw Error('Configuração de armazenamento ausente');
 const removed=UrlFetchApp.fetch(base.replace(/\/$/,'')+'/storage/v1/object/rh-documentos',{method:'delete',contentType:'application/json',headers:{apikey:key,Authorization:'Bearer '+key},payload:JSON.stringify({prefixes:[d.storage_path]}),muteHttpExceptions:true});
 if(removed.getResponseCode()<200||removed.getResponseCode()>=300||!Array.isArray(JSON.parse(removed.getContentText())))throw Error('Storage API não confirmou remoção da cópia temporária');
 atualizarDocumentoRH(d,{storage_deleted_at:new Date().toISOString(),storage_cleanup_error:null});
}
function tentarLimparCopiaDocumentoRH(d){
 try{limparCopiaTemporariaDocumentoRH(d);}
 catch(e){atualizarDocumentoRH(d,{storage_cleanup_error:String(e.message).slice(0,500)});}
}
function limparCopiasConfirmadasRH(deadline){
 const docs=bancoDocumentosRH('rh_delivery_documents','get','source=eq.upload&drive_file_id=not.is.null&storage_deleted_at=is.null&status=in.(ready,queued,accepted,uncertain,cancelled,failed)&order=updated_at.asc&limit=5');
 for(const d of docs){if(Date.now()>deadline-45000)break;tentarLimparCopiaDocumentoRH(d);}
}
function permissoesDocumentoDriveRH(fileId){
 let permissions=[],token;
 do{
  const params={fields:'nextPageToken,permissions(id,type,role,allowFileDiscovery)',pageSize:100};
  if(token)params.pageToken=token;
  const page=apiDriveRH('files/'+fileId+'/permissions','get',undefined,params);
  permissions=permissions.concat(page.permissions||[]);token=page.nextPageToken;
 }while(token);
 return permissions;
}
function garantirLeituraPublicaDocumentoRH(d){
 if(d.source!=='upload')return;
 const fileId=idDriveRH(d.drive_file_id);
 const file=apiDriveRH('files/'+fileId,'get',undefined,{fields:'id,mimeType,trashed,appProperties'});
 if(file.id!==fileId||file.trashed||file.mimeType!=='application/pdf'||file.appProperties?.rh_delivery_id!==d.id)throw Error('PDF não identificado como documento deste lote');
 const anyone=permissoesDocumentoDriveRH(fileId).find(p=>p.type==='anyone');
 if(!anyone)apiDriveRH('files/'+fileId+'/permissions','post',{type:'anyone',role:'reader',allowFileDiscovery:false},{fields:'id,type,role,allowFileDiscovery'});
 else if(anyone.role!=='reader'||anyone.allowFileDiscovery===true)apiDriveRH('files/'+fileId+'/permissions/'+anyone.id,'patch',{role:'reader',allowFileDiscovery:false},{fields:'id,type,role,allowFileDiscovery'});
 const verified=permissoesDocumentoDriveRH(fileId).some(p=>p.type==='anyone'&&p.role==='reader'&&p.allowFileDiscovery!==true);
 if(!verified)throw Error('Drive não confirmou Qualquer pessoa com o link — Leitor');
 atualizarDocumentoRH(d,{drive_public_reader_at:new Date().toISOString(),drive_access_error:null});
}
function liberarLeituraDocumentosPendentesRH(deadline,limit){
 const docs=bancoDocumentosRH('rh_delivery_documents','get','source=eq.upload&drive_file_id=not.is.null&drive_public_reader_at=is.null&status=in.(ready,queued,sending,accepted,uncertain,failed)&order=updated_at.asc&limit='+(limit||5));
 const result={verificados:0,falhas:0};
 for(const d of docs){
  if(Date.now()>deadline-20000)break;
  try{garantirLeituraPublicaDocumentoRH(d);result.verificados++;}
  catch(e){atualizarDocumentoRH(d,{drive_access_error:String(e.message).slice(0,500)});result.falhas++;}
 }
 return result;
}
// Somente permissões de arquivos já importados; não envia nem reenvia mensagens.
function liberarLeituraDocumentosExistentesRH(){
 const lock=LockService.getScriptLock();if(!lock.tryLock(1000))throw Error('Processador em execução. Aguarde e tente novamente.');
 try{
  const result=liberarLeituraDocumentosPendentesRH(Date.now()+240000,100);
  console.log(JSON.stringify(result));return result;
 }finally{lock.releaseLock();}
}
function importarDocumentoDriveRH(d,s){
 const employee=bancoDocumentosRH('funcionarios_epi','get','id=eq.'+d.funcionario_id)[0];
 if(!employee||employee.data_desligamento)throw Error('Cadastro indisponível ou colaborador desligado');
 const link=bancoDocumentosRH('rh_drive_links','get','funcionario_id=eq.'+d.funcionario_id)[0];
 if(!link || link.template_pending)throw Error('Processe primeiro a pasta do colaborador no painel de automações.');
 const folder=pastaDriveRH(link.folder_id);
 if(!(folder.parents||[]).includes(s.active_folder_id))throw Error('Pasta não está na raiz de ativos.');
 if((folder.appProperties||{}).rh_employee_id && folder.appProperties.rh_employee_id!==d.funcionario_id)throw Error('Pasta vinculada a outro colaborador.');
 const existing=listarDriveRH("appProperties has { key='rh_delivery_id' and value='"+d.id+"' }");
 if(existing.length>1)throw Error('Documento duplicado no Drive; revise.');
 let file=existing[0];
 if(!file){
  let target=folder.id;
  if(d.document_type==='FOLHA DE PONTO')target=subpastaDocumentoRH(target,'JORNADA E SEGURANÇA').id;
  target=subpastaDocumentoRH(target,d.document_type).id;
  const match=/^(0[1-9]|1[0-2])\/(\d{4})$/.exec(d.period);
  if(!match)throw Error('Competência precisa estar em MM/AAAA.');
  target=subpastaDocumentoRH(target,match[2]).id;target=subpastaDocumentoRH(target,match[1]).id;
  const props=PropertiesService.getScriptProperties(),base=props.getProperty('SUPABASE_URL'),key=props.getProperty('SUPABASE_KEY');
  const source=UrlFetchApp.fetch(base.replace(/\/$/,'')+'/storage/v1/object/authenticated/rh-documentos/'+encodeURIComponent(d.storage_path),{headers:{apikey:key,Authorization:'Bearer '+key},muteHttpExceptions:true});
  if(source.getResponseCode()!==200)throw Error('PDF privado indisponível no armazenamento');
  const bytes=source.getBlob().getBytes();
  if(bytes.length>10485760)throw Error('PDF excede 10 MB');
  const digest=Utilities.computeDigest(Utilities.DigestAlgorithm.SHA_256,bytes).map(b=>('0'+((b+256)%256).toString(16)).slice(-2)).join('');
  if(digest!==d.sha256)throw Error('Integridade do PDF não confere');
  const init=UrlFetchApp.fetch('https://www.googleapis.com/upload/drive/v3/files?uploadType=resumable&supportsAllDrives=true',{method:'post',headers:{Authorization:'Bearer '+ScriptApp.getOAuthToken(),'Content-Type':'application/json','X-Upload-Content-Type':'application/pdf'},payload:JSON.stringify({name:d.filename,parents:[target],appProperties:{rh_delivery_id:d.id}}),muteHttpExceptions:true});
  if(init.getResponseCode()<200||init.getResponseCode()>=300)throw Error('Não foi possível iniciar upload Drive');
  const uploadUrl=init.getAllHeaders().Location||init.getAllHeaders().location;
  if(!uploadUrl||!uploadUrl.startsWith('https://www.googleapis.com/'))throw Error('Destino de upload inválido');
  const result=UrlFetchApp.fetch(uploadUrl,{method:'put',headers:{Authorization:'Bearer '+ScriptApp.getOAuthToken()},contentType:'application/pdf',payload:bytes,muteHttpExceptions:true});
  if(result.getResponseCode()<200||result.getResponseCode()>=300)throw Error('Upload Drive sem confirmação; revisão necessária');
  file=JSON.parse(result.getContentText());
 }
 // Arquivo privado: a aprovação precisa de um link cujo acesso ao destinatário foi conferido.
 atualizarDocumentoRH(d,{drive_file_id:file.id,link:'https://drive.google.com/file/d/'+file.id+'/view'});
 garantirLeituraPublicaDocumentoRH(Object.assign({},d,{drive_file_id:file.id}));
 atualizarDocumentoRH(d,{status:'ready',drive_file_id:file.id,link:'https://drive.google.com/file/d/'+file.id+'/view',error:null});
 tentarLimparCopiaDocumentoRH(Object.assign({},d,{drive_file_id:file.id,status:'ready'}));
}
function telefoneDocumentoRH(value){let p=String(value||'').replace(/\D/g,'');if(p.length===10||p.length===11)p='55'+p;if(!/^55[1-9]\d\d{8,9}$/.test(p))throw Error('WhatsApp inválido');return p;}
function enviarDocumentoN8NRH(d){
 const e=bancoDocumentosRH('funcionarios_epi','get','id=eq.'+d.funcionario_id)[0];
 if(!e||e.data_desligamento)throw Error('Colaborador desligado ou indisponível');
 if(telefoneDocumentoRH(e.whatsapp)!==d.phone)throw Error('WhatsApp mudou após aprovação. Cancele e revise antes de enviar.');
 if(!d.approved_at||!d.message_text||!d.link)throw Error('Aprovação incompleta');
 const props=PropertiesService.getScriptProperties(),url=props.getProperty('N8N_RH_WEBHOOK_URL'),token=props.getProperty('N8N_RH_TOKEN');
 if(!/^https:\/\/[^/?#]+\/webhook\/[A-Za-z0-9_-]+$/.test(url||'')||!token||!token.trim()){
  const error=Error('N8N_CONFIG_MISSING: Configure webhook HTTPS e token de autenticação nas propriedades do Apps Script');
  error.code='N8N_CONFIG_MISSING';throw error;
 }
 if(d.source==='upload'){
  try{garantirLeituraPublicaDocumentoRH(d);}
  catch(e){const error=Error('DRIVE_LINK_PERMISSION: '+e.message);error.code='DRIVE_LINK_PERMISSION';throw error;}
 }
 let result;
 try{result=UrlFetchApp.fetch(url,{method:'post',contentType:'application/json',headers:{'X-RH-Token':token,'X-Idempotency-Key':d.id},payload:JSON.stringify({documentId:d.id,chatId:d.phone+'@c.us',caption:d.message_text,session:'default'}),muteHttpExceptions:true,followRedirects:false});}
 catch(e){atualizarDocumentoRH(d,{status:'uncertain',error:'Sem confirmação do n8n. Confira a execução antes de reenviar.'});return false;}
 let body;try{body=JSON.parse(result.getContentText());}catch(_){body={};}
 if(result.getResponseCode()>=200&&result.getResponseCode()<300&&body.accepted===true&&body.documentId===d.id){
  atualizarDocumentoRH(d,{status:'accepted',error:null});return true;
 }
 // O webhook pode ter executado mesmo que a resposta falhe: nenhuma tentativa automática.
 atualizarDocumentoRH(d,{status:'uncertain',error:'n8n não confirmou o documento (HTTP '+result.getResponseCode()+'). Confira a execução.'});return false;
}
function intervaloMensagemRH(count,random){random=random||Math.random;return count%5===0?45+Math.floor(random()*46):15+Math.floor(random()*11);}
function processarDocumentosWebRH(){
 const lock=LockService.getScriptLock();if(!lock.tryLock(1000))return;const deadline=Date.now()+240000;
 try{
  const s=bancoDocumentosRH('rh_automation_settings','get','id=eq.true')[0];
  bancoDocumentosRH('rh_automation_settings','patch','id=eq.true',{last_documents_worker_at:new Date().toISOString()});
  if(!s.documents_enabled)return;
  validarRaizesDriveRH(s);
  liberarLeituraDocumentosPendentesRH(deadline,5);
  limparCopiasConfirmadasRH(deadline);
  while(Date.now()<deadline-45000){
   const docs=bancoDocumentosRH('rpc/rh_claim_document','post','',{p_send:false});if(!docs.length)break;
   const d=docs[0];try{importarDocumentoDriveRH(d,s);}catch(e){atualizarDocumentoRH(d,{status:'failed',error:String(e.message).slice(0,500)});}
  }
  while(Date.now()<deadline-45000){
   const current=bancoDocumentosRH('rh_automation_settings','get','id=eq.true')[0];
   if(!current.documents_enabled||!current.n8n_enabled)break;
   const next=current.next_message_at?new Date(current.next_message_at).getTime():0;
   const delay=next-Date.now();if(delay>0){if(delay>deadline-Date.now()-45000)break;Utilities.sleep(delay);}
   const docs=bancoDocumentosRH('rpc/rh_claim_document','post','',{p_send:true});if(!docs.length)break;
   const d=docs[0];let accepted=false;
   try{accepted=enviarDocumentoN8NRH(d);}catch(e){
    const configuration=e.code==='N8N_CONFIG_MISSING',access=e.code==='DRIVE_LINK_PERMISSION';
    atualizarDocumentoRH(d,{status:(configuration||access)?'failed':'uncertain',error:String(e.message).slice(0,500)});
    if(configuration){bancoDocumentosRH('rh_automation_settings','patch','id=eq.true',{n8n_enabled:false});break;}
   }
   const count=current.messages_count+(accepted?1:0),seconds=intervaloMensagemRH(Math.max(count,1));
   bancoDocumentosRH('rh_automation_settings','patch','id=eq.true',{messages_count:count,next_message_at:new Date(Date.now()+seconds*1000).toISOString()});
  }
 }finally{lock.releaseLock();}
}
function instalarDocumentosWebRH(){
 DriveApp.getRootFolder().getId();
 const s=bancoDocumentosRH('rh_automation_settings','get','id=eq.true')[0];validarRaizesDriveRH(s);
 ScriptApp.getProjectTriggers().filter(t=>t.getHandlerFunction()==='processarDocumentosWebRH').forEach(t=>ScriptApp.deleteTrigger(t));
 ScriptApp.newTrigger('processarDocumentosWebRH').timeBased().everyMinutes(1).create();
 bancoDocumentosRH('rh_automation_settings','patch','id=eq.true',{last_documents_worker_at:new Date().toISOString()});
}
