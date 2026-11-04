# Equipamentos — 15/10/2026

O Controle de Entregas permite nomes livres e complementos separados por ` - `.
Exemplo: `BOTA - marca X - tamanho 42`. O CA continua em campo próprio.
As sugestões de novas entregas usam BOTA; o histórico conserva BOTA MARLUVAS.

Cada entrega tem identidade permanente. Devoluções e baixas referenciam essa entrega.
O botão **Devolver / Trocar** permite quantidade parcial, data, motivo, observação,
link de evidência e entrega de substituto. Perda/extravio é baixa sem devolução física.
A troca é confirmada em uma transação, com trava do colaborador e validação do saldo.
O identificador da operação impede repetição em uma nova tentativa após falha de rede.

Os comprovantes guardam uma fotografia dos movimentos e dados do colaborador/empresa
em `rh_equipment_receipts`. A ficha completa inclui o histórico; o comprovante inclui
somente os eventos daquela operação. Reemitir um documento existente usa sua fotografia.
Não há envio automático por WhatsApp ou arquivamento automático do PDF no Drive neste fluxo.
Comprovantes externos podem ser vinculados por URL no lançamento.

`rh_equipment_movements` é imutável. RLS aplica o acesso por colaborador e o nível de
edição existente. Não há leitura anônima. O importador preserva os textos e datas legados;
datas desconhecidas permanecem nulas. Não há inferência de devoluções antigas.

`epi_itens`/`fardamento_itens` passam a representar o saldo em posse após cada operação,
preservando as datas por item. O fluxo existente de desligamento recebe esse saldo.
A aba **Movimentações de equipamentos** espelha os eventos por ID, somente para consulta.
Os campos de resumo de equipamentos da aba antiga não são reenviados ao banco.
Demais campos do cadastro continuam com a sincronização existente.

## Publicação

1. Aplicar `../supabase/sql/rh_equipamentos.sql` no projeto RH PRIME.
2. Atualizar o arquivo principal do Apps Script com `../integrations/google-apps-script/google_apps_script_atualizado.js`.
3. Executar `prepararEquipamentosRH` (backup e nova aba); receber os eventos com
   `sincronizarEquipamentosRH`. O recebimento é em lote para evitar limite de execução.
4. Atualizar a implantação existente mantendo URL, conta executora e permissões.
5. Aplicar `../supabase/sql/rh_equipamentos_webhook.sql`, que reutiliza a configuração do webhook existente.
6. Publicar os arquivos web no GitHub Pages.

## Verificação

- `node tests/rh_equipment.test.cjs`: complemento, saldo parcial, vínculo e escape HTML.
- `node tests/rh_equipment_sync.test.cjs`: regressões da sincronização e proteção do histórico.
- `tests/rh_equipamentos.sql`: integração com transação revertida; entrega, troca, saldo,
  idempotência, imutabilidade e ausência de registros parciais após erro.
- `tests/equipment_preview.html`: prévia com dados fictícios, sem acesso ao banco.

O teste legado `rh_sync.test.cjs` contém uma verificação de férias que procura um helper
removido anteriormente de `ferias.html`; esse teste já falha na revisão anterior.
A suíte específica de sincronização de equipamentos reutiliza suas 26 verificações de
sincronização e acrescenta as proteções novas, sem a verificação antiga de férias.

## Transferências de estoque

Na página Estoque, administradores podem usar **Transferir estoque** ou o botão
**Transferir** em uma linha com saldo. Selecione item, tamanho, origem, destino e
quantidade. As filiais 5 e 8 podem enviar e receber entre si. O modal mostra os
saldos atuais e a previsão após transferir; a confirmação relê e valida o saldo.

A transferência grava a saída e a entrada na mesma transação, com um identificador
compartilhado no histórico, data e responsável. Saldo insuficiente, origem igual ao
destino e saldo alterado desde a consulta impedem a transferência. Repetir o mesmo
pedido após falha de resposta não movimenta o estoque novamente.

**Observação é opcional**, tanto nas transferências quanto em Informar quantidade.
Sem texto, o histórico registra a rota da transferência ou “Atualização de estoque”.
A permissão administrativa existente é preservada. Entregas e documentos emitidos
não são alterados por uma transferência.

Aplicar `supabase/sql/rh_estoque_transferencias.sql` após os scripts de estoque já
instalados. `tests/rh_estoque_transferencias.sql` verifica os dois sentidos, tamanho,
saldo insuficiente, observação opcional, permissões e idempotência em transação
revertida, usando apenas um item fictício. `tests/stock_transfer_preview.html` é uma
prévia sem conexão com o banco e com falha de resposta simulável.

O filtro **Item do estoque** é uma lista pesquisável: digitar filtra as opções,
e selecionar aplica o item exato. Os indicadores, saldos, catálogo e histórico seguem
a mesma seleção de item, tipo e filial. **Todos os itens** remove a seleção. Se o
tipo mudar e o item selecionado não pertencer ao novo tipo, a seleção volta para
Todos os itens. A prévia de estoque inclui itens com nomes semelhantes para conferir
que selecionar BOTA não soma BOTA ESPECIAL.

As únicas filiais operacionais registradas são FILIAL 5 e FILIAL 8. O código interno
da empresa 6 (CNPJ de Jequié) não representa uma terceira unidade de estoque.
