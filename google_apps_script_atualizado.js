// ==========================================
// CONFIGURAÇÕES DO SUPABASE E PLANILHA
// ==========================================
const SUPABASE_URL = "https://gcksbfstheavpfgcdndb.supabase.co"; 
const SUPABASE_KEY = "SUA_CHAVE_AQUI"; // Certifique-se de preencher com a chave real
const SUPABASE_TABLE = "funcionarios_epi";
const NOME_DA_ABA = "Controle EPI e Fardamento"; 

// Função auxiliar para formatar datas 
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
// 1. DO GOOGLE SHEETS PARA O SUPABASE (Gatilho Instalável)
// ==========================================
function syncToSupabaseOnEdit(e) {
  if (!e || !e.range) return;
  
  const sheet = e.source.getActiveSheet();
  if (sheet.getName() !== NOME_DA_ABA) return;
  
  const row = e.range.getRow();
  if (row <= 1) return;
  
  // A planilha agora tem 13 colunas até a Validação (A até M)
  // [0] Admissão | [1] Nome | [2] CPF | [3] Função | [4] Setor | [5] Unidade 
  // [6] EPI Data | [7] EPI Itens | [8] Link EPI 
  // [9] Fardamento Data | [10] Fardamento Itens | [11] Link Fardamento 
  // [12] Validação
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
    console.error("Erro ao sincronizar:", error);
  }
}

// ==========================================
// 2. DO SUPABASE PARA O GOOGLE SHEETS
// ==========================================
function doPost(e) {
  try {
    const data = JSON.parse(e.postData.contents);
    const record = data.record; 
    
    const sheet = SpreadsheetApp.getActiveSpreadsheet().getSheetByName(NOME_DA_ABA);
    if (!sheet) return ContentService.createTextOutput("Aba não encontrada").setMimeType(ContentService.MimeType.TEXT);

    const nomeBusca = record.nome;
    const allData = sheet.getDataRange().getValues();
    let rowToUpdate = -1;

    for (let i = 1; i < allData.length; i++) { 
      if (allData[i][1] === nomeBusca) { 
        rowToUpdate = i + 1; 
        break;
      }
    }

    const newRowData = [
      record.admissao || "",           // Col A (0)
      record.nome || "",               // Col B (1)
      record.cpf || "",                // Col C (2)
      record.funcao || "",             // Col D (3)
      record.unidade || "",            // Col E (4)
      record.epi_data || "",           // Col F (5)
      record.epi_itens || "",          // Col G (6) NOVO
      record.epi_link || "",           // Col H (7)
      record.fardamento_data || "",    // Col I (8)
      record.fardamento_itens || "",   // Col J (9) NOVO
      record.fardamento_link || "",    // Col K (10)
      record.validacao || ""           // Col L (11)
    ];

    if (rowToUpdate !== -1) {
      sheet.getRange(rowToUpdate, 1, 1, 12).setValues([newRowData]);
    } else {
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
    
    // Se não tiver nome, pula a linha vazia
    if (!rowData[1]) continue;
    
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
        // Já existe: Atualiza
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
        // Não existe: Insere
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
      
      // Pausa rápida de 100ms
      Utilities.sleep(100); 
      
    } catch (error) {
      console.error(`Erro ao sincronizar funcionário ${payload.nome}:`, error);
    }
  }
  
  SpreadsheetApp.getUi().alert("Sincronização em massa concluída com sucesso!");
}
