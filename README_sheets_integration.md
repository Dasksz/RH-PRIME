# Integração Bidirecional: Supabase ↔ Google Sheets

Para termos **sincronização bidirecional em tempo real**, configuraremos duas coisas:
1. **Google Sheets -> Supabase:** Já configurado usando a função `onEdit` no Apps Script.
2. **Supabase -> Google Sheets:** (NOVO) Usaremos uma função `doPost` no Apps Script que funcionará como uma API, recebendo os dados do Supabase através de um Webhook e atualizando a planilha.

Siga o passo a passo abaixo para configurar a via de retorno (Supabase -> Google Sheets):

## Parte 1: Atualizando o Código no Google Sheets (Apps Script)

1. Abra a sua planilha no Google Sheets.
2. No menu superior, clique em **Extensões** > **Apps Script**.
3. No editor de código, **apague tudo que estiver lá** e cole o código completo atualizado abaixo:

```javascript
// ==========================================
// CONFIGURAÇÕES DO SUPABASE E PLANILHA
// ==========================================
const SUPABASE_URL = "https://gcksbfstheavpfgcdndb.supabase.co"; 
const SUPABASE_KEY = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Imdja3NiZnN0aGVhdnBmZ2NkbmRiIiwicm9sZSI6ImFub24iLCJpYXQiOjE3Nzc3NTA3MjcsImV4cCI6MjA5MzMyNjcyN30.5yqzDt5mTJRpTavKq4GJ0CwX6qT3GaVvXqbcdawJUmU";
const SUPABASE_TABLE = "funcionarios_epi";
const NOME_DA_ABA = "Página1"; // MUITO IMPORTANTE: Mude para o nome exato da aba da sua planilha!

// ==========================================
// 1. DO GOOGLE SHEETS PARA O SUPABASE (onEdit)
// ==========================================
function onEdit(e) {
  if (!e || !e.range) return;
  
  const sheet = e.source.getActiveSheet();
  const row = e.range.getRow();
  
  // Ignora o cabeçalho (linha 1)
  if (row <= 1) return;
  
  // Pega todos os dados da linha que acabou de ser editada
  const rowData = sheet.getRange(row, 1, 1, 8).getValues()[0];
  
  const payload = {
    admissao: rowData[0] || "",
    nome: rowData[1] || "",
    funcao: rowData[2] || "",
    epi_data: rowData[3] || "",
    epi_link: rowData[4] || "",
    fardamento_data: rowData[5] || "",
    fardamento_link: rowData[6] || "",
    validacao: rowData[7] || ""
  };
  
  try {
    const existingUrl = `${SUPABASE_URL}/rest/v1/${SUPABASE_TABLE}?nome=eq.${encodeURIComponent(payload.nome)}&select=id`;
    const response = UrlFetchApp.fetch(existingUrl, {
      method: "get",
      headers: {
        "apikey": SUPABASE_KEY,
        "Authorization": `Bearer ${SUPABASE_KEY}`,
        "Content-Type": "application/json"
      }
    });
    
    const records = JSON.parse(response.getContentText());
    
    if (records.length > 0) {
      // Já existe, vamos atualizar (UPDATE)
      const id = records[0].id;
      UrlFetchApp.fetch(`${SUPABASE_URL}/rest/v1/${SUPABASE_TABLE}?id=eq.${id}`, {
        method: "patch",
        headers: {
          "apikey": SUPABASE_KEY,
          "Authorization": `Bearer ${SUPABASE_KEY}`,
          "Content-Type": "application/json",
          "Prefer": "return=minimal"
        },
        payload: JSON.stringify(payload)
      });
    } else {
      // Não existe, criar novo (INSERT)
      UrlFetchApp.fetch(`${SUPABASE_URL}/rest/v1/${SUPABASE_TABLE}`, {
        method: "post",
        headers: {
          "apikey": SUPABASE_KEY,
          "Authorization": `Bearer ${SUPABASE_KEY}`,
          "Content-Type": "application/json",
          "Prefer": "return=minimal"
        },
        payload: JSON.stringify([payload])
      });
    }
  } catch (error) {
    console.error("Erro ao sincronizar com Supabase:", error);
  }
}

// ==========================================
// 2. DO SUPABASE PARA O GOOGLE SHEETS (doPost)
// ==========================================
// Esta função recebe requisições Webhook do Supabase sempre que a tabela muda
function doPost(e) {
  try {
    const data = JSON.parse(e.postData.contents);
    const record = data.record; // A linha atualizada/inserida do Supabase
    const type = data.type; // "UPDATE" ou "INSERT"
    
    const sheet = SpreadsheetApp.getActiveSpreadsheet().getSheetByName(NOME_DA_ABA);
    if (!sheet) return ContentService.createTextOutput("Aba não encontrada").setMimeType(ContentService.MimeType.TEXT);

    // Dados do Supabase
    const nomeBusca = record.nome;
    
    // Mapeamento das colunas (baseado na ordem 0 a 7 que configuramos no onEdit)
    const newRowData = [
      record.admissao || "",           // Col A (1)
      record.nome || "",               // Col B (2)
      record.funcao || "",             // Col C (3)
      record.epi_data || "",           // Col D (4)
      record.epi_link || "",           // Col E (5)
      record.fardamento_data || "",    // Col F (6)
      record.fardamento_link || "",    // Col G (7)
      record.validacao || ""           // Col H (8)
    ];

    const allData = sheet.getDataRange().getValues();
    let rowToUpdate = -1;

    // Procura o funcionário pelo nome
    for (let i = 1; i < allData.length; i++) { // começa do 1 pra pular o cabeçalho
      if (allData[i][1] === nomeBusca) { // [1] porque 'nome' é a segunda coluna (A=0, B=1)
        rowToUpdate = i + 1; // +1 porque arrays começam em 0 e as linhas no sheets começam em 1
        break;
      }
    }

    if (rowToUpdate !== -1) {
      // Atualiza a linha existente
      sheet.getRange(rowToUpdate, 1, 1, 8).setValues([newRowData]);
    } else {
      // Se for INSERT no Supabase e não existe na planilha, cria uma nova linha no final
      sheet.appendRow(newRowData);
    }

    return ContentService.createTextOutput(JSON.stringify({"status": "success"})).setMimeType(ContentService.MimeType.JSON);

  } catch (error) {
    return ContentService.createTextOutput(JSON.stringify({"status": "error", "message": error.message})).setMimeType(ContentService.MimeType.JSON);
  }
}
```

4. **IMPORTANTE:** Revise a variável `NOME_DA_ABA` no código acima. Por padrão eu coloquei "Página1", mas se o nome da aba na sua planilha do Google Sheets for diferente (ex: "Planilha1" ou "Funcionários"), mude no código para o nome correto exato.

## Parte 2: Publicar o WebApp no Google Scripts

Para o Supabase conseguir mandar dados, precisamos transformar o script acima num "site" acessível.

1. No topo superior direito do editor do Apps Script, clique no botão azul **"Implantar"** (ou *Deploy*).
2. Selecione **"Nova implantação"** (ou *New deployment*).
3. Ao lado de "Selecione o tipo", clique no ícone da engrenagem ⚙️ e escolha **"App da Web"** (ou *Web app*).
4. Em Descrição, escreva "Webhook Supabase".
5. Em **Executar como**, deixe como "Eu" (seu email).
6. Em **Quem tem acesso**, MUDE para **"Qualquer pessoa"** (*Anyone*). Isso é fundamental para que o servidor do Supabase consiga enviar a requisição de fora!
7. Clique em **"Implantar"**.
8. O Google vai pedir autorização de acesso aos dados. Permita tudo (se avisar que o app não é seguro, vá em Avançado e clique em "Acessar (não seguro)").
9. **Copie o URL do App da Web fornecido.** Vai ser um link que começa com `https://script.google.com/macros/s/.../exec`. 
   **Guarde esse link, você vai precisar dele agora!**

---

## Parte 3: Configurando o Webhook no Supabase

Agora vamos avisar o banco de dados que ele deve disparar as mudanças para aquele link que acabamos de gerar.

1. Vá para o painel do seu projeto no Supabase: `https://supabase.com/dashboard/project/gcksbfstheavpfgcdndb`.
2. No menu lateral esquerdo, clique em **"Database"** e depois selecione **"Webhooks"**.
3. Clique no botão verde **"Create Webhook"**.
4. Configure as seguintes opções:
   - **Name:** "Sync to Google Sheets"
   - **Table:** Selecione `funcionarios_epi`
   - **Events:** Selecione `Insert` e `Update`.
5. Na seção de configuração da Webhook (HTTP Request):
   - **Method:** `POST`
   - **URL:** *Cole aqui o URL do App da Web que você copiou no passo anterior do Google Scripts.*
6. Na seção "HTTP Headers", clique em "Add Header":
   - Você **não** precisa adicionar cabeçalhos extra de autorização, porque o `doPost` aceitará "Qualquer pessoa", então pode deixar vazio ou com `Content-Type: application/json`.
7. Clique em **"Create webhook"** para salvar.

---

## 🚀 Tudo Pronto!

Agora o ciclo está completo e funciona 100% em tempo real nos dois sentidos:

- Se você modificar uma data no **Google Sheets**, a função `onEdit` roda na hora e atualiza o Supabase (e consequentemente o Front-End da sua aplicação que usa Realtime atualiza a tela na hora).
- Se você acessar seu **App Front-End** e anexar um link ou clicar em validar entrega, o App salva no Supabase. Imediatamente o Supabase dispara o Webhook para o Google, a função `doPost` recebe, acha o funcionário na planilha, e reescreve a linha inteira lá dentro do Google Sheets.

Tudo sincronizado!
