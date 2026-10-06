const assert=require('node:assert/strict');
require('../rh-absence-files.js');
const files=globalThis.RHAbsenceFiles;
const employee='11111111-1111-4111-8111-111111111111';
(async()=>{
 const pdf=new File(['%PDF-1.7\nFixture'], 'teste.pdf',{type:'application/pdf'});
 const jpg=new File([Uint8Array.from([255,216,255,224,0])],'teste.jpg',{type:'image/jpeg'});
 const png=new File([Uint8Array.from([137,80,78,71,13,10,26,10])],'teste.png');
 const person='Julio Espirito Santo Nascimento Neto';
 const atestado=files.documentInfo({nome:person,inicio:'2026-09-10',fim:'2026-09-10'});
 assert.equal(atestado.atestado_nome,'ATESTADO - 10.09 1 DIA - JULIO ESPIRITO SANTO NASCIMENTO NETO.pdf');
 assert.equal(files.documentInfo({nome:person,inicio:'2026-12-31',fim:'2027-01-02',mime:'image/jpeg'}).atestado_nome,'ATESTADO - 31.12 3 DIAS - JULIO ESPIRITO SANTO NASCIMENTO NETO.jpg');
 const attendance=files.documentInfo({nome:person,inicio:'2026-08-21',fim:'2026-08-21',tipo:'comparecimento',mime:'image/png'});
 assert.equal(attendance.atestado_nome,'COMPARECIMENTO 21.08 - JULIO ESPIRITO SANTO NASCIMENTO NETO.png');assert.equal(attendance.atestado_dias,null);
 assert.equal(files.documentInfo({nome:person,inicio:'2026-09-10',fim:'2026-09-11',data:'2025-12-31',dias:1}).atestado_data,'2025-12-31');
 assert.throws(()=>files.documentInfo({nome:person,inicio:'2026-02-30',fim:'2026-03-01'}),/datas/);
 assert.throws(()=>files.documentInfo({nome:person,inicio:'2026-09-10',fim:'2026-09-10',dias:0}),/dias/);
 assert.equal((await files.validate(pdf)).mime,'application/pdf');
 assert.equal((await files.validate(jpg)).mime,'image/jpeg');
 assert.equal((await files.validate(png)).mime,'image/png');
 await assert.rejects(files.validate(new File(['<script>'],'falso.pdf',{type:'application/pdf'})),/Formato inválido/);
 await assert.rejects(files.validate(new File(['%PDF-1.7'],'falso.png',{type:'image/png'})),/não corresponde/);
 await assert.rejects(files.validate(new File([],'vazio.pdf')),/conteúdo/);
 await assert.rejects(files.validate({size:10485761}),/10 MB/);
 const calls=[];
 const client={storage:{from(bucket){assert.equal(bucket,'rh-atestados');return {
  upload:async(...args)=>{calls.push(args);return {error:null}},
  remove:async(paths)=>{calls.push(paths);return {error:null}},
  createSignedUrl:async(path,seconds)=>{assert.equal(seconds,60);return {data:{signedUrl:'https://example.invalid/private'},error:null}}
 }}}};
 const first=await files.upload(client,pdf,employee),second=await files.upload(client,pdf,employee);
 assert.notEqual(first.atestado_path,second.atestado_path);
 assert(first.atestado_path.startsWith(employee+'/'));
 assert.equal(calls[0][2].upsert,false);
 assert.equal(first.atestado_size,pdf.size);
 await assert.rejects(files.upload(client,pdf,'invalid'),/colaborador/);
 await assert.rejects(files.upload({storage:{from:()=>({upload:async()=>({error:{message:'denied'}})})}},pdf,employee),/denied/);
 const tab={opener:{},location:{},closed:false,close(){this.closed=true}};
 globalThis.window={open:()=>tab};
 await files.open(client,first);assert.equal(tab.opener,null);assert.equal(tab.location.href,'https://example.invalid/private');
 await assert.rejects(files.open({storage:{from:()=>({createSignedUrl:async()=>({error:{message:'denied'}})})}},first),/acesso/);
 assert.equal(tab.closed,true);
 await files.remove(client,first.atestado_path);assert.deepEqual(calls.at(-1),[first.atestado_path]);
 console.log('Attachment validation, upload errors, unique paths, private URLs and cleanup passed.');
})().catch(e=>{console.error(e);process.exitCode=1});
