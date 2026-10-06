(function(){
 'use strict';
 function enhance(){
  document.querySelectorAll('body.rh-admin table:not(.rp-table)').forEach(table=>{
   table.classList.add('rh-admin-records');table.setAttribute('role','table');
   const headers=Array.from(table.querySelectorAll('thead th')).map(th=>th.textContent.trim());
   table.querySelectorAll('thead input[type=checkbox]').forEach(el=>el.setAttribute('aria-label','Selecionar todos os registros'));
   table.querySelectorAll('tbody tr').forEach(row=>{
    row.setAttribute('role','row');
    Array.from(row.children).forEach((cell,i)=>{cell.setAttribute('role','cell');cell.dataset.label=headers[i]||'Seleção';cell.querySelectorAll('input[type=checkbox]').forEach(el=>el.setAttribute('aria-label','Selecionar registro'));});
   });
  });
 }
 document.addEventListener('DOMContentLoaded',()=>{enhance();new MutationObserver(enhance).observe(document.body,{childList:true,subtree:true});});
})();
