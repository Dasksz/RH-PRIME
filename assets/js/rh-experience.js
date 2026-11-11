(function(global){
 'use strict';
 const h=React.createElement,{useState}=React;
 function matchesArea(profile,employee){
  return (profile.access_scopes||[]).some(scope=>
   (scope.unidade==null||scope.unidade===employee.unidade)&&
   (scope.setor==null||scope.setor===employee.setor));
 }
 function RHExperience({client,employees,profiles,onRefresh}){
  const [query,setQuery]=useState(''),[employeeId,setEmployeeId]=useState(''),[managerId,setManagerId]=useState(''),[saving,setSaving]=useState(false),[error,setError]=useState(''),[message,setMessage]=useState('');
  const selected=employees.find(e=>e.id===employeeId);
  const managers=profiles.filter(p=>['aprovado','admin'].includes(p.status)&&['supervisor','coordenador','gerente','administrador'].includes(p.role));
  const active=employees.filter(e=>!e.data_desligamento);
  const filtered=active.filter(e=>(e.nome+' '+e.unidade+' '+e.setor).toLowerCase().includes(query.toLowerCase()));
  function choose(id){const e=employees.find(e=>e.id===id);setEmployeeId(id);setManagerId(e?.manager_profile_id||'');setMessage('');setError('');}
  async function save(){if(!selected||saving)return;setSaving(true);setError('');setMessage('');try{
   let request=client.from('funcionarios_epi').update({manager_profile_id:managerId||null}).eq('id',selected.id);
   request=selected.manager_profile_id?request.eq('manager_profile_id',selected.manager_profile_id):request.is('manager_profile_id',null);
   await RH.result(request.select(),true);setMessage(managerId?'Vínculo individual salvo.':'Vínculo individual removido.');await onRefresh();
  }catch(e){setError(e.message);}finally{setSaving(false);}}
  const manager=managers.find(p=>p.id===managerId);
  const receivesWhatsApp=p=>p.experience_notifications&&/^55[1-9][0-9][0-9]{8,9}$/.test(p.whatsapp||'');
  const subscriptions=profiles.filter(p=>p.status==='aprovado'&&p.access_mode==='areas'&&receivesWhatsApp(p));
  const areaRecipients=employee=>subscriptions.filter(p=>matchesArea(p,employee));
  function hasRecipient(employee){
   return areaRecipients(employee).length>0||managers.some(p=>p.id===employee.manager_profile_id&&
    receivesWhatsApp(p)&&(p.status==='admin'||p.access_mode==='todos'||(p.access_mode==='areas'&&matchesArea(p,employee))));
  }
  return h('div',{className:'rp-editor'},h('h3',null,'Experiência e avisos por área'),
   h('p',null,'Configure as filiais e os setores no perfil e marque a opção de receber avisos por WhatsApp. O RH PRIME usa essas áreas para identificar os destinatários automaticamente.'),
   h('p',null,'Os avisos de experiência são verificados às 08h, horário de Brasília, aos 38 e 83 dias após a admissão. Cada destinatário recebe um aviso por período.'),
   h('h4',null,'Vínculo individual adicional'),
   error&&h('p',{role:'alert',className:'rp-error'},error),message&&h('p',{role:'status',className:'rp-success'},message),
   h('label',{className:'rp-field'},'Buscar colaborador',h('input',{value:query,onChange:e=>setQuery(e.target.value),placeholder:'Nome, filial ou setor'})),
   h('div',{className:'rp-grid'},h('label',{className:'rp-field'},'Colaborador',h('select',{'aria-label':'Colaborador',value:employeeId,onChange:e=>choose(e.target.value)},h('option',{value:''},'Selecionar colaborador'),filtered.map(e=>h('option',{key:e.id,value:e.id},e.nome+' — '+(e.unidade||'')+' / '+(e.setor||''))))),
    h('label',{className:'rp-field'},'Gestor individual',h('select',{'aria-label':'Gestor individual',value:managerId,onChange:e=>setManagerId(e.target.value),disabled:!selected},h('option',{value:''},'Sem vínculo individual'),managers.map(p=>h('option',{key:p.id,value:p.id},(p.name||p.email)+' — '+p.role))))),
   selected&&h('p',null,'Destinatários pela área: '+(areaRecipients(selected).map(p=>p.name||p.email).join(', ')||'Nenhum perfil com avisos ativos.')),
   manager&&!receivesWhatsApp(manager)&&h('p',null,'Cadastre o WhatsApp e ative os avisos no perfil do gestor individual.'),
   h('button',{onClick:save,disabled:!selected||saving},saving?'Salvando...':'Salvar vínculo individual'),
   h('p',null,active.filter(e=>!hasRecipient(e)).length+' colaborador(es) ativo(s) sem destinatário de avisos de experiência.'));
 }
 global.RHExperience=RHExperience;
})(window);
