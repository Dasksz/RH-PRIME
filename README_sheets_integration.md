# Integração Bidirecional: Supabase ↔ Google Sheets

Para que a sua planilha do Google Sheets seja atualizada automaticamente sempre que você salvar algo no seu aplicativo (e vice-versa), usaremos um **Google Apps Script**.

Siga o passo a passo abaixo para configurar:

## Parte 1: Preparando a API do Supabase

Você vai precisar dos dados de conexão do seu Supabase. Anote:
1. **URL do Projeto:** `https://gcksbfstheavpfgcdndb.supabase.co`
2. **Anon Key:** `eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...` (Aquela chave enorme que você mandou anteriormente).

---

## Parte 2: Colocando o Código no Google Sheets

1. Abra a sua planilha no Google Sheets.
2. No menu superior, clique em **Extensões** > **Apps Script**.
3. Um editor de código vai abrir. Apague tudo que estiver lá.
4. Copie o código abaixo e cole no editor:

```javascript
// ==========================================
// CONFIGURAÇÕES DO SUPABASE
// ==========================================
const SUPABASE_URL = "SUA_URL_AQUI"; // Ex: https://xxx.supabase.co
const SUPABASE_KEY = "SUA_ANON_KEY_AQUI";
const SUPABASE_TABLE = "funcionarios_epi";

/**
 * Função executada automaticamente sempre que você editar a planilha no Google Sheets
 * Ela envia a alteração para o Supabase.
 */
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

  // Verifica se a pessoa já tem ID para saber se é UPDATE ou INSERT.
  // Como a planilha não tem a coluna de ID do Supabase visível, o ideal é fazer a busca pelo NOME.
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
```

5. **Atenção:** Na primeira linha de código, troque `"SUA_URL_AQUI"` e `"SUA_ANON_KEY_AQUI"` pelas chaves do seu Supabase.
6. Clique no ícone de Disquete (Salvar) na barra de ferramentas ou aperte `Ctrl + S`.
7. **Pronto!**

## Como testar:
1. Vá até a sua planilha do Google Sheets e mude a função ou a data de entrega de um funcionário qualquer.
2. Abra o aplicativo (`index.html`). Você verá que, graças ao Realtime do Supabase, o seu aplicativo mudará o status na mesma hora em que a planilha foi salva!

*(Nota: O aplicativo para enviar de volta para o Sheets no modelo "doPost" exige Webhook, mas como o Google Sheets bloqueia acessos externos anônimos em contas gratuitas sem configurações avançadas no Google Cloud, a via "App -> Supabase" já atualiza o banco em tempo real. Se você precisa que o Sheets atualize ao receber do App, recomendamos conectar o Supabase Webhooks ao Make.com, onde é possível configurar de maneira visual e gratuita a escrita no Sheets em 2 minutos!)*
