# RH PRIME — revisão de 04/10/2026 e atualização da sincronização

Analisados: os sete HTMLs do repositório, o script de sincronização, a automação de documentos, os esquemas/permissões/gatilhos do Supabase e as cinco abas existentes de `Controle_EPI_Fardamento_Prime`. Não foram efetuadas operações de escrita no banco ou na planilha, nem executados testes destrutivos em produção. O script implantado no Google não foi lido: as falhas de código abaixo se referem à versão existente no GitHub. Os dados e gatilhos foram consultados diretamente nas integrações conectadas.

## Constatações na planilha e no banco

| Item | Resultado observado |
| --- | --- |
| Controle EPI | 100 cadastros na planilha e 100 no banco; todos com CPF. |
| Movimentações | 171 linhas com nome na planilha e 170 registros no banco; duplicidade nas linhas 109 e 110. No banco, 169 registros não têm CPF. |
| Férias | 101 linhas na planilha e 101 no banco. No banco, 99 registros sem CPF e os outros dois com valores que não têm 11 dígitos. |
| Absenteísmo | 15 registros com nome na planilha e 17 no banco: dois IDs do banco não aparecem na aba. 15 registros do banco estão sem CPF. |
| Regras de EPI | Dois cabeçalhos na aba, mas o script anterior começa na linha 2. O banco contém a função espúria `Função`, confirmando a importação do cabeçalho. Há 18 funções na aba e 20 registros no banco. |
| Cabeçalhos | Movimentações não identifica o CPF no cabeçalho; férias e absenteísmo também têm campos utilizados sem rótulos. |
| Abas ausentes | Não há aba `devolucoes_pendentes`, embora o script anterior a mapeie. |
| Fuso | A planilha está configurada como `America/Los_Angeles`. A nova preparação usa `America/Sao_Paulo`. |
| Webhooks | Há gatilhos para EPI, movimentações, férias e absenteísmo. Não há gatilho de sincronização para empresas, regras de EPI, devoluções ou desligados. |
| Histórico de respostas | 782 respostas disponíveis de 02/10/2026: 220 timeouts, 253 respostas HTML com HTTP 200 e 309 confirmações JSON de atualização. HTTP 200 sozinho não comprova sincronização. Os timeouts também não comprovam, isoladamente, que a alteração deixou de ocorrer no Google. |

## Falhas reproduzidas na versão anterior do script

1. **Exclusão de EPI e de falta não remove a linha da planilha.** O webhook de DELETE traz `record: null`, mas a localização usa `record` em vez de `old_record`.
2. **Renomear movimentação pode duplicar a linha.** A localização procura o nome novo, não o ID ou a identidade anterior.
3. **Horas manuais são sobrescritas.** Uma falta de 2h em um dia útil passa a 8h ao montar o payload para envio ao banco.
4. **Limpar campos não limpa o banco.** Campos vazios são omitidos; apagar uma data de desligamento na planilha conserva o valor anterior no banco.
5. **Colagem de várias linhas processa só a primeira.** O manipulador usa apenas `getRow()`.
6. **A inserção do CNPJ pode deslocar o cadastro.** Escrever em W na próxima linha antes de chamar `appendRow()` altera a última linha e leva os demais campos para a linha seguinte.
7. **Programação de férias e confirmações de devolução não viajam integralmente.** O mapeamento omite datas programadas/retorno, dias programados, histórico e `itens_checked`.
8. **Nomes são usados como identidade em tabelas relacionadas.** Sem ID persistido, renomeações, homônimos, readmissões e várias ocorrências podem atingir a linha errada.
9. **Falhas são ocultadas em algumas operações.** Há requisições com `muteHttpExceptions` sem validação do retorno e sincronização em massa que termina com mensagem de sucesso mesmo após erros.
10. **Desligamento apaga histórico pela planilha.** O script elimina férias e faltas; a tela elimina férias, conserva faltas e não remove o cadastro de EPI. O fluxo depende da origem da edição.
11. **Excluir uma linha manualmente no Sheets não gera exclusão correspondente no banco.** Um gatilho de edição não contém os dados da linha já removida.

## Falhas nos HTMLs e permissões ainda pendentes

- `colaboradores.html`: valida o CPF no formulário de edição, mas não inclui `cpf` no payload de atualização de `funcionarios_epi`. Alterar CPF na tela não o salva ali.
- Renomear ou alterar admissão/carga no cadastro principal não atualiza automaticamente movimentações, férias e faltas relacionadas. Como a maioria não tem CPF, vínculos por nome ficam frágeis.
- Cadastro e desligamento executam várias gravações independentes; diversas respostas `{error}` não são verificadas. Uma etapa pode falhar e a interface anunciar sucesso. O fluxo deve virar uma operação transacional no servidor.
- `ferias.html`: abrir a tela pode avançar o período aquisitivo e zerar dias no mesmo registro, sem acrescentar um histórico. Os 101 registros atuais não têm histórico de períodos preenchido.
- A página de férias e o script usam regras próprias para direitos/proporcionalidade. A regra de retirar 2,5 dias por mês com 15h de faltas e as datas de vencimento devem ser validadas com o responsável de RH antes de alterar cálculos de direito.
- Absenteísmo: o total de um afastamento que atravessa dois meses é atribuído ao mês inicial. Há duas ocorrências desse tipo no banco. O indicador também assume 220h no denominador para um mês completo, independentemente da carga do colaborador; a estimativa usa 8h seg-sex e 4h sábado, sem calendário de jornada/feriados.
- Somente a página principal assina mudanças de `funcionarios_epi` em tempo real. Outras tabelas/telas podem ficar com dados antigos até recarregar.
- Login aceita apenas `aprovado`, mas o admin aceita também `admin`; um perfil com status `admin` pode ser rejeitado nas demais páginas. A tela de detalhes de absenteísmo verifica sessão, sem aprovação do perfil.
- A senha administrativa é lida e comparada no navegador e há fallback público no código. Usuários autenticados têm leitura/escrita da tabela de configuração; o admin HTML aceita um perfil `aprovado`. Essa senha não é uma barreira de autorização no banco.
- `profiles` permite atualizar o próprio perfil, sem uma restrição específica de colunas para `status` nas políticas consultadas. É necessário impedir autoaprovação/alteração de papel no servidor.
- `empresas` e `rh_desligados` têm políticas abertas ao papel público e permissões de leitura/escrita para `anon`. Outras tabelas permitem acesso completo a qualquer autenticado, sem exigir aprovação ou papel administrativo.
- Uma chave `service_role` está publicada no script anterior do repositório público. A nova versão remove a chave literal, mas **não revoga a chave antiga nem a remove do histórico Git**. A chave deve ser rotacionada no Supabase e as integrações dependentes atualizadas. Não foi testada sua validade utilizando essa credencial.
- A reversão administrativa incrementa o contador sem verificar alguns retornos de erro. Logs de INSERT frequentemente não guardam o ID retornado, impossibilitando a exclusão do registro inserido na reversão.
- `AUTOMACAO_ENVIO_DE_DOCUMENTOS/1_Preparar_Holerites.py` contém JSON de um fluxo n8n, não Python executável. O arquivo `.json` tem o mesmo conteúdo. O nome `.py` e o conteúdo não correspondem.

## O que esta atualização implementa

O novo `google_apps_script_atualizado.js` usa IDs persistidos, localiza DELETE pelo registro antigo, usa o estado atual do banco para eventos atrasados, sincroniza todas as linhas editadas, transmite campos vazios explicitamente, mantém horas manuais inclusive zero e rejeita identidades ambíguas. Inclui as colunas de programação de férias, IDs, `itens_checked` e campos de leitura do histórico. Usa bloqueio entre execuções, evita PATCH sem mudanças, pagina leituras e confere as respostas da API. Preserva colunas auxiliares e escreve campos adjacentes em blocos.

A preparação mantém A:W do controle EPI, reconhece o segundo cabeçalho de `epi_funcao`, acrescenta campos faltantes sem remover colunas auxiliares e cria as abas de empresas, devoluções e desligados. Faz uma cópia de segurança antes de alterar a estrutura. O código não embute a chave do banco.

Esta atualização **não** modifica os HTMLs, políticas ou gatilhos do banco. Ela separa sincronização de dados de regras de negócio: não apaga histórico de faltas ou férias ao editar desligamentos na planilha, não cria férias/EPIs por varredura automática de movimentações e não calcula direitos trabalhistas novos. Essas operações precisam ser unificadas com a tela em um fluxo de servidor. Nenhum dado histórico foi corrigido ou apagado nesta revisão.

## Como atualizar manualmente no Apps Script

1. Na planilha `Controle_EPI_Fardamento_Prime`, abra **Extensões → Apps Script**. Guarde uma cópia do código atualmente implantado. Ele pode ser diferente do arquivo no GitHub; se tiver funções adicionais, confira antes de substituir.
2. Substitua o código de sincronização pelo conteúdo integral de `google_apps_script_atualizado.js`. Não mantenha funções duplicadas `doPost`, `onEdit`, `onOpen` ou constantes com o mesmo nome em outros arquivos `.gs`.
3. Em **Configurações do projeto → Propriedades do script**, configure:

| Propriedade | Valor |
| --- | --- |
| `SUPABASE_URL` | `https://gcksbfstheavpfgcdndb.supabase.co` |
| `SUPABASE_KEY` | Chave privilegiada válida, mantida somente nas propriedades. Use a nova chave após rotacionar a exposta. |
| `SPREADSHEET_ID` | `1wJJu3N-lehjZaQw2JtfWLXdss6YbVP1JbfveDzWkGRg` |
| `WEBHOOK_TOKEN` | Opcional durante a transição. Ative somente quando a URL dos gatilhos tiver `?token=VALOR` correspondente. Não comite esse valor no GitHub. |

4. Configure também o fuso do projeto como `America/Sao_Paulo`. Execute **`prepararEstruturaRH`** e autorize os acessos. Ela cria backup e prepara as abas; não envia linhas para o banco.
5. Confira as linhas 109 e 110 da aba `movimentacoes`. Compare o conteúdo completo e mantenha uma identidade única por registro. Não remova uma linha com informações distintas sem revisão. Há nomes duplicados na planilha e a nova versão interrompe a atualização dessas identidades para evitar sobrescrever a linha errada.
6. Execute **`sincronizarBancoParaPlanilha`** antes de enviar qualquer planilha ao banco. Isso preenche IDs, recebe as faltas ausentes e restaura campos com o valor atual do banco. Veja **Execuções**: recebimento parcial é reportado como erro e outras abas continuam a ser processadas. Essa função não remove linhas extras automaticamente. Na aba de regras, o cadastro espúrio `Função` é ignorado.
7. Preencha/reconcilie CPFs ausentes ou inválidos usando o cadastro principal como referência. Não trate valores de saldo como CPF. Não execute o envio em massa enquanto houver essas inconsistências.
8. Execute **`instalarGatilhoRH`**. Ele instala um gatilho de edição autorizado e remove os gatilhos antigos `onEdit`/`syncToSupabaseOnEdit` dessa planilha visíveis para a conta atual. Gatilhos de outras contas devem ser conferidos por seus proprietários.
9. Em **Implantar → Gerenciar implantações**, edite a implantação já usada pelos webhooks, escolha **Nova versão** e implante. Preserve a URL `/exec`; apenas salvar o editor não atualiza a versão publicada. Confira a execução como proprietário e o acesso necessário para as chamadas do Supabase.
10. Teste uma edição simples na tela, confirme o banco e a célula correspondente; depois altere uma célula no Sheets, confirme a execução do gatilho e recarregue a tela. Confirme também exclusões e programação de férias com registros próprios para teste. Os testes locais não substituem a validação da implantação e das credenciais.

**Alterações feitas pela API Google Sheets, inclusive por um conector, não disparam o gatilho de edição.** Depois de uma atualização programática que deve ir ao banco, execute uma função de envio ou use o backend diretamente. Apagar uma linha manualmente também não apaga o banco: use a operação de exclusão do sistema e confira o webhook. Não programe sincronização bidirecional cega para tentar compensar isso.

Para fechar o ciclo de todas as abas, faltam gatilhos do banco para `empresas`, `epi_funcao`, `devolucoes_pendentes` e `rh_desligados`, autenticação do webhook e tratamento/reconciliação das falhas de entrega. `WEBHOOK_TOKEN` permanece opcional somente para compatibilidade de transição; o endpoint não tem autenticação enquanto a propriedade não estiver configurada.

## Validação desta alteração

`node --check google_apps_script_atualizado.js`

`node tests/rh_sync.test.cjs`

23 testes com serviços simulados: horas manuais/zero/estimativa, limpeza explícita, datas/CPF inválidos, campos somente de leitura, segundo cabeçalho, DELETE por identidade, renomeação, eventos atrasados, inserção de EPI+CNPJ na mesma linha, zeros iniciais, deduplicação de PATCH, conflitos, prevenção de recriação de linha excluída, colagem múltipla, token, preservação de colunas auxiliares e erro HTTP. Não fizeram requisições reais nem alteraram produção.

Referências: [Gatilhos instaláveis](https://developers.google.com/apps-script/guides/triggers/installable), [Aplicativos da Web](https://developers.google.com/apps-script/guides/web), [Webhooks Supabase](https://supabase.com/docs/guides/database/webhooks).
