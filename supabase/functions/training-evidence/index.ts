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
  const h={apikey:apiKey,Authorization:'Bearer '+jwt};
  const auth=await fetch(apiUrl+'/auth/v1/user',{headers:h,signal:AbortSignal.timeout(15000)});if(!auth.ok)return reply({error:'Sessão inválida.'},401);
  const user=await auth.json();if(!/^[a-f0-9-]{36}$/i.test(user.id||''))return reply({error:'Sessão inválida.'},401);
  const p=await fetch(apiUrl+'/rest/v1/profiles?id=eq.'+user.id+'&select=status',{headers:h,signal:AbortSignal.timeout(15000)});
  if(!p.ok||(await p.json())[0]?.status!=='admin')return reply({error:'Somente administradores podem anexar comprovantes.'},403);
  const text=await req.text();if(text.length>13983000)return reply({error:'Arquivo maior que 10 MB.'},413);
  const b=JSON.parse(text);if(!/^[a-f0-9-]{36}$/i.test(b.file_id||'')||typeof b.base64!=='string'||!/^[A-Za-z0-9+/]*={0,2}$/.test(b.base64))return reply({error:'Arquivo inválido.'},400);
  const response=await fetch(scriptUrl,{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({action:'training_upload',file_id:b.file_id,base64:b.base64,access_token:jwt}),signal:AbortSignal.timeout(120000)});
  if(!response.ok)return reply({error:'O Drive não confirmou o envio. Tente novamente com o mesmo arquivo.'},502);
  const result=await response.json();if(result.status!=='success')return reply({error:result.message||'Não foi possível arquivar o comprovante.'},502);
  if(result.arquivo?.id!==b.file_id||result.arquivo?.status!=='arquivado')return reply({error:'O arquivamento não foi confirmado.'},502);
  return reply({arquivo:result.arquivo});
 }catch(_){return reply({error:'Não foi possível confirmar o envio. Tente novamente com o mesmo arquivo para evitar duplicação.'},502);}
});
