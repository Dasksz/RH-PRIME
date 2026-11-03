/* Ordenação por tabela; valores de tela nunca alteram os dados do cadastro. */
(function(global){
 'use strict';
 const states=new WeakMap(),collator=new Intl.Collator('pt-BR',{numeric:true,sensitivity:'base'});
 let observer=null,observing=false;
 function parse(value,type){
  if(value===null||value===undefined||String(value).trim()===''||/^(—|-|não informad[oa])$/i.test(String(value).trim()))return null;
  const raw=String(value).trim();
  if(type==='number'){const match=raw.match(/[−+\-]?\s*\d[\d.,]*/);if(!match)return null;const text=match[0].replace(/\s/g,'').replace('−','-');return Number(text.includes(',')?text.replace(/\./g,'').replace(',','.'):/^[+\-]?\d{1,3}(?:\.\d{3})+$/.test(text)?text.replace(/\./g,''):text);}
  if(type==='hours'){const match=raw.match(/([−+\-]?)\s*(\d+)[:h](\d{2})(?::(\d{2}))?/);if(!match)return null;return (match[1]==='-'||match[1]==='−'?-1:1)*(Number(match[2])*60+Number(match[3])+Number(match[4]||0)/60);}
  if(type==='date'){const match=raw.match(/\b(\d{2})\/(\d{2})\/(\d{4})\b/);const date=Date.parse(match?match[3]+'-'+match[2]+'-'+match[1]:raw);return Number.isNaN(date)?null:date;}
  return raw;
 }
 function compare(a,b,type='text',direction='ascending'){
  const av=parse(a,type),bv=parse(b,type);if(av===null)return bv===null?0:1;if(bv===null)return -1;
  const order=type==='text'?collator.compare(av,bv):av-bv;return direction==='descending'?-order:order;
 }
 function sort(table,state){
  if(state.column===null)return;const body=table.tBodies[0];if(!body)return;
  const original=Array.from(body.rows),rows=original.map((row,index)=>({row,index}));
  const value=row=>{const cell=row.cells[state.column];return cell?.dataset.sortValue??cell?.textContent.trim()??'';};
  rows.sort((a,b)=>compare(value(a.row),value(b.row),state.type,state.direction)||a.index-b.index);
  if(rows.every(({row},index)=>row===original[index]))return;
  const fragment=document.createDocumentFragment();rows.forEach(({row})=>fragment.append(row));body.append(fragment);
 }
 function refresh(root=document){
  observer?.disconnect();
  root.querySelectorAll('table[data-sortable]').forEach(table=>{
   let state=states.get(table);
   if(!state){
    state={column:null,direction:null,type:'text'};states.set(table,state);
    const headers=Array.from(table.querySelectorAll('thead th'));
    const update=()=>headers.forEach((th,index)=>{if(!th.dataset.sortType)return;const b=th.querySelector('.rh-sort-heading');if(!b)return;const active=index===state.column,next=active?(state.direction==='ascending'?'decrescente':'crescente'):th.dataset.sortType==='text'?'crescente':'decrescente';th.setAttribute('aria-sort',active?state.direction:'none');b.title='Ordenar '+b.firstChild.textContent+' em ordem '+next;b.querySelector('span').textContent=active?(state.direction==='ascending'?'↑':'↓'):'↕';});
    headers.forEach((header,column)=>{
     if(!header.dataset.sortType)return;
     const label=header.textContent.trim(),type=header.dataset.sortType,button=document.createElement('button'),arrow=document.createElement('span');
     button.type='button';button.className='rh-sort-heading';arrow.className='rh-sort-arrow';arrow.setAttribute('aria-hidden','true');button.append(document.createTextNode(label),arrow);header.replaceChildren(button);
     button.onclick=()=>{state.direction=state.column===column?(state.direction==='ascending'?'descending':'ascending'):(type==='text'?'ascending':'descending');state.column=column;state.type=type;refresh(table.parentElement);update();};
    });update();
   }
   sort(table,state);
  });
  if(observing)observer.observe(document.body,{childList:true,subtree:true});
 }
 function start(){
  observer=new MutationObserver(records=>{if(records.some(r=>r.target.closest?.('table[data-sortable]')||Array.from(r.addedNodes).some(n=>n.nodeType===1&&(n.matches?.('table[data-sortable]')||n.querySelector?.('table[data-sortable]')))))refresh();});
  observing=true;refresh();
 }
 global.RHTableSort={refresh,compare,parse};
 if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',start,{once:true});else start();
})(window);

