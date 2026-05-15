# Integração Google Sheets - Indicadores RH e Férias

Este script permite que as abas de indicadores (Turnover, Absenteísmo e Férias) no seu Google Sheets sejam enviadas automaticamente para o Supabase e vice-versa.

### 1. Preparar o Google Sheets
Crie 3 abas novas na sua planilha com os seguintes nomes EXATOS:
- `movimentacoes`
- `absenteismo`
- `ferias`

### 2. Formato das Colunas (Aba "movimentacoes")
- **A**: `funcionario_nome` (Ex: Joao da Silva)
- **B**: `data_admissao` (Ex: 2024-01-15 - pode ficar vazio)
- **C**: `data_desligamento` (Ex: 2024-05-10 - pode ficar vazio)
- **D**: `tipo_movimentacao` (entrada ou saida - minúsculo, obrigatório)
- **E**: `motivo_saida` (voluntario ou involuntario - obrigatório se for saida, vazio se for entrada)
- **F**: `mes_ref` (Ex: 2024-05 - **OBRIGATÓRIO**)

### 3. Formato das Colunas (Aba "absenteismo")
- **A**: `funcionario_nome` (Ex: Joao da Silva)
- **B**: `mes_ref` (Ex: 2024-05 - **OBRIGATÓRIO**)
- **C**: `horas_previstas` (Ex: 220 - número, pode ficar vazio se não souber)
- **D**: `horas_perdidas` (Ex: 8.5 - número, pode ficar vazio)
- **E**: `motivo` (Ex: Atestado)

### 4. Formato das Colunas (Aba "ferias")
- **A**: `funcionario_nome` (Ex: Joao da Silva)
- **B**: `data_inicio_aquisitivo` (Ex: 2023-01-01)
- **C**: `data_fim_aquisitivo` (Ex: 2023-12-31)
- **D**: `data_vencimento` (Ex: 2024-12-31)
- **E**: `dias_direito` (Ex: 30)
- **F**: `dias_gozados` (Ex: 10)
- **G**: `status` (pendente, programadas, concluidas)

### 5. Código no Apps Script
Vá em `Extensões > Apps Script` e **adicione esse código ao final do seu arquivo existente** (ou crie um novo `indicadores.gs`). Cole o código abaixo:

```javascript
// ATENÇÃO: Substitua pelas suas credenciais reais do Supabase
const SUPABASE_URL_INDICADORES = 'https://gcksbfstheavpfgcdndb.supabase.co';
const SUPABASE_KEY_INDICADORES = 'SUA_CHAVE_AQUI'; // Insira a sua chave Service Role

function syncIndicadores() {
  const sheetNames = [
    { sheetName: 'movimentacoes', tableName: 'rh_movimentacoes', 
      fields: ['funcionario_nome', 'data_admissao', 'data_desligamento', 'tipo_movimentacao', 'motivo_saida', 'mes_ref'] 
    },
    { sheetName: 'absenteismo', tableName: 'rh_absenteismo', 
      fields: ['funcionario_nome', 'mes_ref', 'horas_previstas', 'horas_perdidas', 'motivo'] 
    },
    { sheetName: 'ferias', tableName: 'rh_ferias', 
      fields: ['funcionario_nome', 'data_inicio_aquisitivo', 'data_fim_aquisitivo', 'data_vencimento', 'dias_direito', 'dias_gozados', 'status'] 
    }
  ];

  const ss = SpreadsheetApp.getActiveSpreadsheet();

  sheetNames.forEach(config => {
    const sheet = ss.getSheetByName(config.sheetName);
    if (!sheet) return;

    const data = sheet.getDataRange().getValues();
    if (data.length <= 1) return; // Só tem cabeçalho

    const headers = data[0];
    const rows = data.slice(1);

    // Primeiro, vamos deletar tudo da tabela para manter sincronizado (Abordagem de Replace All)
    // Para tabelas grandes isso não é ideal, mas para indicadores simplifica.
    // Opcionalmente você pode fazer Upsert.
    
    // Deletar os dados da tabela
    const deleteUrl = `${SUPABASE_URL_INDICADORES}/rest/v1/${config.tableName}?id=gt.0`;
    const optionsDelete = {
      method: "delete",
      headers: {
        "apikey": SUPABASE_KEY_INDICADORES,
        "Authorization": `Bearer ${SUPABASE_KEY_INDICADORES}`
      },
      muteHttpExceptions: true
    };
    UrlFetchApp.fetch(deleteUrl, optionsDelete);

    // Agora inserimos as novas linhas
    const payload = [];
    rows.forEach((row, rowIndex) => {
      let obj = {};
      let isEmpty = true;
      config.fields.forEach((field, index) => {
        let val = row[index];
        if (val !== "" && val !== undefined && val !== null) isEmpty = false;
        
        // Conversão de data do formato Google Sheets para YYYY-MM-DD
        if (val instanceof Date) {
          obj[field] = val.toISOString().split('T')[0];
        } else if (val === '' || val === null || val === undefined) {
           obj[field] = null; // Evita erros em dados nulos
        } else if (typeof val === 'string' && val.trim() === '') {
           obj[field] = null; // Evita erros em strings vazias com espaços
        } else {
          // Prevenindo Constraint Checking errors:
          if (config.tableName === 'rh_movimentacoes') {
             if (field === 'tipo_movimentacao' && val) val = String(val).toLowerCase().trim();
             if (field === 'motivo_saida' && val) val = String(val).toLowerCase().trim();
          }
          if (config.tableName === 'rh_absenteismo') {
             if (field === 'horas_previstas' && isNaN(Number(val))) val = null;
             if (field === 'horas_perdidas' && isNaN(Number(val))) val = null;
          }
          // Garante que campos de texto sejam strings
          if (typeof val === 'number' && (field === 'mes_ref' || field === 'funcionario_nome' || field === 'motivo')) {
             val = String(val);
          }
          obj[field] = val;
        }
      });
      
      // Validação: Ignora linhas que estão completamente vazias ou que não tem mes_ref (se for obrigatório na tabela)
      if (!isEmpty) {
        if ((config.tableName === 'rh_movimentacoes' || config.tableName === 'rh_absenteismo') && !obj['mes_ref']) {
           // Se a linha tem nome mas não tem mês ref, vamos pular ela para não dar erro
           console.log(`Pulando linha sem mes_ref na tabela ${config.tableName}:`, obj);
        } else {
           payload.push(obj);
        }
      }
    });

    if (payload.length > 0) {
      // Chunking payload in groups of 100 to avoid large payload errors, just in case
      const chunkSize = 100;
      for (let i = 0; i < payload.length; i += chunkSize) {
          const chunk = payload.slice(i, i + chunkSize);
          const insertUrl = `${SUPABASE_URL_INDICADORES}/rest/v1/${config.tableName}`;
          const optionsInsert = {
            method: "post",
            headers: {
              "apikey": SUPABASE_KEY_INDICADORES,
              "Authorization": `Bearer ${SUPABASE_KEY_INDICADORES}`,
              "Content-Type": "application/json",
              "Prefer": "return=minimal"
            },
            payload: JSON.stringify(chunk),
            muteHttpExceptions: true
          };
          
          const res = UrlFetchApp.fetch(insertUrl, optionsInsert);
          console.log(`Tabela ${config.tableName} sync chunk ${i/chunkSize}: `, res.getResponseCode(), res.getContentText());
      }
    }
  });
}

// ==========================================
// 6. GATILHOS AUTOMÁTICOS PARA EDIÇÃO (Planilha -> Supabase)
// ==========================================
// Esta função roda quando você edita a planilha do google sheets e envia a mudança para o Supabase
function syncIndicadoresOnEdit(e) {
  if (!e || !e.range) return;
  const sheet = e.source.getActiveSheet();
  const sheetName = sheet.getName();
  
  if (['movimentacoes', 'absenteismo', 'ferias'].includes(sheetName)) {
    // Para simplificar, quando houver edição, a gente dispara o sync total daquela aba (ou de todas).
    syncIndicadores();
  }
}

// ==========================================
// 7. WEBHOOK (Supabase -> Planilha)
// ==========================================
// Substitua o doPost do seu código atual por este que tem suporte para múltiplas abas:
function doPost(e) {
  try {
    const data = JSON.parse(e.postData.contents);
    const type = data.type; // 'INSERT', 'UPDATE', or 'DELETE'
    const record = data.record;
    const oldRecord = data.old_record;
    const table = data.table; // Supabase envia o nome da tabela no payload (ex: 'funcionarios_epi', 'rh_ferias')

    let targetSheetName = "";
    let nomeBusca = null;
    let fields = [];

    // Mapear qual aba e quais campos usar dependendo da tabela que disparou o Webhook
    if (table === 'funcionarios_epi') {
        targetSheetName = 'Controle EPI e Fardamento'; // Nome da aba principal
        nomeBusca = type === 'DELETE' ? (oldRecord ? oldRecord.nome : null) : (record ? record.nome : null);
        fields = ['admissao', 'nome', 'cpf', 'funcao', 'setor', 'unidade', 'epi_data', 'epi_itens', 'epi_link', 'fardamento_data', 'fardamento_itens', 'fardamento_link', 'validacao'];
    } else if (table === 'rh_movimentacoes') {
        targetSheetName = 'movimentacoes';
        nomeBusca = type === 'DELETE' ? (oldRecord ? oldRecord.funcionario_nome : null) : (record ? record.funcionario_nome : null);
        fields = ['funcionario_nome', 'data_admissao', 'data_desligamento', 'tipo_movimentacao', 'motivo_saida', 'mes_ref'];
    } else if (table === 'rh_absenteismo') {
        targetSheetName = 'absenteismo';
        nomeBusca = type === 'DELETE' ? (oldRecord ? oldRecord.funcionario_nome : null) : (record ? record.funcionario_nome : null);
        fields = ['funcionario_nome', 'mes_ref', 'horas_previstas', 'horas_perdidas', 'motivo'];
    } else if (table === 'rh_ferias') {
        targetSheetName = 'ferias';
        nomeBusca = type === 'DELETE' ? (oldRecord ? oldRecord.funcionario_nome : null) : (record ? record.funcionario_nome : null);
        fields = ['funcionario_nome', 'data_inicio_aquisitivo', 'data_fim_aquisitivo', 'data_vencimento', 'dias_direito', 'dias_gozados', 'status'];
    }

    if (!targetSheetName) return ContentService.createTextOutput("Tabela não mapeada").setMimeType(ContentService.MimeType.TEXT);

    const sheet = SpreadsheetApp.getActiveSpreadsheet().getSheetByName(targetSheetName);
    if (!sheet) return ContentService.createTextOutput("Aba não encontrada").setMimeType(ContentService.MimeType.TEXT);

    if (!nomeBusca) return ContentService.createTextOutput("Nome/ID não fornecido pelo Supabase").setMimeType(ContentService.MimeType.TEXT);

    const allData = sheet.getDataRange().getValues();
    let rowToUpdate = -1;

    // A coluna onde fica o nome costuma ser a A (índice 0) ou B (índice 1). 
    // Na tabela EPI é a B (índice 1). Nas novas tabelas RH é a A (índice 0).
    const colNameIndex = (table === 'funcionarios_epi') ? 1 : 0; 

    // Procura o funcionário pelo nome (e opcionalmente mes_ref para tabelas agrupadas se fosse mais complexo)
    for (let i = 1; i < allData.length; i++) {
      if (allData[i][colNameIndex] === nomeBusca) {
        // Se for absenteismo ou movimentacoes e for um UPDATE, o ideal seria combinar nome + mes_ref
        // Mas para simplificar vamos achar o primeiro correspondente.
        rowToUpdate = i + 1;
        break;
      }
    }

    if (type === 'DELETE') {
      if (rowToUpdate !== -1) {
        sheet.deleteRow(rowToUpdate);
        return ContentService.createTextOutput(JSON.stringify({"status": "success", "action": "deleted"})).setMimeType(ContentService.MimeType.JSON);
      }
      return ContentService.createTextOutput(JSON.stringify({"status": "ignored", "message": "Linha não encontrada para deletar"})).setMimeType(ContentService.MimeType.JSON);
    }

    // Se for INSERT ou UPDATE, montar os novos dados
    const existingRow = rowToUpdate !== -1 ? sheet.getRange(rowToUpdate, 1, 1, fields.length).getValues()[0] : Array(fields.length).fill("");

    const newRowData = fields.map((field, index) => {
        return record.hasOwnProperty(field) ? (record[field] === null ? "" : record[field]) : existingRow[index];
    });

    if (rowToUpdate !== -1) {
      sheet.getRange(rowToUpdate, 1, 1, fields.length).setValues([newRowData]);
      return ContentService.createTextOutput(JSON.stringify({"status": "success", "action": "updated"})).setMimeType(ContentService.MimeType.JSON);
    } else {
      sheet.appendRow(newRowData);
      return ContentService.createTextOutput(JSON.stringify({"status": "success", "action": "inserted"})).setMimeType(ContentService.MimeType.JSON);
    }

  } catch (error) {
    return ContentService.createTextOutput(JSON.stringify({"status": "error", "message": error.message})).setMimeType(ContentService.MimeType.JSON);
  }
}
```

### 6. Como configurar o Webhook Bidirecional no Supabase (Site -> Planilha)
Para que a comunicação funcione do **Site/Supabase PARA o Google Sheets** nas tabelas novas:

1. No Supabase, vá em **Database** -> **Webhooks**.
2. O webhook atual deve estar apontando para a sua URL `https://script.google.com/macros/s/AKfy.../exec`.
3. Verifique se o seu Webhook atual está configurado para disparar na tabela `funcionarios_epi`.
4. Você precisa editar o webhook atual (ou criar webhooks novos com a mesma URL de destino) e marcar as caixas (Insert, Update, Delete) para as tabelas **`rh_movimentacoes`**, **`rh_absenteismo`** e **`rh_ferias`**.
5. Salve. O Supabase começará a enviar as alterações do site para o seu Google Sheets através do novo método `doPost()` acima!
