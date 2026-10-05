// Somente rede. Não guarda páginas autenticadas, PDFs, tokens ou dados de colaboradores.
self.addEventListener('install',()=>self.skipWaiting());
self.addEventListener('activate',event=>event.waitUntil(self.clients.claim()));
self.addEventListener('fetch',()=>{});
