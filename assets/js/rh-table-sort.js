/* Ordenação independente por tabela; mantém filtros, ações e foco no cabeçalho. */
(function(global){
 'use strict';
 const states=new WeakMap(),collator=new Intl.Collator('pt-BR',{numeric:true,sensitivity:'base'});
 function value(row,column,type){
  const cell=row.cells[column],raw=cell?.dataset.sortValue??cell?.textContent.trim()??'';
  if(type==='number')return Number(raw.replace(/\./g,'').replace(',','.'))||0;
  if(type==='date')return Date.parse(raw)||0;
  return raw;
 }
 function sort(table,state){
  if(state.column===null)return;
  const body=table.tBodies[0];if(!body)return;
  const rows=Array.from(body.rows).map((row,index)=>({row,index}));
  rows.sort((a,b)=>{const av=value(a.row,state.column,state.type),bv=value(b.row,state.column,state.type);const order=state.type==='text'?collator.compare(av,bv):av-bv;return (state.direction==='ascending'?order:-order)||a.index-b.index;});
  const fragment=document.createDocumentFragment();rows.forEach(({row})=>fragment.append(row));body.append(fragment);
 }
 function refresh(root=document){
  root.querySelectorAll('table[data-sortable]').forEach(table=>{
   let state=states.get(table);
   if(!state){
    state={column:null,direction:null,type:'text'};states.set(table,state);
    table.querySelectorAll('thead th[data-sort-type]').forEach((header,column)=>{
     const label=header.textContent.trim(),type=header.dataset.sortType,button=document.createElement('button'),arrow=document.createElement('span');
     button.type='button';button.className='rh-sort-heading';arrow.className='rh-sort-arrow';arrow.setAttribute('aria-hidden','true');arrow.textContent='↕';button.append(document.createTextNode(label),arrow);header.replaceChildren(button);header.setAttribute('aria-sort','none');
     const update=()=>{table.querySelectorAll('thead th[data-sort-type]').forEach((th,index)=>{const active=index===state.column,b=th.querySelector('button'),next=active&&state.direction==='ascending'?'decrescente':active?'crescente':th.dataset.sortType==='text'?'crescente':'decrescente';if(!b)return;th.setAttribute('aria-sort',active?state.direction:'none');b.title='Ordenar '+b.firstChild.textContent+' em ordem '+next;b.querySelector('span').textContent=active?(state.direction==='ascending'?'↑':'↓'):'↕';});};
     button.onclick=()=>{state.direction=state.column===column?(state.direction==='ascending'?'descending':'ascending'):(type==='text'?'ascending':'descending');state.column=column;state.type=type;sort(table,state);update();};
     update();
    });
   }
   sort(table,state);
  });
 }
 global.RHTableSort={refresh};
})(window);

