# Importação de PDFs e envio ao n8n pelo navegador

## Recursos disponíveis

A página `documentos-web.html` lê PDFs com texto no próprio navegador, identifica colaboradores por CPF válido ou nome único, separa por quantidade de páginas informada, mostra uma prévia para download/conferência e permite selecionar todos ou alguns documentos prontos. Documentos digitalizados sem texto, grupos com pessoas diferentes, colaboradores desligados e telefones inválidos ficam bloqueados. OCR e execução de Python/BAT não estão implementados no navegador.

Somente a seleção confirmada é importada para um bucket privado do Supabase. Depois o Apps Script organiza os PDFs na pasta vinculada do colaborador, por Tipo/Ano/Mês. Folha de ponto também usa a subpasta JORNADA E SEGURANÇA. Não cria permissão pública e não apaga documentos existentes.

O PDF separado não recebe criptografia por senha nesta versão. O armazenamento e o Drive permanecem privados. Confira o acesso do colaborador ao link, ou informe um link válido do portal de documentos antes de autorizar a mensagem. Não use a mensagem antiga do Python que promete senha se o PDF não estiver protegido dessa forma.

Após upload: selecione os documentos prontos, confira telefone/link/mensagem e autorize. O processador chama o novo webhook n8n usando `chatId`, `caption`, `session` e `documentId`. O status **Aceito pelo n8n** confirma a execução aceita pelo fluxo; não comprova entrega no WhatsApp ou assinatura.

Intervalos: 15–25 segundos entre mensagens; 45–90 segundos após cinco aceites. Os tempos são persistidos entre ciclos. Não há garantia de evitar bloqueios de serviços externos. Timeouts/respostas sem confirmação ficam como incertos e não são repetidos automaticamente.

## Configurar o novo fluxo n8n

1. Importe `n8n_rh_prime_web.json` **como um novo fluxo** na instância RH da porta 5679. Mantenha o fluxo Python atual.
2. No nó **Receber do RH Web**, escolha/crie uma credencial **Header Auth**. Nome do cabeçalho: `X-RH-Token`. Se já existir uma credencial Header Auth com esse cabeçalho, reutilize seu token. Caso contrário, crie um token aleatório forte e guarde-o. Reutilize a conta WAHA existente; a credencial MCP não autentica automaticamente este webhook. Não coloque esse token no GitHub ou no painel web.
3. No nó **Enviar mensagem WAHA**, selecione a credencial WAHA da instância RH e confira a sessão `default`. O fluxo importado não contém credenciais reais.
4. Ative/publique o fluxo e copie a **Production URL** do webhook. O caminho novo é `/webhook/rh-prime-web`.
5. A URL deve ser HTTPS pública pelo túnel configurado para a instância RH. O endereço `http://100.90.6.30:5679` usado pelo Python é privado e não serve para o Google Apps Script. O endereço `/mcp-server/http` é MCP e não é o webhook de mensagens.
6. O fluxo responde `{ "accepted": true, "documentId": "...", "status": "accepted" }` apenas após o nó WAHA concluir. Não há tentativa de inventar o nono dígito de um telefone.

O fluxo guarda aceites recentes em dados estáticos do n8n para reduzir repetições sequenciais do mesmo `documentId`. Isso não é uma garantia transacional de execução única sob chamadas concorrentes; o processador Google usa trava e não repete resultados incertos. Se surgir uma execução incerta, confira o histórico real do n8n antes de qualquer nova tentativa.

## Configurar o Apps Script

1. No mesmo projeto Google já usado para sincronização e pastas, crie um **novo arquivo** `RH_Documentos_N8N`.
2. Cole todo o conteúdo de `RH_Documentos_N8N.gs`. Ele depende do arquivo `RH_Drive_Automacoes.gs` já instalado. Preserve todos os arquivos de sincronização existentes.
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
\n\n## Armazenamento temporário e consulta no Drive\nAtualize o arquivo completo RH_Documentos_N8N.gs no Apps Script. O gatilho já existente processarDocumentosWebRH fará a limpeza; não é necessário mudar credenciais.\nO processador grava o ID/link do Drive, verifica o arquivo por identidade, tipo, tamanho e SHA-256 do conteúdo baixado do Drive, e somente depois remove o objeto exato no bucket privado rh-documentos usando a Storage API. Se a verificação ou a remoção falhar, o histórico permanece e storage_cleanup_error registra o motivo para nova tentativa. Não se apagam registros do banco.\nNovos uploads são limpos após confirmação; PDFs já enviados são verificados e limpos em grupos de cinco por execução. A consulta dos lotes usa drive_file_id para abrir o arquivo original no Drive, inclusive após remover a cópia temporária. O SHA-256 continua no banco para deduplicar importações. Arquivos que falharam antes de chegar ao Drive continuam temporariamente disponíveis no Supabase.\nOs PDFs gerados pela versão web não recebem senha de CPF. Essa atualização não remove senhas de arquivos antigos gerados pelo Python.\n

## Envios para retomar
A lista “Envios para retomar” reconhece o erro exato de configuração do webhook/token, inclusive registros antigos classificados como incertos. “Preparar reenvio” conserva o PDF, o ID e o lote, limpa a aprovação anterior e volta o documento para pronto. Confira e autorize novamente no lote. A retomada é restrita a administradores e colaboradores ativos. Timeouts, falhas de resposta, erros HTTP e outros resultados incertos não entram nesta lista.

Aplique rh_documentos_reenvio.sql no Supabase e atualize RH_Documentos_N8N.gs no mesmo Apps Script. O gatilho existente continua válido. A versão nova marca a falha de configuração como falha conhecida e desativa o envio ao n8n após a primeira ocorrência, preservando os demais documentos na fila. Após corrigir as propriedades, ative o envio novamente no painel.

URL de produção confirmada pela conexão n8n RH: https://login.tail239ac4.ts.net:8443/webhook/rh-prime-web. O token permanece somente nas propriedades do script e na credencial Header Auth.
