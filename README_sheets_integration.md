# Integração Bidirecional: Supabase ↔ Google Sheets

Para termos **sincronização bidirecional em tempo real**, configuraremos duas coisas:
1. **Google Sheets -> Supabase:** Usaremos um Gatilho Instalável no Apps Script.
2. **Supabase -> Google Sheets:** Usaremos uma função `doPost` no Apps Script que funcionará como uma API, recebendo os dados do Supabase através de um Webhook e atualizando a planilha.

Siga o passo a passo abaixo para configurar a integração corretamente:

## Parte 1: Atualizando o Código no Google Sheets (Apps Script)

1. Abra a sua planilha no Google Sheets.
2. No menu superior, clique em **Extensões** > **Apps Script**.
3. No editor de código, **apague tudo que estiver lá** e cole o código completo atualizado abaixo:

```javascript
// ==========================================
// CONFIGURAÇÕES DO SUPABASE E PLANILHA
// ==========================================
// AVISO DE SEGURANÇA (RLS):
// Como o Google Sheets faz chamadas nos bastidores, o banco de dados (que usa RLS)
// vai bloquear as edições se você usar a chave pública ('anon key').
// Por isso, você DEVE usar a 'service_role key' (Chave de Serviço) na variável SUPABASE_KEY abaixo.
const SUPABASE_URL = "https://gcksbfstheavpfgcdndb.supabase.co"; 
const SUPABASE_KEY = "SUPABASE_SERVER_KEY_REMOVED"; // IMPORTANTE: Use a chave service_role para ignorar regras de RLS
const SUPABASE_TABLE = "funcionarios_epi";
const NOME_DA_ABA = "Controle EPI e Fardamento"; // MUITO IMPORTANTE: Mude para o nome exato da aba da sua planilha!

// Função auxiliar para formatar datas do Google Sheets (ex: 2025-12-16T... para 16/12/2025)
function formatarData(valor) {
  if (valor instanceof Date) {
    const d = valor.getDate().toString().padStart(2, '0');
    const m = (valor.getMonth() + 1).toString().padStart(2, '0');
    const y = valor.getFullYear();
    return `${d}/${m}/${y}`;
  }
  // Se já for string (ou vazio), retorna o próprio valor
  return valor ? valor.toString() : "";
}

// ==========================================
// 1. DO GOOGLE SHEETS PARA O SUPABASE (Gatilho Instalável)
// ==========================================
// Foi renomeado de onEdit para syncToSupabaseOnEdit para evitar ser um "Gatilho Simples"
function syncToSupabaseOnEdit(e) {
  if (!e || !e.range) return;
  
  const sheet = e.source.getActiveSheet();
  // Verifica se estamos na aba correta
  if (sheet.getName() !== NOME_DA_ABA) return;
  
  const row = e.range.getRow();
  
  // Ignora o cabeçalho (linha 1)
  if (row <= 1) return;
  
  // A planilha agora tem 10 colunas até a Validação (A até J)
  // [0] Admissão | [1] Nome | [2] CPF | [3] Função | [4] Unidade | [5] EPI Data | [6] (Vazia/Link EPI) | [7] Fardamento Data | [8] Link Fardamento | [9] Validação
  const rowData = sheet.getRange(row, 1, 1, 10).getValues()[0];
  
  // Enviando também o CPF, a Unidade e garantindo a formatação correta das datas
  const payload = {
    admissao: formatarData(rowData[0]),
    nome: rowData[1] ? rowData[1].toString() : "",
    cpf: rowData[2] ? rowData[2].toString() : "",
    funcao: rowData[3] ? rowData[3].toString() : "",
    unidade: rowData[4] ? rowData[4].toString() : "",
    epi_data: formatarData(rowData[5]),
    epi_link: rowData[6] ? rowData[6].toString() : "", 
    fardamento_data: formatarData(rowData[7]),
    fardamento_link: rowData[8] ? rowData[8].toString() : "",
    validacao: rowData[9] ? rowData[9].toString() : ""
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
    
    const sheet = SpreadsheetApp.getActiveSpreadsheet().getSheetByName(NOME_DA_ABA);
    if (!sheet) return ContentService.createTextOutput("Aba não encontrada").setMimeType(ContentService.MimeType.TEXT);

    // Dados do Supabase
    const nomeBusca = record.nome;
    
    const allData = sheet.getDataRange().getValues();
    let rowToUpdate = -1;

    // Procura o funcionário pelo nome (Nome é o índice 1)
    for (let i = 1; i < allData.length; i++) { 
      if (allData[i][1] === nomeBusca) { 
        rowToUpdate = i + 1; // +1 porque arrays começam em 0 e as linhas no sheets começam em 1
        break;
      }
    }

    // Mapeamento das colunas (10 colunas totais agora)
    const newRowData = [
      record.admissao || "",           // Col A (0)
      record.nome || "",               // Col B (1)
      record.cpf || "",                // Col C (2) 
      record.funcao || "",             // Col D (3)
      record.unidade || "",            // Col E (4)
      record.epi_data || "",           // Col F (5)
      record.epi_link || "",           // Col G (6)
      record.fardamento_data || "",    // Col H (7)
      record.fardamento_link || "",    // Col I (8)
      record.validacao || ""           // Col J (9)
    ];

    if (rowToUpdate !== -1) {
      // Atualiza a linha existente
      sheet.getRange(rowToUpdate, 1, 1, 10).setValues([newRowData]);
    } else {
      // Se for INSERT no Supabase e não existe na planilha, cria uma nova linha no final
      sheet.appendRow(newRowData);
    }

    return ContentService.createTextOutput(JSON.stringify({"status": "success"})).setMimeType(ContentService.MimeType.JSON);

  } catch (error) {
    return ContentService.createTextOutput(JSON.stringify({"status": "error", "message": error.message})).setMimeType(ContentService.MimeType.JSON);
  }
}

// ==========================================
// FUNÇÃO EXTRA: SINCRONIZAR TUDO (FORÇAR ATUALIZAÇÃO EM MASSA)
// ==========================================
function syncAllToSupabase() {
  const sheet = SpreadsheetApp.getActiveSpreadsheet().getSheetByName(NOME_DA_ABA);
  if (!sheet) return;
  
  const allData = sheet.getDataRange().getValues();
  
  // Começa de 1 para pular o cabeçalho
  for (let i = 1; i < allData.length; i++) {
    const rowData = allData[i];
    
    // Se não tiver nome, pula
    if (!rowData[1]) continue;
    
    const payload = {
      admissao: formatarData(rowData[0]),
      nome: rowData[1] ? rowData[1].toString() : "",
      cpf: rowData[2] ? rowData[2].toString() : "",
      funcao: rowData[3] ? rowData[3].toString() : "",
      unidade: rowData[4] ? rowData[4].toString() : "",
      epi_data: formatarData(rowData[5]),
      epi_link: rowData[6] ? rowData[6].toString() : "", 
      fardamento_data: formatarData(rowData[7]),
      fardamento_link: rowData[8] ? rowData[8].toString() : "",
      validacao: rowData[9] ? rowData[9].toString() : ""
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
        // Atualiza
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
        // Insere
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
      
      // Pequena pausa para evitar bloqueio da API por fazer muitos requests rápidos
      Utilities.sleep(100); 
      
    } catch (error) {
      console.error(`Erro ao sincronizar funcionário ${payload.nome}:`, error);
    }
  }
  
  // Alerta na tela da planilha quando terminar
  SpreadsheetApp.getUi().alert("Sincronização em massa concluída com sucesso!");
}
```

4. **IMPORTANTE:** Clique no botão de Salvar (ícone de disquete) no Apps Script.

## Parte 2: Configurando o Gatilho Instalável (IMPORTANTE)

Como a sua função faz chamadas externas (para o Supabase), o Google bloqueia isso se for um "Gatilho Simples" (funções com nome `onEdit`). É por isso que você via o erro de permissão. Precisamos dizer explicitamente ao Google para rodar a nossa nova função.

1. No menu esquerdo do Apps Script, clique no ícone de um **Relógio** (chamado "Acionadores" ou "Triggers").
2. No canto inferior direito, clique no botão azul gigante **"Adicionar Acionador"**.
3. Na janela que abrir, configure assim:
   - **Escolha a função que será executada:** Selecione `syncToSupabaseOnEdit`
   - **Escolha qual implantação deve ser executada:** Deixe em `Test` ou `Head`
   - **Selecione a origem do evento:** `Da planilha` (From spreadsheet)
   - **Selecione o tipo de evento:** `Ao editar` (On edit)
4. Clique em **Salvar**.
5. O Google vai abrir um pop-up pedindo permissões. Clique na sua conta. Se der um aviso de segurança (O Google não verificou este app), clique em **Avançado** e depois em **Acessar [Nome do seu script] (não seguro)**.
6. Clique em **Permitir**.

## Parte 3: Publicar o WebApp no Google Scripts

Para o Supabase conseguir mandar dados, precisamos transformar o script num "site" acessível.

1. No topo superior direito do editor do Apps Script, clique no botão azul **"Implantar"** (ou *Deploy*).
2. Selecione **"Nova implantação"** (ou *New deployment*). *(Se já existir uma, você pode gerenciá-la, mas crie uma Nova para garantir)*
3. Ao lado de "Selecione o tipo", clique no ícone da engrenagem ⚙️ e escolha **"App da Web"** (ou *Web app*).
4. Em Descrição, escreva "Webhook Supabase".
5. Em **Executar como**, deixe como "Eu" (seu email).
6. Em **Quem tem acesso**, MUDE para **"Qualquer pessoa"** (*Anyone*). Isso é fundamental para que o servidor do Supabase consiga enviar a requisição de fora!
7. Clique em **"Implantar"**.
8. **Copie o URL do App da Web fornecido.** Vai ser um link que começa com `https://script.google.com/macros/s/.../exec`. 

---

## Parte 4: Configurando o Webhook no Supabase

1. Vá para o painel do seu projeto no Supabase: `https://supabase.com/dashboard/project/gcksbfstheavpfgcdndb`.
2. No menu lateral esquerdo, clique em **"Database"** e depois selecione **"Webhooks"**.
3. Se já existir um Webhook antigo, edite-o. Se não, clique em **"Create Webhook"**.
4. Configure as seguintes opções:
   - **Name:** "Sync to Google Sheets"
   - **Table:** Selecione `funcionarios_epi`
   - **Events:** Selecione `Insert` e `Update`.
5. Na seção de configuração da Webhook (HTTP Request):
   - **Method:** `POST`
   - **URL:** *Cole aqui o URL do App da Web que você copiou no passo anterior do Google Scripts.*
6. Na seção "HTTP Headers", clique em "Add Header":
   - Coloque: `Content-Type: application/json`.
7. Clique em **"Save"** ou **"Create webhook"**.

---

## 🚀 Tudo Pronto!

Agora o ciclo está completo e as permissões estão resolvidas! As modificações feitas na planilha agora terão autorização para notificar o Supabase e vice-versa.
