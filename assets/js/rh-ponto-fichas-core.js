/* Fichas mensais A4 vetoriais, sem horários preenchidos e sem bibliotecas externas. */
(function(root,factory){
 'use strict';const api=factory();
 if(typeof module==='object'&&module.exports)module.exports=api;
 else root.RHPontoFichasCore=api;
})(typeof globalThis!=='undefined'?globalThis:this,function(){
 'use strict';
 const digits=value=>String(value||'').replace(/\D/g,'');
 const norm=value=>String(value||'').normalize('NFD').replace(/[\u0300-\u036f]/g,'').toUpperCase();
 const pad=n=>String(n).padStart(2,'0');
 const cpf=value=>{const n=digits(value);return n.length===11?n.replace(/(\d{3})(\d{3})(\d{3})(\d{2})/,'$1.$2.$3-$4'):String(value||'');};
 const cnpj=value=>{const n=digits(value);return n.length===14?n.replace(/(\d{2})(\d{3})(\d{3})(\d{4})(\d{2})/,'$1.$2.$3/$4-$5'):String(value||'');};
 function resolveCompany(employee,companies){
  if(employee.empresa_id!=null){
   const linked=companies.find(c=>String(c.id)===String(employee.empresa_id));
   if(!linked)throw Error('Empresa de registro não encontrada para '+employee.nome+'.');
   return linked;
  }
  const local=norm(employee.local_registro),explicit=digits(employee.local_registro);
  const found=companies.find(c=>digits(c.cnpj)===explicit);
  if(found)return found;
  const wanted=local.includes('NUNES')?'48986353000139':local.includes('JEQUIE')?'52522019000282':local.includes('PRIME')?'52522019000100':'';
  const company=companies.find(c=>wanted&&digits(c.cnpj)===wanted);
  if(!company)throw Error('Defina a empresa de registro no cadastro de '+employee.nome+'.');
  return company;
 }
 function monthDays(month,holiday=()=>null){
  if(!/^\d{4}-(0[1-9]|1[0-2])$/.test(String(month)))throw Error('Selecione um mês válido.');
  const [y,m]=month.split('-').map(Number);
  if(y<2000||y>2100)throw Error('Escolha um ano entre 2000 e 2100.');
  return Array.from({length:new Date(Date.UTC(y,m,0)).getUTCDate()},(_,i)=>{
   const day=i+1,date=month+'-'+pad(day),weekday=new Date(date+'T12:00:00Z').getUTCDay(),h=holiday(date);
   return {date,day,weekday,holiday:h&&['brasil','bahia','municipal'].includes(h.scope)?h:null};
  });
 }
 function eligible(employee,month){
  const days=monthDays(month),first=days[0].date,last=days.at(-1).date;
  const iso=value=>{const v=String(value||'').slice(0,10);return /^\d{2}\/\d{2}\/\d{4}$/.test(v)?v.split('/').reverse().join('-'):v;};
  return (!employee.data_desligamento||iso(employee.data_desligamento)>=first)&&(!employee.admissao||iso(employee.admissao)<=last);
 }
 // Escape Windows-1252 text as octal, keeping the complete PDF and xref byte offsets ASCII.
 function literal(value){
  return '('+String(value??'').replace(/[\r\n\t]/g,' ').replace(/[–—]/g,'-').split('').map(ch=>{
   const n=ch.charCodeAt(0);if('\\()'.includes(ch))return '\\'+ch;
   if(n>=32&&n<=126)return ch;
   if(n>=160&&n<=255)return '\\'+n.toString(8).padStart(3,'0');
   return '?';
  }).join('')+')';
 }
 function pageStream(month,company,employee,city,holiday){
  if(!company?.nome||digits(company.cnpj).length!==14)throw Error('Empresa sem nome ou CNPJ válido. Confira o cadastro.');
  if(employee&&(!employee.nome||!employee.funcao||digits(employee.cpf).length!==11))throw Error('Complete nome, função e CPF no cadastro de '+(employee.nome||'colaborador')+'.');
  const days=monthDays(month,holiday),cmd=[],number=n=>Number(n.toFixed(2)),height=841.89;
  const text=(x,y,t,size=9,bold=false)=>cmd.push(`0 g BT /${bold?'F2':'F1'} ${size} Tf ${number(x)} ${number(y)} Td ${literal(t)} Tj ET`);
  const line=(x1,y1,x2,y2)=>cmd.push(`0.55 G 0.4 w ${number(x1)} ${number(y1)} m ${number(x2)} ${number(y2)} l S`);
  const rect=(x,y,w,h,gray)=>cmd.push(`${gray} g ${number(x)} ${number(y)} ${number(w)} ${number(h)} re f`);
  const blank='________________________________________________________';
  text(28,height-36,'FICHA DE PONTO MANUAL',14,true);
  text(408,height-36,month.slice(5)+' / '+month.slice(0,4),12,true);
  text(28,height-55,company.nome.slice(0,90),10,true);
  text(28,height-70,'CNPJ: '+cnpj(company.cnpj),9);line(28,height-79,567,height-79);
  text(28,height-96,'Colaborador(a): '+(employee?.nome||blank),9);
  text(28,height-114,'CPF / Matrícula: '+(employee?cpf(employee.cpf):'_______________________'),9);
  text(270,height-114,'Função: '+(employee?.funcao||'____________________________'),8.5);
  text(28,height-132,'Cidade de trabalho: '+(city||blank),9);
  const top=height-145,header=26,row=Math.min(17,480/days.length),xs=[28,68,98,151,210,269,322,416,567];
  rect(28,top-header,539,header,.9);
  const labels=[['Dia'],['Sem.'],['Entrada'],['Saída para','intervalo'],['Retorno do','intervalo'],['Saída'],['Assinatura'],['Ocorrência / observação']];
  labels.forEach((ls,i)=>ls.forEach((s,j)=>text(xs[i]+4,top-(ls.length===1?16:10)-j*9,s,i===7?7:7.4,true)));
  days.forEach((d,i)=>{
   const y=top-header-(i+1)*row;
   if(d.holiday||d.weekday===0)rect(28,y,539,row,d.holiday?.scope?.length?0.93:0.97);
   text(32,y+5,pad(d.day)+'/'+month.slice(5),8,!!d.holiday);
   text(72,y+5,['Dom','Seg','Ter','Qua','Qui','Sex','Sáb'][d.weekday],8,!!d.holiday);
   if(d.holiday){
    const name=d.holiday.name.replace('Dia Nacional de Zumbi e da Consciência Negra','Consciência Negra');
    if(name.length>32){text(420,y+8,'Feriado',6.8);text(420,y+1,name.slice(0,38),6.4);}
    else text(420,y+5,'Feriado - '+name,7);
   }
  });
  const bottom=top-header-days.length*row;
  xs.forEach(x=>line(x,top,x,bottom));line(28,top,567,top);
  for(let i=0;i<=days.length;i++)line(28,top-header-i*row,567,top-header-i*row);
  let y=bottom-14;
  const notes=['Preencha diariamente os horários reais (HH:MM). Anote folgas, faltas e afastamentos em Ocorrência.',
   'Domingos e feriados: registre os horários se houver trabalho; caso contrário, identifique o motivo.',
   'Feriados municipais da cidade de trabalho devem ser anotados em Ocorrência, quando aplicáveis.'];
  notes.forEach(s=>{text(28,y,s,7.4);y-=12;});
  text(28,y-9,'Observações / justificativas: ______________________________________________________________',8);
  text(28,y-26,'____________________________________________________________________________________',8);
  text(28,y-44,'Conferi os registros acima e registrei eventuais divergências nas observações.',8);
  line(28,y-69,310,y-69);text(28,y-80,'Assinatura do(a) colaborador(a)',8);
  text(402,y-66,'Data: ____ / ____ / ________',8);
  return cmd.join('\n')+'\n';
 }
 function pdf({month,sheets,holiday=()=>null}){
  if(!Array.isArray(sheets)||!sheets.length)throw Error('Nenhuma ficha para gerar.');
  if(sheets.length>500)throw Error('Gere até 500 fichas por lote.');
  const streams=sheets.map(s=>pageStream(month,s.company,s.employee,s.city,holiday));
  const objects=['<< /Type /Catalog /Pages 2 0 R >>','',
   '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica /Encoding /WinAnsiEncoding >>',
   '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica-Bold /Encoding /WinAnsiEncoding >>'];
  const kids=[];
  streams.forEach(stream=>{const page=objects.length+1,content=page+1;kids.push(`${page} 0 R`);
   objects.push(`<< /Type /Page /Parent 2 0 R /MediaBox [0 0 595.28 841.89] /Resources << /Font << /F1 3 0 R /F2 4 0 R >> >> /Contents ${content} 0 R >>`);
   objects.push(`<< /Length ${stream.length} >>\nstream\n${stream}endstream`);
  });
  objects[1]=`<< /Type /Pages /Count ${streams.length} /Kids [${kids.join(' ')}] >>`;
  let output='%PDF-1.4\n',offsets=[0];objects.forEach((obj,i)=>{offsets.push(output.length);output+=`${i+1} 0 obj\n${obj}\nendobj\n`;});
  const xref=output.length;output+=`xref\n0 ${objects.length+1}\n0000000000 65535 f \n`;
  offsets.slice(1).forEach(n=>{output+=String(n).padStart(10,'0')+' 00000 n \n';});
  output+=`trailer\n<< /Size ${objects.length+1} /Root 1 0 R >>\nstartxref\n${xref}\n%%EOF\n`;
  return new TextEncoder().encode(output);
 }
 return {cpf,cnpj,resolveCompany,monthDays,eligible,pdf};
});
