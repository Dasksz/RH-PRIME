# Entregas históricas sem desconto de estoque

Ao escolher uma data anterior a hoje (São Paulo), o formulário de EPI ou fardamento apresenta **Registrar sem descontar do estoque atual**. A opção começa desmarcada e é individual por item. Serve para registrar entregas antigas já consideradas no saldo atual, inclusive com estoque zerado.

- Sem marcar: a entrega continua descontando o estoque e exige saldo suficiente.
- Marcada: preserva a data informada e registra a entrega, o responsável e a opção, sem alterar o saldo, a versão do estoque ou gerar um movimento fictício.
- Ao voltar a data para hoje, a opção desaparece e é desmarcada. Cada item novo exige uma nova escolha; editar um item preparado preserva sua escolha.
- O resumo antes de salvar e o histórico identificam os lançamentos sem desconto. A ficha guarda a opção no snapshot, mantendo a apresentação do recibo do colaborador.

O banco valida a regra também fora da interface: a opção só é aceita para entregas anteriores ao dia de registro e não pode ser modificada depois de salvar. Correções e exclusões desses registros não criam descontos ou estornos. As permissões existentes, o catálogo, as regras por função e os tamanhos continuam sendo conferidos.

## Verificação

`tests/historical_stock_delivery_rollback.sql` foi executado no banco conectado, com reversão integral. Cobre EPI e fardamento, saldo zero, confirmação da opção no snapshot, repetição segura, bloqueio da opção para hoje, desconto obrigatório quando desmarcada, correções, exclusão sem estorno e lote misto.

`tests/retroactive_equipment_preview.html` usa dados fictícios e serviços simulados. A interface foi conferida para inclusão com saldo zero, preservação ao editar, reinício ao voltar para hoje, anotação no histórico e disponibilidade na aba de fardamento.

O teste existente `tests/rh_equipment.test.cjs` também passou, incluindo as verificações de descrição, devolução, vínculo e documento.
