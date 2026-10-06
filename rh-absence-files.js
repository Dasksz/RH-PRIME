(function(root){
 'use strict';
 const bucket='rh-atestados',limit=10*1024*1024;
 const empty={atestado_path:null,atestado_nome:null,atestado_mime:null,atestado_size:null,atestado_tipo:null,atestado_data:null,atestado_dias:null};
 function documentInfo({nome,inicio,fim,tipo='atestado',data,dias,mime='application/pdf'}){
  const validDate=s=>/^\d{4}-\d{2}-\d{2}$/.test(s||'')&&Number.isFinite(Date.parse(s+'T00:00:00Z'))&&new Date(s+'T00:00:00Z').toISOString().slice(0,10)===s;
  data=data||inicio;
  if(!validDate(data)||!validDate(inicio)||!validDate(fim)||fim<inicio)throw Error('Confira as datas do documento e do afastamento.');
  if(!['atestado','comparecimento'].includes(tipo))throw Error('Tipo de documento inválido.');
  const person=String(nome||'').trim().replace(/\s+/g,' ').toUpperCase().slice(0,220);
  if(!person)throw Error('Nome do colaborador não informado.');
  const extension={'application/pdf':'.pdf','image/jpeg':'.jpg','image/png':'.png'}[mime];
  if(!extension)throw Error('Formato de documento inválido.');
  const count=tipo==='comparecimento'?null:(dias==null||dias===''?Math.round((Date.parse(fim+'T00:00:00Z')-Date.parse(inicio+'T00:00:00Z'))/86400000)+1:Number(dias));
  if(tipo==='atestado'&&(!Number.isInteger(count)||count<1||count>3660))throw Error('Informe a quantidade de dias do atestado.');
  const date=data.slice(8,10)+'.'+data.slice(5,7);
  const filename=(tipo==='comparecimento'?'COMPARECIMENTO '+date:'ATESTADO - '+date+' '+count+(count===1?' DIA':' DIAS'))+' - '+person+extension;
  return {atestado_nome:filename,atestado_tipo:tipo,atestado_data:data,atestado_dias:count};
 }
 async function validate(file){
  if(!file||file.size<1)throw Error('Selecione um arquivo com conteúdo.');
  if(file.size>limit)throw Error('O atestado deve ter até 10 MB.');
  const h=new Uint8Array(await file.slice(0,8).arrayBuffer());
  let mime,extension;
  if(h.length>=5&&[37,80,68,70,45].every((v,i)=>h[i]===v)){mime='application/pdf';extension='pdf';}
  else if(h.length>=3&&h[0]===255&&h[1]===216&&h[2]===255){mime='image/jpeg';extension='jpg';}
  else if(h.length===8&&[137,80,78,71,13,10,26,10].every((v,i)=>h[i]===v)){mime='image/png';extension='png';}
  else throw Error('Formato inválido. Escolha um PDF, JPG ou PNG.');
  if(file.type&&file.type!==mime)throw Error('O conteúdo do arquivo não corresponde ao formato informado.');
  return {mime,extension};
 }
 async function upload(client,file,employee){
  if(!/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(employee||''))throw Error('Selecione um colaborador cadastrado.');
  const {mime,extension}=await validate(file);
  const path=employee.toLowerCase()+'/'+crypto.randomUUID()+'.'+extension;
  const {error}=await client.storage.from(bucket).upload(path,file,{contentType:mime,upsert:false});
  if(error)throw Error('Não foi possível enviar o atestado: '+error.message);
  return {atestado_path:path,atestado_nome:file.name.slice(0,255),atestado_mime:mime,atestado_size:file.size};
 }
 async function remove(client,path){
  if(!path)return;
  const {error}=await client.storage.from(bucket).remove([path]);
  if(error)throw Error('Não foi possível limpar o arquivo: '+error.message);
 }
 async function open(client,item){
  if(!item?.atestado_path)throw Error('Este registro não possui atestado anexado.');
  const tab=window.open('about:blank','_blank');
  if(tab)tab.opener=null;
  try{
   const {data,error}=await client.storage.from(bucket).createSignedUrl(item.atestado_path,60);
   if(error||!data?.signedUrl)throw Error('Não foi possível abrir o atestado. Confira seu acesso ou tente novamente.');
   if(tab)tab.location.href=data.signedUrl;
   else throw Error('Permita abrir uma nova aba para consultar o atestado.');
  }catch(e){if(tab)tab.close();throw e;}
 }
 root.RHAbsenceFiles={validate,upload,remove,open,documentInfo,empty};
})(globalThis);
