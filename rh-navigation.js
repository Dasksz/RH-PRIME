(function(){
 'use strict';
 const pages=[['index','EPI/Fardamento','Gestão de segurança'],['colaboradores','Colaboradores','Gestão de colaboradores'],['ferias','Férias','Períodos e histórico'],['indicadores','Indicadores','Indicadores de RH']];
 class RHNavigation extends HTMLElement{
  connectedCallback(){
   if(this.shadowRoot)return;
   const root=this.attachShadow({mode:'open'}),active=this.getAttribute('active')||'index';
   root.innerHTML=`<style>
    :host{display:block;position:sticky;top:0;z-index:50;font:14px system-ui,sans-serif;color:#f1f8fa}
    *{box-sizing:border-box}header{background:var(--rh-header,#102c38);border-bottom:1px solid #344b58;position:relative}
    .bar{display:flex;align-items:center;gap:16px;padding:14px 20px;min-height:76px}.brand{display:flex;align-items:center;gap:12px;margin-right:auto;text-decoration:none;color:inherit;min-width:0}.brand svg{flex:none;color:#e30613}.brand strong{display:block;font-size:21px;line-height:1.15}.brand small{display:block;font-size:10px;letter-spacing:1.3px;text-transform:uppercase;margin-top:4px;color:#adc2cd}
    nav{display:flex;align-items:center;gap:6px}a,button{-webkit-tap-highlight-color:transparent}nav a,button{display:flex;align-items:center;justify-content:center;min-height:44px;padding:10px 12px;border:0;border-radius:8px;color:inherit;background:transparent;font:600 14px system-ui;cursor:pointer;text-decoration:none;white-space:nowrap}nav a[aria-current]{background:#244d57;box-shadow:inset 0 -3px #44c8b1}nav a:hover,button:hover{background:#244d57}a:focus-visible,button:focus-visible{outline:3px solid #5de2b5;outline-offset:2px}.logout{color:#ffb9be}.theme{border:1px solid #587783;gap:6px}.toggle{display:none;width:44px;font-size:24px}.actions{display:flex;align-items:center;gap:6px}.theme-icon{font-size:19px}
    @media(max-width:900px){.bar{padding:12px 16px;gap:8px;min-height:72px}.brand strong{font-size:20px}.brand small{font-size:9px;letter-spacing:.8px}.brand svg{width:25px}.theme{width:44px;padding:8px}.theme-text{display:none}.toggle{display:flex}nav{display:none;position:absolute;top:100%;left:0;right:0;background:var(--rh-header,#102c38);padding:10px 16px 16px;border-bottom:1px solid #344b58;box-shadow:0 8px 14px #0003;max-height:calc(100dvh - 72px);overflow-y:auto;align-items:stretch;gap:6px}nav.open{display:flex;flex-direction:column}nav a,nav .logout{justify-content:flex-start;min-height:44px;padding:12px 14px}nav .logout{border-top:1px solid #344b58;margin-top:4px;border-radius:0;padding-top:14px}}
   </style><header><div class="bar"><a class="brand" href="admin.html" title="Área administrativa"><svg width="28" height="32" viewBox="0 0 24 28" fill="none" stroke="currentColor" stroke-width="2"><path d="M12 2 22 6v8c0 6-10 12-10 12S2 20 2 14V6Z"/></svg><span><strong>PRIME RH</strong><small>${pages.find(p=>p[0]===active)?.[2]||'Gestão de RH'}</small></span></a><nav id="navigation" aria-label="Menu principal">${pages.map(([id,label])=>`<a href="${id}.html" ${id===active?'aria-current="page"':''}>${label}</a>`).join('')}<button class="logout" type="button">Sair</button></nav><div class="actions"><button class="toggle" type="button" aria-label="Abrir menu" aria-controls="navigation" aria-expanded="false">☰</button><button class="theme" type="button"><span class="theme-icon"></span><span class="theme-text"></span></button></div></div></header>`;
   const nav=root.querySelector('nav'),toggle=root.querySelector('.toggle');
   const close=()=>{nav.classList.remove('open');toggle.setAttribute('aria-expanded','false');toggle.setAttribute('aria-label','Abrir menu');toggle.textContent='☰';};
   toggle.onclick=()=>{const open=nav.classList.toggle('open');toggle.setAttribute('aria-expanded',String(open));toggle.setAttribute('aria-label',open?'Fechar menu':'Abrir menu');toggle.textContent=open?'×':'☰';};
   root.addEventListener('keydown',e=>{if(e.key==='Escape'){close();toggle.focus();}});
   nav.querySelectorAll('a').forEach(a=>a.addEventListener('click',close));
   root.querySelector('.brand').onclick=e=>{e.preventDefault();if(window.RHNavigationClient)window.RH.openAdmin(window.RHNavigationClient);};
   root.querySelector('.logout').onclick=async e=>{e.currentTarget.disabled=true;await window.RH.logout(window.RHNavigationClient);};
   root.querySelector('.theme').onclick=()=>window.RHTheme?.toggle();
   const update=()=>{const dark=document.documentElement.dataset.rhTheme==='dark',button=root.querySelector('.theme');button.setAttribute('aria-label',dark?'Ativar tema claro':'Ativar tema escuro');button.title=button.getAttribute('aria-label');button.setAttribute('aria-pressed',String(dark));button.querySelector('.theme-icon').textContent=dark?'☀':'☾';button.querySelector('.theme-text').textContent=dark?'Claro':'Escuro';};
   update();this.observer=new MutationObserver(update);this.observer.observe(document.documentElement,{attributes:true,attributeFilter:['data-rh-theme']});
  }
  disconnectedCallback(){this.observer?.disconnect();}
 }
 customElements.define('rh-navigation',RHNavigation);
})();
