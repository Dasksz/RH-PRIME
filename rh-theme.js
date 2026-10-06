(function(){
 'use strict';
 const key='rh-prime-theme';let current='light';try{current=localStorage.getItem(key)==='dark'?'dark':'light';}catch(_){}
 function apply(theme){current=theme;document.documentElement.dataset.rhTheme=theme;document.documentElement.style.colorScheme=theme;try{localStorage.setItem(key,theme);}catch(_){}document.querySelectorAll('[data-rh-theme-toggle]').forEach(button=>{button.setAttribute('aria-pressed',String(theme==='dark'));const label=theme==='dark'?'Ativar tema claro':'Ativar tema escuro';button.setAttribute('aria-label',label);button.title=label;button.textContent=document.body?.classList.contains('rh-login')?(theme==='dark'?'☀':'☾'):(theme==='dark'?'☀ Claro':'☾ Escuro');});}
 apply(current);window.RHTheme={toggle(){apply(current==='dark'?'light':'dark');}};
 document.addEventListener('click',event=>{if(event.target.closest('[data-rh-theme-toggle]'))window.RHTheme.toggle();});
 function mount(){
  const header=document.querySelector('header');let host=header&&(Array.from(header.querySelectorAll('nav')).find(nav=>getComputedStyle(nav).display!=='none')||header);
  if(document.body.classList.contains('rh-login'))host=document.body;
  if(!host){host=document.querySelector('[data-rh-theme-host]');}
  if(!host)return;
  const existing=document.querySelector('[data-rh-theme-toggle]');if(existing){if(existing.parentElement!==host)host.append(existing);return;}
  const button=document.createElement('button');button.type='button';button.dataset.rhThemeToggle='';button.className='rh-theme-toggle';host.append(button);apply(current);
 }
 window.addEventListener('resize',mount);
 document.addEventListener('DOMContentLoaded',()=>{mount();new MutationObserver(mount).observe(document.body,{childList:true,subtree:true});});
})();
