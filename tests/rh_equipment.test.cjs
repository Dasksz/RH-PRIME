const fs=require('node:fs'),vm=require('node:vm'),assert=require('node:assert/strict');
const ctx={window:{},React:{createElement(){}},console};vm.createContext(ctx);vm.runInContext(fs.readFileSync('rh-ficha-padrao.js','utf8'),ctx);ctx.RHFichaPadrao=ctx.window.RHFichaPadrao;vm.runInContext(fs.readFileSync('rh-equipamentos.js','utf8'),ctx);
const api=ctx.window.RHEquipment;
assert.equal(api.needsReview({id:'old',saldo:1,data_movimento:'2026-01-14'},{},'2026-10-16'),true);
assert.equal(api.needsReview({id:'recent',saldo:2,data_movimento:'2026-09-18'},{},'2026-10-16'),false);
assert.equal(api.needsReview({id:'old',saldo:0,data_movimento:'2026-01-14'},{},'2026-10-16'),false);
assert.equal(api.needsReview({id:'old',saldo:1,data_movimento:'2026-01-14'},{old:{data_verificacao:'2026-10-01'}},'2026-10-16'),false);
assert.equal(api.latestCorrections([{entrega_id:'a',created_at:'2026-10-15',primeiro_nome:'Ana'},{entrega_id:'a',created_at:'2026-10-16',primeiro_nome:'Daniel'}]).a.primeiro_nome,'Daniel');
assert.equal(api.nameParts('BOTA - MARCA X - tamanho 42').equipamento,'BOTA');
assert.equal(api.nameParts('BOTA - MARCA X - tamanho 42').complemento,'MARCA X - tamanho 42');
const rows=[{id:'a',tipo:'entrega',quantidade:2,descricao:'BOTA <img>',data_movimento:'2026-08-04',ca:'123',operacao_id:'old'},{id:'b',tipo:'devolucao',quantidade:1,entrega_origem_id:'a',motivo:'Rasgo',data_movimento:'2026-10-15',operacao_id:'new'},{id:'c',tipo:'entrega',quantidade:1,entrega_origem_id:'a',descricao:'BOTA - NOVA',data_movimento:'2026-10-15',operacao_id:'new'}];
assert.equal(api.balances(rows)[0].saldo,1);assert.equal(api.balances(rows)[1].saldo,1);
const receipt={id:'new',created_at:'2026-10-15T15:00:00Z',snapshot:{colaborador:{nome:'TESTE <script>',cpf:'000',funcao:'TESTE',local_registro:'EMPRESA'},movimentos:rows,categoria:'epi'}};
const full=api.documentHtml(receipt,false),swap=api.documentHtml(receipt,true);
assert.ok(full.includes('BOTA &lt;img&gt;'));assert.ok(!full.includes('<script>'));assert.ok(swap.includes('Rasgo'));assert.ok(swap.includes('BOTA - NOVA'));assert.ok(swap.includes('Reposição referente à entrega de 04/08/2026'));
assert.ok(full.includes('FICHA INDIVIDUAL DE FARDAMENTO E EQUIPAMENTO DE PROTEÇÃO INDIVIDUAL'));
for(const term of ['Termo de Responsabilidade','Obrigações do Empregador','Obrigações dos Colaboradores','Termo de Movimentação e Responsabilidade de EPI','DATA DE<br>DEVOLUÇÃO','MOTIVO DA<br>DEVOLUÇÃO']) assert.ok(swap.includes(term),term);
assert.ok(!swap.includes('Termo de Recebimento (Entrega)'));assert.ok(!swap.includes('Termo de Devolução'));
assert.equal((swap.match(/Assinatura do Colaborador/g)||[]).length,1);assert.ok(swap.includes('confirmo a devolução dos itens indicados para devolução e o recebimento dos itens indicados como entregues'));
const projected=api.documentRows(receipt,false);assert.equal(projected.filter(x=>x.nomeItem.includes('BOTA &lt;img&gt;')).reduce((n,x)=>n+x.qtd,0),2);assert.equal(projected.filter(x=>x.dataDevolucao).length,1);assert.equal(api.documentRows(receipt,true).length,2);
assert.ok(full.includes('15/10/2026'));assert.ok(full.includes('Rasgo'));
const historyReceipt={...receipt,id:'future',snapshot:{...receipt.snapshot,movimentos:rows}};
const historyHtml=api.documentHtml(historyReceipt,false);assert.ok(historyHtml.includes('histórico de devoluções'));assert.ok(historyHtml.includes('Rasgo'));assert.ok(historyHtml.includes('15/10/2026'));assert.equal((historyHtml.match(/Assinatura do Colaborador/g)||[]).length,1);
const deliveryReceipt={...receipt,id:'delivery-only',snapshot:{...receipt.snapshot,movimentos:[rows[0]]}};
const deliveryHtml=api.documentHtml(deliveryReceipt,false);assert.ok(deliveryHtml.includes('Termo de Recebimento de EPI'));assert.ok(deliveryHtml.includes('confirmo o recebimento dos itens registrados como entregues'));assert.equal((deliveryHtml.match(/Assinatura do Colaborador/g)||[]).length,1);
rows.push({id:'d',tipo:'baixa',quantidade:1,entrega_origem_id:'a',motivo:'Perda / extravio',data_movimento:'2026-10-15',operacao_id:'new'});
assert.equal(api.balances(rows)[0].saldo,0);assert.ok(api.documentHtml(receipt,true).includes('Baixa sem devolução'));
console.log('OK: descrição, devolução parcial, vínculo, baixa sem devolução, ficha e escape HTML');

// O cabeçalho, as obrigações, o termo de responsabilidade e as seis colunas
// devem permanecer idênticos aos templates do gerador anterior.
const original=fs.readFileSync('index.html','utf8').replace(/\r\n/g,'\n');
const standard=fs.readFileSync('rh-ficha-padrao.js','utf8').replace(/\r\n/g,'\n');
for(const pattern of [/let pageContent = isFirstPage\s*\?\s*`([\s\S]*?)`\s*:\s*"";/,/const generateTableHeaders = \(\) => \x60([\s\S]*?)\x60;/]){
 assert.equal(standard.match(pattern)?.[1],original.match(pattern)?.[1]);
 assert.ok(original.match(pattern));
}
console.log('OK: cabeçalho, textos do termo e colunas idênticos ao código anterior');

const checksReceipt={...receipt,id:'check-only',snapshot:{...receipt.snapshot,verificacoes:[{id:'v1',entrega_id:'c',operacao_id:'check-only',data_verificacao:'2026-10-15',created_at:'2026-10-15T12:00:00Z'}]}};
const checkHtml=api.documentHtml(checksReceipt,false);assert.ok(checkHtml.includes('Verificado em 15/10/2026'));assert.ok(checkHtml.includes('Termo de Movimentação e Responsabilidade de EPI'));assert.ok(checkHtml.includes('histórico de devoluções'));assert.ok(!checkHtml.includes('Termo de Recebimento (Entrega)'));assert.equal(api.documentRows(checksReceipt,false).find(x=>x.nomeItem.includes('Verificado em')).dataEntrega,'2026-10-15');
const oldReceipt={id:'old',snapshot:{...receipt.snapshot,movimentos:[{id:'a',tipo:'entrega',quantidade:1,descricao:'BOTA',data_movimento:'2026-01-02',operacao_id:'old'}],verificacoes:[{id:'v',entrega_id:'a',operacao_id:'check',data_verificacao:'2026-10-15'}]}};
assert.equal(api.documentRows(oldReceipt,false)[0].dataEntrega,'2026-01-02');assert.ok(api.documentHtml(oldReceipt,false).includes('Verificado em 15/10/2026'));console.log('OK: conferência visível na ficha, termo adequado e data original preservada');
