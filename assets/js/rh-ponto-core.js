(function(root){
 'use strict';
 const iso=d=>d.toISOString().slice(0,10),date=s=>new Date(s+'T12:00:00Z');
 const valid=s=>typeof s==='string'&&/^\d{4}-\d{2}-\d{2}$/.test(s)&&!Number.isNaN(+date(s))&&iso(date(s))===s;
 const add=(s,n)=>{const d=date(s);d.setUTCDate(d.getUTCDate()+n);return iso(d);};
 const weekday=s=>date(s).getUTCDay();
 const monday=s=>add(s,-((weekday(s)+6)%7));
 const sunday=s=>add(monday(s),6);
 function cycle(today){const d=date(today);if(d.getUTCDate()>25)d.setUTCMonth(d.getUTCMonth()+1,1);const end=iso(new Date(Date.UTC(d.getUTCFullYear(),d.getUTCMonth(),25,12)));return {start:iso(new Date(Date.UTC(d.getUTCFullYear(),d.getUTCMonth()-1,26,12))),end};}
 function cycleMonth(value){const [y,m]=value.split('-').map(Number);return {start:iso(new Date(Date.UTC(y,m-2,26,12))),end:iso(new Date(Date.UTC(y,m-1,25,12)))};}
 function hours(seconds,signed=false){if(seconds===null||seconds===undefined)return '—';const n=Math.round(Math.abs(seconds)/60);return (seconds<0?'−':signed&&seconds>0?'+':'')+Math.floor(n/60)+'h'+String(n%60).padStart(2,'0');}
 function schedule(employee,override){
  const count=Number(employee.dias_trabalho_semana)||5;
  return {daily:Number(override?.minutos_dia)||Number(employee.jornada_diaria_minutos)||528,
   weekly:Number(override?.minutos_semana)||(Number(employee.carga_horaria_semanal)||44)*60,
   days:[...new Set(override?.dias||(count===5?[1,2,3,4,5]:count===6?[1,2,3,4,5,6]:[1,2,3,4,5,6,0].slice(0,count)))]};
 }
 function admission(value){if(/^\d{2}\/\d{2}\/\d{4}$/.test(value||''))return value.split('/').reverse().join('-');return valid(value)?value:null;}
 const sec=t=>{const [h,m,s]=t.split(':').map(Number);return h*3600+m*60+s;};
 const reviewTolerance=30*60;
 function dayAlerts(day){
  if(day.future||day.partial||!day.employed)return [];
  const alerts=[],sequence=/Entrada sem saída|Saída sem entrada|Entradas consecutivas|Marcação duplicada/;
  const inconsistent=day.warnings.some(w=>sequence.test(w))||(day.punches.filter(p=>['Aprovado (Auto)','Aprovado Manualmente'].includes(p.situacao)).length%2!==0);
  if(inconsistent)alerts.push({type:'missing',message:'Marcações incompletas ou inconsistentes · '+day.punches.length+' registro(s)'});
  const otherWarnings=day.warnings.filter(w=>!sequence.test(w));
  if(otherWarnings.length)alerts.push({type:'data',message:otherWarnings.join('; ')});
  if(day.working&&!day.covered)alerts.push({type:'data',message:'Dia sem consulta confirmada; conferir os dados antes de apurar'});
  if(day.absenceClass==='injustificada')alerts.push({type:'no_record',message:'Dia sem marcações e sem justificativa'});
  if(Number.isFinite(day.delta)&&day.worked>0&&day.delta<=-reviewTolerance)alerts.push({type:'below',message:'Jornada abaixo do esperado · '+hours(day.delta,true)});
  if(Number.isFinite(day.delta)&&day.delta>=reviewTolerance)alerts.push({type:'above',message:day.expected?'Jornada acima do esperado · '+hours(day.delta,true):'Trabalho em dia sem jornada prevista · '+hours(day.delta,true)});
  return alerts;
 }
 function summarize(employee,marks,consultations,{start,end,today,availableFrom,override,holiday=()=>null,absences=[],vacations=[],occurrences=[],historyFrom='2026-09-01'}){
  const plan=schedule(employee,override),byDate=new Map(),days=[],weeks=[];
  marks.forEach(p=>{const key=p.data_hora.slice(0,10);if(!byDate.has(key))byDate.set(key,[]);byDate.get(key).push(p);});
  const hired=admission(employee.admissao),left=employee.data_desligamento;
  const observed=marks.map(p=>p.data_hora.slice(0,10)).sort()[0];

  for(let day=monday(start);day<=sunday(end);day=add(day,1)){
   const punches=(byDate.get(day)||[]).slice().sort((a,b)=>a.data_hora.localeCompare(b.data_hora)||a.entrada_saida.localeCompare(b.entrada_saida));
   const all=(consultations||[]).filter(c=>c.inicio<=day&&c.fim>=day),covered=all.some(c=>c.sucesso);
   const employed=(!hired||day>=hired)&&(!left||day<=left),h=holiday(day),isHoliday=h&&h.scope!=='facultativo';
   const vacation=vacations.find(v=>v.inicio<=day&&v.fim>=day&&v.dias_gozo>0&&['programado','concluido'].includes(v.status));
   const justification=absences.find(a=>a.data_inicio<=day&&a.data_fim>=day);
   const working=employed&&plan.days.includes(weekday(day))&&!isHoliday&&!vacation;
   const expected=working?plan.daily*60:0;
   const approved=punches.filter(p=>['Aprovado (Auto)','Aprovado Manualmente'].includes(p.situacao));
   const warnings=[];let worked=0,entry=null;
   if(punches.some(p=>!['Aprovado (Auto)','Aprovado Manualmente'].includes(p.situacao)))warnings.push('Marcações pendentes, rejeitadas ou de abono: conferir');
   const seen=new Set();approved.forEach(p=>{
    const k=p.data_hora+'|'+p.entrada_saida;if(seen.has(k)){warnings.push('Marcação duplicada');return;}seen.add(k);
    if(p.entrada_saida==='E'){if(entry!==null)warnings.push('Entradas consecutivas');entry=sec(p.data_hora.slice(11,19));}
    else{const out=sec(p.data_hora.slice(11,19));if(entry===null||out<=entry)warnings.push('Saída sem entrada válida');else worked+=out-entry;entry=null;}
   });
   if(entry!==null)warnings.push('Entrada sem saída; jornada incompleta');
   const decision=occurrences.find(o=>o.dia===day);
   if(justification&&!decision)warnings.push('Há lançamento no absenteísmo: '+(justification.motivo||'conferir justificativa'));
   const future=day>today,partial=day===today;
   const historical=working&&!future&&!partial&&day>=historyFrom&&day<availableFrom&&!punches.length&&!decision;
   const known=historical||!!decision||covered&&(day>=availableFrom||punches.length>0);
   const absent=working&&!future&&!partial&&!punches.length&&known;
   const absenceClass=absent?(decision?.classificacao||(historical?'justificada':'injustificada')):null;
   const credit=working&&((decision?.classificacao==='justificada'&&decision.abonar)||historical)?Math.max(0,expected-worked):0;
   if(decision?.classificacao==='pendente')warnings.push('Classificação pendente de conferência');
   const pending=!future&&!partial&&employed&&((working&&!known)||warnings.length>0);
   let status=future?'Futuro':partial?'Em andamento':!employed?'Fora do vínculo':warnings.length?'Conferir':vacation?'Férias':isHoliday?h.name:!working?'Folga':historical?'Justificada — corte de implantação':absenceClass==='justificada'?'Falta justificada':absenceClass==='injustificada'?'Sem ponto — sem justificativa':!known?(observed?'Sem dados confirmados':'Sem histórico observado'):worked+credit<expected?'Abaixo da jornada':worked+credit>expected?'Acima da jornada':'Jornada realizada';
   days.push({date:day,punches,expected,worked,delta:known&&!future&&!partial&&!warnings.length?worked+credit-expected:null,status,warnings,absenceClass,historical,credit,decision,covered:known,pending,partial,future,working,employed,excluded:!!(isHoliday||vacation),inCycle:day>=start&&day<=end});
  }
  for(let w=monday(start);w<=sunday(end);w=add(w,7)){
   const last=add(w,6),list=days.filter(d=>d.date>=w&&d.date<=last),eligible=list.filter(d=>d.employed&&plan.days.includes(weekday(d.date))&&!d.excluded);
   const target=Math.max(0,Math.round(plan.weekly*60*eligible.length/plan.days.length)-list.reduce((sum,d)=>sum+d.credit,0)),worked=list.reduce((sum,d)=>sum+d.worked,0);
   const closed=last<today,pending=list.some(d=>d.pending),assigned=last>=start&&last<=end;
   const delta=closed&&!pending?worked-target:null;
   weeks.push({start:w,end:last,worked,expected:target,delta,extra:delta===null?0:Math.max(0,delta),negative:delta===null?0:Math.max(0,-delta),closed,pending,assigned,status:!closed?'Em andamento':pending?'Conferir':'Fechada'});
  }
  const visible=days.filter(d=>d.inCycle),assigned=weeks.filter(w=>w.assigned),closed=assigned.filter(w=>w.delta!==null);
  days.forEach(day=>{day.alerts=dayAlerts(day);});const reviewCount=visible.filter(d=>d.alerts.length).length;const reviewCounts=Object.fromEntries(['missing','no_record','below','above','data'].map(type=>[type,visible.filter(d=>d.alerts.some(a=>a.type===type)).length]));
  return {employee,plan,days:visible,weeks,reviewCount,reviewCounts,worked:visible.reduce((s,d)=>s+d.worked,0),expected:visible.filter(d=>!d.future).reduce((s,d)=>s+d.expected,0),extra:closed.reduce((s,w)=>s+w.extra,0),negative:closed.reduce((s,w)=>s+w.negative,0),pending:visible.filter(d=>d.pending).length,possibleAbsences:visible.filter(d=>d.absenceClass==='injustificada').length,justified:visible.filter(d=>d.absenceClass==='justificada').length,unjustified:visible.filter(d=>d.absenceClass==='injustificada').length,provisional:visible.reduce((n,d)=>n+(d.delta||0),0),closedWeeks:closed.length,openWeeks:assigned.filter(w=>w.delta===null).length,marks:visible.reduce((s,d)=>s+d.punches.length,0)};
 }
 function absenceGroups(summaries,kind){
  const groups=new Map();
  summaries.forEach(summary=>summary.days.filter(day=>day.absenceClass===kind).forEach(day=>{
   if(!groups.has(day.date))groups.set(day.date,[]);
   groups.get(day.date).push({employee:summary.employee,day});
  }));
  return [...groups].sort(([a],[b])=>b.localeCompare(a)).map(([date,items])=>({date,items:items.sort((a,b)=>a.employee.nome.localeCompare(b.employee.nome,'pt-BR'))}));
 }
 function distribution(summaries){
  const labels=['Seg','Ter','Qua','Qui','Sex','Sáb','Dom'];
  const buckets=labels.map((label,i)=>({label,weekday:(i+1)%7,total:0,sectors:{}}));
  const dates=new Set();let total=0;
  for(const summary of summaries){for(const day of summary.days){
   if(day.future||day.partial||!Number.isFinite(day.delta)||day.delta<=0||day.warnings.length)continue;
   const key=(summary.employee.setor||'Sem setor').trim()||'Sem setor',bucket=buckets[(weekday(day.date)+6)%7];
   bucket.total+=day.delta;bucket.sectors[key]=(bucket.sectors[key]||0)+day.delta;total+=day.delta;dates.add(day.date);
  }}
  return {buckets,total,dates:dates.size,maximum:Math.max(0,...buckets.map(b=>b.total))};
 }
 function reviewSignature(day){return JSON.stringify({v:1,date:day.date,punches:day.punches.map(p=>[p.data_hora,p.entrada_saida,p.situacao,p.tipo_registro||'',p.obs||'']).sort((a,b)=>JSON.stringify(a).localeCompare(JSON.stringify(b))),expected:day.expected,worked:day.worked,delta:day.delta,covered:day.covered,credit:day.credit,status:day.status,decision:day.decision?[day.decision.classificacao,day.decision.abonar,day.decision.motivo]:null,alerts:dayAlerts(day)});}
 function applyVerifications(summary,records){
  for(const day of summary.days){day.alerts=dayAlerts(day);const signature=reviewSignature(day);day.verification=records.filter(r=>r.funcionario_id===summary.employee.id&&r.dia===day.date&&r.assinatura===signature).sort((a,b)=>b.verificado_em.localeCompare(a.verificado_em))[0]||null;day.allAlerts=day.alerts;if(day.verification)day.alerts=[];}
  summary.reviewCount=summary.days.filter(d=>d.alerts.length).length;summary.reviewCounts=Object.fromEntries(['missing','no_record','below','above','data'].map(t=>[t,summary.days.filter(d=>d.alerts.some(a=>a.type===t)).length]));return summary;
 }
 const api={valid,add,monday,sunday,cycle,cycleMonth,hours,schedule,summarize,absenceGroups,distribution,dayAlerts,reviewTolerance,reviewSignature,applyVerifications};
 if(typeof module!=='undefined'&&module.exports)module.exports=api;else root.RHPonto=api;
})(typeof window==='undefined'?globalThis:window);



