# Automações web do RH PRIME

## O que já funciona

Acesse `automacoes.html` com uma conta administradora. A página permite configurar raízes do Drive, ativar/pausar a fila, vincular pastas existentes a colaboradores, solicitar processamento individual, acompanhar o histórico, salvar um modelo de mensagem, copiar o texto preenchido e registrar links de documentos com situação manual.

A fila é persistida no Supabase. Cadastro e alteração da data de desligamento geram tarefas quando a automação está ativa, inclusive se a edição chegar pela sincronização da planilha. Alterações durante uma execução são guardadas para novo processamento. Registros históricos não são movimentados em massa ao ativar; use o seletor individual.

## Ativação única no Google Apps Script

1. Abra a planilha → Extensões → Apps Script, no projeto que já contém o sincronizador RH PRIME.
2. Crie um **novo arquivo de script** chamado `RH_Drive_Automacoes`.
3. Cole todo o conteúdo de `RH_Drive_Automacoes.gs` e salve. **Mantenha o código de sincronização existente.**
4. Nas configurações do projeto, confira que as Propriedades do script contêm `SUPABASE_URL` e `SUPABASE_KEY`, usadas pelo sincronizador. A chave deve ser a chave de servidor já configurada; não coloque a chave no HTML nem em campos do painel.
5. Habilite a exibição do manifesto nas Configurações do projeto. Em `appsscript.json`, declare os escopos explicitamente: preserve os atuais e inclua `https://www.googleapis.com/auth/drive`, `https://www.googleapis.com/auth/script.external_request` e `https://www.googleapis.com/auth/script.scriptapp`.
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

## Correção de ACCESS_TOKEN_SCOPE_INSUFFICIENT

Esse erro significa que o token daquela execução não tinha o escopo necessário. Ler pastas e capacidades com sucesso não comprova autorização para criar/copiar/mover por REST. A instalação e o diagnóstico atualizados exigem o consentimento do escopo completo `https://www.googleapis.com/auth/drive` antes de continuar, usando `ScriptApp.requireScopes`. O escopo deve estar declarado no manifesto; a chamada não adiciona escopos ao manifesto.

1. Substitua o conteúdo do arquivo `RH_Drive_Automacoes` pelo arquivo atualizado deste repositório.
2. No Apps Script, Configurações do projeto → marque **Mostrar arquivo de manifesto appsscript.json no editor**.
3. Abra `appsscript.json` e inclua os escopos abaixo em `oauthScopes`, mantendo outros escopos e as demais configurações existentes. Não substitua o manifesto inteiro por esse trecho.

```json
"oauthScopes": [
  "https://www.googleapis.com/auth/drive",
  "https://www.googleapis.com/auth/spreadsheets",
  "https://www.googleapis.com/auth/script.external_request",
  "https://www.googleapis.com/auth/script.scriptapp"
]
```

4. Salve e execute **instalarAutomacaoDriveRH** pela sua conta com acesso às pastas; conceda os escopos solicitados. Se a execução solicitar consentimento e parar, conclua a autorização e execute a função novamente.
5. Execute **diagnosticarAutomacaoDriveRH** para conferir acesso às três pastas. O diagnóstico não cria, move ou apaga arquivos.
6. Na página Automações, selecione o colaborador, confira a pasta/destino e clique no botão para colocar na fila/solicitar novo processamento. A tarefa antiga em Falha não é retomada automaticamente. O gatilho roda a cada cinco minutos; atualize o acompanhamento e verifique a data e a situação novas. Para processar imediatamente, execute **processarFilaDriveRH**, que processará tarefas aguardando na fila quando a automação estiver ativa.

A autorização deve ser concedida pela conta que instala o gatilho. Uma chave do Supabase ou token do n8n não corrige esse escopo Google. Não é necessário apagar pastas, gatilhos de sincronização ou documentos existentes.

Referência: [Google — escopos de autorização](https://developers.google.com/apps-script/concepts/scopes).

## Vincular pastas existentes em lote

O botão **Vincular pastas existentes do lote**, na página de documentos, usa uma tarefa de reconciliação que apenas encontra uma correspondência única e salva `rh_drive_links`. Não cria pastas novas nem renomeia, copia ou move conteúdo. Pastas com apenas o nome são aceitas; homônimos, múltiplos CPFs ou nomes não encontrados exigem revisão manual. Atualize `RH_Drive_Automacoes.gs` e execute a instalação antes desse recurso: o banco exige a identificação de versão `existing-link-v1` publicada pelo novo processador. A rotina de cadastro/desligamento usa tarefas normais, com criação/movimentação conforme já autorizado no fluxo.


## Confirmação de pasta existente
Aplique rh_drive_confirmacao.sql no Supabase antes de substituir RH_Drive_Automacoes.gs no Apps Script. A migração bloqueia a fila normal para processadores antigos; os cadastros e a sincronização com planilhas continuam. Atualize o arquivo completo e salve. O gatilho existente processarFilaDriveRH não precisa ser recriado.

Na Administração e em Automações, a janela aparece depois da busca do processador (até cinco minutos), com nome, localização, ID e link das pastas compatíveis. Escolha Usar pasta selecionada, Criar uma nova pasta ou Decidir depois. Fechar ou adiar conserva a pendência, acessível pelo aviso Conferir pastas. A escolha só é aceita para a revisão atual do cadastro e administradores autenticados.

Usar uma pasta existente preserva seu nome e conteúdo, sem copiar o modelo; se estiver em ex-funcionários, o processador a move para ativos. Criar outra preserva a antiga, cria uma pasta com o nome completo e copia o modelo; o Drive permite pastas com nomes iguais. Sem correspondências, a criação continua automática. Pastas já vinculadas e desligamentos continuam pelo fluxo anterior. O modo Vincular pastas existentes do lote preserva seu comportamento de vínculo sem mutação.

Nenhuma escolha é feita automaticamente pelo modal. Nome/CPF alterados, pasta removida, mudança de dono ou de raiz exigem nova conferência. Solicite nova busca pelo seletor em Automações.
