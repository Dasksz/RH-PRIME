/* Confirmação assíncrona: cadastro e sincronização não dependem da escolha da pasta. */
(function(root){
 'use strict';
 function start(client){
  const deferred=new Set();let running=false,busy=false,current=null;
  const style=document.createElement('style');style.textContent='.rh-folder-dialog{width:min(620px,94vw);max-height:85vh;overflow:auto;padding:24px;border:1px solid #bccdd4;border-radius:14px;background:var(--rh-panel,#fff);color:var(--rh-text,#183440);font:15px system-ui}.rh-folder-dialog::backdrop{background:#0008}.rh-folder-dialog button{padding:10px 14px;border:0;border-radius:8px;background:#0d6c60;color:white;cursor:pointer;margin:8px 8px 0 0;font:inherit}.rh-folder-dialog label{display:block;padding:12px;border:1px solid #bccdd4;border-radius:8px;margin:12px 0}.rh-folder-dialog input{width:auto;margin-right:8px}.rh-folder-dialog a{color:inherit;text-decoration:underline}.rh-folder-banner{padding:14px;margin:16px;background:var(--rh-panel,#e2f2ee);color:var(--rh-text,#183440);border:1px solid #bccdd4;border-radius:10px}.rh-folder-banner button{margin-left:12px;padding:8px;cursor:pointer}.rh-folder-dialog small{display:block;margin:6px 0}';document.head.append(style);
  const banner=document.createElement('div');banner.className='rh-folder-banner';banner.hidden=true;banner.setAttribute('role','status');
  const count=document.createElement('span'),review=document.createElement('button');review.type='button';review.textContent='Conferir pastas';banner.append(count,review);document.body.prepend(banner);
  const dialog=document.createElement('dialog');dialog.className='rh-folder-dialog';dialog.setAttribute('aria-labelledby','rh-folder-title');
  const title=document.createElement('h2');title.id='rh-folder-title';title.textContent='Encontramos uma pasta existente';
  const employee=document.createElement('p'),intro=document.createElement('p');intro.textContent='Confira a pasta antes de escolher. Usar a existente preserva seu nome e arquivos; se estiver em ex-funcionários, ela será movida para ativos. Criar outra mantém a antiga e gera uma pasta com o modelo.';
  const candidates=document.createElement('div'),message=document.createElement('p');message.setAttribute('role','status');
  const use=document.createElement('button'),create=document.createElement('button'),later=document.createElement('button');
  use.textContent='Usar pasta selecionada';create.textContent='Criar uma nova pasta';later.textContent='Decidir depois';
  [use,create,later].forEach(b=>b.type='button');dialog.append(title,employee,intro,candidates,message,use,create,later);document.body.append(dialog);
  const key=j=>j.id+':'+j.revision;
  function open(job){
   current=job;employee.textContent=job.folder_employee?.nome||'Colaborador';candidates.replaceChildren();message.textContent='';
   (job.folder_candidates||[]).forEach((f,i)=>{
    const label=document.createElement('label'),radio=document.createElement('input');radio.type='radio';radio.name='rh-folder-candidate';radio.value=f.id;radio.checked=i===0;
    const name=document.createTextNode(f.name),detail=document.createElement('small');detail.textContent=f.location+' · ID: '+f.id;
    const link=document.createElement('a');link.href='https://drive.google.com/drive/folders/'+encodeURIComponent(f.id);link.target='_blank';link.rel='noopener noreferrer';link.textContent='Abrir e conferir no Drive';
    label.append(radio,name,detail,link);candidates.append(label);
   });dialog.showModal();
  }
  async function choose(folder){
   if(busy||!current)return;busy=true;[use,create,later].forEach(b=>b.disabled=true);message.textContent='Registrando escolha…';
   try{
    await RH.result(client.rpc('rh_choose_employee_folder',{p_id:current.id,p_revision:current.revision,p_folder:folder}));
    dialog.close();current=null;count.textContent='Escolha registrada. Aguarde o processamento da pasta.';
   }catch(e){message.textContent=e.message||String(e);}
   finally{busy=false;[use,create,later].forEach(b=>b.disabled=false);await poll();}
  }
  use.onclick=()=>{const selected=candidates.querySelector('input:checked');if(selected)choose(selected.value);else message.textContent='Selecione uma pasta.';};
  create.onclick=()=>choose('new');
  function postpone(){if(busy)return;deferred.add(key(current));dialog.close();current=null;}
  later.onclick=postpone;dialog.addEventListener('cancel',event=>{event.preventDefault();postpone();});
  review.onclick=()=>{deferred.clear();poll();};
  async function poll(){
   if(running||busy||dialog.open||document.hidden)return;running=true;
   try{
    const profile=await RH.profile(client);if(profile.status!=='admin'){banner.hidden=true;return;}
    const jobs=await RH.result(client.from('rh_drive_jobs').select('id,revision,folder_candidates,folder_employee').eq('status','awaiting_choice').order('updated_at',{ascending:true}));
    banner.hidden=!jobs.length;count.textContent=jobs.length+' cadastro(s) aguardando sua escolha da pasta.';
    const next=jobs.find(j=>!deferred.has(key(j)));if(next)open(next);
   }catch(e){if(banner.hidden)return;count.textContent='Não foi possível consultar as confirmações. Tente novamente em Automações.';}
   finally{running=false;}
  }
  poll();const timer=setInterval(poll,15000);root.addEventListener('pagehide',()=>clearInterval(timer),{once:true});
 }
 root.RHFolderChoice={start};
})(window);
