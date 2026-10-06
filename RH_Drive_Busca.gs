/* Busca somente leitura. Adicione ao mesmo projeto de RH_Drive_Automacoes.gs.
 * Usa SUPABASE_KEY já configurada. Não cria pastas nem salva vínculos.
 */
function buscarPastaColaboradorRH(data) {
  const employeeId=String(data.employee_id||''), jwt=String(data.access_token||'');
  if(!/^[a-f0-9-]{36}$/i.test(employeeId)||jwt.length>10000||!/^eyJ[A-Za-z0-9_.-]+$/.test(jwt)) throw Error('Busca não autorizada.');
  const props=propriedadesRH(),base=props.getProperty('SUPABASE_URL'),key=props.getProperty('SUPABASE_KEY');
  if(!/^https:\/\/[a-z0-9-]+\.supabase\.co\/?$/.test(base||'')||!key)throw Error('Configuração Supabase ausente.');
  const auth=UrlFetchApp.fetch(base.replace(/\/$/,'')+'/auth/v1/user',{headers:{apikey:key,Authorization:'Bearer '+jwt},muteHttpExceptions:true});
  if(auth.getResponseCode()!==200)throw Error('Sessão inválida. Entre novamente no sistema.');
  const user=JSON.parse(auth.getContentText());
  if(!/^[a-f0-9-]{36}$/i.test(user.id||''))throw Error('Busca não autorizada.');
  // Verifica a aprovação atual no banco; não usa permissões do metadata do usuário.
  const profile=UrlFetchApp.fetch(base.replace(/\/$/,'')+'/rest/v1/profiles?id=eq.'+user.id+'&select=status',{
    headers:{apikey:key,Authorization:'Bearer '+jwt},muteHttpExceptions:true
  });
  if(profile.getResponseCode()!==200)throw Error('Esta busca exige acesso de administrador.');
  const profiles=JSON.parse(profile.getContentText());
  if(profiles.length!==1||profiles[0].status!=='admin')throw Error('Esta busca exige acesso de administrador.');
  const people=bancoDriveRH('funcionarios_epi','get','id=eq.'+employeeId+'&select=id,nome,cpf');
  if(people.length!==1)throw Error('Colaborador indisponível.');
  const employee=people[0],s=bancoDriveRH('rh_automation_settings','get','id=eq.true')[0];
  if(!s||!s.active_folder_id||!s.former_folder_id)throw Error('Configure as pastas de ativos e ex-funcionários antes da busca.');
  const folders=filhosDriveRH(s.active_folder_id).concat(filhosDriveRH(s.former_folder_id)).filter(f=>f.mimeType==='application/vnd.google-apps.folder');
  const linked=bancoDriveRH('rh_drive_links','get','funcionario_id=eq.'+employeeId)[0];
  const bound=linked&&folders.find(f=>f.id===linked.folder_id&&(!(f.appProperties||{}).rh_employee_id||f.appProperties.rh_employee_id===employeeId));
  const matches=bound?[bound]:candidatasPastaRH(folders,employee);
  const unique=Array.from(new Map(matches.map(f=>[f.id,f])).values());
  return {status:'success',employee_id:employeeId,folders:unique.map(f=>({id:f.id,name:f.name,location:(f.parents||[]).includes(s.active_folder_id)?'Funcionários ativos':'Ex-funcionários',linked:!!bound}))};
}
