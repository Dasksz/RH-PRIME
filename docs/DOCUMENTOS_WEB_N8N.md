# Preparar PDFs para assinatura no Facilita Ponto

O fluxo principal da página Documentos agora é: separar e conferir → baixar ZIP → extrair e carregar os PDFs manualmente no Facilita Ponto → disponibilizar para assinatura → confirmar o lote e autorizar avisos. Os arquivos usam `CPF-TIPO - NOME MM-AAAA.pdf`, sem espaços junto ao hífen após o CPF. A competência anual aceita `AAAA`.

O ZIP contém os PDFs selecionados na raiz e `_controle_do_lote/manifest.json`. Guarde o ZIP: os bytes ficam no computador, sem upload para Supabase ou Drive nesta etapa. O banco guarda somente os nomes, hashes, vínculos de colaboradores e histórico dos avisos. Se o registro falhar após o download, importe o `manifest.json` pelo campo de controle do lote. Baixar novamente a mesma seleção na sessão conserva o identificador do lote; reimportar o mesmo controle é idempotente.

Depois de disponibilizar todos os documentos, marque a confirmação no lote e autorize os avisos. Um aviso por colaborador contém o portal `https://sistema.facilitaponto.com.br/portal`, login com CPF e código da empresa **032612**. A confirmação representa a declaração do operador, sem consultar a API do Facilita Ponto. Não há integração automática de upload ou consulta de assinatura. Telefones inválidos/desligados ficam bloqueados; após corrigir, use a mesma ação do lote, que não reenfileira avisos já aprovados.

A nova tela usa `../supabase/sql/rh_documentos_facilita.sql` (já aplicado na instância RH PRIME em 29/10/2026). Mantém a fila e o processador Apps Script existentes, com `source=link` e link do portal. Assim, o processador não chama o upload ou a liberação de permissões de PDF para esses avisos. O histórico e as configurações antigas permanecem recolhidos para consulta. Nenhum envio antigo foi cancelado ou reenviado por esta atualização.

O n8n recebe somente `chatId`, `caption`, `session` e `documentId`, no contrato já usado pelo fluxo web. **Aceito** não comprova entrega ou assinatura. Resultados incertos exigem conferência no n8n, sem repetição automática. A implementação usa o fluxo de texto existente; as ferramentas n8n RH disponíveis nesta sessão não oferecem leitura/edição de workflows, portanto não houve alteração nem disparo real no n8n.

## Python separado

O preparador foi recuperado da cópia anterior de 07/10/2026. A primeira etapa conserva o processamento original e acrescenta `CPF-` ao nome dos PDFs quando há CPF identificado; documentos sem CPF conservam o comportamento anterior e exibem aviso para revisão. Não se inventa matrícula. A proteção por senha do PDF foi preservada: confira no Facilita Ponto se o arquivo foi aceito antes de avisar o colaborador.

A segunda etapa gerada como `2_Enviar_WhatsApp.py` envia exclusivamente avisos de disponibilidade do Facilita Ponto. Não faz upload, não altera permissões nem envia links do Drive ou anexos. Só inclui ativos no relatório com PDF existente; deduplica colaboradores e pede confirmação explícita de publicação e autorização de avisos. O histórico fica em `avisos_facilita.json`, separado dos logs antigos; não exclua esse arquivo para tentar novamente um resultado incerto.

Para lotes já existentes, copie a versão nova de `2_Enviar_WhatsApp.py` para a pasta com `Relatorio_Mapeamento.xlsx`. O script público `2_Avisar_Facilita.py` pede o webhook existente ou lê `N8N_RH_WEBHOOK_URL`; o preparador preserva o webhook usado na versão anterior. Se faltarem referências de tipo ou competência, a etapa avulsa pede esses campos antes da confirmação.

---

## Referência do fluxo anterior (histórico)

# Importação de PDFs e envio ao n8n pelo navegador

## Recursos disponíveis

A página `documentos-web.html` lê PDFs com texto no próprio navegador, identifica colaboradores por CPF válido ou nome único, separa por quantidade de páginas informada, mostra uma prévia para download/conferência e permite selecionar todos ou alguns documentos prontos. Documentos digitalizados sem texto, grupos com pessoas diferentes, colaboradores desligados e telefones inválidos ficam bloqueados. OCR e execução de Python/BAT não estão implementados no navegador.

Somente a seleção confirmada é importada para um bucket privado do Supabase. Depois o Apps Script organiza os PDFs na pasta vinculada do colaborador, por Tipo/Ano/Mês. Folha de ponto também usa a subpasta JORNADA E SEGURANÇA. Libera apenas os PDFs individuais como Qualquer pessoa com o link — Leitor, sem alterar a permissão das pastas.

O PDF separado não recebe criptografia por senha nesta versão. O armazenamento temporário do Supabase é privado; os PDFs no Drive ficam acessíveis para leitura por link conforme a configuração autorizada. Confira o acesso do colaborador ao link, ou informe um link válido do portal de documentos antes de autorizar a mensagem. Não use a mensagem antiga do Python que promete senha se o PDF não estiver protegido dessa forma.

Após upload: selecione os documentos prontos, confira telefone/link/mensagem e autorize. O processador chama o novo webhook n8n usando `chatId`, `caption`, `session` e `documentId`. O status **Aceito pelo n8n** confirma a execução aceita pelo fluxo; não comprova entrega no WhatsApp ou assinatura.

Intervalos: 15–25 segundos entre mensagens; 45–90 segundos após cinco aceites. Os tempos são persistidos entre ciclos. Não há garantia de evitar bloqueios de serviços externos. Timeouts/respostas sem confirmação ficam como incertos e não são repetidos automaticamente.

## Configurar o novo fluxo n8n

1. Importe `../n8n/rh-prime-web.json` **como um novo fluxo** na instância RH da porta 5679. Mantenha o fluxo Python atual.
2. No nó **Receber do RH Web**, escolha/crie uma credencial **Header Auth**. Nome do cabeçalho: `X-RH-Token`. Se já existir uma credencial Header Auth com esse cabeçalho, reutilize seu token. Caso contrário, crie um token aleatório forte e guarde-o. Reutilize a conta WAHA existente; a credencial MCP não autentica automaticamente este webhook. Não coloque esse token no GitHub ou no painel web.
3. No nó **Enviar mensagem WAHA**, selecione a credencial WAHA da instância RH e confira a sessão `default`. O fluxo importado não contém credenciais reais.
4. Ative/publique o fluxo e copie a **Production URL** do webhook. O caminho novo é `/webhook/rh-prime-web`.
5. A URL deve ser HTTPS pública pelo túnel configurado para a instância RH. O endereço `<URL_LOCAL_N8N_RH>` usado pelo Python é privado e não serve para o Google Apps Script. O endereço `/mcp-server/http` é MCP e não é o webhook de mensagens.
6. O fluxo responde `{ "accepted": true, "documentId": "...", "status": "accepted" }` apenas após o nó WAHA concluir. Não há tentativa de inventar o nono dígito de um telefone.

O fluxo guarda aceites recentes em dados estáticos do n8n para reduzir repetições sequenciais do mesmo `documentId`. Isso não é uma garantia transacional de execução única sob chamadas concorrentes; o processador Google usa trava e não repete resultados incertos. Se surgir uma execução incerta, confira o histórico real do n8n antes de qualquer nova tentativa.

## Configurar o Apps Script

1. No mesmo projeto Google já usado para sincronização e pastas, crie um **novo arquivo** `RH_Documentos_N8N`.
2. Cole todo o conteúdo de `../integrations/google-apps-script/RH_Documentos_N8N.gs`. Ele depende do arquivo `../integrations/google-apps-script/RH_Drive_Automacoes.gs` já instalado. Preserve todos os arquivos de sincronização existentes.
3. Nas Propriedades do script, mantenha `SUPABASE_URL` e `SUPABASE_KEY` e acrescente:
   - `N8N_RH_WEBHOOK_URL`: Production URL HTTPS do novo webhook.
   - `N8N_RH_TOKEN`: o mesmo token escolhido na credencial Header Auth.
4. Execute `instalarDocumentosWebRH`, autorize as permissões e confira o novo gatilho `processarDocumentosWebRH` a cada minuto. O gatilho de movimentação de pastas continua independente.
5. Em Importação e envio, ative primeiro **Processar uploads**. Importe e confira um PDF real conhecido e confirme a organização privada no Drive.
6. Após confirmar o link acessível ao destinatário e o webhook, ative **Permitir envio ao n8n** e autorize somente as mensagens que deseja enviar.

O n8n/WAHA no computador precisam estar funcionando e o túnel precisa estar disponível. A preparação não depende de Python instalado; o envio depende da disponibilidade do n8n. As credenciais ficam no servidor Google, não no JavaScript público.

## Limites da versão

Origem até 30 MB, até mil páginas, até 100 páginas por documento, PDF separado até 10 MB. Seleção de pasta depende do suporte do navegador; selecionar múltiplos PDFs é a alternativa. Separação exige agrupamento uniforme, com identificação em cada página. PDFs com assinaturas existentes são modificados ao separar e devem ser conferidos antes de usar o resultado.

Não cria assinaturas ZapSign/Facilita Ponto. A integração oficial Facilita Ponto permanece dependente de documentação/autorização do fornecedor. Não envia PDF anexo pelo WhatsApp: entrega a mensagem com o link conforme o fluxo atual do Python/n8n.

## Tema

O controle Claro/Escuro está dentro da navegação das páginas e no cartão de login. Preferência salva localmente por navegador. Não altera permissões, dados ou configurações dos demais usuários.

## Lotes, PDFs e pastas de colaboradores já existentes

As novas importações guardam um lote com nome, tipo, competência, data/hora e criador. Abra o lote para conferir os PDFs, mensagens e situações. A lista permanece após recarregar a página; a análise local anterior à importação continua temporária. **Conferir / baixar PDF** abre o arquivo no Drive quando já foi transferido, ou gera acesso temporário ao PDF privado enquanto a transferência está pendente ou falhou. Esse link temporário não deve ser usado na mensagem ao colaborador: confira o link definitivo do Drive/portal.

Os 43 registros anteriores foram preservados em um agrupamento legado por tipo, competência e data da importação. O sistema anterior não armazenava um ID de lote; esse agrupamento não pretende reconstruir a divisão original com certeza. Não houve nova importação, envio de WhatsApp ou alteração das pastas para criar esse histórico.

### Resolver os 42 uploads com pasta não vinculada

1. Atualize **RH_Drive_Automacoes.gs** no mesmo Apps Script e execute **instalarAutomacaoDriveRH**. A versão nova informa ao banco que suporta vínculo sem mutação; a página bloqueia a ação coletiva enquanto um processador antigo estiver registrado. Não precisa alterar credenciais nem reinstalar o processador de documentos.
2. Confira que a automação de pastas está ativa em Automações. Na página de documentos, abra o lote e clique em **Vincular pastas existentes do lote**. Confirme a solicitação.
3. O processador procura nas raízes configuradas, aceita pastas com nome sem CPF, normaliza acentos e salva o ID quando há uma correspondência única. Nesse modo não cria, move, copia ou renomeia pastas. Nomes divergentes ou ambíguos ficam para vínculo manual; nenhum ID é adivinhado. Aguarde o gatilho de até cinco minutos ou execute **processarFilaDriveRH** para processar as tarefas aguardando (inclusive outras tarefas já solicitadas).
4. Atualize o acompanhamento. Clique em **Retomar uploads com falha**. Essa ação utiliza os PDFs já armazenados, conserva o lote e o ID do documento, e somente retoma falhas de upload sem aprovação, de colaboradores ativos com pasta vinculada e modelo concluído. Não retoma envios incertos nem autoriza mensagens.
5. Aguarde os documentos ficarem **Pronto para aprovação**, confira os PDFs/telefone/link/texto, selecione os prontos **do lote aberto** e autorize o envio. Confira também a execução do n8n e o recebimento real.

O botão **Selecionar todos os prontos para envio** seleciona somente `ready` no lote aberto e informa a quantidade. PDFs com falha ficam desabilitados; falta de CPF no nome da pasta não é motivo para desabilitar. O cadastro/desligamento futuro continua com seu fluxo normal de criação/movimentação e vínculo persistente.

Validação: transações SQL com rollback para lotes, autorização, proteção contra processador antigo e retomada sem autorização de mensagem; testes de pastas existentes sem CPF, ausência de correspondência e homônimos sem nenhuma mutação no Drive; navegador simulado para lotes após recarga, seleção/autorização restrita ao lote, PDF privado e layouts claro/escuro em celular, tablet e PC.


## Armazenamento temporário e consulta no Drive
Atualize o arquivo completo ../integrations/google-apps-script/RH_Documentos_N8N.gs no Apps Script. O gatilho já existente processarDocumentosWebRH fará a limpeza; não é necessário mudar credenciais.
O processador grava o ID/link do Drive, verifica o arquivo por identidade, tipo, tamanho e SHA-256 do conteúdo baixado do Drive, e somente depois remove o objeto exato no bucket privado rh-documentos usando a Storage API. Se a verificação ou a remoção falhar, o histórico permanece e storage_cleanup_error registra o motivo para nova tentativa. Não se apagam registros do banco.
Novos uploads são limpos após confirmação; PDFs já enviados são verificados e limpos em grupos de cinco por execução. A consulta dos lotes usa drive_file_id para abrir o arquivo original no Drive, inclusive após remover a cópia temporária. O SHA-256 continua no banco para deduplicar importações. Arquivos que falharam antes de chegar ao Drive continuam temporariamente disponíveis no Supabase.
Os PDFs gerados pela versão web não recebem senha de CPF. Essa atualização não remove senhas de arquivos antigos gerados pelo Python.


## Envios para retomar
A lista “Envios para retomar” reconhece o erro exato de configuração do webhook/token, inclusive registros antigos classificados como incertos. “Preparar reenvio” conserva o PDF, o ID e o lote, limpa a aprovação anterior e volta o documento para pronto. Confira e autorize novamente no lote. A retomada é restrita a administradores e colaboradores ativos. Timeouts, falhas de resposta, erros HTTP e outros resultados incertos não entram nesta lista.

Aplique ../supabase/sql/rh_documentos_reenvio.sql no Supabase e atualize ../integrations/google-apps-script/RH_Documentos_N8N.gs no mesmo Apps Script. O gatilho existente continua válido. A versão nova marca a falha de configuração como falha conhecida e desativa o envio ao n8n após a primeira ocorrência, preservando os demais documentos na fila. Após corrigir as propriedades, ative o envio novamente no painel.

URL de produção confirmada pela conexão n8n RH: <URL_WEBHOOK_PRODUCAO_N8N_RH>. O token permanece somente nas propriedades do script e na credencial Header Auth.


## Leitura por link e correção dos arquivos já enviados
Após atualizar ../integrations/google-apps-script/RH_Documentos_N8N.gs no Apps Script, execute liberarLeituraDocumentosExistentesRH para liberar os PDFs do histórico (até 100 por execução, respeitando o limite de tempo). Essa função não chama o n8n e não reenvia mensagens: o link antigo permanece o mesmo. O gatilho processarDocumentosWebRH também corrige grupos de cinco documentos pendentes por ciclo.
O processador verifica identidade do arquivo por ID e appProperties.rh_delivery_id, cria ou ajusta somente a permissão anyone/reader com allowFileDiscovery=false, consulta novamente as permissões e grava a confirmação no banco. PDFs novos são liberados antes de ficarem prontos e o acesso é reconferido antes de enviar mensagens. Se o Google bloquear o compartilhamento, a falha fica registrada; a mensagem não é disparada nessa tentativa. Links externos cadastrados manualmente não têm suas permissões alteradas por esta rotina.
