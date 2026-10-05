# Automações web do RH PRIME

## O que já funciona

Acesse `automacoes.html` com uma conta administradora. A página permite configurar raízes do Drive, ativar/pausar a fila, vincular pastas existentes a colaboradores, solicitar processamento individual, acompanhar o histórico, salvar um modelo de mensagem, copiar o texto preenchido e registrar links de documentos com situação manual.

A fila é persistida no Supabase. Cadastro e alteração da data de desligamento geram tarefas quando a automação está ativa, inclusive se a edição chegar pela sincronização da planilha. Alterações durante uma execução são guardadas para novo processamento. Registros históricos não são movimentados em massa ao ativar; use o seletor individual.

## Ativação única no Google Apps Script

1. Abra a planilha → Extensões → Apps Script, no projeto que já contém o sincronizador RH PRIME.
2. Crie um **novo arquivo de script** chamado `RH_Drive_Automacoes`.
3. Cole todo o conteúdo de `RH_Drive_Automacoes.gs` e salve. **Mantenha o código de sincronização existente.**
4. Nas configurações do projeto, confira que as Propriedades do script contêm `SUPABASE_URL` e `SUPABASE_KEY`, usadas pelo sincronizador. A chave deve ser a chave de servidor já configurada; não coloque a chave no HTML nem em campos do painel.
5. Se o projeto possui escopos explícitos em `appsscript.json`, preserve os atuais e inclua `https://www.googleapis.com/auth/drive`, `https://www.googleapis.com/auth/script.external_request` e `https://www.googleapis.com/auth/script.scriptapp`.
6. Selecione **instalarAutomacaoDriveRH** e clique em Executar. Autorize sua conta Google com acesso às três pastas. A instalação valida as raízes e cria somente o gatilho `processarFilaDriveRH`, a cada cinco minutos; não remove gatilhos de sincronização.
7. Abra a página de automações e atualize o acompanhamento. Confira o último contato do processador. Marque **Ativar automação** e salve quando quiser habilitar a execução.
8. Para a primeira verificação real, selecione um colaborador conhecido, confira o vínculo/destino e coloque na fila. Depois confirme a pasta e o histórico.

Não é necessário reimplantar o endpoint Web App: este arquivo trabalha por gatilho de tempo. Não depende do Windows, do navegador aberto ou do aplicativo instalável. Está sujeito às permissões e cotas da conta Google/Apps Script.

## Regras de pastas

- Procura apenas pastas diretamente dentro das raízes de ativos e ex-funcionários.
- Mantém os nomes existentes, com ou sem CPF. Uma pasta nova recebe o nome do colaborador.
- Quando cria uma pasta nova, copia recursivamente o conteúdo do modelo; não acrescenta o modelo a pastas antigas já existentes.
- Desligamento move a mesma pasta, mantendo o ID e os documentos. Reativação devolve à raiz de ativos.
- CPF divergente, homônimos, múltiplos vínculos e pasta fora das raízes impedem processamento automático.
- Ex-funcionário sem pasta localizada exige vínculo manual; não cria uma pasta vazia.
- Cópias parciais têm marcadores para continuação. Se o limite de execução for atingido, revise o erro e coloque novamente na fila. Falhas não são repetidas indefinidamente.
- O código não cria compartilhamento público nem altera permissões de arquivos. A movimentação pode mudar permissões herdadas das pastas; confira a configuração das duas raízes.
- Modelo com atalhos exige revisão; as três raízes não podem estar uma dentro da outra.

## Mensagens, documentos e integração futura

O modelo de mensagem é usado na prévia e na cópia manual. Registrar um link não envia PDF, não compartilha o documento e não solicita assinatura. Os estados de envio/assinatura desta página são informados manualmente e aparecem identificados assim. Envio automático e retorno de status do Facilita Ponto aguardam documentação e credenciais da API do fornecedor.

A página web não executa `.bat`, `.exe` ou Python por caminho local. Esse recurso permanece pendente de componente local. O navegador não guarda documentos ou dados de RH no cache offline do service worker.

## Instalação da versão web

A versão web possui manifesto e ícones e pode ser instalada nos navegadores compatíveis. Na página de automações, use **Instalar versão web** quando disponível ou a opção de instalação do navegador. No iPhone/iPad use a opção de adicionar à tela de início quando disponível. Exige internet para os dados; não inclui o processador Python e não substitui o instalador Windows. O fluxo do GitHub Pages permanece disponível normalmente.

## Validação realizada

Testes simulados de identificação de pastas (com/sem CPF, divergências, homônimos e vínculo), fila transacional com revisão concorrente e conclusão, bloqueio de leitura para não administradores/anon e bloqueio de execução do processador pelo cliente autenticado. Os testes no banco foram revertidos. Nenhuma pasta real foi criada/movida para testar. Instalação e autorização do Apps Script precisam ser realizadas pelo administrador Google.

## Diagnóstico do erro Drive HTTP 403

Substitua o conteúdo de RH_Drive_Automacoes pelo arquivo atualizado. Execute `diagnosticarAutomacaoDriveRH` manualmente: apenas consulta as raízes e permissões, sem alterar documentos. A função apresenta o motivo técnico da API e uma orientação específica.

Se indicar API desativada, habilite Google Drive API no projeto Cloud vinculado ao Apps Script. Se indicar escopo insuficiente, execute `instalarAutomacaoDriveRH` novamente e autorize o Drive; havendo `oauthScopes` explícitos no manifesto, preserve os atuais e inclua `https://www.googleapis.com/auth/drive`. Se indicar permissão de arquivo, confira a conta que criou o gatilho e seu acesso às três pastas. Depois selecione Adriano no painel e solicite novo processamento.
