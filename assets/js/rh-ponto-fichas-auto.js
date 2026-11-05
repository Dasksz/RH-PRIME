(function(root,doc){
 'use strict';const $=id=>doc.getElementById(id),title={ficha:'Nova ficha PDF',parcial:'Cobrar parcial',final:'Cobrar ficha completa'};
 const states={informado_rh:'Enviado anteriormente, informado pelo RH',ficha_pendente:'Na fila',aguardando:'Aguardando processamento',enviando:'Enviando',aceito:'Aceito pelo WhatsApp',falha:'Falha no envio',incerto:'Envio incerto — conferir',cancelado:'Cancelado',bloqueado:'Cadastro incompleto'};
 let client,cfg,history=[],approvals=[],busy=false;
 const format=d=>String(d||'').slice(0,10).split('-').reverse().join('/');
 function node(tag,text){const e=doc.createElement(tag);if(text!==undefined)e.textContent=text;return e;}
 function notice(msg){$('sheetAutoNotice').textContent=msg;}
 async function render(){
  const month=$('sheetMonth').value;if(!/^\d{4}-\d{2}$/.test(month))return;
  const {data:dates,error}=await client.rpc('rh_ponto_fichas_datas',{p_mes:month+'-01'});if(error)throw error;
  $('sheetAutoToggle').checked=cfg.ativo;
  $('sheetAutoSchedule').replaceChildren(...Object.entries(title).map(([kind,label])=>{
   const card=node('div');card.append(node('strong',label),node('span',format(dates[kind])+' · autorização às 07h'));
   if(kind==='ficha'&&month+'-01'<cfg.pdf_desde)card.append(node('small','Envio automático a partir de '+format(cfg.pdf_desde)));
   return card;
  }));
  const approvalStates={pendente:'Aguardando resposta 1 ou 2 no WhatsApp do RH',aprovado:'Autorizado pelo RH',recusado:'Não autorizado pelo RH',expirado:'Prazo encerrado sem envio',cancelado:'Solicitação cancelada'};
  $('sheetAutoApprovals').replaceChildren(...approvals.filter(a=>a.mes===month+'-01').map(a=>{
   const repeat=new Date(a.dia_ultima_pergunta+'T12:00:00Z');repeat.setUTCDate(repeat.getUTCDate()+1);
   const extra=a.status==='expirado'&&a.tentativas===1?' · última repetição prevista para '+format(repeat.toISOString())+' às 7h':'';
   return node('p',title[a.tipo]+' — '+approvalStates[a.status]+' · tentativa '+a.tentativas+' de 2'+extra);
  }));
  const rows=history.filter(h=>h.mes===month+'-01');
  $('sheetAutoHistory').replaceChildren(...rows.map(h=>{
   const row=node('tr');row.append(node('td',h.nome),node('td',title[h.tipo]),node('td',states[h.status]||h.status),node('td',h.enviado_em?new Date(h.enviado_em).toLocaleString('pt-BR',{timeZone:'America/Sao_Paulo'}):'—'),node('td',h.erro||''));return row;
  }));
  if(!rows.length){const row=node('tr'),cell=node('td','Nenhum envio registrado neste mês. As etapas serão criadas na data programada.');cell.colSpan=5;row.append(cell);$('sheetAutoHistory').append(row);}
 }
 async function load(){
  const [settings,events,requests]=await Promise.all([
   RH.result(client.from('rh_ponto_fichas_config').select('*').eq('id',true),true),
   RH.fetchAll(client,'rh_ponto_fichas_historico','*','agendado'),
   RH.fetchAll(client,'rh_ponto_fichas_autorizacoes','id,mes,tipo,status,criado_em,expira_em,respondido_em,tentativas,dia_ultima_pergunta','criado_em')
  ]);cfg=settings[0];history=events;approvals=requests;if(!cfg)throw Error('Configuração de envio não encontrada.');await render();
 }
 async function action(fn){if(busy)return;busy=true;$('sheetAutoRefresh').disabled=true;$('sheetAutoToggle').disabled=true;try{await fn();}catch(error){notice(error.message||'Não foi possível atualizar os envios.');}finally{busy=false;$('sheetAutoRefresh').disabled=false;$('sheetAutoToggle').disabled=false;}}
 async function init({supabase,profile}){
  if(profile?.status!=='admin')return;client=supabase;
  $('sheetAutoToggle').onchange=()=>action(async()=>{const active=$('sheetAutoToggle').checked;try{await RH.result(client.from('rh_ponto_fichas_config').update({ativo:active}).eq('id',true).select(),true);}catch(error){$('sheetAutoToggle').checked=cfg.ativo;throw error;}await load();notice(active?'Pedidos de autorização ativados. Nenhum envio ocorre sem sua resposta 1.':'Pedidos e envios pausados.');});
  $('sheetAutoRefresh').onclick=()=>action(async()=>{await load();notice('Histórico atualizado.');});
  $('sheetMonth').addEventListener('change',()=>action(render));
  await action(load);
 }
 root.RHPontoFichasAuto={init,refresh:()=>client&&action(load)};
})(window,document);
