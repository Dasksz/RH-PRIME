// Autentica o administrador antes de consultar o Apps Script, que repete a validação.
const apiUrl=Deno.env.get('SUPABASE_URL')!;
const apiKey=JSON.parse(Deno.env.get('SUPABASE_PUBLISHABLE_KEYS')||'{}')['default']||'sb_publishable_UrTJ8_SyM3n800C4LZQWpw_5Ah8Ko98';
const scriptUrl=Deno.env.get('RH_APPS_SCRIPT_URL')||'https://script.google.com/macros/s/AKfycbxiOCFqmTythI4H9Lemp_b_9fsZcJrDZX-CBGWleVq0jV22EDtYASP5XmnWE5_7vqqg/exec';
Deno.serve(async(req:Request)=>{
  const origin=req.headers.get('origin'),headers:Record<string,string>={'Content-Type':'application/json','Cache-Control':'no-store','Vary':'Origin','Access-Control-Allow-Headers':'authorization, x-client-info, apikey, content-type','Access-Control-Allow-Methods':'POST, OPTIONS'};
  if(origin==='https://dasksz.github.io')headers['Access-Control-Allow-Origin']=origin;
  const reply=(body:unknown,status=200)=>new Response(JSON.stringify(body),{status,headers});
  if(origin&&origin!=='https://dasksz.github.io')return reply({error:'Origem não autorizada.'},403);
  if(req.method==='OPTIONS')return new Response(null,{status:204,headers});
  if(req.method!=='POST')return reply({error:'Método inválido.'},405);
  const jwt=(req.headers.get('authorization')||'').replace(/^Bearer /i,'');
  if(jwt.length>10000||!/^eyJ[A-Za-z0-9_.-]+$/.test(jwt))return reply({error:'Entre novamente no sistema.'},401);
  try{
    const authHeaders={apikey:apiKey,Authorization:'Bearer '+jwt};
    const auth=await fetch(apiUrl+'/auth/v1/user',{headers:authHeaders,signal:AbortSignal.timeout(15000)});
    if(!auth.ok)return reply({error:'Sessão inválida. Entre novamente no sistema.'},401);
    const user=await auth.json();
    if(!/^[a-f0-9-]{36}$/i.test(user.id||''))return reply({error:'Sessão inválida.'},401);
    const profile=await fetch(apiUrl+'/rest/v1/profiles?id=eq.'+user.id+'&select=status',{headers:authHeaders,signal:AbortSignal.timeout(15000)});
    if(!profile.ok)return reply({error:'Esta busca exige acesso de administrador.'},403);
    const profiles=await profile.json();
    if(profiles.length!==1||profiles[0].status!=='admin')return reply({error:'Esta busca exige acesso de administrador.'},403);
    const text=await req.text();if(text.length>1024)return reply({error:'Pedido inválido.'},400);
    const body=JSON.parse(text);
    if(!/^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$/i.test(body.employeeId||''))return reply({error:'Escolha um colaborador.'},400);
    const response=await fetch(scriptUrl,{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({action:'lookup_folder',employee_id:body.employeeId,access_token:jwt}),signal:AbortSignal.timeout(45000)});
    if(!response.ok)return reply({error:'Não foi possível consultar o Apps Script. Confira a implantação.'},502);
    let result;
    try{result=await response.json();}catch(_){return reply({error:'A implantação do Apps Script não respondeu à busca. Confira o acesso e a versão publicada.'},502);}
    if(result.status!=='success'){
      const missing=/Evento inválido|Webhook não autorizado|buscarPastaColaboradorRH/.test(result.message||'');
      return reply({error:missing?'Instale o arquivo RH_Drive_Busca e atualize a implantação do Apps Script para habilitar esta busca.':result.message||'Não foi possível buscar a pasta.'},502);
    }
    if(result.employee_id!==body.employeeId||!Array.isArray(result.folders))return reply({error:'Resposta da busca inválida.'},502);
    return reply(result);
  }catch(_){return reply({error:'Não foi possível concluir a busca. Tente novamente ou informe o ID manualmente.'},502);}
});
