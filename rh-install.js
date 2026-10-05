// Instalação web: não armazena dados de RH em cache e não executa arquivos locais.
if('serviceWorker' in navigator)navigator.serviceWorker.register('./rh-sw.js').catch(()=>{});
let rhInstallPrompt;
window.addEventListener('beforeinstallprompt',event=>{event.preventDefault();rhInstallPrompt=event;const button=document.getElementById('install');if(button){button.hidden=false;button.onclick=async()=>{await rhInstallPrompt.prompt();rhInstallPrompt=null;button.hidden=true;};}});
