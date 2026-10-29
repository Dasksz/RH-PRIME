(function(){
 'use strict';
 const months=['janeiro','fevereiro','março','abril','maio','junho','julho','agosto','setembro','outubro','novembro','dezembro'];
 const week=['Seg','Ter','Qua','Qui','Sex','Sáb','Dom'];
 const pad=n=>String(n).padStart(2,'0');
 let year=new Date().getFullYear();
 const $=id=>document.getElementById(id);
 const iso=(y,m,d)=>`${y}-${pad(m)}-${pad(d)}`;
 function renderMonth(month){
  const first=new Date(Date.UTC(year,month,1)),days=new Date(Date.UTC(year,month+1,0)).getUTCDate(),offset=(first.getUTCDay()+6)%7;let content='';
  for(let i=0;i<offset;i++)content+='<span class="month-empty" aria-hidden="true"></span>';
  for(let day=1;day<=days;day++){
   const value=iso(year,month+1,day),holiday=window.RHHolidays.getHoliday(value),today=value===iso(new Date().getFullYear(),new Date().getMonth()+1,new Date().getDate());
   const classes=['month-day',holiday?`is-${holiday.scope}`:'',today?'is-today':''].filter(Boolean).join(' ');
   content+=`<span class="${classes}" ${holiday?`title="${holiday.name} · ${holiday.label}" aria-label="${pad(day)} de ${months[month]}: ${holiday.name}, ${holiday.label}"`:''}>${day}</span>`;
  }
  return `<section class="month-card" aria-label="${months[month]} de ${year}"><h3>${months[month]}</h3><div class="month-weekdays">${week.map(d=>`<span>${d}</span>`).join('')}</div><div class="month-days">${content}</div></section>`;
 }
 function render(){
  $('calendarYear').textContent=year;$('calendarTitle').textContent=`Feriados de ${year}`;$('monthsGrid').innerHTML=months.map((_,i)=>renderMonth(i)).join('');
  const holidays=window.RHHolidays.getYear(year);$('holidayCount').textContent=`${holidays.length} datas`;
  $('holidayList').innerHTML=holidays.map(item=>{const [y,m,d]=item.date.split('-'),label=item.scope==='bahia'?'Bahia':item.scope==='facultativo'?'Ponto facultativo':'Brasil';return `<li><time datetime="${item.date}">${d}/${m}/${y}</time><strong>${item.name}</strong><span class="holiday-badge ${item.scope}">${label}</span></li>`;}).join('');
 }
 $('previousYear').addEventListener('click',()=>{year--;render();});$('nextYear').addEventListener('click',()=>{year++;render();});$('currentYear').addEventListener('click',()=>{year=new Date().getFullYear();render();});
 render();
})();
