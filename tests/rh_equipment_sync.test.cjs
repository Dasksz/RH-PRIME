const fs=require('fs'),vm=require('vm');const source=fs.readFileSync('tests/rh_sync.test.cjs','utf8').split("test('férias excluem")[0];
const extra=`
test('resumo de equipamentos não pode apagar histórico pelo envio da planilha',()=>{
 const {ctx}=environment();
 const p=ctx.buildPayload('Controle EPI e Fardamento',{nome:'TESTE',cpf:'12345678901',epi_itens:'BOTA - TAMANHO 42',epi_data:'15/10/2026',fardamento_itens:'CAMISA'});
 assert.equal('epi_itens' in p,false);assert.equal('epi_data' in p,false);assert.equal('fardamento_itens' in p,false);
});
test('histórico não pode ser alterado por sincronização reversa',()=>{
 const {ctx,config}=environment();
 assert.equal(config['Movimentações de equipamentos'].readOnlyAll,true);
 assert.equal(ctx.sincronizarLinhaRH(null,2,config['Movimentações de equipamentos'],{}),'somente_leitura');
 assert.throws(()=>ctx.buildPayload('Movimentações de equipamentos',{id:'test'}),/somente leitura/);
});
test('nomes com complemento são copiados literalmente e sem fórmulas',()=>{
 const env=environment(),config=env.config['Movimentações de equipamentos'];
 env.db.funcionarios_epi=[{id:'emp',nome:'TESTE'}];
 const sheet=new env.Sheet('Movimentações de equipamentos',[config.fields.concat(config.extra)]);
 env.ctx.escreverRegistroRH(sheet,config,env.ctx.layoutRH(sheet,config,false),2,{id:'test',funcionario_id:'emp',descricao:'BOTA - MARCA X - TAMANHO 42',observacao:'=IMPORTXML("https://example.invalid")'});
 assert.equal(sheet.rows[1][config.fields.indexOf('descricao')],'BOTA - MARCA X - TAMANHO 42');
 assert.equal(sheet.rows[1][config.fields.indexOf('observacao')].startsWith("'="),true);
});
console.log(checks+' verificações de sincronização concluídas.');`;
vm.runInNewContext(source+extra,{require,process,console,URL},{filename:'tests/rh_equipment_sync.test.cjs'});
