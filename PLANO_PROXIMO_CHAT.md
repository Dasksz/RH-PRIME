# Plano de Ação: Integração ZapSign & Lembretes

Este documento contém o escopo completo para implementar a nova integração da ZapSign e o fluxo de lembretes automáticos na aplicação PRIME RH. Use este plano para guiar a execução no próximo chat.

## 1. Contexto e Objetivos
- Substituir o método atual de assinatura eletrônica (Google Apps Script com portal próprio) pela plataforma **ZapSign**.
- O sistema Python (`1_Preparar_Holerites.py`) deverá comunicar-se com a ZapSign, enviando o documento original e obtendo um **link de assinatura**.
- O link de assinatura será enviado ao colaborador pelo WhatsApp através do n8n.
- Criar uma automação no Google Sheets (via Apps Script) que receberá um Webhook da ZapSign sempre que um documento for assinado, mudando o status para "Assinado".
- Esta mesma automação do Google Sheets deverá rodar diariamente (via Cron/Trigger) para verificar documentos pendentes há mais de 24 horas e acionar o fluxo n8n de lembrete.
- Atualizar o fluxo n8n para tratar o envio das mensagens de lembrete e corrigir problemas com eventos brutos do WAHA, adicionando um nó **IF**.

## 2. Credenciais e Variáveis de Ambiente
- **Token ZapSign**: `106edcc3-1a22-4a00-ba53-64bfec863584` (Deve ser inserido no arquivo Python e não versionado no GitHub caso seja público).
- **URL Webhook n8n (Atual)**: `https://rhprime.app.n8n.cloud/webhook/holerites` (Mesma URL para envio do link e do lembrete).

## 3. Alterações Necessárias (Passo a Passo)

### 3.1. Python: `AUTOMACAO_ENVIO_DE_DOCUMENTOS/1_Preparar_Holerites.py`
- Adicionar as bibliotecas: `import requests` e `import base64`.
- Configurar a variável `ZAP_API_TOKEN` com o token fornecido.
- Criar a função `create_zapsign_document(pdf_path, signer_name, signer_phone)`.
  - Esta função faz um POST para `https://api.zapsign.com.br/api/v1/docs/`.
  - Converte o arquivo PDF local (passado via argumento) em `base64`.
  - Configura o payload desabilitando os e-mails da própria ZapSign (`"disable_signer_emails": True`) e forçando a linguagem `"pt-br"`.
  - Retorna o `sign_url` obtido na resposta JSON da ZapSign.
- Na função principal (que itera e processa os PDFs):
  - **Remover** o passo de criptografar o PDF com CPF (a ZapSign recebe o arquivo original).
  - Chamar a nova função `create_zapsign_document` passando o caminho do PDF não criptografado.
  - Compor a mensagem a ser enviada pelo n8n, incluindo o `sign_url` obtido.
  - Enviar apenas o payload (caption/texto com link) via HTTP POST para o N8N. **Não** enviar o arquivo PDF pesadamente, enviar apenas o texto da URL e saudação.
- Garantir que o Python, ao enviar, também registre o "Status" inicial como "Pendente" (se houver controle de planilha no script Python).

### 3.2. Google Apps Script: Webhook ZapSign + Lembretes
- O desenvolvedor deverá criar um novo arquivo `AUTOMACAO_ENVIO_DE_DOCUMENTOS/zapsign_apps_script.js`.
- O código deve ter a função `doPost(e)` para receber o Webhook da ZapSign e atualizar a coluna "Status" da nova planilha `Status_Assinaturas` de "Pendente" para "Assinado", baseando-se no `documentId` ou `token` do documento.
- O código deve ter a função `enviarLembretes()` para rodar uma vez ao dia via Trigger temporal. Ela deve checar se a diferença da data atual com a de criação é maior que 24 horas, e, caso o status não seja "Assinado", disparar um POST para o webhook n8n com a mensagem de lembrete e o link de assinatura salvo na planilha.

### 3.3. n8n: Arquivo `AUTOMACAO_ENVIO_DE_DOCUMENTOS/RH PRIME.json`
- O fluxo base terá inicialmente apenas 3 nós (Webhook -> WAHA Principal -> WAHA Fallback).
- É necessário **adicionar um nó IF (Condicional)** logo após o Webhook para ignorar eventos de status gerados pelo WAHA.
- A condição do IF deve validar: `{{ $json.body.caption }}` **Não Está Vazio (Is Not Empty)**.
- Desta forma, conexões do tipo `message.any` que não tenham `caption` não acionarão o disparo fantasma.

### 3.4. Documentação: `AUTOMACAO_ENVIO_DE_DOCUMENTOS/README_zapsign_integration.md`
- Criar um manual em Markdown explicando como o usuário deve:
  1. Criar a nova Planilha do Google (com as colunas Document ID, Nome, Telefone, Status, Data Assinatura, Data Criação, Link Assinatura).
  2. Inserir o código do `zapsign_apps_script.js` e publicar como "App da Web" (Deploy).
  3. Copiar a URL gerada e colar nas Configurações de Webhook da ZapSign.
  4. Configurar o Acionador (Trigger) no Apps Script para rodar a função de lembretes diariamente.

## 4. Ordem de Execução Recomendada (Para o Agente)
1. Elaborar e criar o arquivo `zapsign_apps_script.js`.
2. Elaborar e criar o `README_zapsign_integration.md`.
3. Ler e alterar o `1_Preparar_Holerites.py` para injetar as lógicas da ZapSign (removendo as partes antigas de criptografia com PyPDF2 e o envio do arquivo binário pro N8N).
4. Ler o fluxo base limpo do `RH PRIME.json` providenciado pelo usuário e adicionar o nó **IF**.
5. Validar todas as sintaxes e versionar com Git.
