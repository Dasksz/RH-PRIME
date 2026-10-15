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

1. Aplicar `rh_equipamentos.sql` no projeto RH PRIME.
2. Atualizar o arquivo principal do Apps Script com `google_apps_script_atualizado.js`.
3. Executar `prepararEquipamentosRH` (backup e nova aba); receber os eventos com
   `sincronizarEquipamentosRH`. O recebimento é em lote para evitar limite de execução.
4. Atualizar a implantação existente mantendo URL, conta executora e permissões.
5. Aplicar `rh_equipamentos_webhook.sql`, que reutiliza a configuração do webhook existente.
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
