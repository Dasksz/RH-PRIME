# Integração ZapSign & Lembretes n8n - Manual de Configuração

Esta documentação descreve os passos necessários para finalizar a integração da ZapSign com o Google Sheets e o n8n para a automação de envio de holerites.

## 1. Configuração da Planilha do Google (Google Sheets)

O sistema agora utiliza uma planilha central para rastrear o status das assinaturas e enviar lembretes.

1. Abra a sua planilha "Registros de Assinatura RH PRIME".
2. Certifique-se de que a planilha possui **exatamente** as seguintes colunas (na primeira linha, a partir da coluna A):
   * **A:** Data/Hora
   * **B:** Nome
   * **C:** Mês/Ref
   * **D:** Tipo Documento
   * **E:** Pasta Drive
   * **F:** Declaração
   * **G:** Assinatura (CPF IP / Dispositivo)
   * **H:** Document ID ZapSign *(Nova Coluna)*
   * **I:** Status *(Nova Coluna - Pendente/Assinado)*
   * **J:** Link Assinatura *(Nova Coluna)*
   * **K:** Telefone n8n *(Nova Coluna)*

## 2. Configuração do Google Apps Script (Webhook & Lembretes)

Você precisa publicar o código `zapsign_apps_script.js` para gerar a URL do Webhook.

1. Na sua planilha do Google, vá em **Extensões** > **Apps Script**.
2. Copie todo o conteúdo do arquivo `zapsign_apps_script.js` (gerado na pasta `AUTOMACAO_ENVIO_DE_DOCUMENTOS`) e cole no editor do Apps Script (substituindo o `myFunction` padrão).
3. Salve o projeto (ícone de disquete).
4. Clique em **Implantar** (Deploy) > **Nova implantação** (New deployment).
5. Selecione o tipo **App da Web** (Web app).
6. Configure:
   * **Descrição:** Webhook ZapSign
   * **Executar como:** Você (seu email)
   * **Quem tem acesso:** Qualquer pessoa (Anyone)
7. Clique em **Implantar**. Autorize os acessos na janela do Google que abrir (Avançado > Acessar [Nome do Projeto]).
8. **Copie a URL do App da Web gerada.**

## 3. Atualizar a URL no Script Python

O robô precisa saber para onde enviar os dados de novos documentos.

1. Abra o arquivo `AUTOMACAO_ENVIO_DE_DOCUMENTOS/1_Preparar_Holerites.py` em um editor de texto (Bloco de Notas, VS Code).
2. Pressione `Ctrl + F` e procure por: `COLOQUE_AQUI_A_URL_DO_WEBHOOK_DO_APPS_SCRIPT`
3. Substitua este texto (mantendo as aspas) pela URL do App da Web que você copiou no passo anterior.
4. Salve o arquivo.

## 4. Configuração do Webhook na ZapSign

A ZapSign precisa avisar sua planilha quando um documento for assinado.

1. Acesse o painel da [ZapSign](https://zapsign.com.br/) e faça login.
2. Vá em **Configurações** (engrenagem) > **Integração / Webhooks**.
3. Adicione um novo Webhook.
4. Cole a **mesma URL do App da Web** (copiada no passo 2) no campo de URL.
5. Selecione para receber eventos de **Documento Assinado** (`doc_signed`) e **Documento Concluído** (`doc_completed`).
6. Salve a configuração.

## 5. Configurar Acionador (Trigger) Diário para Lembretes

Para que o sistema envie lembretes a cada 24 horas para quem não assinou:

1. Volte ao Google Apps Script.
2. No menu esquerdo, clique no ícone de relógio (**Acionadores** / Triggers).
3. Clique no botão azul **Adicionar Acionador** (Add Trigger) no canto inferior direito.
4. Configure assim:
   * Escolha a função que será executada: `enviarLembretes`
   * Escolha qual implantação deve ser executada: `Testa (Head)`
   * Selecione a origem do evento: `Baseado no tempo` (Time-driven)
   * Selecione o tipo de acionador baseado no tempo: `Temporizador baseado em dias` (Day timer)
   * Selecione a hora do dia: Ex: `09:00 as 10:00` (Escolha o melhor horário para cobrar os funcionários).
5. Clique em **Salvar**.

Pronto! A integração está completa. O robô em Python gerará os links da ZapSign, disparará a primeira mensagem e registrará na planilha. O Apps Script verificará diariamente quem está "Pendente" a mais de 24 horas e enviará novos lembretes via n8n. Quando assinarem, a ZapSign atualizará a planilha automaticamente para "Assinado".
