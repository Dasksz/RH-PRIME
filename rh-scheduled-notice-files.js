(function(root){
 'use strict';
 const bucket='rh-documentos-desligamento',limit=10*1024*1024;
 async function validate(file){
  if(!file||file.size<1)throw Error('Selecione o arquivo do aviso prévio.');
  if(file.size>limit)throw Error('O documento deve ter até 10 MB.');
  const h=new Uint8Array(await file.slice(0,8).arrayBuffer());
  let mime,extension;
  if(h.length>=5&&[37,80,68,70,45].every((v,i)=>h[i]===v)){mime='application/pdf';extension='pdf';}
  else if(h.length>=3&&h[0]===255&&h[1]===216&&h[2]===255){mime='image/jpeg';extension='jpg';}
  else if(h.length===8&&[137,80,78,71,13,10,26,10].every((v,i)=>h[i]===v)){mime='image/png';extension='png';}
  else throw Error('Formato inválido. Escolha um PDF, JPG ou PNG.');
  if(file.type&&file.type!==mime)throw Error('O conteúdo do arquivo não corresponde ao formato informado.');
  return {mime,extension};
 }
 function filename(nome,data,extension,tipo='aviso'){
  if(!/^\d{4}-\d{2}-\d{2}$/.test(data||''))throw Error('Informe a data do desligamento programado.');
  const person=String(nome||'').trim().replace(/\s+/g,' ').toUpperCase();
  if(!person)throw Error('Informe o nome do colaborador.');
  const date=data.slice(8,10)+'.'+data.slice(5,7)+'.'+data.slice(0,4);
  return `${tipo==='rescisao'?'RESCISAO':'AVISO PREVIO'} - ${person} - ${date}.${extension}`;
 }
 async function upload(client,file,employeeId,nome,data,tipo='aviso'){
  if(!/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(employeeId||''))throw Error('Identificador do colaborador inválido.');
  const {mime,extension}=await validate(file),path=employeeId.toLowerCase()+'/'+crypto.randomUUID()+'.'+extension;
  const {error}=await client.storage.from(bucket).upload(path,file,{contentType:mime,upsert:false});
  if(error)throw Error('Não foi possível enviar o aviso prévio: '+error.message);
  const prefix=tipo==='rescisao'?'rescisao':'aviso_previo';
  return {[prefix+'_path']:path,[prefix+'_nome']:filename(nome,data,extension,tipo),[prefix+'_mime']:mime,[prefix+'_size']:file.size};
 }
 async function open(client,path){
  if(!path)throw Error('Nenhum aviso prévio foi anexado.');
  const tab=window.open('about:blank','_blank');if(tab)tab.opener=null;
  try{const {data,error}=await client.storage.from(bucket).createSignedUrl(path,60);if(error||!data?.signedUrl)throw Error('Não foi possível abrir o arquivo. Confira seu acesso.');if(tab)tab.location.href=data.signedUrl;else throw Error('Permita abrir uma nova aba para consultar o arquivo.');}
  catch(e){if(tab)tab.close();throw e;}
 }
 root.RHScheduledNoticeFiles={validate,filename,upload,open};
})(globalThis);
