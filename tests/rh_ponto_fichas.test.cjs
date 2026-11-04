const {test}=require('node:test'),assert=require('node:assert/strict');
const F=require('../assets/js/rh-ponto-fichas-core.js');
const companies=[{id:1,nome:'Prime Matriz',cnpj:'52.522.019/0001-00'},{id:2,nome:'Prime Filial',cnpj:'52.522.019/0002-82'},{id:3,nome:'Nunes & Vieira',cnpj:'48.986.353/0001-39'}];
test('mês civil, fevereiro bissexto e fins de semana sem deslocamento de fuso',()=>{
 const days=F.monthDays('2026-11');assert.equal(days.length,30);assert.equal(days[0].date,'2026-11-01');assert.equal(days[0].weekday,0);assert.equal(days[19].weekday,5);
 assert.equal(F.monthDays('2028-02').length,29);assert.equal(F.monthDays('2027-02').length,28);assert.equal(F.monthDays('2026-12').length,31);
 for(const m of ['2026-13','2026-00','2026-2','bad','1999-11','2101-01'])assert.throws(()=>F.monthDays(m));
});
test('não transforma ponto facultativo em feriado nem preenche horários',()=>{
 const days=F.monthDays('2026-11',d=>({name:'Data teste',scope:d.endsWith('20')?'brasil':'facultativo'}));
 assert.equal(days.filter(d=>d.holiday).length,1);assert.equal(days[19].holiday.scope,'brasil');assert.equal(days[0].holiday,null);
});
test('empresa canônica prevalece sobre rótulo legado e sobre filial operacional',()=>{
 assert.equal(F.resolveCompany({nome:'Pessoa',empresa_id:3,local_registro:'PRIME ILHÉUS',unidade:'FILIAL 8'},companies).id,3);
 assert.equal(F.resolveCompany({nome:'Pessoa',local_registro:'PRIME DISTRIBUICAO - JEQUIÉ'},companies).id,2);
 assert.throws(()=>F.resolveCompany({nome:'Pessoa',empresa_id:99,local_registro:'NUNES'},companies),/não encontrada/);
 assert.throws(()=>F.resolveCompany({nome:'Pessoa',unidade:'FILIAL 8'},companies),/Defina a empresa/);
 assert.equal(F.cpf('00124876510'),'001.248.765-10');
});
test('vínculo fora do mês é excluído; desligamento dentro do mês é preservado',()=>{
 assert.equal(F.eligible({admissao:'2026-12-01'},'2026-11'),false);
 assert.equal(F.eligible({data_desligamento:'2026-10-31'},'2026-11'),false);
 assert.equal(F.eligible({admissao:'21/11/2026',data_desligamento:'2026-11-30'},'2026-11'),true);
});
test('PDF multipágina tem xref correto, dados escapados e empresas separadas',()=>{
 const employee={nome:'Pessoa (Teste) São João',funcao:'Promotor de Vendas',cpf:'00124876510'};
 const bytes=F.pdf({month:'2026-11',sheets:[{company:companies[0],employee,city:'Ilhéus'},{company:companies[2]}]});
 const text=new TextDecoder().decode(bytes);assert.ok(text.startsWith('%PDF-1.4'));assert.match(text,/\/Count 2/);assert.match(text,/Prime Matriz/);assert.match(text,/Nunes & Vieira/);assert.match(text,/001\.248\.765-10/);assert.match(text,/Pessoa \\\(Teste\\\)/);
 const start=Number(text.match(/startxref\n(\d+)/)[1]);assert.equal(text.slice(start,start+4),'xref');
 for(const line of text.slice(start).split('\n').filter(l=>/^\d{10} 00000 n/.test(l))){const offset=Number(line.slice(0,10));assert.match(text.slice(offset,offset+20),/^\d+ 0 obj/);}
 assert.throws(()=>F.pdf({month:'2026-11',sheets:[{company:companies[0],employee:{nome:'Cadastro incompleto'}}]}),/Complete nome/);
 assert.throws(()=>F.pdf({month:'2026-11',sheets:[]}),/Nenhuma ficha/);
});
