/* Manutenção manual, retomável. Não envia mensagens e não exclui PDFs. */
var cacheConsolidacaoRH=null;
var comprovantesConsolidacaoRH=null;
function arquivosConsolidacaoRH(parent){
 if(cacheConsolidacaoRH&&cacheConsolidacaoRH[parent])return cacheConsolidacaoRH[parent];
 let rows=[],token;
 do{const r=apiDriveRH('files','get',undefined,{q:"'"+idDriveRH(parent)+"' in parents and trashed=false",pageSize:1000,fields:'nextPageToken,files(id,name,mimeType,parents,modifiedTime,size)',includeItemsFromAllDrives:true,pageToken:token||''});rows=rows.concat(r.files||[]);token=r.nextPageToken;}while(token);
 if(cacheConsolidacaoRH)cacheConsolidacaoRH[parent]=rows;return rows;
}
function prepararLeiturasConsolidacaoRH(pairs){
 cacheConsolidacaoRH={};comprovantesConsolidacaoRH={};let wave=pairs;
 const headers={Authorization:'Bearer '+ScriptApp.getOAuthToken()};
 while(wave.length){
  const ids=[...new Set(wave.flatMap(p=>[p.source,p.target]).filter(Boolean))].filter(id=>!cacheConsolidacaoRH[id]);
  for(let start=0;start<ids.length;start+=40){
   const batch=ids.slice(start,start+40),responses=UrlFetchApp.fetchAll(batch.map(id=>({url:'https://www.googleapis.com/drive/v3/files?'+Object.entries({q:"'"+idDriveRH(id)+"' in parents and trashed=false",pageSize:1000,fields:'nextPageToken,files(id,name,mimeType,parents,modifiedTime,size)',supportsAllDrives:true,includeItemsFromAllDrives:true}).map(([k,v])=>encodeURIComponent(k)+'='+encodeURIComponent(v)).join('&'),headers,muteHttpExceptions:true})));
   responses.forEach((r,i)=>{if(r.getResponseCode()!==200)throw Error('Falha na leitura de pasta');const body=JSON.parse(r.getContentText());if(!body.nextPageToken)cacheConsolidacaoRH[batch[i]]=body.files||[];else arquivosConsolidacaoRH(batch[i]);});
  }
  const next=[];
  for(const pair of wave){
   const dest=cacheConsolidacaoRH[pair.target]||[];
   for(const f of cacheConsolidacaoRH[pair.source]||[]){if(f.mimeType!=='application/vnd.google-apps.folder')continue;
    const matches=dest.filter(d=>d.mimeType===f.mimeType&&chavePastaConsolidacaoRH(d.name)===chavePastaConsolidacaoRH(f.name));
    if(matches.length>1)throw Error('Mês ou ano ambíguo');if(matches.length)next.push({source:f.id,target:matches[0].id});
   }
  }
  wave=next;
 }
 const proofs=Object.values(cacheConsolidacaoRH).flat().filter(f=>f.mimeType==='text/plain'&&/COMPROVANTE/.test(nomeDriveRH(f.name))&&Number(f.size)<=100000);
 for(let start=0;start<proofs.length;start+=40){const batch=proofs.slice(start,start+40),responses=UrlFetchApp.fetchAll(batch.map(f=>({url:'https://www.googleapis.com/drive/v3/files/'+idDriveRH(f.id)+'?alt=media&supportsAllDrives=true',headers,muteHttpExceptions:true})));
  responses.forEach((r,i)=>{if(r.getResponseCode()!==200)throw Error('Comprovante indisponível');comprovantesConsolidacaoRH[batch[i].id]=r.getContentText();});
 }
}
function chavePastaConsolidacaoRH(name){
 const n=nomeDriveRH(name),m=n.match(/^(0?[1-9]|1[0-2])(?: (20\d{2}))?$/);
 return m?String(Number(m[1])).padStart(2,'0'):n;
}
function paresConsolidacaoRH(){
 const s=bancoDocumentosRH('rh_automation_settings','get','id=eq.true')[0],pairs=[];
 const employees=[...arquivosConsolidacaoRH(s.active_folder_id),...arquivosConsolidacaoRH(s.former_folder_id)].filter(f=>f.mimeType==='application/vnd.google-apps.folder');
 const all=listarDriveRH("(name = 'HOLERITE' or name = 'HOLERITES') and mimeType = 'application/vnd.google-apps.folder'");
  for(const employee of employees){
   const dirs=all.filter(f=>(f.parents||[]).includes(employee.id));
   const a=dirs.filter(f=>nomeDriveRH(f.name)==='HOLERITE'),b=dirs.filter(f=>nomeDriveRH(f.name)==='HOLERITES');
   if(a.length>1||b.length>1)throw Error('Pastas homônimas ambíguas em '+employee.id);
   if(a.length===1&&b.length===1)pairs.push({source:b[0].id,target:a[0].id,employee:employee.id});
  }
 return pairs;
}
function verificarConsolidacaoHoleritesRH(){
 const pairs=paresConsolidacaoRH();console.log(JSON.stringify({pares:pairs.length,pairs}));return pairs.length;
}
function consolidarHoleritesRH(){
 const lock=LockService.getScriptLock();if(!lock.tryLock(1000))throw Error('Outro processador está em execução.');
 const end=Date.now()+270000,report={consolidadas:0,movidos:0,arquivados:0,pastasVazias:0,ambiguos:0,pendentes:0},audit=[];
 const isFolder=f=>f.mimeType==='application/vnd.google-apps.folder';
 const check=()=>{if(Date.now()>end)throw Error('CONTINUAR');};
 function move(f,from,to){
  check();const r=apiDriveRH('files/'+idDriveRH(f.id),'patch',undefined,{addParents:to,removeParents:from,fields:'id,parents'});
  if(!(r.parents||[]).includes(to)||(r.parents||[]).includes(from))throw Error('Movimento não confirmado: '+f.id);
  if(cacheConsolidacaoRH){cacheConsolidacaoRH[from]=(cacheConsolidacaoRH[from]||[]).filter(x=>x.id!==f.id);if(cacheConsolidacaoRH[to])cacheConsolidacaoRH[to]=cacheConsolidacaoRH[to].concat([{...f,parents:r.parents}]);}
  report.movidos++;audit.push({id:f.id,from,to});
 }
 function emptyTrash(id){
  check();if(cacheConsolidacaoRH)delete cacheConsolidacaoRH[id];if(arquivosConsolidacaoRH(id).length)throw Error('Pasta ainda contém arquivos: '+id);
  const r=apiDriveRH('files/'+id,'patch',{trashed:true},{fields:'id,trashed'});if(!r.trashed)throw Error('Lixeira não confirmada');report.pastasVazias++;
 }
 function proofText(f){
  if(!/COMPROVANTE/.test(nomeDriveRH(f.name))||f.mimeType!=='text/plain'||Number(f.size)>100000)return '';
  let text=comprovantesConsolidacaoRH&&comprovantesConsolidacaoRH[f.id];
  if(text===undefined||text===null){const r=UrlFetchApp.fetch('https://www.googleapis.com/drive/v3/files/'+idDriveRH(f.id)+'?alt=media&supportsAllDrives=true',{headers:{Authorization:'Bearer '+ScriptApp.getOAuthToken()},muteHttpExceptions:true});if(r.getResponseCode()!==200)throw Error('Comprovante indisponível: '+f.id);text=r.getContentText();}
  return /COMPROVANTE DE ENVIO DE DOCUMENTO/.test(text)&&/Status HTTP: 200/.test(text)&&/ID Oficial da Transmissão/.test(text)?text:'';
 }
 function dedup(parent,archiveRoot,path){
  check();const files=arquivosConsolidacaoRH(parent).filter(f=>!isFolder(f));
  const proof=files.map(proofText).filter(Boolean),groups={};
  const ordinary=files.filter(f=>f.mimeType==='application/pdf'&&/HOLERITES?/.test(nomeDriveRH(f.name))&&!/ADIANTAMENTO|DECIMO|13 SALARIO|FERIAS|RESCISAO|COMPLEMENTAR/.test(nomeDriveRH(f.name)));
  for(const f of files){
   const key=ordinary.length===2&&ordinary.some(x=>x.id===f.id)?'HOLERITE_MENSAL':nomeDriveRH(f.name);
   (groups[key]||(groups[key]=[])).push(f);
  }
  for(const group of Object.values(groups).filter(g=>g.length>1)){
   if(group.some(f=>/COMPROVANTE/.test(nomeDriveRH(f.name)))){report.ambiguos++;continue;}
   const sent=f=>proof.some(t=>t.includes(f.id)||(!group.some(g=>t.includes(g.id))&&t.includes('Arquivo de Referência: '+f.name)));
   group.sort((a,b)=>Number(sent(b))-Number(sent(a))||Date.parse(b.modifiedTime)-Date.parse(a.modifiedTime));
   if(sent(group[0])===sent(group[1])&&group[0].modifiedTime===group[1].modifiedTime){report.ambiguos++;continue;}
   let archives=arquivosConsolidacaoRH(archiveRoot).filter(f=>isFolder(f)&&f.name==='VERSÕES ANTERIORES');
   if(archives.length>1)throw Error('Arquivo de versões ambíguo');
   const archive=archives[0]||apiDriveRH('files','post',{name:'VERSÕES ANTERIORES',mimeType:'application/vnd.google-apps.folder',parents:[archiveRoot]},{fields:'id'});
   if(!archives.length&&cacheConsolidacaoRH&&cacheConsolidacaoRH[archiveRoot])cacheConsolidacaoRH[archiveRoot].push({...archive,name:'VERSÕES ANTERIORES',mimeType:'application/vnd.google-apps.folder',parents:[archiveRoot]});
   for(const loser of group.slice(1)){move(loser,parent,archive.id);report.arquivados++;console.log(JSON.stringify({mantido:group[0].id,arquivado:loser.id,motivo:sent(group[0])?'comprovante':'edicao_mais_recente',periodo:path}));}
  }
 }
 function merge(source,target,archiveRoot,path){
  check();let dest=arquivosConsolidacaoRH(target);
  for(const f of arquivosConsolidacaoRH(source)){
   check();if(isFolder(f)){
    const matches=dest.filter(x=>isFolder(x)&&chavePastaConsolidacaoRH(x.name)===chavePastaConsolidacaoRH(f.name));
    if(matches.length>1)throw Error('Mês ou ano ambíguo: '+target);
    if(matches.length)merge(f.id,matches[0].id,archiveRoot,path+'/'+f.name);
    else{move(f,source,target);dest.push(f);}
   }else{move(f,source,target);dest.push(f);}
  }
  dedup(target,archiveRoot,path);emptyTrash(source);
 }
 try{
  const pairs=paresConsolidacaoRH();report.pendentes=pairs.length;
  if(pairs.length>10)prepararLeiturasConsolidacaoRH(pairs);else{cacheConsolidacaoRH={};comprovantesConsolidacaoRH={};}
  for(const pair of pairs){check();merge(pair.source,pair.target,pair.target,'');report.consolidadas++;report.pendentes--;console.log(JSON.stringify({pastaConsolidada:pair.target,progresso:report}));}
 }catch(e){report.erro=String(e.message);if(e.message!=='CONTINUAR')console.log('ERRO: '+e.message);}
 finally{console.log(JSON.stringify({resumo:report,movimentos:audit}));cacheConsolidacaoRH=null;comprovantesConsolidacaoRH=null;lock.releaseLock();}
 return report;
}
