'use strict';
const pontoClient=window.supabase.createClient('https://gcksbfstheavpfgcdndb.supabase.co','sb_publishable_UrTJ8_SyM3n800C4LZQWpw_5Ah8Ko98');
const P=RHPonto,$=id=>document.getElementById(id),today=RH.today();
let people=[],marks=[],consultations=[],overrides=[],absences=[],vacations=[],config={disponivel_desde:'2026-10-26',historico_desde:'2026-09-01'},summaries=[],shown=[],profile,selected=null,busy=false,period,sector='',occurrences=[],occurrenceDay=null;
const fmt=d=>d.split('-').reverse().join('/');
function node(tag,text,className){const e=document.createElement(tag);if(text!==undefined)e.textContent=text;if(className)e.className=className;return e;}
function notice(text,error=false){$('notice').textContent=text;$('notice').classList.toggle('error',error);}
async function action(fn){if(busy)return;busy=true;document.querySelectorAll('button,input,select,textarea').forEach(e=>e.disabled=true);try{await fn();}catch(e){notice(e.message||'Não foi possível concluir.',true);}finally{busy=false;document.querySelectorAll('button,input,select,textarea').forEach(e=>e.disabled=false);if(profile?.status!=='admin')$('sync').disabled=true;}}
async function fetchRows(table,columns,filter=q=>q){const rows=[];for(let offset=0;offset<100000;offset+=1000){const page=await RH.result(filter(pontoClient.from(table).select(columns)).order('id',{ascending:true}).range(offset,offset+999));rows.push(...page);if(page.length<1000)return rows;}throw Error('Consulta muito grande. Reduza o período.');}
function readPeriod(){const start=$('start').value,end=$('end').value;if(!P.valid(start)||!P.valid(end)||start<config.historico_desde||end<start||(Date.parse(end)-Date.parse(start))/86400000>62)throw Error('Escolha um período a partir de setembro/2026, com até 63 dias.');return {start,end};}
async function load(){
 period=readPeriod();const first=P.monday(period.start),last=P.sunday(period.end);
 [people,marks,consultations,overrides,absences,vacations,occurrences]=await Promise.all([
  RH.fetchAll(pontoClient,'funcionarios_epi','id,nome,cpf,admissao,data_desligamento,carga_horaria_semanal,jornada_diaria_minutos,dias_trabalho_semana,setor,unidade'),
  fetchRows('rh_ponto_marcacoes','id,funcionario_id,data_hora,entrada_saida,tipo_registro,situacao,obs',q=>q.gte('data_hora',first+' 00:00:00').lt('data_hora',P.add(last,1)+' 00:00:00')),
  fetchRows('rh_ponto_consultas','id,funcionario_id,inicio,fim,iniciado_em,consultado_em,sucesso,quantidade,erro',q=>q.lte('inicio',last).gte('fim',first)),
  RH.fetchAll(pontoClient,'rh_ponto_jornadas','*','funcionario_id'),
  fetchRows('rh_absenteismo','id,funcionario_id,data_inicio,data_fim,motivo',q=>q.lte('data_inicio',last).gte('data_fim',first)),
  fetchRows('rh_ferias_lancamentos','id,inicio,fim,status,dias_gozo,rh_ferias_periodos!inner(funcionario_id)',q=>q.lte('inicio',last).gte('fim',first)),
  fetchRows('rh_ponto_ocorrencias','*',q=>q.gte('dia',first).lte('dia',last))
 ]);
 const settings=await RH.result(pontoClient.from('rh_ponto_config').select('*'));if(settings[0])config=settings[0];
 summaries=people.map(e=>P.summarize(e,marks.filter(m=>m.funcionario_id===e.id),consultations.filter(c=>c.funcionario_id===e.id),{...period,today,availableFrom:config.disponivel_desde,historyFrom:config.historico_desde,occurrences:occurrences.filter(o=>o.funcionario_id===e.id),override:overrides.find(o=>o.funcionario_id===e.id),holiday:RHHolidays.getHoliday,absences:absences.filter(a=>a.funcionario_id===e.id),vacations:vacations.filter(v=>v.rh_ferias_periodos?.funcionario_id===e.id)}));
 $('periodLabel').textContent='Ciclo: '+fmt(period.start)+' a '+fmt(period.end)+' · Hoje: '+fmt(today)+' · Fuso: America/Sao_Paulo';
 const lastSuccess=consultations.filter(c=>c.sucesso).map(c=>c.consultado_em).sort().at(-1);
 const failures=consultations.filter(c=>!c.sucesso).length;
 $('coverage').textContent='Histórico disponível a partir de setembro/2026. Corte de faltas: '+fmt(config.disponivel_desde)+'. Dias úteis sem registro anteriores ao corte são justificados por implantação; após o corte, só há falta inferida quando o período foi consultado com sucesso. '+(lastSuccess?'Última consulta concluída no banco: '+new Date(lastSuccess).toLocaleString('pt-BR')+'.':'Nenhuma consulta deste período foi registrada. Use Sincronizar para buscar os dados.')+(failures?' Há '+failures+' tentativa(s) com falha no histórico; os dados anteriores foram preservados.':'');
 setupFilters();render();if(selected){const s=summaries.find(s=>s.employee.id===selected);if(s)drawDetail(s);}
}
function makeCards(target,rows){target.replaceChildren(...rows.map(([label,value,note])=>{const card=node('article',undefined,'card');card.append(node('span',label),node('strong',value),node('span',note));return card;}));}
function setupFilters(){
 const branch=$('branch').value;const units=[...new Set(people.map(e=>e.unidade).filter(Boolean))].sort();
 $('branch').replaceChildren(...[['','Todas as filiais'],...units.map(u=>[u,u])].map(([value,label])=>{const option=node('option',label);option.value=value;return option;}));$('branch').value=units.includes(branch)?branch:'';
 const sectors=[...new Set(people.map(e=>e.setor).filter(Boolean))].sort();if(sector&&!sectors.includes(sector))sector='';
 const labels={ARMAZEM:'Armazém',TRANSPORTE:'Transporte',COMERCIAL:'Comercial',MERCHANDISING:'Merchandising','SERVIÇOS GERAIS':'Serviços gerais',ADMINISTRATIVO:'Administrativo'};
 $('teamTabs').replaceChildren(...[['','Todas as equipes'],...sectors.map(s=>[s,labels[s]||s])].map(([value,label])=>{const button=node('button',label);button.type='button';button.setAttribute('role','tab');button.dataset.sector=value;button.setAttribute('aria-selected',String(value===sector));button.onclick=()=>{sector=value;$('teamTabs').querySelectorAll('button').forEach(b=>b.setAttribute('aria-selected',String(b.dataset.sector===sector)));render();};return button;}));
 $('start').min=config.historico_desde;$('end').min=config.historico_desde;
}
function openOccurrence(day){
 occurrenceDay=day.date;const current=occurrences.find(o=>o.funcionario_id===selected&&o.dia===day.date);
 $('occurrenceTitle').textContent='Classificar dia · '+summaries.find(s=>s.employee.id===selected).employee.nome;
 $('occurrenceDate').textContent=fmt(day.date);$('occurrenceClass').value=current?.classificacao||'justificada';$('occurrenceReason').value=current?.motivo||'';$('occurrenceCredit').checked=current?current.abonar:true;
 $('occurrenceNotice').textContent=day.historical?'Dia justificado automaticamente pelo corte de implantação. Uma decisão manual ficará registrada no histórico.':'';
 $('occurrenceHistory').textContent='Carregando histórico…';$('occurrence').showModal();
 action(async()=>{if(!current){$('occurrenceHistory').textContent='Nenhuma classificação manual registrada.';return;}
  const data=await RH.result(pontoClient.from('rh_ponto_ocorrencias_historico').select('id,antes,depois,criado_em').eq('ocorrencia_id',current.id).order('id',{ascending:false}).limit(10));
  $('occurrenceHistory').replaceChildren(...data.map(h=>{const item=node('p');item.textContent=new Date(h.criado_em).toLocaleString('pt-BR')+' · '+h.depois.classificacao+' · '+h.depois.motivo;return item;}));
 });
}
$('closeOccurrence').onclick=()=>$('occurrence').close();
$('occurrenceClass').onchange=()=>{if($('occurrenceClass').value!=='justificada')$('occurrenceCredit').checked=false;};
$('occurrenceForm').onsubmit=event=>{event.preventDefault();action(async()=>{
 try{
  if(profile.status!=='admin'||!selected||!occurrenceDay)throw Error('Administrador obrigatório.');
  const classification=$('occurrenceClass').value,reason=$('occurrenceReason').value.trim();if(reason.length<3)throw Error('Informe o motivo da classificação.');
  await RH.result(pontoClient.from('rh_ponto_ocorrencias').upsert({funcionario_id:selected,dia:occurrenceDay,classificacao:classification,motivo:reason,abonar:classification==='justificada'&&$('occurrenceCredit').checked},{onConflict:'funcionario_id,dia'}).select(),true);
  $('occurrence').close();await load();notice('Classificação salva com histórico. Os horários originais foram preservados.');
 }catch(error){$('occurrenceNotice').textContent=error.message;throw error;}
 });};
function render(){
 const search=$('search').value.normalize('NFD').replace(/[\u0300-\u036f]/g,'').toUpperCase(),kind=$('situation').value;
 shown=summaries.filter(s=>(!sector||s.employee.setor===sector)&&(!$('branch').value||s.employee.unidade===$('branch').value)&&($('includeLeft').checked||!s.employee.data_desligamento)&&(!search||(s.employee.nome+' '+(s.employee.cpf||'')).normalize('NFD').replace(/[\u0300-\u036f]/g,'').toUpperCase().includes(search))&&(kind==='all'||kind==='pending'&&s.pending>0||kind==='justified'&&s.justified>0||kind==='unjustified'&&s.unjustified>0||kind==='extra'&&s.extra>0||kind==='negative'&&s.negative>0));
 const sum=key=>shown.reduce((t,s)=>t+s[key],0);
 const hasClosed=shown.some(s=>s.closedWeeks>0),net=hasClosed?sum('extra')-sum('negative'):sum('provisional');
 $('balanceLabel').textContent=hasClosed?(net<0?'SALDO NEGATIVO ACUMULADO DA EQUIPE':net>0?'HORAS EXTRAS ACUMULADAS DA EQUIPE':'SALDO SEMANAL EQUILIBRADO'):'SALDO PARCIAL DA EQUIPE · EM APURAÇÃO';
 $('balanceValue').textContent=P.hours(net,true);$('balance').classList.toggle('debt',net<0);
 $('balanceDescription').textContent=(hasClosed?'Após compensação em semanas fechadas.':'Variação dos dias completos; ainda sujeita à compensação e ao fechamento semanal.')+' '+P.hours(sum('worked'))+' realizadas no ciclo.';
 $('balanceStats').replaceChildren(...[[shown.filter(s=>(hasClosed?s.extra-s.negative:s.provisional)>0).length,'Com saldo +'],[shown.filter(s=>(hasClosed?s.extra-s.negative:s.provisional)<0).length,'Com saldo −']].map(([value,label])=>{const box=node('div');box.append(node('strong',String(value)),node('span',label));return box;}));
 $('overviewStats').textContent=shown.length+' colaboradores · '+sum('pending')+' dias para conferir · '+P.hours(sum('worked'))+' realizadas';
 makeCards($('cards'),[['Faltas justificadas',String(sum('justified')),'Dias justificados pelo RH ou pelo corte de implantação'],['Faltas injustificadas',String(sum('unjustified')),'Dias úteis consultados sem ponto e sem justificativa cadastrada']]);
 $('employees').replaceChildren(...shown.sort((a,b)=>a.employee.nome.localeCompare(b.employee.nome)).map(s=>{
  const row=node('tr'),name=node('td');row.tabIndex=0;row.setAttribute('aria-label','Abrir espelho de '+s.employee.nome);const open=()=>{selected=s.employee.id;drawDetail(s);$('detail').showModal();};row.onclick=event=>{if(!event.target.closest('button,a,input'))open();};row.onkeydown=event=>{if(event.target===row&&['Enter',' '].includes(event.key)){event.preventDefault();open();}};name.append(node('strong',s.employee.nome),node('small',[s.employee.setor,s.employee.unidade].filter(Boolean).join(' · ')));row.append(name,node('td',P.hours(s.worked)));
  const week=s.weeks.find(w=>w.start<=today&&w.end>=today),current=node('td');current.append(node('span',week?P.hours(week.worked)+' / '+P.hours(week.expected):'—'),node('small',week?.status||'Fora do período'));row.append(current,node('td',P.hours(s.extra),'positive'),node('td',P.hours(s.negative),'negative'));
  row.append(node('td',String(s.justified)),node('td',String(s.unjustified)));
  const review=node('td');review.append(node('span',s.pending+' dia(s) para conferir'),node('small',s.unjustified+' sem justificativa · '+s.openWeeks+' semana(s) em apuração'));row.append(review);
  const button=node('button','Abrir colaborador');button.onclick=()=>{selected=s.employee.id;drawDetail(s);$('detail').showModal();};const box=node('td');box.append(button);row.append(box);return row;
 }));if(!shown.length){const row=node('tr'),cell=node('td','Nenhum colaborador neste filtro.');cell.colSpan=9;row.append(cell);$('employees').append(row);}
}
function drawDetail(s){
 $('detailTitle').textContent=s.employee.nome;$('detailSubtitle').textContent=P.hours(s.plan.weekly*60)+' por semana · '+P.hours(s.plan.daily*60)+' por dia · ciclo '+fmt(period.start)+' a '+fmt(period.end);
 makeCards($('detailCards'),[['Realizado',P.hours(s.worked),'Dentro do ciclo selecionado'],['Extra semanal',P.hours(s.extra),'Após compensação semanal'],['Negativo semanal',P.hours(s.negative),'Semanas fechadas'],['Conferir',String(s.pending),'Dias pendentes']]);
 $('scheduleBox').hidden=profile.status!=='admin';$('dailyMinutes').value=s.plan.daily;$('weeklyHours').value=s.plan.weekly/60;
 $('workDays').replaceChildren(node('legend','Dias da jornada'));['Dom','Seg','Ter','Qua','Qui','Sex','Sáb'].forEach((name,i)=>{const label=node('label'),check=node('input');check.type='checkbox';check.value=i;check.checked=s.plan.days.includes(i);label.append(check,document.createTextNode(name));$('workDays').append(label);});
 $('weeks').replaceChildren(...s.weeks.map(w=>{const row=node('tr'),label=node('td');label.append(node('span',fmt(w.start)+' a '+fmt(w.end)),node('small',w.assigned?'Saldo somado a este ciclo':'Contexto semanal; saldo não somado a este ciclo'));row.append(label,node('td',P.hours(w.worked)),node('td',P.hours(w.expected)),node('td',P.hours(w.delta,true),w.delta<0?'negative':'positive'),node('td',w.status));return row;}));
 $('days').replaceChildren(...s.days.map(d=>{const row=node('tr'),punches=node('td');d.punches.forEach(p=>punches.append(node('small',(p.entrada_saida==='E'?'Entrada ':'Saída ')+p.data_hora.slice(11,19)+' · '+p.situacao+(p.tipo_registro==='M'?' · manual':'')+(p.obs?' · '+p.obs:''))));if(!d.punches.length)punches.textContent='Sem marcações';const status=node('td');status.append(node('strong',d.status));d.warnings.forEach(w=>status.append(node('small',w)));if(d.decision)status.append(node('small',d.decision.motivo+(d.decision.abonar?' · com abono':' · sem abono')));if(d.historical)status.append(node('small','Regularização automática anterior a 26/10/2026; não representa falta apurada.'));if(profile.status==='admin'&&d.working&&!d.future&&!d.partial){const classify=node('button','Classificar dia');classify.onclick=()=>openOccurrence(d);status.append(classify);}row.append(node('td',fmt(d.date)),punches,node('td',P.hours(d.expected)),node('td',P.hours(d.worked)),node('td',P.hours(d.delta,true),d.delta<0?'negative':'positive'),status);return row;}));
 const history=consultations.filter(c=>c.funcionario_id===s.employee.id).sort((a,b)=>b.consultado_em.localeCompare(a.consultado_em));
 $('detailHistory').textContent=history[0]?'Última tentativa: '+new Date(history[0].consultado_em).toLocaleString('pt-BR')+' · '+(history[0].sucesso?history[0].quantidade+' marcações recebidas':history[0].erro):'Ainda não sincronizado neste período.';
}
$('filter').onclick=()=>action(load);$('search').oninput=render;$('situation').onchange=render;$('includeLeft').onchange=render;$('branch').onchange=render;
$('cycleMonth').onchange=()=>{if(!$('cycleMonth').value)return;const c=P.cycleMonth($('cycleMonth').value);$('start').value=[c.start,config.historico_desde].sort().at(-1);$('end').value=c.end;action(load);};
$('closeDetail').onclick=()=>$('detail').close();$('detail').addEventListener('close',()=>selected=null);
$('scheduleForm').onsubmit=e=>{e.preventDefault();action(async()=>{
 if(profile.status!=='admin'||!selected)throw Error('Administrador obrigatório.');
 const daily=Number($('dailyMinutes').value),weekly=Number($('weeklyHours').value)*60,days=[...$('workDays').querySelectorAll('input:checked')].map(e=>Number(e.value));
 if(!Number.isInteger(daily)||daily<1||daily>1440||!Number.isInteger(weekly)||weekly<1||weekly>10080||!days.length)throw Error('Informe uma jornada válida e ao menos um dia.');
 await RH.result(pontoClient.from('rh_ponto_jornadas').upsert({funcionario_id:selected,minutos_dia:daily,minutos_semana:weekly,dias:days,updated_at:new Date().toISOString()},{onConflict:'funcionario_id'}).select(),true);await load();notice('Jornada de apuração salva. Os horários originais foram preservados.');
});};
$('sync').onclick=()=>action(async()=>{
 if(profile.status!=='admin')throw Error('Administrador obrigatório para sincronizar.');
 const current=readPeriod();if(current.start!==period.start||current.end!==period.end)throw Error('Aplique o novo período antes de sincronizar.');
 if(!shown.length)throw Error('Nenhum colaborador exibido.');
 const first=P.monday(period.start),last=[P.sunday(period.end),today].sort()[0];if(first>last)throw Error('O período ainda não começou.');
 if(!confirm('Consultar o Facilita Ponto para '+shown.length+' colaboradores exibidos e armazenar as marcações de '+fmt(first)+' a '+fmt(last)+'? Os dias fora do ciclo são necessários à compensação semanal.'))return;
 const ids=shown.map(s=>s.employee.id),windows=[];for(let start=first;start<=last;){const end=[P.add(start,62),last].sort()[0];windows.push({start,end});start=P.add(end,1);}
 let success=0,failed=0;
 try{for(const window of windows){for(let i=0;i<ids.length;i+=3){$('progress').textContent='Consultando '+Math.min(i+3,ids.length)+' de '+ids.length+' colaboradores · '+fmt(window.start)+' a '+fmt(window.end)+'…';const {data,error}=await pontoClient.functions.invoke('ponto-sync',{body:{inicio:window.start,fim:window.end,funcionarios:ids.slice(i,i+3)}});if(error||data?.error)throw Error(data?.error||'Não foi possível chamar a integração. Entre novamente ou confira o processador.');for(const r of data.resultados){if(r.sucesso)success++;else failed++;}}}}
 finally{await load();$('progress').textContent=success+' consulta(s) concluída(s) · '+failed+' com falha. Dados anteriores de consultas com falha foram preservados.';}
 notice('Sincronização concluída. Confira dias pendentes e as semanas em apuração.');
});
action(async()=>{profile=await RH.profile(pontoClient);if(!['admin','aprovado'].includes(profile.status))throw Error('Acesso restrito a usuários aprovados.');const c=P.cycle(today);$('start').value=c.start;$('end').value=c.end;$('cycleMonth').value=c.end.slice(0,7);await load();$('app').hidden=false;if(profile.status!=='admin')$('sync').hidden=true;notice('Dados carregados do banco. As credenciais de integração ficam somente no servidor.');});
