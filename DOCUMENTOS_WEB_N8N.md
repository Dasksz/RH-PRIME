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
