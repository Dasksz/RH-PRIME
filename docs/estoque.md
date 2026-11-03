# Estoque por filial e tamanho

Abra `estoque.html` pelo menu Estoque. O estoque tem somente dois tipos: EPI e Fardamento. O filtro e o cadastro usam a mesma categoria das entregas. Administradores podem cadastrar, renomear, unificar e informar quantidades; usuários aprovados consultam os saldos dentro do seu acesso existente.

1. Confira os itens importados do histórico. Selecione as funções autorizadas e ajuste os tamanhos; use ÚNICO para itens sem numeração. A seleção Todas as funções libera qualquer cargo. Sem funções selecionadas, novas entregas ficam bloqueadas.
2. Informe o saldo físico de cada item, tamanho e filial em **Informar quantidade**. O valor é o total disponível após a conferência, e não a quantidade a somar. O motivo fica no histórico. O sistema começa sem saldo informado; entregas antigas não descontam o estoque inicial.
3. Na entrega, escolha o item e tamanho cadastrados. O sistema confere a função, a filial atual do colaborador e o saldo no servidor. Uma entrega de 2 desconta 2 apenas daquela filial/tamanho. Faltando saldo, toda a operação é revertida. Uma repetição da mesma operação não desconta novamente.
4. Devoluções avariadas e baixas não voltam automaticamente ao estoque disponível. Após conferir condições de reutilização, registre a quantidade física disponível e o motivo no estoque. Correções de novas entregas ajustam a diferença no depósito original, mesmo se a pessoa mudar de filial depois. Correções do histórico anterior à implantação não geram descontos retroativos.

## Nomes e cadastros antigos

**Editar / renomear** conserva a identificação permanente do item, seus vínculos e saldos. O histórico do sistema, os resumos em posse, a planilha espelhada e novas fichas usam o nome atual. Os aliases antigos continuam reconhecidos, inclusive por telas que já estavam abertas.

Se o nome desejado já pertence a outro cadastro, abra **Substituir por outro cadastro existente** e escolha qual será mantido. A unificação soma os saldos por filial e tamanho, reúne as entregas e os tamanhos e inativa a origem. As regras de função do destino são mantidas. O histórico de auditoria conserva a nomenclatura original; documentos já emitidos ou assinados conservam sua fotografia de emissão.

## Implantação

`supabase/sql/rh_estoque.sql` cria catálogo, aliases, vínculos e saldos protegidos. `rh_estoque_finalize.sql` integra o resumo e a unificação. A ativação instala `zz_stock_equipment` após INSERT/UPDATE de `rh_equipment_movements`. O gatilho de `rh_product_events` reutiliza o endpoint existente da planilha. Não existe novo fluxo n8n ou envio de mensagens neste recurso.

O Apps Script usa `readTable: rh_equipment_current` ao ler movimentos e trata o evento de catálogo atualizando a aba somente de consulta. O projeto instalado recebeu apenas esse ajuste sobre a versão existente, preservando a conciliação por CPF presente no Google.

O catálogo contém os 22 nomes distintos (desconsiderando caixa/espaços) dos 341 movimentos existentes. Sinônimos não foram unificados sem escolha do RH. Filiais seguem os valores atuais do cadastro: FILIAL 5 e FILIAL 8.

## Validação

`tests/rh_estoque_transaction.sql` verifica no banco: filiais isoladas, quantidade, repetição, falta de saldo, tamanho, função, renomeação, unificação, correção e preservação de documentos. Todos os dados do teste são revertidos. Leitura e escrita por usuário sem aprovação foram verificadas como bloqueadas.

`node --test tests/rh_equipment.test.cjs` passou. A suíte completa manteve o resultado da revisão de origem: 125 testes aprovados e 15 falhas anteriores (mocks de interface/ponto, chave legada e sincronização), confirmado em checkout separado.
