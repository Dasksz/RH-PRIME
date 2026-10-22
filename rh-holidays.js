(function(root,doc){
 'use strict';
 const nationalFixed={
  '01-01':'Confraternização Universal','04-21':'Tiradentes','05-01':'Dia Mundial do Trabalho',
  '09-07':'Independência do Brasil','10-12':'Nossa Senhora Aparecida','11-02':'Finados',
  '11-15':'Proclamação da República','12-25':'Natal'
 };
 const months=['janeiro','fevereiro','março','abril','maio','junho','julho','agosto','setembro','outubro','novembro','dezembro'];
 const weekdays=['Seg','Ter','Qua','Qui','Sex','Sáb','Dom'];
 const pad=n=>String(n).padStart(2,'0');
 const iso=(y,m,d)=>`${y}-${pad(m)}-${pad(d)}`;
 const validISO=value=>/^\d{4}-\d{2}-\d{2}$/.test(String(value||''))&&(()=>{const d=new Date(`${value}T12:00:00Z`);return !Number.isNaN(+d)&&d.toISOString().slice(0,10)===value;})();
 const easterSunday=year=>{
  const a=year%19,b=Math.floor(year/100),c=year%100,d=Math.floor(b/4),e=b%4,f=Math.floor((b+8)/25),g=Math.floor((b-f+1)/3),h=(19*a+b-d-g+15)%30;
  const i=Math.floor(c/4),k=c%4,l=(32+2*e+2*i-h-k)%7,m=Math.floor((a+11*h+22*l)/451),month=Math.floor((h+l-7*m+114)/31),day=((h+l-7*m+114)%31)+1;
  return new Date(Date.UTC(year,month-1,day));
 };
 const easterOffset=(year,offset)=>{const date=easterSunday(year);date.setUTCDate(date.getUTCDate()+offset);return date.toISOString().slice(0,10);};
 const goodFriday=year=>easterOffset(year,-2);
 const facultativos=year=>[
  {date:easterOffset(year,-48),name:'Carnaval · segunda-feira'},
  {date:easterOffset(year,-47),name:'Carnaval · terça-feira'},
  {date:easterOffset(year,-46),name:'Quarta-feira de Cinzas · até 14h'},
  {date:easterOffset(year,60),name:'Corpus Christi'},
  ...(year===2026?[
   {date:'2026-04-20',name:'Ponto facultativo'},
   {date:'2026-06-05',name:'Ponto facultativo'},
   {date:'2026-10-28',name:'Dia do Servidor Público federal'},
   {date:'2026-12-24',name:'Véspera de Natal · após 13h'},
   {date:'2026-12-31',name:'Véspera de Ano Novo · após 13h'}
  ]:[])
 ].map(item=>({...item,scope:'facultativo',label:'Ponto facultativo federal'}));
 function getHoliday(value){
  if(!validISO(value))return null;
  const year=Number(value.slice(0,4)),mmdd=value.slice(5);
  if(nationalFixed[mmdd])return {date:value,name:nationalFixed[mmdd],scope:'brasil',label:'Feriado nacional'};
  if(year>=2024&&mmdd==='11-20')return {date:value,name:'Dia Nacional de Zumbi e da Consciência Negra',scope:'brasil',label:'Feriado nacional'};
  if(value===goodFriday(year))return {date:value,name:'Paixão de Cristo',scope:'brasil',label:'Feriado nacional'};
  if(mmdd==='07-02')return {date:value,name:'Independência da Bahia',scope:'bahia',label:'Feriado estadual · Bahia'};
  const optional=facultativos(year).find(item=>item.date===value);if(optional)return optional;
  return null;
 }
 function getYear(year){
  const result=[];
  Object.entries(nationalFixed).forEach(([mmdd,name])=>result.push({date:`${year}-${mmdd}`,name,scope:'brasil',label:'Feriado nacional'}));
  if(year>=2024)result.push({date:`${year}-11-20`,name:'Dia Nacional de Zumbi e da Consciência Negra',scope:'brasil',label:'Feriado nacional'});
  result.push({date:goodFriday(year),name:'Paixão de Cristo',scope:'brasil',label:'Feriado nacional'});
  result.push({date:`${year}-07-02`,name:'Independência da Bahia',scope:'bahia',label:'Feriado estadual · Bahia'});
  result.push(...facultativos(year));
  return result.sort((a,b)=>a.date.localeCompare(b.date));
 }
 function format(value){return validISO(value)?value.split('-').reverse().join('/'):'Selecione uma data';}
 function monthGrid(year,month,selected,min,max){
  const first=new Date(Date.UTC(year,month-1,1)),daysInMonth=new Date(Date.UTC(year,month,0)).getUTCDate(),offset=(first.getUTCDay()+6)%7;
  let cells='';
  for(let i=0;i<offset;i++)cells+='<span class="rh-holiday-empty" aria-hidden="true"></span>';
  for(let day=1;day<=daysInMonth;day++){
   const value=iso(year,month,day),holiday=getHoliday(value),outside=(min&&value<min)||(max&&value>max),classes=['rh-holiday-day',holiday?`is-${holiday.scope}`:'',value===selected?'is-selected':'',value===iso(new Date().getFullYear(),new Date().getMonth()+1,new Date().getDate())?'is-today':''].filter(Boolean).join(' ');
   const label=`${pad(day)}/${pad(month)}/${year}${holiday?` — ${holiday.name}, ${holiday.label}`:''}`;
   cells+=`<button class="${classes}" type="button" data-rh-day="${value}" aria-label="${label}" ${outside?'disabled':''}><span>${day}</span>${holiday?'<i aria-hidden="true"></i>':''}</button>`;
  }
  return `<div class="rh-holiday-weekdays">${weekdays.map(d=>`<span>${d}</span>`).join('')}</div><div class="rh-holiday-days">${cells}</div>`;
 }
 function addStyles(){
  if(doc.getElementById('rh-holiday-styles'))return;
  const style=doc.createElement('style');style.id='rh-holiday-styles';style.textContent=`
   .rh-date-native{visibility:hidden!important;pointer-events:none!important}
   .rh-date-trigger{box-sizing:border-box;display:flex;align-items:center;justify-content:space-between;gap:12px;min-width:0;padding:9px 12px;border:1px solid var(--rh-border,#344b58);border-radius:10px;background:var(--rh-panel,#142630);color:var(--rh-ink,#e7f0f4);font:inherit;text-align:left;cursor:pointer}
   .rh-date-trigger>span{min-width:0;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}.rh-date-trigger:hover{border-color:#4c9b92}.rh-date-trigger:focus-visible,.rh-holiday-popover button:focus-visible{outline:3px solid #5de2b5;outline-offset:2px}.rh-date-trigger[disabled]{opacity:.55;cursor:not-allowed}.rh-date-placeholder{opacity:.65}.rh-date-icon{width:18px;height:18px;flex:none;color:currentColor}
   .rh-holiday-popover{position:fixed;inset:auto;margin:0;z-index:100000;width:min(340px,calc(100vw - 20px));max-height:min(540px,calc(100vh - 20px));overflow:auto;padding:14px;border:1px solid var(--rh-border,#344b58);border-radius:14px;background:var(--rh-panel,#142630);color:var(--rh-ink,#e7f0f4);box-shadow:0 18px 48px #0006;font:14px/1.4 system-ui,sans-serif}
   .rh-holiday-popover[hidden]{display:none}.rh-holiday-head{display:flex;align-items:center;justify-content:space-between;gap:10px;margin-bottom:10px}.rh-holiday-head strong{text-transform:capitalize}.rh-holiday-nav{display:flex;gap:6px}.rh-holiday-nav button{width:34px;height:34px;padding:0;border:1px solid var(--rh-border,#344b58);border-radius:9px;background:var(--rh-soft,#203540);color:inherit;cursor:pointer;font:600 18px system-ui}.rh-holiday-weekdays,.rh-holiday-days{display:grid;grid-template-columns:repeat(7,minmax(0,1fr));gap:3px}.rh-holiday-weekdays{margin-bottom:4px;text-align:center;color:var(--rh-muted,#adc2cd);font-size:11px}.rh-holiday-day,.rh-holiday-empty{position:relative;display:grid;place-items:center;min-width:0;min-height:38px;border:1px solid transparent;border-radius:9px;background:transparent;color:inherit;font:500 13px system-ui}.rh-holiday-day{cursor:pointer}.rh-holiday-day:hover{background:var(--rh-soft,#203540)}.rh-holiday-day.is-selected{border-color:#64a9ff;background:#173b58;color:#fff}.rh-holiday-day.is-today{box-shadow:inset 0 0 0 1px #68cfb7}.rh-holiday-day.is-brasil{background:#4a252b;color:#ffc1c6}.rh-holiday-day.is-bahia{background:#453a1d;color:#ffdf82}.rh-holiday-day.is-brasil.is-selected,.rh-holiday-day.is-bahia.is-selected{outline:2px solid #69adff;outline-offset:0}.rh-holiday-day i{position:absolute;bottom:3px;width:4px;height:4px;border-radius:50%;background:currentColor}.rh-holiday-day:disabled{opacity:.3;cursor:not-allowed}.rh-holiday-legend{display:flex;flex-wrap:wrap;gap:10px;margin-top:12px;padding-top:10px;border-top:1px solid var(--rh-border,#344b58);color:var(--rh-muted,#adc2cd);font-size:11px}.rh-holiday-legend span{display:inline-flex;align-items:center;gap:5px}.rh-holiday-legend i{width:9px;height:9px;border-radius:3px}.rh-holiday-legend .brasil{background:#c8505d}.rh-holiday-legend .bahia{background:#d4a832}.rh-holiday-note{min-height:20px;margin:10px 0 0;color:var(--rh-muted,#adc2cd);font-size:12px}.rh-holiday-note strong{color:var(--rh-ink,#e7f0f4)}
   .rh-holiday-year{font-variant-numeric:tabular-nums}
   @media(max-width:480px){.rh-holiday-popover{padding:12px}.rh-holiday-day,.rh-holiday-empty{min-height:36px}}
   `;style.textContent+=`.rh-holiday-day.is-facultativo{background:#273958;color:#b8c7ff}.rh-holiday-legend .facultativo{background:#7489d5}.rh-holiday-heading{display:flex;align-items:center;gap:7px;min-width:0}.rh-holiday-year-select{width:auto;min-width:82px;min-height:34px;padding:5px 24px 5px 8px;border:1px solid var(--rh-border,#344b58);border-radius:8px;background:var(--rh-soft,#203540);color:inherit;font:600 13px system-ui;cursor:pointer}`;doc.head.appendChild(style);
 }
 function labelFor(input){
  const explicit=input.id&&Array.from(doc.querySelectorAll('label[for]')).find(label=>label.htmlFor===input.id);
  const wrapping=input.closest('label');
  return (explicit?.textContent||wrapping?.textContent||input.getAttribute('aria-label')||input.name||'Selecionar data').trim().replace(/\s+/g,' ');
 }
 let active=null;
 function releaseManagedParent(state){
  const parent=state.managedParent;if(!parent)return;parent.__rhDateUsers=Math.max(0,(parent.__rhDateUsers||1)-1);
  if(!parent.__rhDateUsers){parent.style.position=parent.__rhDateOriginalPosition||'';delete parent.dataset.rhDatePosition;delete parent.__rhDateOriginalPosition;delete parent.__rhDateUsers;}state.managedParent=null;
 }
 function syncGeometry(state){
  const {input,trigger}=state;if(!input.isConnected||!trigger.isConnected)return;
  const parent=input.parentElement;if(parent&&trigger.parentElement!==parent)parent.insertBefore(trigger,input.nextSibling);
  if(parent&&(getComputedStyle(parent).position==='static'||parent.dataset.rhDatePosition)){
   if(state.managedParent!==parent){releaseManagedParent(state);if(!parent.dataset.rhDatePosition){parent.dataset.rhDatePosition='managed';parent.__rhDateOriginalPosition=parent.style.position;parent.style.position='relative';}parent.__rhDateUsers=(parent.__rhDateUsers||0)+1;state.managedParent=parent;}
  }else if(state.managedParent)releaseManagedParent(state);
  const rect=input.getBoundingClientRect(),parentRect=parent?.getBoundingClientRect(),computed=getComputedStyle(input);
  trigger.style.position='absolute';trigger.style.left=`${rect.left-(parentRect?.left||0)-(parent?.clientLeft||0)+(parent?.scrollLeft||0)}px`;trigger.style.top=`${rect.top-(parentRect?.top||0)-(parent?.clientTop||0)+(parent?.scrollTop||0)}px`;trigger.style.width=`${rect.width}px`;trigger.style.height=`${rect.height}px`;trigger.style.zIndex='100001';
  ['boxSizing','fontFamily','fontSize','fontWeight','fontStyle','lineHeight','letterSpacing','textTransform','textAlign','color','backgroundColor','border','borderRadius','boxShadow','padding','direction'].forEach(property=>{trigger.style[property]=computed[property];});
  trigger.style.minHeight='0';trigger.style.cursor=input.disabled||input.readOnly?'not-allowed':'pointer';trigger.disabled=input.disabled||input.readOnly;
 }
 function cleanup(input){
  const state=input?.rhDateState;if(!state)return;
  if(active===state)close(false);
  state.trigger.remove();input.classList.remove('rh-date-native');state.originalTabIndex===null?input.removeAttribute('tabindex'):input.setAttribute('tabindex',state.originalTabIndex);state.originalAriaHidden===null?input.removeAttribute('aria-hidden'):input.setAttribute('aria-hidden',state.originalAriaHidden);state.originalAriaLabel===null?input.removeAttribute('aria-label'):input.setAttribute('aria-label',state.originalAriaLabel);
  releaseManagedParent(state);
  delete input.rhDateState;delete input.dataset.rhHolidayEnhanced;
 }
 function close(restore){
  if(!active)return;const current=active;if(typeof current.popover.hidePopover==='function')current.popover.hidePopover();current.popover.remove();current.trigger.setAttribute('aria-expanded','false');active=null;
  if(restore)current.trigger.focus();
 }
 function setNativeValue(input,value){
  const setter=Object.getOwnPropertyDescriptor(root.HTMLInputElement.prototype,'value')?.set;
  if(setter)setter.call(input,value);else input.value=value;
  input.dispatchEvent(new Event('input',{bubbles:true}));
  input.dispatchEvent(new Event('change',{bubbles:true}));
 }
 function renderPicker(widget,year,month){
  const input=widget.input,trigger=widget.trigger,selected=input.value,min=input.min,max=input.max;
  const holiday=selected?getHoliday(selected):null;
  const currentYear=new Date().getFullYear(),firstYear=Math.min(currentYear-10,year),lastYear=Math.max(currentYear+20,year),yearOptions=Array.from({length:lastYear-firstYear+1},(_,index)=>firstYear+index).map(value=>`<option value="${value}" ${value===year?'selected':''}>${value}</option>`).join('');
  widget.popover.innerHTML=`<div class="rh-holiday-head"><div class="rh-holiday-heading"><strong>${months[month-1]}</strong><select class="rh-holiday-year-select" data-rh-year aria-label="Selecionar ano">${yearOptions}</select></div><div class="rh-holiday-nav"><button type="button" data-rh-month="-1" aria-label="Mês anterior">‹</button><button type="button" data-rh-month="1" aria-label="Próximo mês">›</button></div></div>${monthGrid(year,month,selected,min,max)}<div class="rh-holiday-legend"><span><i class="brasil"></i>Feriado nacional</span><span><i class="bahia"></i>Feriado da Bahia</span><span><i class="facultativo"></i>Ponto facultativo</span></div><p class="rh-holiday-note" aria-live="polite">${holiday?`<strong>${format(selected)} · ${holiday.name}</strong><br>${holiday.label}`:'Feriados e pontos facultativos do Brasil e da Bahia estão destacados.'}</p>`;
  widget.year=year;widget.month=month;
 }
 function position(widget){
  if(!widget.popover.isConnected)return;syncGeometry(widget);const rect=widget.trigger.getBoundingClientRect(),width=Math.min(340,innerWidth-20),height=Math.min(widget.popover.scrollHeight,innerHeight-20),left=Math.max(10,Math.min(rect.left,innerWidth-width-10));
  const below=rect.bottom+8,top=below+height<=innerHeight-10?below:Math.max(10,rect.top-height-8);
  widget.popover.style.left=`${left}px`;widget.popover.style.top=`${top}px`;
 }
 function open(widget){
  if(widget.input.disabled||widget.input.readOnly)return;widget.sync();
  if(active===widget){close(false);return;}close(false);
  const today=new Date(),start=validISO(widget.input.value)?widget.input.value:`${today.getFullYear()}-${pad(today.getMonth()+1)}-${pad(today.getDate())}`;
  const [year,month]=start.split('-').map(Number),popover=doc.createElement('div');popover.className='rh-holiday-popover';if(typeof popover.showPopover==='function')popover.setAttribute('popover','manual');popover.setAttribute('role','dialog');popover.setAttribute('aria-label',`Calendário de ${widget.label}`);widget.popover=popover;
  renderPicker(widget,year,month);(widget.input.closest('dialog[open]')||doc.body).appendChild(popover);if(typeof popover.showPopover==='function')popover.showPopover();else popover.style.display='block';widget.trigger.setAttribute('aria-expanded','true');active=widget;position(widget);
  const focusDate=popover.querySelector(`[data-rh-day="${validISO(widget.input.value)&&widget.input.value.slice(0,7)===`${year}-${pad(month)}`?widget.input.value:start}"]`);
  (focusDate&&!focusDate.disabled?focusDate:popover.querySelector('.rh-holiday-day:not(:disabled)'))?.focus();
 }
 function enhance(input){
  if(input.dataset.rhHolidayEnhanced==='true'||input.type!=='date')return;
  if(!input.parentNode)return;
  input.dataset.rhHolidayEnhanced='true';
  const trigger=doc.createElement('button');trigger.type='button';trigger.className='rh-date-trigger';trigger.setAttribute('aria-haspopup','dialog');trigger.setAttribute('aria-expanded','false');trigger.setAttribute('aria-label',`Selecionar data: ${labelFor(input)}`);trigger.setAttribute('aria-required',String(input.required));trigger.disabled=input.disabled||input.readOnly;
  trigger.innerHTML='<span></span><svg class="rh-date-icon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" aria-hidden="true"><rect x="3" y="5" width="18" height="16" rx="2"></rect><path d="M16 3v4M8 3v4M3 10h18"></path></svg>';
  const state={input,trigger,popover:null,label:labelFor(input),originalTabIndex:input.getAttribute('tabindex'),originalAriaHidden:input.getAttribute('aria-hidden'),originalAriaLabel:input.getAttribute('aria-label')};
  input.classList.add('rh-date-native');input.tabIndex=-1;input.setAttribute('aria-hidden','true');input.removeAttribute('aria-label');input.parentNode.insertBefore(trigger,input.nextSibling);input.rhDateState=state;
  const sync=()=>{const span=trigger.querySelector('span'),holiday=getHoliday(input.value);span.textContent=input.value?format(input.value):input.placeholder||'Selecione uma data';span.classList.toggle('rh-date-placeholder',!input.value);trigger.setAttribute('aria-label',`${input.value?format(input.value):'Selecionar data'}: ${state.label}${holiday?`; ${holiday.name} — ${holiday.label}`:''}`);trigger.title=holiday?`${holiday.name} · ${holiday.label}`:state.label;trigger.setAttribute('aria-required',String(input.required));syncGeometry(state);if(active===state)renderPicker(state,state.year,state.month);};
  state.sync=sync;trigger.rhDateState=state;trigger.addEventListener('click',()=>open(state));input.addEventListener('input',sync);input.addEventListener('change',sync);sync();
 }
 function init(){
  addStyles();const scan=node=>{if(node.nodeType!==1)return;const visit=input=>{if(input.dataset.rhHolidayEnhanced==='true')input.rhDateState?.sync();else enhance(input);};if(node.matches?.('input[type="date"]'))visit(node);node.querySelectorAll?.('input[type="date"]').forEach(visit);};
  doc.querySelectorAll('input[type="date"]').forEach(enhance);
  const observer=new MutationObserver(records=>records.forEach(record=>{
   if(record.type==='attributes'){if(record.target.matches?.('input[type="date"]'))record.target.rhDateState?.sync();else if(record.target===doc.documentElement||record.target===doc.body)doc.querySelectorAll('input[data-rh-holiday-enhanced="true"]').forEach(input=>input.rhDateState?.sync());return;}
   record.removedNodes.forEach(node=>{if(node.nodeType!==1)return;if(node.matches?.('input[data-rh-holiday-enhanced="true"]'))cleanup(node);node.querySelectorAll?.('input[data-rh-holiday-enhanced="true"]').forEach(cleanup);});record.addedNodes.forEach(scan);
  }));observer.observe(doc.body,{childList:true,subtree:true,attributes:true,attributeFilter:['disabled','readonly','required','min','max','value','class','style']});
  doc.addEventListener('click',event=>{
   if(event.target.closest?.('.rh-date-trigger'))return;
   const label=event.target.closest?.('label');if(label){const input=label.htmlFor?doc.getElementById(label.htmlFor):label.querySelector('input[type="date"]');if(input?.dataset.rhHolidayEnhanced==='true'){event.preventDefault();input.rhDateState?.trigger.click();return;}}
   if(active&&!event.target.closest('.rh-holiday-popover')&&!active.trigger.contains(event.target))close(false);
  },true);
  doc.addEventListener('invalid',event=>{const input=event.target;if(input?.dataset?.rhHolidayEnhanced==='true'){event.preventDefault();const state=input.rhDateState;state?.trigger.focus();if(state)open(state);}},true);
  doc.addEventListener('keydown',event=>{
   if(!active)return;if(event.key==='Escape'){event.preventDefault();close(true);return;}
   const monthButton=event.target.closest?.('[data-rh-month]');if(monthButton){event.preventDefault();const delta=Number(monthButton.dataset.rhMonth),date=new Date(Date.UTC(active.year,active.month-1+delta,1));renderPicker(active,date.getUTCFullYear(),date.getUTCMonth()+1);position(active);active.popover.querySelector(`[data-rh-month="${delta}"]`)?.focus();return;}
   const day=event.target.closest?.('[data-rh-day]');if(day&&!day.disabled){event.preventDefault();setNativeValue(active.input,day.dataset.rhDay);active.sync?.();close(true);}
  });
  doc.addEventListener('click',event=>{
   if(!active)return;const nav=event.target.closest?.('[data-rh-month]');if(nav){const delta=Number(nav.dataset.rhMonth),date=new Date(Date.UTC(active.year,active.month-1+delta,1));renderPicker(active,date.getUTCFullYear(),date.getUTCMonth()+1);position(active);active.popover.querySelector(`[data-rh-month="${delta}"]`)?.focus();return;}
   const day=event.target.closest?.('[data-rh-day]');if(day&&!day.disabled){setNativeValue(active.input,day.dataset.rhDay);active.sync?.();close(true);}
  });
  doc.addEventListener('change',event=>{
   const select=event.target.closest?.('[data-rh-year]');if(!active||!select||!active.popover.contains(select))return;
   const year=Number(select.value);if(!Number.isInteger(year))return;renderPicker(active,year,active.month);position(active);active.popover.querySelector('[data-rh-year]')?.focus();
  });
  root.addEventListener('resize',()=>{doc.querySelectorAll('input[data-rh-holiday-enhanced="true"]').forEach(input=>input.rhDateState?.sync());if(active)position(active);});root.addEventListener('scroll',()=>active&&position(active),true);
 }
 const api={getHoliday,getYear,isHoliday:value=>!!getHoliday(value),isNationalHoliday:value=>getHoliday(value)?.scope==='brasil',isBahiaHoliday:value=>getHoliday(value)?.scope==='bahia',goodFriday};
 root.RHHolidays=api;
 if(doc.readyState==='loading')doc.addEventListener('DOMContentLoaded',init,{once:true});else init();
})(window,document);
