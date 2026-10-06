/* Utilidades compartilhadas: identidade, erros, datas e atualização das telas. */
(function (global) {
  'use strict';
  const cleanCpf = value => String(value || '').replace(/\D/g, '');
  function validCpf(value) {
    const cpf = cleanCpf(value);
    if (!/^\d{11}$/.test(cpf) || /^(\d)\1{10}$/.test(cpf)) return false;
    for (let n = 9; n < 11; n++) {
      let sum = 0; for (let i = 0; i < n; i++) sum += Number(cpf[i]) * (n+1-i);
      let digit = (sum*10)%11; if (digit === 10) digit = 0;
      if (digit !== Number(cpf[n])) return false;
    }
    return true;
  }
  async function result(promise, expectRow) {
    const response = await promise;
    if (response.error) throw response.error;
    if (expectRow && (!response.data || (Array.isArray(response.data) && !response.data.length))) throw new Error('Nenhum registro foi confirmado. Atualize a tela e confira sua permissão.');
    return response.data;
  }
  async function fetchAll(client, table, columns='*', order='id') {
    const list=[];
    for (let offset=0;;offset+=1000) {
      const page = await result(client.from(table).select(columns).order(order,{ascending:true}).range(offset,offset+999));
      list.push(...page); if(page.length<1000) return list;
    }
  }
  function today() {
    const parts=new Intl.DateTimeFormat('en-CA',{timeZone:'America/Sao_Paulo',year:'numeric',month:'2-digit',day:'2-digit'}).formatToParts(new Date());
    const values=Object.fromEntries(parts.map(p=>[p.type,p.value]));return values.year+'-'+values.month+'-'+values.day;
  }
  function date(value) {
    if (!value) return null;
    let text=String(value).split('T')[0];
    if (/^\d{2}\/\d{2}\/\d{4}$/.test(text)) text=text.split('/').reverse().join('-');
    const d=new Date(text+'T12:00:00'); return Number.isNaN(d.getTime()) ? null : d;
  }
  function archivePeriod(record, changes) {
    const { historico_periodos, ...period } = record;
    return [...(historico_periodos || []), { ...period, ...changes }];
  }
  function absByMonth(records) {
    return records.flatMap(record => {
      const start=date(record.data_inicio), end=date(record.data_fim);
      if (!start || !end || end < start) return [record];
      const weights={},days={}; let total=0;
      for(let d=new Date(start);d<=end;d.setDate(d.getDate()+1)) {
        const month=String(d.getMonth()+1).padStart(2,'0')+'/'+d.getFullYear();
        const weight=d.getDay()===0?0:d.getDay()===6?4:8;
        weights[month]=(weights[month]||0)+weight;days[month]=(days[month]||0)+1;total+=weight;
      }
      const basis=total ? weights : days;
      const sum=Object.values(basis).reduce((a,b)=>a+b,0);
      return Object.keys(basis).map(month=>({...record,mes_ref:month,horas_perdidas:(Number(record.horas_perdidas)||0)*basis[month]/sum}));
    });
  }
  function watch(client,tables,refresh) {
    let timer,closed=false;
    const schedule=()=>{clearTimeout(timer);timer=setTimeout(()=>{if(!closed) refresh();},250);};
    const channel=client.channel('rh-'+tables.join('-')+'-'+Math.random().toString(36).slice(2));
    tables.forEach(table=>channel.on('postgres_changes',{event:'*',schema:'public',table},schedule));
    channel.subscribe();
    const focus=()=>{if(document.visibilityState==='visible') schedule();};
    window.addEventListener('focus',focus);document.addEventListener('visibilitychange',focus);
    return ()=>{closed=true;clearTimeout(timer);client.removeChannel(channel);window.removeEventListener('focus',focus);document.removeEventListener('visibilitychange',focus);};
  }
  async function profile(client) {
    const {data:{session},error}=await client.auth.getSession();
    if(error)throw error;if(!session)throw new Error('Faça login para continuar.');
    const p=await result(client.from('profiles').select('status').eq('id',session.user.id).single(),true);
    if(!['aprovado','admin'].includes(p.status)) throw new Error('Cadastro pendente de aprovação.');
    return p;
  }
  async function openAdmin(client) {
    try { const p=await profile(client);if(p.status!=='admin') throw new Error('Esta área exige acesso de administrador.');window.location.href='admin.html'; }
    catch(error){window.alert(error.message);}
  }
  async function logout(client) {
    const storageKey = client.auth.storageKey || 'sb-gcksbfstheavpfgcdndb-auth-token';
    let timer;
    try {
      await Promise.race([
        client.auth.signOut({scope:'local'}).catch(() => null),
        new Promise(resolve => { timer=setTimeout(resolve,4000); })
      ]);
    } finally {
      clearTimeout(timer);
      // Limpa somente a sessão deste projeto, inclusive se a rede falhar.
      for (const storage of [localStorage,sessionStorage]) {
        try { storage.removeItem(storageKey);storage.removeItem(storageKey+'-code-verifier'); } catch (_) {}
      }
      window.location.replace('login.html');
    }
  }
  global.RH={cleanCpf,validCpf,result,fetchAll,today,date,archivePeriod,absByMonth,watch,profile,openAdmin,logout};
})(window);
