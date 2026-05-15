# Integração Google Sheets - Indicadores RH e Férias

Este script permite que todas as abas (EPI, Turnover, Absenteísmo e Férias) no seu Google Sheets sejam sincronizadas de forma bidirecional com o Supabase.

### 1. Preparar o Google Sheets
Certifique-se de que sua planilha tenha as seguintes abas com os nomes EXATOS:
- `Controle EPI e Fardamento`
- `movimentacoes`
- `absenteismo`
- `ferias`

### 2. Código Único para o Apps Script
Substitua TODO o conteúdo do seu arquivo atual no Apps Script por este código abaixo. Ele unifica a lógica do EPI com a lógica dos Indicadores, para que um único Webhook funcione para tudo.

```javascript
// ==========================================
// CONFIGURAÇÕES DO SUPABASE E PLANILHA
// ==========================================
const SUPABASE_URL = "https://gcksbfstheavpfgcdndb.supabase.co"; 
const SUPABASE_KEY = "SUA_CHAVE_AQUI"; // Coloque a sua chave Service Role verdadeira aqui

// Função auxiliar para formatar datas (Usada pela aba de EPI)
function formatarData(valor) {
  if (valor instanceof Date) {
    const d = valor.getDate().toString().padStart(2, '0');
    const m = (valor.getMonth() + 1).toString().padStart(2, '0');
    const y = valor.getFullYear();
    return `${d}/${m}/${y}`;
  }
  return valor ? valor.toString() : "";
}

// ==========================================
// 1. GATILHO ON EDIT (Planilha -> Supabase)
// ==========================================
// Esta função roda quando você edita a planilha do google sheets e envia a mudança para o Supabase
function syncToSupabaseOnEdit(e) {
  if (!e || !e.range) return;
  
  const sheet = e.source.getActiveSheet();
  const sheetName = sheet.getName();
  const row = e.range.getRow();
  
  // Se for edição na aba de EPI, usa a lógica linha-a-linha:
  if (sheetName === "Controle EPI e Fardamento") {
      if (row <= 1) return;
      
      const rowData = sheet.getRange(row, 1, 1, 13).getValues()[0];
      const payload = {
        admissao: formatarData(rowData[0]),
        nome: rowData[1] ? rowData[1].toString() : "",
        cpf: rowData[2] ? rowData[2].toString() : "",
        funcao: rowData[3] ? rowData[3].toString() : "",
        setor: rowData[4] ? rowData[4].toString() : "",
        unidade: rowData[5] ? rowData[5].toString() : "",
        epi_data: formatarData(rowData[6]),
        epi_itens: rowData[7] ? rowData[7].toString() : "",
        epi_link: rowData[8] ? rowData[8].toString() : "", 
        fardamento_data: formatarData(rowData[9]),
        fardamento_itens: rowData[10] ? rowData[10].toString() : "",
        fardamento_link: rowData[11] ? rowData[11].toString() : "",
        validacao: rowData[12] ? rowData[12].toString() : ""
      };
      
      try {
        const existingUrl = `${SUPABASE_URL}/rest/v1/funcionarios_epi?nome=eq.${encodeURIComponent(payload.nome)}&select=id`;
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
          const id = records[0].id;
          UrlFetchApp.fetch(`${SUPABASE_URL}/rest/v1/funcionarios_epi?id=eq.${id}`, {
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
          UrlFetchApp.fetch(`${SUPABASE_URL}/rest/v1/funcionarios_epi`, {
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
        console.error("Erro ao sincronizar EPI:", error);
      }
  } 
  // Se for edição nas abas de Indicadores, usa a lógica de sincronização total em massa:
  else if (['movimentacoes', 'absenteismo', 'ferias'].includes(sheetName)) {
      syncIndicadores();
  }
}

// ==========================================
// 2. SINCRONIZAR INDICADORES EM MASSA (Google Sheets -> Supabase)
// ==========================================
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

    const rows = data.slice(1);

    // Deletar os dados da tabela
    const deleteUrl = `${SUPABASE_URL}/rest/v1/${config.tableName}?id=gt.0`;
    const optionsDelete = {
      method: "delete",
      headers: {
        "apikey": SUPABASE_KEY,
        "Authorization": `Bearer ${SUPABASE_KEY}`
      },
      muteHttpExceptions: true
    };
    UrlFetchApp.fetch(deleteUrl, optionsDelete);

    // Inserir novas linhas
    const payload = [];
    rows.forEach((row, rowIndex) => {
      let obj = {};
      let isEmpty = true;
      config.fields.forEach((field, index) => {
        let val = row[index];
        if (val !== "" && val !== undefined && val !== null) isEmpty = false;
        
        if (val instanceof Date) {
          obj[field] = val.toISOString().split('T')[0];
        } else if (val === '' || val === null || val === undefined) {
           obj[field] = null; 
        } else if (typeof val === 'string' && val.trim() === '') {
           obj[field] = null; 
        } else {
          if (config.tableName === 'rh_movimentacoes') {
             if (field === 'tipo_movimentacao' && val) val = String(val).toLowerCase().trim();
             if (field === 'motivo_saida' && val) val = String(val).toLowerCase().trim();
          }
          if (config.tableName === 'rh_absenteismo') {
             if (field === 'horas_previstas' && isNaN(Number(val))) val = null;
             if (field === 'horas_perdidas' && isNaN(Number(val))) val = null;
          }
          if (typeof val === 'number' && (field === 'mes_ref' || field === 'funcionario_nome' || field === 'motivo')) {
             val = String(val);
          }
          obj[field] = val;
        }
      });
      
      if (!isEmpty) {
        if ((config.tableName === 'rh_movimentacoes' || config.tableName === 'rh_absenteismo') && !obj['mes_ref']) {
           console.log(`Pulando linha sem mes_ref na tabela ${config.tableName}:`, obj);
        } else {
           payload.push(obj);
        }
      }
    });

    if (payload.length > 0) {
      const chunkSize = 100;
      for (let i = 0; i < payload.length; i += chunkSize) {
          const chunk = payload.slice(i, i + chunkSize);
          const insertUrl = `${SUPABASE_URL}/rest/v1/${config.tableName}`;
          const optionsInsert = {
            method: "post",
            headers: {
              "apikey": SUPABASE_KEY,
              "Authorization": `Bearer ${SUPABASE_KEY}`,
              "Content-Type": "application/json",
              "Prefer": "return=minimal"
            },
            payload: JSON.stringify(chunk),
            muteHttpExceptions: true
          };
          UrlFetchApp.fetch(insertUrl, optionsInsert);
      }
    }
  });
}

// ==========================================
// 3. WEBHOOK UNIFICADO (Supabase -> Planilha)
// ==========================================
// Lê o webhook do Supabase e decide qual aba preencher
function doPost(e) {
  try {
    const data = JSON.parse(e.postData.contents);
    const type = data.type; // 'INSERT', 'UPDATE', or 'DELETE'
    const record = data.record;
    const oldRecord = data.old_record;
    const table = data.table; // ex: 'funcionarios_epi', 'rh_ferias'

    let targetSheetName = "";
    let nomeBusca = null;
    let fields = [];

    // Mapeamento dinâmico
    if (table === 'funcionarios_epi') {
        targetSheetName = 'Controle EPI e Fardamento'; 
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

    if (!nomeBusca) return ContentService.createTextOutput("Nome não fornecido pelo Supabase").setMimeType(ContentService.MimeType.TEXT);

    const allData = sheet.getDataRange().getValues();
    let rowToUpdate = -1;

    // A coluna de nome na aba EPI é a B(1), nas outras é a A(0)
    const colNameIndex = (table === 'funcionarios_epi') ? 1 : 0; 

    for (let i = 1; i < allData.length; i++) {
      if (allData[i][colNameIndex] === nomeBusca) {
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

### Passo a Passo para Implantar a Integração Unificada

1. Cole o código acima no seu arquivo **`indicadores.gs`** (ou `Código.gs`), apagando tudo o que tinha lá antes. 
2. Atualize a variável `SUPABASE_KEY` no topo do código com a sua chave verdadeira (que começa com `eyJhbGci...`).
3. Clique em **Implantar > Nova implantação**. Selecione o tipo de "Aplicativo da Web". Clique em **Implantar** e copie a "URL do aplicativo da Web".
4. Vá em **Triggers** (Acionadores - ícone de relógio na lateral esquerda). Se você tiver algum trigger existente, certifique-se de que ele esteja chamando a função **`syncToSupabaseOnEdit`**, e que esteja configurado como `Da planilha` e `Ao editar`. (Apague qualquer trigger duplicado).
5. No Supabase, vá em **Database > Webhooks**.
6. Edite seu Webhook existente:
   - Cole a NOVA "URL do aplicativo da Web" que você acabou de gerar no Google Apps Script.
   - Em "Conditions", selecione **todas as 4 tabelas**: `funcionarios_epi`, `rh_movimentacoes`, `rh_absenteismo`, `rh_ferias`.
   - Marque as caixas para Insert, Update, e Delete.
   - Salve.

Agora as 4 abas estão 100% integradas e sincronizadas para enviar e receber informações automaticamente!
