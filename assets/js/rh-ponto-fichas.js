(function(root,doc){
 'use strict';
 const F=root.RHPontoFichasCore,$=id=>doc.getElementById(id),table='rh_ponto_fichas_destinatarios';
 let client,employees=[],companies=[],recipients=[],working=false;
 const norm=v=>String(v||'').normalize('NFD').replace(/[\u0300-\u036f]/g,'').toUpperCase();
 function node(tag,text){const e=doc.createElement(tag);if(text!==undefined)e.textContent=text;return e;}
 function message(text,error=false){$('sheetNotice').textContent=text;$('sheetNotice').classList.toggle('error',error);}
 function company(employee){return F.resolveCompany(employee,companies);}
 function selectedCompany(){return $('sheetCompany').value;}
 function matchesCompany(employee){try{return !selectedCompany()||String(company(employee).id)===selectedCompany();}catch(_){return !selectedCompany();}}
 function selectedRows(){
  const month=$('sheetMonth').value;F.monthDays(month);
  return recipients.map(r=>({...r,employee:employees.find(e=>e.id===r.funcionario_id)}))
   .filter(r=>r.employee&&F.eligible(r.employee,month)&&matchesCompany(r.employee))
   .sort((a,b)=>a.employee.nome.localeCompare(b.employee.nome,'pt-BR'));
 }
 function refresh(){
  const query=norm($('sheetSearch').value),saved=new Set(recipients.map(r=>r.funcionario_id));
  const available=employees.filter(e=>!e.data_desligamento&&!saved.has(e.id)&&matchesCompany(e)&&
   (!query||norm(e.nome).includes(query)||norm(e.cpf).includes(query)||String(e.cpf||'').replace(/\D/g,'').includes(query.replace(/\D/g,'')||'NOT_A_CPF')))
   .sort((a,b)=>a.nome.localeCompare(b.nome,'pt-BR'));
  const placeholder=node('option',available.length?'Selecione um colaborador':'Nenhum colaborador disponível');placeholder.value='';
  $('sheetEmployee').replaceChildren(placeholder,...available.map(e=>{const o=node('option',e.nome+' · '+(e.funcao||'Sem função'));o.value=e.id;return o;}));
  const list=selectedRows();$('sheetCount').textContent=list.length+' ficha(s) para o mês e empresa selecionados';
  const visible=recipients.map(r=>({...r,employee:employees.find(e=>e.id===r.funcionario_id)})).filter(r=>r.employee&&matchesCompany(r.employee));
  $('sheetRecipients').replaceChildren(...visible.sort((a,b)=>a.employee.nome.localeCompare(b.employee.nome,'pt-BR')).map(r=>{
   const e=r.employee,row=node('div');row.className='sheet-recipient';
   const info=node('div');info.className='sheet-person';info.append(node('strong',e.nome),node('small',[e.funcao,F.cpf(e.cpf)].filter(Boolean).join(' · ')));
   let label;try{const c=company(e);label=c.nome+' · '+F.cnpj(c.cnpj);}catch(error){label=error.message;}
   info.append(node('small',label));if(!F.eligible(e,$('sheetMonth').value))info.append(node('small','Fora do vínculo neste mês; não será gerada ficha.'));
   const cityLabel=node('label','Cidade de trabalho (opcional)'),city=node('input');city.type='text';city.maxLength=120;city.value=r.cidade_trabalho||'';city.setAttribute('aria-label','Cidade de trabalho de '+e.nome);cityLabel.append(city);
   const save=node('button','Salvar cidade');save.type='button';save.onclick=()=>run(async()=>{
    const rows=await RH.result(client.from(table).upsert({funcionario_id:e.id,cidade_trabalho:city.value.trim()},{onConflict:'funcionario_id'}).select(),true);
    recipients=recipients.map(x=>x.funcionario_id===e.id?rows[0]:x);refresh();message('Cidade salva.');
   });
   const remove=node('button','Remover da lista');remove.type='button';remove.className='secondary';remove.onclick=()=>run(async()=>{
    await RH.result(client.from(table).delete().eq('funcionario_id',e.id).select(),true);
    recipients=recipients.filter(x=>x.funcionario_id!==e.id);refresh();message('Colaborador removido apenas da lista de fichas.');
   });
   row.append(info,cityLabel,save,remove);return row;
  }));
  if(!visible.length)$('sheetRecipients').append(node('p','Nenhum colaborador salvo para esta empresa. Adicione os colaboradores acima.'));
  $('sheetGenerate').disabled=working||!list.length;
 }
 async function run(fn){
  if(working)return;working=true;
  $('manualSheetPanel').querySelectorAll('button:not(#closeManualSheets),input,select').forEach(e=>e.disabled=true);
  try{await fn();}catch(error){message(error.message||'Não foi possível concluir.',true);}
  finally{working=false;$('manualSheetPanel').querySelectorAll('button:not(#closeManualSheets),input,select').forEach(e=>e.disabled=false);try{refresh();}catch(error){message(error.message,true);$('sheetGenerate').disabled=true;}}
 }
 function download(sheets,label){
  const month=$('sheetMonth').value,bytes=F.pdf({month,sheets,holiday:root.RHHolidays.getHoliday});
  const url=URL.createObjectURL(new Blob([bytes],{type:'application/pdf'})),a=node('a');
  a.href=url;a.download='Fichas_Ponto_'+label+'_'+month+'.pdf';doc.body.append(a);a.click();a.remove();setTimeout(()=>URL.revokeObjectURL(url),60000);
  message(sheets.length+' ficha(s) gerada(s). Os horários ficaram em branco para preenchimento manual.');
 }
 async function loadData(){
  [employees,companies,recipients]=await Promise.all([
   RH.fetchAll(client,'funcionarios_epi','id,nome,cpf,funcao,empresa_id,local_registro,admissao,data_desligamento','nome'),
   RH.fetchAll(client,'empresas','id,nome,cnpj','id'),
   RH.fetchAll(client,table,'funcionario_id,cidade_trabalho','funcionario_id')
  ]);
  const old=selectedCompany(),all=node('option','Todas as empresas');all.value='';
  $('sheetCompany').replaceChildren(all,...companies.map(c=>{const o=node('option',c.nome+' · '+F.cnpj(c.cnpj));o.value=String(c.id);return o;}));
  $('sheetCompany').value=companies.some(c=>String(c.id)===old)?old:'';refresh();
 }
 async function init({supabase,profile}){
  if(profile?.status!=='admin')return;client=supabase;
  $('openManualSheets').hidden=false;
  $('openManualSheets').onclick=()=>{if(!$('manualSheetPanel').open)$('manualSheetPanel').showModal();};
  $('closeManualSheets').onclick=()=>$('manualSheetPanel').close();
  $('sheetMonth').value=RH.today().slice(0,7);
  $('sheetSearch').oninput=refresh;$('sheetCompany').onchange=refresh;
  $('sheetMonth').onchange=()=>{try{refresh();message('');}catch(e){message(e.message,true);$('sheetGenerate').disabled=true;}};
  $('sheetReload').onclick=()=>run(async()=>{await loadData();message('Lista atualizada com os dados do cadastro.');});
  $('sheetAdd').onclick=()=>run(async()=>{
   const id=$('sheetEmployee').value,e=employees.find(x=>x.id===id);if(!e)throw Error('Selecione um colaborador para adicionar.');company(e);
   const rows=await RH.result(client.from(table).upsert({funcionario_id:id,cidade_trabalho:''},{onConflict:'funcionario_id',ignoreDuplicates:true}).select(),true);
   if(rows.length)recipients.push(rows[0]);else await loadData();refresh();message('Colaborador salvo para as próximas emissões.');
  });
  $('sheetGenerate').onclick=()=>run(async()=>{
   await loadData();const rows=selectedRows();if(!rows.length)throw Error('Não há colaboradores salvos com vínculo neste mês e empresa.');
   download(rows.map(r=>({company:company(r.employee),employee:r.employee,city:r.cidade_trabalho})),'Colaboradores');
  });
  $('sheetBlank').onclick=()=>run(async()=>{
   await loadData();const list=companies.filter(c=>!selectedCompany()||String(c.id)===selectedCompany());
   download(list.map(company=>({company})),'Modelos_em_Branco');
  });
  await run(async()=>{await loadData();message('Adicione quem recebe ficha manual. A lista fica salva para os próximos meses.');});
 }
 root.RHPontoFichas={init};
})(window,document);
