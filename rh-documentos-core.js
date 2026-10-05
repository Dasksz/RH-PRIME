(function(root){
'use strict';
function normalize(s){return String(s||'').normalize('NFD').replace(/[\u0300-\u036f]/g,'').toUpperCase().replace(/[^A-Z0-9 ]/g,' ').replace(/\s+/g,' ').trim();}
function digits(s){return String(s||'').replace(/\D/g,'');}
function validCpf(s){const p=digits(s);if(!/^\d{11}$/.test(p)||/^(\d)\1{10}$/.test(p))return false;for(let n=9;n<11;n++){let sum=0;for(let i=0;i<n;i++)sum+=+p[i]*(n+1-i);let k=sum*10%11;if(k===10)k=0;if(k!==+p[n])return false;}return true;}
function identify(text,employees){
 const cpfs=[...new Set((text.match(/(?<!\d)\d{3}\.?\d{3}\.?\d{3}-?\d{2}(?!\d)/g)||[]).map(digits).filter(validCpf))];
 let matches;
 if(cpfs.length){if(cpfs.length!==1)throw Error('Página contém múltiplos CPFs; revise.');matches=employees.filter(e=>digits(e.cpf)===cpfs[0]);}
 else{const t=' '+normalize(text)+' ';matches=employees.filter(e=>normalize(e.nome).length>5&&t.includes(' '+normalize(e.nome)+' '));}
 if(matches.length!==1)throw Error('Identificação ausente ou ambígua. Revise o PDF.');
 if(matches[0].data_desligamento)throw Error('Colaborador desligado: envio automático bloqueado.');
 return matches[0];
}
function phone(s){let p=digits(s);if([10,11].includes(p.length))p='55'+p;if(!/^55[1-9]\d\d{8,9}$/.test(p))throw Error('WhatsApp inválido no cadastro.');return p;}
function message(template,values){return template.replace(/\{([^{}]+)\}/g,(_,key)=>{if(!['nome','tipo','competencia','link'].includes(key))throw Error('Variável desconhecida: '+key);return values[key]||'';});}
const api={normalize,digits,validCpf,identify,phone,message};if(typeof module!=='undefined'&&module.exports)module.exports=api;else root.RHDocuments=api;
})(typeof window==='undefined'?globalThis:window);
