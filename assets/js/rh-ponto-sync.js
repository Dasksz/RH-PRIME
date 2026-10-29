(function(root){
 'use strict';
 const duration=seconds=>{const n=Math.max(0,Math.round(seconds));return Math.floor(n/60)+'min '+String(n%60).padStart(2,'0')+'s';};
 async function request(invoke,body,timeoutMs=120000){
  let timer;try{return await Promise.race([invoke(body),new Promise((_,reject)=>{timer=setTimeout(()=>reject(Error('O servidor demorou a responder. Esta consulta pode ainda concluir no banco. Confira a última atualização antes de tentar novamente.')),timeoutMs);})]);}finally{clearTimeout(timer);}
 }
 async function run({ids,windows,invoke,onProgress=()=>{},timeoutMs=120000}){
  const state={total:ids.length*windows.length,done:0,success:0,failed:0,issues:[]};onProgress({...state,phase:'starting'});
  for(const window of windows){for(let i=0;i<ids.length;i+=3){
   const batch=ids.slice(i,i+3);onProgress({...state,phase:'querying',batch,window});
   try{
    const response=await request(invoke,{inicio:window.start,fim:window.end,funcionarios:batch},timeoutMs);
    if(response.error||response.data?.error)throw Error(response.data?.error||'Não foi possível chamar a integração. Confira sua sessão e tente novamente.');
    const rows=response.data?.resultados;
    if(!Array.isArray(rows)||rows.length!==batch.length||new Set(rows.map(r=>r.funcionario_id)).size!==batch.length||rows.some(r=>!batch.includes(r.funcionario_id)||typeof r.sucesso!=='boolean'))throw Error('A resposta não confirmou todos os colaboradores. Confira a última atualização antes de repetir.');
    for(const row of rows){state.done++;if(row.sucesso)state.success++;else{state.failed++;state.issues.push({id:row.funcionario_id,message:row.erro||'Consulta não concluída.'});}}
    onProgress({...state,phase:'received',batch,window});
   }catch(error){state.error=error.message||'Consulta interrompida.';onProgress({...state,phase:'interrupted'});return state;}
  }}return state;
 }
 const api={duration,request,run};if(typeof module!=='undefined'&&module.exports)module.exports=api;else root.RHPontoSync=api;
})(typeof window==='undefined'?globalThis:window);
