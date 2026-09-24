// ==========================================
// FUNÇÃO PARA CALCULAR HORAS ÚTEIS (ABSENTEÍSMO)
// ==========================================
function calcularHorasUteis(dataInicio, dataFim) {
  if (!dataInicio || !dataFim) return 0;

  let dInicio = dataInicio instanceof Date ? new Date(dataInicio) : new Date(dataInicio + "T00:00:00");
  let dFim = dataFim instanceof Date ? new Date(dataFim) : new Date(dataFim + "T00:00:00");

  if (isNaN(dInicio.getTime()) || isNaN(dFim.getTime()) || dInicio > dFim) {
    return 0;
  }

  let totalHoras = 0;
  let current = new Date(dInicio);

  while (current <= dFim) {
    const diaSemana = current.getDay();
    if (diaSemana >= 1 && diaSemana <= 5) {
      totalHoras += 8;
    } else if (diaSemana === 6) {
      totalHoras += 4;
    }
    current.setDate(current.getDate() + 1);
  }

  return totalHoras;
}

// ==========================================
// CONFIGURAÇÕES DO SUPABASE E PLANILHA
// ==========================================
const SUPABASE_URL = "https://gcksbfstheavpfgcdndb.supabase.co";
const SUPABASE_KEY = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Imdja3NiZnN0aGVhdnBmZ2NkbmRiIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc3Nzc1MDcyNywiZXhwIjoyMDkzMzI2NzI3fQ.yuYxAYnllivwnR7fKzEAfgUIdLEAQZjIBAPrWfQh0IY";

// Configuração das abas e suas tabelas
const SHEET_CONFIG = {
  "Controle EPI e Fardamento": {
    tableName: "funcionarios_epi",
    nameField: "nome",
    fields: [
      "admissao",
      "nome",
      "cpf",
      "funcao",
      "setor",
      "unidade",
      "epi_data",
      "epi_itens",
      "epi_link",
      "fardamento_data",
      "fardamento_itens",
      "fardamento_link",
      "validacao",
      "local_registro",
    ],
  },
  movimentacoes: {
    tableName: "rh_movimentacoes",
    nameField: "funcionario_nome",
    fields: [
      "funcionario_nome",
      "data_admissao",
      "data_desligamento",
      "motivo_saida",
    ],
  },
  absenteismo: {
    tableName: "rh_absenteismo",
    nameField: "id",
    fields: [
      "id",
      "funcionario_nome",
      "data_inicio",
      "data_fim",
      "horas_previstas",
      "horas_perdidas",
      "motivo",
    ],
  },
  ferias: {
    tableName: "rh_ferias",
    nameField: "funcionario_nome",
    fields: [
      "funcionario_nome",
      "data_inicio_aquisitivo",
      "data_fim_aquisitivo",
      "data_vencimento",
      "dias_direito",
      "dias_gozados",
      "status",
      "dias_abonados",
    ],
  },
  epi_funcao: {
    tableName: "epi_funcao",
    nameField: "funcao",
    fields: [
      "funcao",
      "capacete",
      "protetor_auricular",
      "colete_refletivo",
      "protetor_dorsal",
      "calca_faixa_refletiva",
      "bota_marluvas",
      "camisa_elma",
      "regata_elma",
      "camisa_copa",
      "oculos_policarbonato",
    ],
  },
  devolucoes_pendentes: {
    tableName: "devolucoes_pendentes",
    nameField: "funcionario_nome",
    fields: [
      "funcionario_nome",
      "cpf",
      "funcao",
      "setor",
      "unidade",
      "local_registro",
      "data_admissao",
      "data_desligamento",
      "epi_data",
      "epi_itens",
      "fardamento_data",
      "fardamento_itens",
      "status",
    ],
  },
};

// Formatação de data universal YYYY-MM-DD
function formatarData(valor) {
  if (valor instanceof Date) {
    const d = valor.getDate().toString().padStart(2, "0");
    const m = (valor.getMonth() + 1).toString().padStart(2, "0");
    const y = valor.getFullYear();
    return `${y}-${m}-${d}`;
  } else if (typeof valor === "string") {
    const parts = valor.split("/");
    if (parts.length === 3) {
      return `${parts[2]}-${parts[1]}-${parts[0]}`;
    }
  }
  return valor ? valor.toString() : null;
}

function addYears(dateObj, years) {
  let result = new Date(dateObj);
  result.setFullYear(result.getFullYear() + years);
  return result;
}

function addMonths(dateObj, months) {
  let result = new Date(dateObj);
  result.setMonth(result.getMonth() + months);
  return result;
}

// ==========================================
// FUNÇÃO PARA ATUALIZAR/INSERIR REGISTRO NO SUPABASE
// ==========================================
function upsertRecord(tableName, nameField, payload) {
  const identificador = payload[nameField];

  if (nameField === "id" && (!identificador || identificador === "")) {
      try {
          UrlFetchApp.fetch(`${SUPABASE_URL}/rest/v1/${tableName}`, {
            method: "post",
            headers: {
              apikey: SUPABASE_KEY,
              Authorization: `Bearer ${SUPABASE_KEY}`,
              "Content-Type": "application/json",
              Prefer: "return=minimal",
            },
            payload: JSON.stringify([payload]),
          });
          console.log(`Inserido novo registro na tabela ${tableName} (sem ID)`);
      } catch (error) {
          console.error(`Erro ao inserir na tabela ${tableName}: `, error.message);
      }
      return;
  }

  if (!identificador && nameField !== "id") return;

  try {
    let existingUrl;
    let urlWithSelect;

    if (nameField === "id") {
        existingUrl = `${SUPABASE_URL}/rest/v1/${tableName}?id=eq.${identificador}`;
        urlWithSelect = `${existingUrl}&select=id`;
    } else {
        existingUrl = `${SUPABASE_URL}/rest/v1/${tableName}?${nameField}=eq.${encodeURIComponent(identificador)}`;
        urlWithSelect = tableName === "epi_funcao" ? existingUrl : `${existingUrl}&select=id`;
    }

    const response = UrlFetchApp.fetch(urlWithSelect, {
      method: "get",
      headers: {
        apikey: SUPABASE_KEY,
        Authorization: `Bearer ${SUPABASE_KEY}`,
        "Content-Type": "application/json",
      },
    });

    const records = JSON.parse(response.getContentText());

    if (records.length > 0) {
      // UPDATE
      let patchUrl = `${SUPABASE_URL}/rest/v1/${tableName}?`;
      if (tableName === "epi_funcao") {
        patchUrl += `funcao=eq.${encodeURIComponent(identificador)}`;
      } else {
        patchUrl += `id=eq.${records[0].id}`;
      }

      UrlFetchApp.fetch(patchUrl, {
        method: "patch",
        headers: {
          apikey: SUPABASE_KEY,
          Authorization: `Bearer ${SUPABASE_KEY}`,
          "Content-Type": "application/json",
          Prefer: "return=minimal",
        },
        payload: JSON.stringify(payload),
      });
      console.log(`Atualizado registro de ${identificador} na tabela ${tableName}`);
    } else {
      // INSERT
      UrlFetchApp.fetch(`${SUPABASE_URL}/rest/v1/${tableName}`, {
        method: "post",
        headers: {
          apikey: SUPABASE_KEY,
          Authorization: `Bearer ${SUPABASE_KEY}`,
          "Content-Type": "application/json",
          Prefer: "return=minimal",
        },
        payload: JSON.stringify([payload]),
      });
      console.log(`Inserido registro de ${identificador} na tabela ${tableName}`);
    }
  } catch (error) {
    console.error(`Erro ao sincronizar ${identificador} na tabela ${tableName}: `, error.message);
  }
}

// Deleta um registro da tabela no Supabase
function deleteRecord(tableName, fieldName, fieldValue) {
  if (!fieldValue) return;
  try {
    const deleteUrl = `${SUPABASE_URL}/rest/v1/${tableName}?${fieldName}=eq.${encodeURIComponent(fieldValue)}`;
    UrlFetchApp.fetch(deleteUrl, {
      method: "delete",
      headers: {
        apikey: SUPABASE_KEY,
        Authorization: `Bearer ${SUPABASE_KEY}`,
        "Content-Type": "application/json"
      }
    });
    console.log(`Deletado registro com ${fieldName}=${fieldValue} da tabela ${tableName}`);
  } catch(err) {
    console.error(`Erro ao deletar de ${tableName}: `, err.message);
  }
}

// Constrói o payload para uma linha baseada na configuração da aba
function buildPayload(sheetName, rowData) {
  const config = SHEET_CONFIG[sheetName];
  if (!config) return null;

  let payload = {};

  if (sheetName === "Controle EPI e Fardamento") {
    const formatarDataEPI = (v) => {
      if (v instanceof Date) {
        const d = v.getDate().toString().padStart(2, "0");
        const m = (v.getMonth() + 1).toString().padStart(2, "0");
        const y = v.getFullYear();
        return `${d}/${m}/${y}`;
      } else if (typeof v === "string") {
        const parts = v.split("/");
        if (parts.length === 3) {
          return `${parts[0].padStart(2, "0")}/${parts[1].padStart(2, "0")}/${parts[2]}`;
        }
      }
      return v ? v.toString() : "";
    };

    payload = {
      admissao: formatarDataEPI(rowData[0]),
      nome: rowData[1] ? rowData[1].toString() : "",
      cpf: rowData[2] ? rowData[2].toString() : "",
      funcao: rowData[3] ? rowData[3].toString() : "",
      setor: rowData[4] ? rowData[4].toString() : "",
      unidade: rowData[5] ? rowData[5].toString() : "",
      epi_data: formatarDataEPI(rowData[6]),
      epi_itens: rowData[7] ? rowData[7].toString() : "",
      epi_link: rowData[8] ? rowData[8].toString() : "",
      fardamento_data: formatarDataEPI(rowData[9]),
      fardamento_itens: rowData[10] ? rowData[10].toString() : "",
      fardamento_link: rowData[11] ? rowData[11].toString() : "",
      validacao: rowData[12] ? rowData[12].toString() : "",
      local_registro: rowData[13] ? rowData[13].toString() : "",
    };
  } else if (sheetName === "epi_funcao") {
    config.fields.forEach((field, index) => {
      let val = rowData[index];
      if (field === "funcao") {
        payload[field] = val ? val.toString().trim() : "";
      } else {
        payload[field] = val && typeof val === "string" && val.trim().toUpperCase() === "SIM";
      }
    });
  } else {
    config.fields.forEach((field, index) => {
      let val = rowData[index];

      if (field === "id" && (!val || val.toString().trim() === "")) return;

      if (field === "mes_ref") {
        if (val instanceof Date) {
            const m = (val.getMonth() + 1).toString().padStart(2, "0");
            const y = val.getFullYear();
            payload[field] = `${m}/${y}`;
        } else if (typeof val === "string") {
            const valClean = val.trim();
            if (valClean.match(/^\d{4}-\d{2}-\d{2}/)) {
                const parts = valClean.split("T")[0].split("-");
                payload[field] = `${parts[1]}/${parts[0]}`;
            } else if (valClean.match(/^\d{2}\/\d{4}$/)) {
                payload[field] = valClean;
            } else if (valClean.match(/^\d{1,2}\/\d{1,2}\/\d{4}/)) {
                const parts = valClean.split(" ")[0].split("/");
                payload[field] = `${parts[1].padStart(2, '0')}/${parts[2]}`;
            } else if (valClean) {
                payload[field] = valClean.substring(0, 7);
            }
        }
      }
      else if (val instanceof Date || (typeof val === "string" && /\d{1,2}\/\d{1,2}\/\d{4}/.test(val))) {
        const formated = formatarData(val);
        if (formated) payload[field] = formated;
      } else if (val === "" || val === null || val === undefined || (typeof val === "string" && val.trim() === "")) {
        // ignora
      } else {
        if (config.tableName === "rh_movimentacoes" && field === "motivo_saida" && val) {
          val = String(val).toLowerCase().trim();
        }
        if (config.tableName === "rh_absenteismo") {
          if ((field === "horas_previstas" || field === "horas_perdidas") && isNaN(Number(val))) val = null;
        }
        if (typeof val === "number" && (field === "funcionario_nome" || field === "motivo")) {
          val = String(val);
        }
        if (val !== null && payload[field] === undefined) {
          payload[field] = val;
        }
      }
    });

    if (config.tableName === "rh_absenteismo") {
        if (payload["data_inicio"] && typeof payload["data_inicio"] === "string" && /^\d{4}-\d{2}-\d{2}/.test(payload["data_inicio"])) {
            const parts = payload["data_inicio"].split("-");
            payload["mes_ref"] = `${parts[1]}/${parts[0]}`;
        }
        if (payload["data_inicio"] && payload["data_fim"]) {
            if (payload["horas_perdidas"] === undefined || payload["horas_perdidas"] === null || payload["horas_perdidas"] === "") {
                payload["horas_perdidas"] = calcularHorasUteis(payload["data_inicio"], payload["data_fim"]);
            }
        }
    }
  }

  return payload;
}

// ==========================================
// AUTOMAÇÕES DE MOVIMENTAÇÕES E FÉRIAS
// ==========================================

// Sincroniza ativos de Movimentações -> Férias automaticamente
function sincronizarAtivosParaFerias() {
  const ss = SpreadsheetApp.getActiveSpreadsheet();
  const movSheet = ss.getSheetByName("movimentacoes");
  const feriasSheet = ss.getSheetByName("ferias");
  if (!movSheet || !feriasSheet) return;

  const movData = movSheet.getDataRange().getValues();
  const feriasData = feriasSheet.getDataRange().getValues();

  const feriasNomesSet = new Set();
  for (let i = 1; i < feriasData.length; i++) {
    const nome = feriasData[i][0] ? feriasData[i][0].toString().trim().toUpperCase() : "";
    if (nome) feriasNomesSet.add(nome);
  }

  for (let i = 1; i < movData.length; i++) {
    const nome = movData[i][0] ? movData[i][0].toString().trim() : "";
    const dtAdmissaoVal = movData[i][1];
    const dtDesligamentoVal = movData[i][2];

    if (nome && dtAdmissaoVal && (!dtDesligamentoVal || dtDesligamentoVal.toString().trim() === "")) {
      const nomeUpper = nome.toUpperCase();
      if (!feriasNomesSet.has(nomeUpper)) {
        let dtAdmissao = dtAdmissaoVal instanceof Date ? dtAdmissaoVal : new Date(formatarData(dtAdmissaoVal));
        if (isNaN(dtAdmissao.getTime())) continue;

        let dtFimAquisitivo = addYears(dtAdmissao, 1);
        dtFimAquisitivo.setDate(dtFimAquisitivo.getDate() - 1);

        let dtVencimento = addMonths(dtFimAquisitivo, 11);

        let dtIniStr = formatarData(dtAdmissao);
        let dtFimStr = formatarData(dtFimAquisitivo);
        let dtVencStr = formatarData(dtVencimento);

        feriasSheet.appendRow([nome, dtIniStr, dtFimStr, dtVencStr, 30, 0, "pendente", 0]);

        upsertRecord("rh_ferias", "funcionario_nome", {
          funcionario_nome: nome,
          data_inicio_aquisitivo: dtIniStr,
          data_fim_aquisitivo: dtFimStr,
          data_vencimento: dtVencStr,
          dias_direito: 30,
          dias_gozados: 0,
          status: "pendente",
          dias_abonados: 0
        });

        feriasNomesSet.add(nomeUpper);
        console.log(`Criado registro de férias automático para ${nome}`);
      }
    }
  }
}

// Trata o desligamento de funcionário nas abas e banco de dados
function verificarETratarDesligamento(funcionarioNome, dataDesligamento) {
  if (!funcionarioNome || !dataDesligamento) return;
  const ss = SpreadsheetApp.getActiveSpreadsheet();
  const nomeUpper = funcionarioNome.toString().trim().toUpperCase();

  // 1. Remover da aba e tabela "ferias"
  const feriasSheet = ss.getSheetByName("ferias");
  if (feriasSheet) {
    const data = feriasSheet.getDataRange().getValues();
    for (let i = data.length - 1; i >= 1; i--) {
      if (data[i][0] && data[i][0].toString().trim().toUpperCase() === nomeUpper) {
        feriasSheet.deleteRow(i + 1);
      }
    }
  }
  deleteRecord("rh_ferias", "funcionario_nome", funcionarioNome);

  // 2. Remover da aba e tabela "absenteismo"
  const absSheet = ss.getSheetByName("absenteismo");
  if (absSheet) {
    const data = absSheet.getDataRange().getValues();
    for (let i = data.length - 1; i >= 1; i--) {
      if (data[i][1] && data[i][1].toString().trim().toUpperCase() === nomeUpper) {
        absSheet.deleteRow(i + 1);
      }
    }
  }
  deleteRecord("rh_absenteismo", "funcionario_nome", funcionarioNome);

  // 3. Verificar EPIs e Fardamentos em "Controle EPI e Fardamento"
  const epiSheet = ss.getSheetByName("Controle EPI e Fardamento");
  if (epiSheet) {
    const data = epiSheet.getDataRange().getValues();
    let rowIdx = -1;
    for (let i = 1; i < data.length; i++) {
      if (data[i][1] && data[i][1].toString().trim().toUpperCase() === nomeUpper) {
        rowIdx = i;
        break;
      }
    }

    if (rowIdx !== -1) {
      const row = data[rowIdx];
      const epiItens = row[7] ? row[7].toString().trim() : "";
      const fardItens = row[10] ? row[10].toString().trim() : "";

      if (epiItens !== "" || fardItens !== "") {
        const devPayload = {
          funcionario_nome: row[1] ? row[1].toString() : funcionarioNome,
          cpf: row[2] ? row[2].toString() : "",
          funcao: row[3] ? row[3].toString() : "",
          setor: row[4] ? row[4].toString() : "",
          unidade: row[5] ? row[5].toString() : "",
          local_registro: row[13] ? row[13].toString() : "",
          data_admissao: formatarData(row[0]),
          data_desligamento: formatarData(dataDesligamento),
          epi_data: row[6] ? row[6].toString() : "",
          epi_itens: epiItens,
          fardamento_data: row[9] ? row[9].toString() : "",
          fardamento_itens: fardItens,
          status: "pendente"
        };

        const devSheet = ss.getSheetByName("devolucoes_pendentes");
        if (devSheet) {
          devSheet.appendRow([
            devPayload.funcionario_nome,
            devPayload.cpf,
            devPayload.funcao,
            devPayload.setor,
            devPayload.unidade,
            devPayload.local_registro,
            devPayload.data_admissao,
            devPayload.data_desligamento,
            devPayload.epi_data,
            devPayload.epi_itens,
            devPayload.fardamento_data,
            devPayload.fardamento_itens,
            "pendente"
          ]);
        }

        upsertRecord("devolucoes_pendentes", "funcionario_nome", devPayload);
        console.log(`Criada pendência de devolução para ${funcionarioNome}`);
      }

      epiSheet.deleteRow(rowIdx + 1);
      deleteRecord("funcionarios_epi", "nome", funcionarioNome);
    }
  }
}

// ==========================================
// 1. GATILHO ON EDIT (Planilha -> Supabase)
// ==========================================
function syncToSupabaseOnEdit(e) {
  if (!e || !e.range) return;

  const sheet = e.source.getActiveSheet();
  const sheetName = sheet.getName();
  const row = e.range.getRow();

  if (row <= 1) return;

  const config = SHEET_CONFIG[sheetName];
  if (!config) return;

  if (sheetName === "absenteismo") {
    const dataInicioCell = sheet.getRange(row, 3);
    const dataFimCell = sheet.getRange(row, 4);
    const horasPerdidasCell = sheet.getRange(row, 6);

    const vDataInicio = dataInicioCell.getValue();
    const vDataFim = dataFimCell.getValue();
    const vHorasPerdidas = horasPerdidasCell.getValue();

    if (vDataInicio && vDataFim && (vHorasPerdidas === "" || vHorasPerdidas === null)) {
      let dtIniStr = formatarData(vDataInicio);
      let dtFimStr = formatarData(vDataFim);

      if (dtIniStr && dtFimStr) {
        const horasCalculadas = calcularHorasUteis(dtIniStr, dtFimStr);
        horasPerdidasCell.setValue(horasCalculadas);
      }
    }
  }

  const numColumns = config.fields.length;
  const columnsToFetch = sheetName === "Controle EPI e Fardamento" ? 14 : numColumns;

  const rowData = sheet.getRange(row, 1, 1, columnsToFetch).getValues()[0];
  const payload = buildPayload(sheetName, rowData);

  if (payload) {
    upsertRecord(config.tableName, config.nameField, payload);

    if (sheetName === "movimentacoes") {
      const funcionarioNome = payload["funcionario_nome"];
      const dataDesligamento = payload["data_desligamento"];

      if (dataDesligamento && dataDesligamento !== "") {
        verificarETratarDesligamento(funcionarioNome, dataDesligamento);
      } else if (payload["data_admissao"]) {
        sincronizarAtivosParaFerias();
      }
    }

    if (sheetName === "devolucoes_pendentes") {
      const statusVal = payload["status"] ? payload["status"].toString().trim().toUpperCase() : "";
      if (statusVal === "DEVOLVIDO" || statusVal === "OK") {
        deleteRecord("devolucoes_pendentes", "funcionario_nome", payload["funcionario_nome"]);
        sheet.deleteRow(row);
      }
    }
  }
}

// ==========================================
// 2. SINCRONIZAÇÃO EM MASSA DE TODAS AS ABAS
// ==========================================
function syncAllToSupabase() {
  const ss = SpreadsheetApp.getActiveSpreadsheet();
  const sheetNames = Object.keys(SHEET_CONFIG);

  sheetNames.forEach((sheetName) => {
    const sheet = ss.getSheetByName(sheetName);
    if (!sheet) return;

    const config = SHEET_CONFIG[sheetName];
    const data = sheet.getDataRange().getValues();
    if (data.length <= 1) return;

    const columnsToFetch = sheetName === "Controle EPI e Fardamento" ? 14 : config.fields.length;

    for (let i = 1; i < data.length; i++) {
      const rowData = data[i].slice(0, columnsToFetch);
      const payload = buildPayload(sheetName, rowData);
      if (!payload || !payload[config.nameField]) continue;

      upsertRecord(config.tableName, config.nameField, payload);
      Utilities.sleep(100);
    }
  });

  sincronizarAtivosParaFerias();

  try {
    SpreadsheetApp.getUi().alert("Sincronização completa de todas as abas finalizada com sucesso!");
  } catch (e) {
    console.log("Sincronização completa finalizada com sucesso! (UI não disponível)");
  }
}

// ==========================================
// 3. WEBHOOK UNIFICADO (Supabase -> Planilha)
// ==========================================
function doPost(e) {
  try {
    const data = JSON.parse(e.postData.contents);
    const type = data.type;
    const record = data.record;
    const oldRecord = data.old_record;
    const table = data.table;

    let targetSheetName = "";
    let nomeBusca = null;
    let fields = [];

    if (table === "funcionarios_epi") {
      targetSheetName = "Controle EPI e Fardamento";
      nomeBusca = type === "DELETE" ? (oldRecord ? oldRecord.nome : null) : (record ? record.nome : null);
      fields = SHEET_CONFIG[targetSheetName].fields;
    } else if (table === "rh_movimentacoes") {
      targetSheetName = "movimentacoes";
      nomeBusca = type === "DELETE" ? (oldRecord ? oldRecord.funcionario_nome : null) : (record ? record.funcionario_nome : null);
      fields = SHEET_CONFIG[targetSheetName].fields;
    } else if (table === "rh_absenteismo") {
      targetSheetName = "absenteismo";
      nomeBusca = type === "DELETE" ? (oldRecord ? oldRecord.funcionario_nome : null) : (record ? record.funcionario_nome : null);
      fields = SHEET_CONFIG[targetSheetName].fields;
    } else if (table === "rh_ferias") {
      targetSheetName = "ferias";
      nomeBusca = type === "DELETE" ? (oldRecord ? oldRecord.funcionario_nome : null) : (record ? record.funcionario_nome : null);
      fields = SHEET_CONFIG[targetSheetName].fields;
    } else if (table === "epi_funcao") {
      targetSheetName = "epi_funcao";
      nomeBusca = type === "DELETE" ? (oldRecord ? oldRecord.funcao : null) : (record ? record.funcao : null);
      fields = SHEET_CONFIG[targetSheetName].fields;
    } else if (table === "devolucoes_pendentes") {
      targetSheetName = "devolucoes_pendentes";
      nomeBusca = type === "DELETE" ? (oldRecord ? oldRecord.funcionario_nome : null) : (record ? record.funcionario_nome : null);
      fields = SHEET_CONFIG[targetSheetName].fields;
    }

    if (!targetSheetName) return ContentService.createTextOutput("Tabela não mapeada").setMimeType(ContentService.MimeType.TEXT);

    const sheet = SpreadsheetApp.getActiveSpreadsheet().getSheetByName(targetSheetName);
    if (!sheet) return ContentService.createTextOutput("Aba não encontrada").setMimeType(ContentService.MimeType.TEXT);

    if (!nomeBusca) return ContentService.createTextOutput("Chave (nome/função) não fornecida pelo Supabase").setMimeType(ContentService.MimeType.TEXT);

    const allData = sheet.getDataRange().getValues();
    let rowToUpdate = -1;

    let colNameIndex = 0;
    if (table === "funcionarios_epi") colNameIndex = 1;
    if (table === "rh_absenteismo") colNameIndex = 1;

    for (let i = 1; i < allData.length; i++) {
      if (targetSheetName === "absenteismo") {
          let idPlanilha = allData[i][0];
          let nomePlanilha = allData[i][1];
          let dataInicioPlanilha = allData[i][2];

          if (record && record.id && idPlanilha == record.id) {
              rowToUpdate = i + 1;
              break;
          }

          if (nomePlanilha === nomeBusca && record && record.data_inicio) {
              let dataPlanilhaFormatada = "";
              if (dataInicioPlanilha instanceof Date) {
                  dataPlanilhaFormatada = dataInicioPlanilha.toISOString().split("T")[0];
              } else if (typeof dataInicioPlanilha === "string") {
                  if (dataInicioPlanilha.match(/^\d{1,2}\/\d{1,2}\/\d{4}/)) {
                      let p = dataInicioPlanilha.split(" ")[0].split("/");
                      dataPlanilhaFormatada = `${p[2]}-${p[1].padStart(2, '0')}-${p[0].padStart(2, '0')}`;
                  } else {
                      dataPlanilhaFormatada = dataInicioPlanilha.split("T")[0];
                  }
              }

              if (dataPlanilhaFormatada === record.data_inicio) {
                  rowToUpdate = i + 1;
                  break;
              }
          }
      } else {
          if (allData[i][colNameIndex] === nomeBusca) {
              rowToUpdate = i + 1;
              break;
          }
      }
    }

    if (type === "DELETE") {
      if (rowToUpdate !== -1) {
        sheet.deleteRow(rowToUpdate);
        return ContentService.createTextOutput(JSON.stringify({ status: "success", action: "deleted" })).setMimeType(ContentService.MimeType.JSON);
      }
      return ContentService.createTextOutput(JSON.stringify({ status: "ignored", message: "Linha não encontrada para deletar" })).setMimeType(ContentService.MimeType.JSON);
    }

    const existingRow = rowToUpdate !== -1 ? sheet.getRange(rowToUpdate, 1, 1, fields.length).getValues()[0] : Array(fields.length).fill("");

    const newRowData = fields.map((field, index) => {
      if (targetSheetName === "epi_funcao" && field !== "funcao") {
        if (record.hasOwnProperty(field)) {
          return record[field] ? "SIM" : "NÃO";
        } else {
          return existingRow[index];
        }
      } else {
        if (record.hasOwnProperty(field)) {
            let val = record[field];
            if (val === null) return "";
            if (typeof val === "string" && /^\d{4}-\d{2}-\d{2}$/.test(val)) {
                const parts = val.split("-");
                return `${parts[2]}/${parts[1]}/${parts[0]}`;
            }
            return val;
        } else {
            return existingRow[index];
        }
      }
    });

    if (rowToUpdate !== -1) {
      sheet.getRange(rowToUpdate, 1, 1, fields.length).setValues([newRowData]);
      return ContentService.createTextOutput(JSON.stringify({ status: "success", action: "updated" })).setMimeType(ContentService.MimeType.JSON);
    } else {
      sheet.appendRow(newRowData);
      return ContentService.createTextOutput(JSON.stringify({ status: "success", action: "inserted" })).setMimeType(ContentService.MimeType.JSON);
    }
  } catch (error) {
    return ContentService.createTextOutput(JSON.stringify({ status: "error", message: error.message })).setMimeType(ContentService.MimeType.JSON);
  }
}
