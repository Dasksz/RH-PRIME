// Funções puras compartilhadas com as verificações de regressão.
const RHIndicators = (() => {
  const date = value => {if(!value)return null;const s=String(value).split('T')[0];if(!/^\d{4}-\d{2}-\d{2}$/.test(s))return null;const d=new Date(s+'T12:00:00');return Number.isNaN(+d)||d.getFullYear()!==+s.slice(0,4)||d.getMonth()+1!==+s.slice(5,7)||d.getDate()!==+s.slice(8,10)?null:s;};
  const day=s=>new Date(s+'T12:00:00');
  const iso=d=>`${d.getFullYear()}-${String(d.getMonth()+1).padStart(2,'0')}-${String(d.getDate()).padStart(2,'0')}`;
  const next=s=>{const d=day(s);d.setDate(d.getDate()+1);return iso(d);};
  const monthEnd=(y,m)=>iso(new Date(y,m+1,0,12));
  const weight=s=>{const n=day(s).getDay();return n===0?0:n===6?4:8;};
  const hours=(start,end)=>{let n=0;for(let d=start;d<=end;d=next(d))n+=weight(d);return n;};
  const days=(a,b)=>{const utc=s=>{const [y,m,d]=s.split('-').map(Number);return Date.UTC(y,m-1,d);};return Math.round((utc(b)-utc(a))/86400000)+1;};
  const ratio=(n,d)=>d>0?n/d*100:null;
  const category=value=>{const s=String(value||'').trim().toLowerCase();return s==='voluntario'?'vol':['involuntario','involuntario_justa_causa'].includes(s)?'invol':'unknown';};
  function lost(records,start,end){
    let total=0,invalid=0;
    records.forEach(r=>{
      const value=Number(r.horas_perdidas);if(!Number.isFinite(value)||value<0){invalid++;return;}
      const a=date(r.data_inicio),b=date(r.data_fim);
      if(a&&b&&b>=a){
        if(b<start||a>end)return;const from=a>start?a:start,to=b<end?b:end,basis=hours(a,b);
        total+=value*(basis?hours(from,to)/basis:days(from,to)/days(a,b));
      }else{
        if(r.data_inicio||r.data_fim){invalid++;return;}
        // Legado sem datas: apuração apenas depois de encerrado o mês inteiro.
        const match=/^(\d{2})\/(\d{4})$/.exec(String(r.mes_ref||''));
        if(!match||+match[1]<1||+match[1]>12){invalid++;return;}
        const first=`${match[2]}-${match[1]}-01`,last=monthEnd(+match[2],+match[1]-1);
        if(first>=start&&last<=end)total+=value;else if(first<=end&&last>=start)invalid++;
      }
    });return {total,invalid};
  }
  function calculate(movements,absences,start,end){
    let opening=0,closing=0,entries=0,exits=0,vol=0,invol=0,unknown=0,expected=0,invalidMovements=0;
    movements.forEach(r=>{
      const a=date(r.data_admissao),b=date(r.data_desligamento);if(!a||(r.data_desligamento&&!b)||(b&&b<a)){invalidMovements++;return;}
      if(a<start&&(!b||b>=start))opening++;
      if(a<=end&&(!b||b>end))closing++;
      if(a>=start&&a<=end)entries++;
      if(b&&b>=start&&b<=end){exits++;const c=category(r.motivo_saida);if(c==='vol')vol++;else if(c==='invol')invol++;else unknown++;}
      for(let cursor=start.slice(0,7)+'-01';cursor<=end;){
        const y=+cursor.slice(0,4),m=+cursor.slice(5,7)-1,last=monthEnd(y,m);
        const from=[a,start,cursor].sort().at(-1),to=[b||end,end,last].sort()[0];
        if(from<=to){const load=Number(r.carga_horaria);expected+=(load>0?load:220)*hours(from,to)/hours(cursor,last);}
        cursor=next(last);
      }
    });
    const average=(opening+closing)/2,loss=lost(absences,start,end);
    return {opening,closing,entries,exits,vol,invol,unknown,average,expected,lost:loss.total,invalidAbsences:loss.invalid,invalidMovements,turnover:ratio(exits,average),volRate:ratio(vol,average),involRate:ratio(invol,average),absence:ratio(loss.total,expected)};
  }
  function annual(movements,absences,year,today){return Array.from({length:12},(_,m)=>{const start=`${year}-${String(m+1).padStart(2,'0')}-01`,last=monthEnd(year,m),end=last<today?last:today;return {month:m,start,end,status:start>today?'Não apurado':last>today?'Parcial':'Fechado',kpis:start>today?null:calculate(movements,absences,start,end)};});}
  return {date,calculate,annual};
})();
