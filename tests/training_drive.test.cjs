const {test}=require('node:test');
const assert=require('node:assert/strict');
const fs=require('node:fs');
const vm=require('node:vm');
const crypto=require('node:crypto');
const source=fs.readFileSync('integrations/google-apps-script/RH_Treinamentos.gs','utf8');
test('Uses the exact argument shape of both database RPCs',()=>{const requests=[],context={propriedadesRH:()=>({getProperty:k=>k==='SUPABASE_URL'?'https://unit.supabase.co':'sb_secret_unit_test'}),UrlFetchApp:{fetch:(url,options)=>{requests.push({url,body:JSON.parse(options.payload)});return {getResponseCode:()=>200,getContentText:()=>JSON.stringify({ok:true})};}}};vm.createContext(context);vm.runInContext(source,context);context.bancoTreinamentoRH('rh_begin_training_upload',{file_id:'file'});context.bancoTreinamentoRH('rh_finish_training_upload',{id:'file',sha256:'hash'});assert.deepEqual(requests[0].body,{file_id:'file'});assert.deepEqual(requests[1].body,{payload:{id:'file',sha256:'hash'}});});
function fixture(){
 const bytes=Buffer.from('%PDF-1.4\nTest only\n%%EOF'),hash=crypto.createHash('sha256').update(bytes).digest('hex');
 const file={id:'10000000-0000-4000-8000-000000000001',nome:'teste.pdf',mime:'application/pdf',tamanho:bytes.length,sha256:hash,status:'pendente'};
 const training={id:'20000000-0000-4000-8000-000000000001',nome:'Treinamento NR 23 Incêndio',status:'concluido',data_realizacao:'2026-11-04'};
 const root='1BIlpnhv9m7LJrW-XtpJaZo2NLY7loSi2',folders=[{id:root,name:'Registros de Treinamentos',mimeType:'application/vnd.google-apps.folder',parents:[]},{id:'year2026_folder',name:'2026',mimeType:'application/vnd.google-apps.folder',parents:[root]}];
 let sequence=0,uploaded=0,metadata,failFinish=false,role='admin',released=0;
 const response=(body,code=200,headers={})=>({getContentText:()=>JSON.stringify(body),getResponseCode:()=>code,getHeaders:()=>headers});
 const context={console,Error,JSON,propriedadesRH:()=>({getProperty:name=>name==='SUPABASE_URL'?'https://unit.supabase.co':'sb_secret_unit_test'}),ScriptApp:{getOAuthToken:()=> 'test-oauth'},LockService:{getScriptLock:()=>({tryLock:()=>true,releaseLock:()=>released++})},Utilities:{DigestAlgorithm:{MD5:'md5'},base64Decode:value=>[...Buffer.from(value,'base64')],computeDigest:(algorithm,value)=>[...crypto.createHash(algorithm).update(Buffer.from(value)).digest()]},hashAtestadoRH:value=>crypto.createHash('sha256').update(Buffer.from(value)).digest('hex'),idDriveRH:id=>id};
 context.UrlFetchApp={fetch:(url,options)=>{
  if(url.endsWith('/auth/v1/user'))return response({id:'30000000-0000-4000-8000-000000000001'});
  if(url.includes('/rest/v1/profiles'))return response([{status:role}]);
  if(url.includes('uploadType=resumable')){metadata=JSON.parse(options.payload);return response({},200,{Location:'https://upload.unit/session'});}
  if(url==='https://upload.unit/session'){uploaded++;const f={...metadata,id:'uploaded_file_0001',size:bytes.length,mimeType:options.contentType,md5Checksum:crypto.createHash('md5').update(Buffer.from(options.payload)).digest('hex'),webViewLink:'https://drive.google.com/file/d/uploaded_file_0001/view'};folders.push(f);return response(f);}
  throw Error('Unexpected URL');
 }};
 vm.createContext(context);vm.runInContext(source,context);
 context.bancoTreinamentoRH=(resource,payload)=>{
  if(resource==='rh_begin_training_upload')return {arquivo:{...file},treinamento:{...training}};
  if(payload.erro){file.status='falhou';return {...file};}
  if(failFinish){failFinish=false;throw Error('Simulated response loss');}
  Object.assign(file,payload,{status:'arquivado'});training.drive_folder_id=payload.folder_id;return {...file};
 };
 context.filhosDriveRH=id=>folders.filter(f=>(f.parents||[]).includes(id));
 context.pastaDriveRH=id=>{const folder=folders.find(f=>f.id===id);assert.ok(folder);return folder;};
 context.apiDriveRH=(path,method,body)=>{if(path==='files'&&method==='post'){const folder={...body,id:'created_folder_'+(++sequence)};folders.push(folder);return folder;}return folders.find(f=>f.id===path.slice(6));};
 return {context,file,training,folders,bytes,payload:()=>({access_token:'eyJunit',file_id:file.id,base64:bytes.toString('base64')}),setFail:()=>failFinish=true,setRole:value=>role=value,getUploaded:()=>uploaded,getReleased:()=>released};
}
test('Archives by actual year/month/course and verifies bytes and metadata',()=>{
 const f=fixture(),result=f.context.salvarComprovanteTreinamentoRH(f.payload());assert.equal(result.arquivo.status,'arquivado');assert.equal(f.getUploaded(),1);assert.equal(f.getReleased(),1);
 const course=f.folders.find(x=>x.id===f.training.drive_folder_id);assert.equal(course.name,'Treinamento NR 23 Incêndio');const month=f.folders.find(x=>x.id===course.parents[0]);assert.equal(month.name,'11 - Novembro');assert.equal(f.folders.find(x=>x.id===month.parents[0]).name,'2026');
 f.context.salvarComprovanteTreinamentoRH(f.payload());assert.equal(f.getUploaded(),1);
});
test('Retries after confirmation failure without duplicating the Drive file',()=>{const f=fixture();f.setFail();assert.throws(()=>f.context.salvarComprovanteTreinamentoRH(f.payload()),/response loss/);assert.equal(f.file.status,'falhou');assert.equal(f.getUploaded(),1);assert.equal(f.context.salvarComprovanteTreinamentoRH(f.payload()).arquivo.status,'arquivado');assert.equal(f.getUploaded(),1);});
test('Rejects content mismatch and users without administrator access',()=>{const f=fixture();assert.throws(()=>f.context.salvarComprovanteTreinamentoRH({...f.payload(),base64:Buffer.from('not PDF').toString('base64')}),/conteúdo/);assert.equal(f.getUploaded(),0);f.setRole('aprovado');assert.throws(()=>f.context.salvarComprovanteTreinamentoRH(f.payload()),/administradores/);assert.throws(()=>f.context.autorizarTreinamentoRH('invalid'),/Sessão inválida/);});
