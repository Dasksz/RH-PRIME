const fs=require('node:fs'),vm=require('node:vm'),assert=require('node:assert/strict'),crypto=require('node:crypto');
const employee={id:'11111111-1111-4111-8111-111111111111',nome:'PESSOA FICTÍCIA',cpf:'12345678901'};
const active='active-folder-001',former='former-folder-001',home='employee-folder-001';
const folders=[{id:home,name:employee.nome,mimeType:'application/vnd.google-apps.folder',parents:[active],appProperties:{rh_employee_id:employee.id}},
 {id:'atestados-folder-001',name:'ATESTADOS',mimeType:'application/vnd.google-apps.folder',parents:[home]},
 {id:'year-folder-001',name:'2026',mimeType:'application/vnd.google-apps.folder',parents:['atestados-folder-001']}];
const files=[],createdFolders=[],uploaded=[];let pending,publicSharing=false,link={folder_id:home,template_pending:false};
const bytes=Array.from(Buffer.from('%PDF-1.7\nDocumento ficticio'));
function response(body,status=200,headers={}){return {getResponseCode:()=>status,getContentText:()=>JSON.stringify(body),getAllHeaders:()=>headers,getBlob:()=>({getBytes:()=>body})};}
const ctx={console,Date,Set,JSON,encodeURIComponent,
 PropertiesService:{getScriptProperties:()=>({getProperty:key=>key==='SUPABASE_URL'?'https://fixture.supabase.co':'sb_secret_fixture'})},
 ScriptApp:{getOAuthToken:()=> 'fixture-oauth'},
 Utilities:{DigestAlgorithm:{SHA_256:'sha256'},computeDigest:(_,b)=>Array.from(crypto.createHash('sha256').update(Buffer.from(b.map(x=>(x+256)%256))).digest())},
 UrlFetchApp:{fetch(url,opts){
  if(url.includes('/storage/')){assert.equal(opts.headers.apikey,'sb_secret_fixture');assert.equal(opts.headers.Authorization,undefined);return response(bytes);}
  if(url.includes('uploadType=resumable')){pending=JSON.parse(opts.payload);assert.equal(opts.headers['X-Upload-Content-Type'],'application/pdf');return response({},200,{Location:'https://www.googleapis.com/upload/fixture-session'});}
  if(url.includes('/upload/fixture-session')){const file={id:'file-fixture-'+(files.length+1),...pending,mimeType:opts.contentType,size:opts.payload.length,bytes:[...opts.payload]};files.push(file);uploaded.push(file);return response({id:file.id});}
  if(url.includes('alt=media')){const file=files.find(f=>url.includes(f.id));return response(file.bytes);}
  throw Error('Unexpected request '+url);
 }},
 idDriveRH:id=>id,
 nomeDriveRH:s=>s.toUpperCase(),
 filhosDriveRH:id=>folders.filter(f=>f.parents.includes(id)),
 pastaDriveRH:id=>folders.find(f=>f.id===id),
 candidatasPastaRH:candidates=>candidates.filter(f=>f.id===home),
 listarDriveRH:q=>files.filter(f=>q.includes(f.appProperties.rh_absence_source)),
 apiDriveRH(route,method,body,params){
  if(route==='files'&&method==='post'){const folder={id:'folder-created-'+(createdFolders.length+1),...body};folders.push(folder);createdFolders.push(folder);return folder;}
  if(route.endsWith('/permissions'))return {permissions:[{type:publicSharing?'anyone':'user',role:'reader'}]};
  const file=files.find(f=>route==='files/'+f.id);assert(file,'File not found '+route);
  if(method==='patch'){Object.assign(file,body);if(params.addParents)file.parents=[params.addParents];}
  return {...file};
 }
};
vm.createContext(ctx);vm.runInContext(fs.readFileSync(require('node:path').join(__dirname,'../RH_Atestados_Drive.gs'),'utf8'),ctx);
ctx.bancoAtestadosRH=(table,method,query,body)=>{
 if(table==='funcionarios_epi')return [employee];
 if(table==='rh_drive_links'){if(method==='post'){link=body;return [body];}return link?[link]:[];}
 throw Error('Unexpected table '+table);
};
const job={funcionario_id:employee.id,storage_path:employee.id+'/22222222-2222-4222-8222-222222222222.pdf',filename:'ATESTADO - 10.09 1 DIA - PESSOA FICTÍCIA.pdf',mime:'application/pdf',size:bytes.length,year:'2026'};
const settings={active_folder_id:active,former_folder_id:former};
const first=ctx.importarAtestadoDriveRH(job,settings);
assert.equal(createdFolders.length,0);assert.equal(uploaded.length,1);assert.equal(files[0].parents[0],'year-folder-001');
assert.equal(first.sha256,crypto.createHash('sha256').update(Buffer.from(bytes)).digest('hex'));
const retry=ctx.importarAtestadoDriveRH(job,settings);assert.equal(retry.fileId,first.fileId);assert.equal(uploaded.length,1);
ctx.importarAtestadoDriveRH({...job,year:'2025',filename:'COMPARECIMENTO 21.08 - PESSOA FICTÍCIA.pdf'},settings);
assert.deepEqual(createdFolders.map(f=>f.name),['2025']);assert.equal(files[0].name,'COMPARECIMENTO 21.08 - PESSOA FICTÍCIA.pdf');assert.equal(files[0].parents[0],createdFolders[0].id);assert.equal(uploaded.length,1);
link=null;ctx.importarAtestadoDriveRH({...job,year:'2025'},settings);assert.equal(link.folder_id,home);
files[0].bytes=[...bytes,32];assert.throws(()=>ctx.importarAtestadoDriveRH({...job,year:'2025'},settings),/conteúdo gravado/);files[0].bytes=bytes;
publicSharing=true;assert.throws(()=>ctx.importarAtestadoDriveRH(job,settings),/compartilhamento público/);publicSharing=false;
folders.push({id:'duplicate-year-001',name:'2026',mimeType:'application/vnd.google-apps.folder',parents:['atestados-folder-001']});
assert.throws(()=>ctx.importarAtestadoDriveRH(job,settings),/duplicadas/);
assert.equal(createdFolders.some(f=>/^(0[1-9]|1[0-2])$/.test(f.name)),false);
console.log('Year-only folders, reuse, deduplication, rename, year move, auto link, private sharing and byte integrity passed.');
