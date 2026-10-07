(function(global){
 'use strict';
 const h=React.createElement,{useState}=React;
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
   await RH.result(request.select(),true);setMessage('Gestor vinculado. Os avisos serão enviados somente a ele.');await onRefresh();
  }catch(e){setError(e.message);}finally{setSaving(false);}}
  const manager=managers.find(p=>p.id===managerId);
  return h('div',{className:'rp-editor'},h('h3',null,'Experiência — gestor do colaborador'),
   h('p',null,'Aviso diário às 08h, horário de Brasília, a partir de 80 dias após a admissão. Prazo padrão: 90 dias. Um aviso por contrato, somente ao gestor vinculado. Colaboradores desligados não recebem avisos.'),
   error&&h('p',{role:'alert',className:'rp-error'},error),message&&h('p',{role:'status',className:'rp-success'},message),
   h('label',{className:'rp-field'},'Buscar colaborador',h('input',{value:query,onChange:e=>setQuery(e.target.value),placeholder:'Nome, filial ou setor'})),
   h('div',{className:'rp-grid'},h('label',{className:'rp-field'},'Colaborador',h('select',{'aria-label':'Colaborador',value:employeeId,onChange:e=>choose(e.target.value)},h('option',{value:''},'Selecionar colaborador'),filtered.map(e=>h('option',{key:e.id,value:e.id},e.nome+' — '+(e.unidade||'')+' / '+(e.setor||''))))),
    h('label',{className:'rp-field'},'Gestor responsável',h('select',{'aria-label':'Gestor responsável',value:managerId,onChange:e=>setManagerId(e.target.value),disabled:!selected},h('option',{value:''},'Sem gestor vinculado'),managers.map(p=>h('option',{key:p.id,value:p.id},(p.name||p.email)+' — '+p.role))))),
   selected&&h('p',null,'Admissão: '+(selected.admissao||'Não informada')+'. O gestor precisa ter acesso à filial/setor deste colaborador.'),
   manager&&h('p',null,manager.whatsapp&&manager.experience_notifications?'WhatsApp do gestor: +'+manager.whatsapp:'Configure o WhatsApp e ative “Receber avisos de experiência” no perfil deste gestor.'),
   h('button',{onClick:save,disabled:!selected||saving},saving?'Salvando...':'Salvar gestor'),
   h('p',null,active.filter(e=>!e.manager_profile_id).length+' colaborador(es) ativo(s) sem gestor vinculado. Não haverá envio para esses colaboradores.'));
 }
 global.RHExperience=RHExperience;
})(window);
