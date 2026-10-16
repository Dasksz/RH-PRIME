(() => {
  'use strict';
  const client=window.supabase.createClient('https://gcksbfstheavpfgcdndb.supabase.co','sb_publishable_UrTJ8_SyM3n800C4LZQWpw_5Ah8Ko98');window.RHNavigationClient=client;
  const $=id=>document.getElementById(id),months=['Janeiro','Fevereiro','Março','Abril','Maio','Junho','Julho','Agosto','Setembro','Outubro','Novembro','Dezembro'];
  const num=(v,d=0)=>v===null?'—':Number(v).toLocaleString('pt-BR',{minimumFractionDigits:d,maximumFractionDigits:d}),pct=v=>v===null?'—':num(v,2)+'%';
  const query=new URLSearchParams(location.search),requestedYear=query.get('ano'),requestedMonth=query.get('mes');
  const series=[['turnover','Turnover',''],['volRate','Perda voluntária','6 3'],['involRate','Perda involuntária','2 3'],['absence','Absenteísmo¹','10 3 2 3']];
  let movements=[],absences=[],rows=[],active=null,cutoff='',lastUpdate='',busy=false,stopWatch;
  function renderChart(){
    if(!rows.length||!$('annual-chart').clientWidth)return;
    const width=$('annual-chart').clientWidth,height=$('annual-chart').clientHeight,left=34,right=12,top=14,bottom=30,plotW=width-left-right,plotH=height-top-bottom;
    const values=rows.flatMap(r=>series.map(([key])=>r.kpis?.[key]).filter(v=>v!=null)),max=Math.max(1,...values),step=max<=2?.5:max<=10?2:max<=25?5:Math.ceil(max/4/5)*5,ceiling=Math.ceil(max/step)*step;
    const x=i=>left+i*plotW/11,y=value=>top+(1-value/ceiling)*plotH,selected=$('month').value;
    const readoutMonth=selected==='all'?rows.filter(r=>r.kpis).at(-1):rows[+selected];
    $('chart-legend').innerHTML=series.map(([,label,dash],i)=>`<span class="legend-item"><svg aria-hidden="true"><line x1="0" y1="4" x2="22" y2="4" stroke="var(--series-${i})" stroke-width="2.5" stroke-dasharray="${dash}"/></svg>${label}</span>`).join('');
    const grid=Array.from({length:Math.round(ceiling/step)+1},(_,i)=>{const v=i*step;return `<line class="chart-grid" x1="${left}" x2="${width-right}" y1="${y(v)}" y2="${y(v)}"/><text class="chart-axis" x="${left-7}" y="${y(v)+4}" text-anchor="end">${num(v,v%1?1:0)}%</text>`;}).join('');
    const bands=rows.map((r,i)=>`<g class="chart-point ${selected===String(i)?'is-selected':''}" role="button" tabindex="0" data-month="${i}" aria-label="${months[i]}: ${r.kpis?series.map(([key,label])=>`${label} ${pct(r.kpis[key])}`).join('; '):'não apurado'}"><title>${months[i]} · ${r.status}${r.kpis?' — '+series.map(([key,label])=>`${label}: ${pct(r.kpis[key])}`).join(' / '):''}</title><rect class="month-band" x="${Math.max(left-8,x(i)-plotW/22)}" y="${top}" width="${i===0||i===11?plotW/22+8:plotW/11}" height="${plotH+bottom}" rx="4"/><text class="chart-axis" x="${x(i)}" y="${height-8}" text-anchor="middle">${months[i].slice(0,3)}</text></g>`).join('');
    const lines=series.map(([key,,dash],s)=>{
      let previous=null,paths='',dots='';
      rows.forEach((r,i)=>{const value=r.kpis?.[key];if(value==null){previous=null;return;}const point={x:x(i),y:y(value)};
        if(previous)paths+=`<line x1="${previous.x}" y1="${previous.y}" x2="${point.x}" y2="${point.y}" stroke-dasharray="${r.status==='Parcial'?'3 4':dash}"/>`;
        dots+=`<circle cx="${point.x}" cy="${point.y}" r="${selected===String(i)?4:2.5}"/>`;previous=point;
      });return `<g aria-hidden="true" pointer-events="none" stroke="var(--series-${s})" stroke-width="2" fill="none">${paths}<g fill="var(--series-${s})" stroke="var(--rh-panel)">${dots}</g></g>`;
    }).join('');
    $('annual-chart').innerHTML=`<svg viewBox="0 0 ${width} ${height}" role="group" aria-label="Evolução mensal dos quatro indicadores em porcentagem. Selecione um mês para consultar os KPIs.">${grid}${bands}${lines}</svg>`;
    $('chart-readout').textContent=readoutMonth?`${months[readoutMonth.month]} · ${readoutMonth.status}${readoutMonth.kpis?' — '+series.map(([key,label])=>`${label}: ${pct(readoutMonth.kpis[key])}`).join(' · '):' — sem apuração'}`:'Sem meses apurados.';
  }
  const controls=disabled=>['refresh','export','print'].forEach(id=>$(id).disabled=disabled);
  function render(){
    const year=+$('year').value,month=$('month').value,today=RH.today();cutoff=today;rows=RHIndicators.annual(movements,absences,year,today);
    const state=`ano=${year}&mes=${month}`;
    if($('details-link'))$('details-link').href=`detalhes_indicadores.html?${state}`;
    $('back-link').href=`indicadores.html?${state}`;
    history.replaceState(null,'',`${location.pathname}?${state}`);
    const end=`${year}-12-31`<today?`${year}-12-31`:today;
    active=month==='all'?RHIndicators.calculate(movements,absences,`${year}-01-01`,end):rows[+month].kpis;
    const title=month==='all'?`Acumulado de ${year}`:`${months[+month]} de ${year}`,partial=year===+today.slice(0,4)&&(month==='all'||+month===+today.slice(5,7)-1);
    $('period').textContent=title;$('period-badge').textContent=!active?'Não apurado':partial?'Período parcial':'Período fechado';
    $('updated').textContent=`Atualizado ${lastUpdate} • corte ${today.split('-').reverse().join('/')}`;
    $('print-meta').textContent=`${title} • corte ${today.split('-').reverse().join('/')} • geração ${lastUpdate}`;
    const k=active,cards=[['Turnover de saídas',k?.turnover,'Desligamentos ÷ quadro médio × 100',`${num(k?.exits??null)} desligamentos`,'#087c73'],['Perda voluntária',k?.volRate,'Pedidos ÷ quadro médio × 100',`${num(k?.vol??null)} pedidos`,'#4d78ab'],['Perda involuntária',k?.involRate,'Saídas involuntárias ÷ quadro médio × 100',`${num(k?.invol??null)} saídas involuntárias`,'#99733a'],['Absenteísmo estimado',k?.absence,'Horas perdidas ÷ horas previstas × 100',k?`${num(k.lost,1)} h perdidas / ${num(k.expected,1)} h previstas`:'Não apurado','#8b68a4']];
    $('metrics').innerHTML=cards.map(([name,value,formula,detail,tone],i)=>`<article class="metric" style="--tone:${tone}"><h3>${name}</h3><span class="value">${pct(value??null)}</span><p>${formula}</p><small class="muted">${detail}</small>${i===3?`<a class="absence-details" href="detalhes_absenteismo.html${month==='all'?'':`?mes=${encodeURIComponent(String(+month+1).padStart(2,'0')+'/'+year)}`}">Ver lançamentos${month==='all'?' de todos os períodos':''}</a>`:''}</article>`).join('');
    $('summary').innerHTML=[['Admissões no período',k?.entries],['Desligamentos no período',k?.exits],['Quadro no início → fim',k?`${num(k.opening)} → ${num(k.closing)}`:'—'],['Quadro médio do período',k?num(k.average,1):'—']].map(([label,value])=>`<div><strong>${typeof value==='string'?value:num(value??null)}</strong><span>${label}</span></div>`).join('');
    $('table-caption').textContent=`${year} • Turnover e perdas sobre o quadro médio de cada mês. Absenteísmo estimado.`;$('annual-title').textContent=`Evolução mensal · ${year}`;
    $('annual-body').innerHTML=rows.map(r=>{const a=r.kpis;return `<tr class="${month===String(r.month)?'selected ':''}${!a?'future':''}"><td><button type="button" class="month-link" data-month="${r.month}" aria-label="Ver ${months[r.month]} de ${year}">${months[r.month]}</button>${r.status!=='Fechado'?` <span class="badge">${r.status}</span>`:''}</td>${[num(a?.entries??null),num(a?.exits??null),num(a?.average??null,1),pct(a?.turnover??null),pct(a?.volRate??null),pct(a?.involRate??null),pct(a?.absence??null)].map(v=>`<td>${v}</td>`).join('')}</tr>`;}).join('');
    $('mobile-months').innerHTML=rows.map(r=>{const a=r.kpis;return `<article class="month-card ${month===String(r.month)?'selected':''}"><div class="month-head"><button type="button" class="month-link" data-month="${r.month}">${months[r.month]}</button><span class="badge">${r.status}</span></div>${a?`<div class="month-values">${[['Turnover',a.turnover],['Perda voluntária',a.volRate],['Perda involuntária',a.involRate],['Absenteísmo¹',a.absence]].map(([l,v])=>`<div><span>${l}</span><strong>${pct(v)}</strong></div>`).join('')}</div><p class="muted">${a.entries} entradas · ${a.exits} saídas · quadro médio ${num(a.average,1)}</p>`:'<p class="muted">Mês futuro, sem índices apurados.</p>'}</article>`;}).join('');
    $('distribution').innerHTML=!k||!k.exits?'<p class="muted">Sem desligamentos no período apurado.</p>':[['Voluntários',k.vol],['Involuntários',k.invol],['Sem classificação',k.unknown]].map(([label,n])=>`<div><div class="dist-label"><span>${label}: ${n}</span><strong>${pct(n/k.exits*100)}</strong></div><div class="bar"><span style="width:${n/k.exits*100}%"></span></div></div>`).join('');
    const historical=movements.filter(r=>RHIndicators.date(r.data_admissao)&&r.data_admissao.slice(0,10)<`${year}-01-01`).length,missingLinks=movements.filter(r=>!r.funcionario_id).length;
    $('history').textContent=`Histórico cadastrado: ${num(movements.length)} vínculos; ${num(historical)} com admissão anterior a ${year}, fora da contagem de entradas deste ano. ${missingLinks?`${num(missingLinks)} vínculos sem identificação integrada; recortes por filial e função dependem de conciliação. `:''}${k?.unknown?`${k.unknown} desligamento(s) sem classificação no período. `:''}${k?.invalidAbsences?`${k.invalidAbsences} lançamento(s) de ausência com dados inválidos ou sem datas no mês parcial não foram incluídos. `:''}${k?.invalidMovements?`${k.invalidMovements} vínculo(s) com datas inválidas não foram incluídos. `:''}Datas e vínculos históricos devem ser validados pelo RH.`;
    renderChart();
  }
  async function load(){
    if(busy)return;busy=true;controls(true);$('status').hidden=false;$('status').className='panel status';$('status').textContent='Carregando indicadores…';$('dashboard').hidden=true;
    try{
      const data=await Promise.all([RH.fetchAll(client,'rh_movimentacoes','*','id'),RH.fetchAll(client,'rh_absenteismo','*','id')]);movements=data[0];absences=data[1];
      const current=+RH.today().slice(0,4),years=new Set([current]);
      movements.forEach(r=>[r.data_admissao,r.data_desligamento].forEach(d=>{if(RHIndicators.date(d)&&+d.slice(0,4)<=current)years.add(+d.slice(0,4));}));
      absences.forEach(r=>{const y=RHIndicators.date(r.data_inicio)?.slice(0,4)||/\/(\d{4})$/.exec(r.mes_ref||'')?.[1];if(y&&+y<=current)years.add(+y);});
      const selected=$('year').value||requestedYear;$('year').replaceChildren(...[...years].sort((a,b)=>b-a).map(y=>new Option(y,y)));$('year').value=years.has(+selected)?selected:current;
      lastUpdate=new Intl.DateTimeFormat('pt-BR',{timeZone:'America/Sao_Paulo',dateStyle:'short',timeStyle:'short'}).format(new Date());$('dashboard').hidden=false;render();$('status').hidden=true;controls(false);
    }catch(error){console.error('Falha ao carregar indicadores',error);$('status').className='panel status error';$('status').textContent='Não foi possível carregar os indicadores. Use Atualizar para tentar novamente.';$('refresh').disabled=false;}finally{busy=false;}
  }
  function csv(){
    const headings=['Ano','Mês','Situação','Admissões','Desligamentos','Quadro inicial','Quadro final','Quadro médio','Turnover de saídas (%)','Perda voluntária (%)','Perda involuntária (%)','Absenteísmo estimado (%)','Horas perdidas','Horas previstas estimadas','Saídas sem classificação','Ausências não incluídas por dados insuficientes','Vínculos com datas inválidas','Data de corte','Método','Base de horas'];
    const values=rows.map(r=>{const k=r.kpis;return [$('year').value,months[r.month],r.status,k?.entries,k?.exits,k?.opening,k?.closing,k?.average,k?.turnover,k?.volRate,k?.involRate,k?.absence,k?.lost,k?.expected,k?.unknown,k?.invalidAbsences,k?.invalidMovements,cutoff,'Taxas de saídas = desligamentos da categoria / ((quadro inicial + quadro final) / 2) * 100','Carga mensal cadastrada (padrão 220 h), proporcional seg-sáb; sem ajuste de férias, feriados ou afastamentos; atrasos e saídas antecipadas não incluídos'];});
    const cell=v=>'"'+(v==null?'':typeof v==='number'?num(v,2):String(v)).replace(/"/g,'""')+'"';
    const blob=new Blob(['\uFEFF'+[headings,...values].map(r=>r.map(cell).join(';')).join('\r\n')],{type:'text/csv;charset=utf-8;'}),url=URL.createObjectURL(blob),a=document.createElement('a');a.href=url;a.download=`PRIME-RH-indicadores-${$('year').value}.csv`;document.body.append(a);a.click();a.remove();setTimeout(()=>URL.revokeObjectURL(url),1000);
  }
  months.forEach((m,i)=>$('month').add(new Option(m,i)));$('year').addEventListener('change',render);$('month').addEventListener('change',render);$('refresh').addEventListener('click',load);$('export').addEventListener('click',csv);$('print').addEventListener('click',()=>window.print());
  if(requestedMonth==='all'||/^(?:[0-9]|1[01])$/.test(requestedMonth||''))$('month').value=requestedMonth;
  new ResizeObserver(()=>renderChart()).observe($('annual-chart'));
  window.addEventListener('beforeprint',renderChart);window.addEventListener('afterprint',renderChart);
  $('annual-chart').addEventListener('keydown',event=>{if((event.key==='Enter'||event.key===' ')&&event.target.closest('[data-month]')){event.preventDefault();event.target.closest('[data-month]').dispatchEvent(new MouseEvent('click',{bubbles:true}));}});
  $('dashboard').addEventListener('click',event=>{const b=event.target.closest('[data-month]');if(b){$('month').value=b.dataset.month;render();$('period').focus({preventScroll:true});$('period').scrollIntoView({behavior:window.matchMedia('(prefers-reduced-motion: reduce)').matches?'instant':'smooth',block:'center'});}});
  (async()=>{try{await RH.profile(client);}catch(error){console.error('Falha na verificação de acesso',error);window.location.replace('login.html');return;}await load();stopWatch=RH.watch(client,['rh_movimentacoes','rh_absenteismo'],load);window.addEventListener('pagehide',()=>stopWatch?.(),{once:true});})();
})();

