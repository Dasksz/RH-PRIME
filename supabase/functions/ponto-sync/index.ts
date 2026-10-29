// A página chama esta função autenticada; credenciais e resposta do fornecedor ficam no servidor/banco.
const apiUrl = Deno.env.get('SUPABASE_URL')!;
const publicKey = JSON.parse(Deno.env.get('SUPABASE_PUBLISHABLE_KEYS') || '{}').default || Deno.env.get('SUPABASE_ANON_KEY')!;
const serverKey = JSON.parse(Deno.env.get('SUPABASE_SECRET_KEYS') || '{}').default || Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
const statuses = new Set(['Aprovado (Auto)','Aprovado Manualmente','Rejeitado (Auto)','Pendente','Reprovado Manualmente','Abono/Atestado']);
const uuid = /^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$/i;
function validDate(value: unknown): value is string {
 return typeof value === 'string' && /^\d{4}-\d{2}-\d{2}$/.test(value) && !Number.isNaN(Date.parse(value)) && new Date(value).toISOString().slice(0,10) === value;
}
function validatePoints(value: unknown, start: string, end: string) {
 if(!Array.isArray(value) || value.length>10000)throw Error('Formato de resposta inesperado. Dados anteriores preservados.');
 return value.map(p=>{
  if(!p || typeof p!=='object' || !['E','S'].includes(p.entrada_saida) || !['A','M'].includes(p.tipo_registro) || !statuses.has(p.situacao) || typeof p.data_hora!=='string' || !/^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}$/.test(p.data_hora) || !validDate(p.data_hora.slice(0,10)) || p.data_hora.slice(0,10)<start || p.data_hora.slice(0,10)>end || !/^([01]\d|2[0-3]):[0-5]\d:[0-5]\d$/.test(p.data_hora.slice(11)) || (p.obs!==null && p.obs!==undefined && (typeof p.obs!=='string'||p.obs.length>4000)))throw Error('Marcação fora do contrato. Dados anteriores preservados.');
  return {entrada_saida:p.entrada_saida,tipo_registro:p.tipo_registro,data_hora:p.data_hora,situacao:p.situacao,obs:p.obs??null};
 });
}
async function rest(resource: string, body?: unknown) {
 const headers:Record<string,string>={apikey:serverKey,'Content-Type':'application/json'};
 if(!serverKey.startsWith('sb_secret_'))headers.Authorization='Bearer '+serverKey;
 const r=await fetch(apiUrl+'/rest/v1/'+resource,{method:body===undefined?'GET':'POST',headers,body:body===undefined?undefined:JSON.stringify(body),signal:AbortSignal.timeout(15000)});
 if(!r.ok)throw Error('Não foi possível acessar o banco de ponto.');
 return r.json();
}
Deno.serve(async(req: Request)=>{
 const origin=req.headers.get('origin');
 const headers:Record<string,string>={'Content-Type':'application/json','Cache-Control':'no-store',Vary:'Origin','Access-Control-Allow-Headers':'authorization, x-client-info, apikey, content-type','Access-Control-Allow-Methods':'POST, OPTIONS'};
 if(origin==='https://dasksz.github.io')headers['Access-Control-Allow-Origin']=origin;
 const reply=(body:unknown,status=200)=>new Response(JSON.stringify(body),{status,headers});
 if(origin&&origin!=='https://dasksz.github.io')return reply({error:'Origem não autorizada.'},403);
 if(req.method==='OPTIONS')return new Response(null,{status:204,headers});
 if(req.method!=='POST')return reply({error:'Método inválido.'},405);
 const authorization=req.headers.get('authorization')||'';
 if(!/^Bearer eyJ[A-Za-z0-9_.-]+$/.test(authorization)||authorization.length>10000)return reply({error:'Entre novamente no RH.'},401);
 try {
  const authHeaders={apikey:publicKey,Authorization:authorization};
  const auth=await fetch(apiUrl+'/auth/v1/user',{headers:authHeaders,signal:AbortSignal.timeout(15000)});
  if(!auth.ok)return reply({error:'Sessão inválida.'},401);
  const user=await auth.json();if(!uuid.test(user.id||''))return reply({error:'Sessão inválida.'},401);
  const profile=await fetch(apiUrl+'/rest/v1/profiles?id=eq.'+user.id+'&select=status',{headers:authHeaders,signal:AbortSignal.timeout(15000)});
  if(!profile.ok)return reply({error:'Administrador obrigatório.'},403);
  const profiles=await profile.json();if(profiles.length!==1||profiles[0].status!=='admin')return reply({error:'Administrador obrigatório.'},403);
  const text=await req.text();if(text.length>2048)return reply({error:'Pedido muito grande.'},400);
  const body=JSON.parse(text),start=body.inicio,end=body.fim,ids=body.funcionarios;
  const today=new Intl.DateTimeFormat('en-CA',{timeZone:'America/Sao_Paulo',year:'numeric',month:'2-digit',day:'2-digit'}).format(new Date());
  if(!validDate(start)||!validDate(end)||end<start||end>today||(Date.parse(end)-Date.parse(start))/86400000>62||!Array.isArray(ids)||ids.length<1||ids.length>3||ids.some(id=>typeof id!=='string'||!uuid.test(id))||new Set(ids).size!==ids.length)return reply({error:'Informe até três colaboradores e um período válido de até 63 dias.'},400);
  const employees=await rest('funcionarios_epi?select=id,cpf&id=in.('+ids.join(',')+')');
  if(employees.length!==ids.length)return reply({error:'Colaborador não encontrado.'},400);
  const secrets=await rest('rpc/rh_ponto_segredos',{}),results=[];
  for(const employee of employees){
   const began=new Date().toISOString();let points=null,error=null;
   try{
    const cpf=String(employee.cpf||'').replace(/\D/g,'');if(!/^\d{11}$/.test(cpf)||/^(\d)\1{10}$/.test(cpf))throw Error('CPF inválido no cadastro.');
    const params=new URLSearchParams({chave_empresa:secrets.rh_facilita_empresa,senha_integracao:secrets.rh_facilita_senha_sha1,matricula:cpf,data_inicio:start,data_fim:end});
    const response=await fetch('https://api.facilitaponto.com.br/registroponto/lista_pontos?'+params,{signal:AbortSignal.timeout(18000),redirect:'error'});
    if(!response.ok)throw Error('Facilita Ponto respondeu HTTP '+response.status+'.');
    const responseText=await response.text();if(responseText.length>2097152)throw Error('Resposta acima do limite permitido.');
    let parsed;try{parsed=JSON.parse(responseText);}catch{throw Error('O fornecedor não retornou JSON válido.');}
    points=validatePoints(parsed,start,end);
   }catch(e){error=e instanceof Error&&/^(CPF inválido|Facilita Ponto respondeu|Resposta acima|O fornecedor|Formato de resposta|Marcação fora)/.test(e.message)?e.message:'Falha de conexão com o Facilita Ponto; dados anteriores preservados.';}
   const consultation=await rest('rpc/rh_ponto_salvar_consulta',{p_funcionario:employee.id,p_inicio:start,p_fim:end,p_iniciado:began,p_registros:points,p_erro:error,p_por:user.id});
   results.push({funcionario_id:employee.id,consulta_id:consultation,sucesso:error===null,quantidade:points?.length||0,erro:error});
  }
  return reply({resultados:results});
 }catch{return reply({error:'Não foi possível concluir a sincronização. Confira a configuração e tente novamente.'},500);}
});
