// Função para calcular horas úteis entre duas datas
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
const SUPABASE_KEY = "SUPABASE_SERVER_KEY_REMOVED"; // Coloque a sua chave Service Role verdadeira aqui

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
    nameField: "id", // Use ID to identify rows uniquely for updates
    fields: [
      "id", // Coluna A
      "funcionario_nome", // Coluna B
      "data_inicio", // Coluna C
      "data_fim", // Coluna D
      "horas_previstas", // Coluna E
      "horas_perdidas", // Coluna F
      "motivo", // Coluna G
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
};

// Função auxiliar para formatar datas
function formatarData(valor) {
  if (valor instanceof Date) {
    const d = valor.getDate().toString().padStart(2, "0");
    const m = (valor.getMonth() + 1).toString().padStart(2, "0");
    const y = valor.getFullYear();
    // O banco espera YYYY-MM-DD para colunas de data padrão, mas a aba EPI formata para DD/MM/YYYY.
    // Para simplificar, usamos o formato YYYY-MM-DD para ser aceito universalmente pelas colunas tipo "date" do Supabase
    return `${y}-${m}-${d}`;
  } else if (typeof valor === "string") {
    // Tenta converter string do formato DD/MM/YYYY para YYYY-MM-DD
    const parts = valor.split("/");
    if (parts.length === 3) {
      return `${parts[2]}-${parts[1]}-${parts[0]}`;
    }
  }
  return valor ? valor.toString() : null;
}

// ==========================================
// FUNÇÕES DE SINCRONIZAÇÃO LINEAR
// ==========================================

// Atualiza ou Insere um registro no Supabase
function upsertRecord(tableName, nameField, payload) {
  const identificador = payload[nameField];

  // Se a tabela usar "id" como chave e ele estiver ausente no payload (linha nova na planilha), é um INSERT direto
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
          console.log(`Inserido novo registro na tabela ${tableName} (sem ID definido)`);
      } catch (error) {
          console.error(`Erro ao inserir na tabela ${tableName}: `, error.message);
      }
      return;
  }

  if (!identificador && nameField !== "id") return; // Para tabelas normais onde nome é obrigatório

  try {
    let existingUrl;
    let urlWithSelect;

    // Agora que sabemos o ID exato (se tiver), podemos buscar direto
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
      console.log(
        `Inserido novo registro de ${identificador} na tabela ${tableName}`,
      );
    }
  } catch (error) {
    console.error(
      `Erro ao sincronizar ${identificador} na tabela ${tableName}: O payload era `,
      JSON.stringify(payload),
      ` | Erro: `,
      error.message,
    );
  }
}

// Constrói o payload para uma linha baseada na configuração da aba
function buildPayload(sheetName, rowData) {
  const config = SHEET_CONFIG[sheetName];
  if (!config) return null;

  let payload = {};

  if (sheetName === "Controle EPI e Fardamento") {
    // A aba EPI tem formato especial DD/MM/YYYY e lida com datas como string formatada
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
    };
  } else if (sheetName === "epi_funcao") {
    // Transforma "SIM" em true, o resto em false
    config.fields.forEach((field, index) => {
      let val = rowData[index];
      if (field === "funcao") {
        payload[field] = val ? val.toString().trim() : "";
      } else {
        payload[field] =
          val && typeof val === "string" && val.trim().toUpperCase() === "SIM";
      }
    });
  } else {
    // Para as demais abas de indicadores (movimentacoes, absenteismo, ferias)
    config.fields.forEach((field, index) => {
      let val = rowData[index];

      if (field === "id" && (!val || val.toString().trim() === "")) {
          // Ignora ID vazio
          return;
      }

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
      else if (
        val instanceof Date ||
        (typeof val === "string" && /\d{1,2}\/\d{1,2}\/\d{4}/.test(val))
      ) {
        const formated = formatarData(val);
        if (formated) payload[field] = formated;
      } else if (
        val === "" ||
        val === null ||
        val === undefined ||
        (typeof val === "string" && val.trim() === "")
      ) {
        // Vazio: ignora
      } else {
        if (config.tableName === "rh_movimentacoes") {
          if (field === "motivo_saida" && val)
            val = String(val).toLowerCase().trim();
        }
        if (config.tableName === "rh_absenteismo") {
          if (field === "horas_previstas" && isNaN(Number(val))) {
            val = null;
          }
          if (field === "horas_perdidas" && isNaN(Number(val))) {
            val = null;
          }
        }
        if (
          typeof val === "number" &&
          (field === "funcionario_nome" || field === "motivo")
        ) {
          val = String(val);
        }

        if (val !== null && payload[field] === undefined) {
          payload[field] = val;
        }
      }
    });

    // POS-PROCESSAMENTO para ABSENTEISMO
    if (config.tableName === "rh_absenteismo") {
        // 1. Gerar mes_ref baseado na data_inicio
        if (payload["data_inicio"]) {
            const val = payload["data_inicio"]; // YYYY-MM-DD
            if (typeof val === "string" && /^\d{4}-\d{2}-\d{2}/.test(val)) {
                const parts = val.split("-");
                payload["mes_ref"] = `${parts[1]}/${parts[0]}`;
            }
        }

        // 2. Calcular horas_perdidas automaticamente usando a função global (Seg-Sex = 8h, Sab = 4h)
        // Isso serve como fallback caso o gatilho onEdit não tenha rodado (ex: sync em massa)
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
// 1. GATILHO ON EDIT (Planilha -> Supabase)
// ==========================================
function syncToSupabaseOnEdit(e) {
  if (!e || !e.range) return;

  const sheet = e.source.getActiveSheet();
  const sheetName = sheet.getName();
  const row = e.range.getRow();

  if (row <= 1) return; // Ignora o cabeçalho

  const config = SHEET_CONFIG[sheetName];
  if (!config) return; // Se a aba não estiver configurada, não faz nada

  // ==========================================
  // LÓGICA DE AUTO-PREENCHIMENTO PARA ABSENTEISMO
  // ==========================================
  if (sheetName === "absenteismo") {
    // Colunas na planilha:
    // C (3) = data_inicio
    // D (4) = data_fim
    // F (6) = horas_perdidas

    // Obtemos apenas as células de interesse da linha atual
    const dataInicioCell = sheet.getRange(row, 3);
    const dataFimCell = sheet.getRange(row, 4);
    const horasPerdidasCell = sheet.getRange(row, 6);

    const vDataInicio = dataInicioCell.getValue();
    const vDataFim = dataFimCell.getValue();
    const vHorasPerdidas = horasPerdidasCell.getValue();

    // Só calcula e preenche a célula SE:
    // 1. As duas datas estiverem preenchidas
    // 2. A célula de horas perdidas estiver TOTALMENTE vazia
    if (vDataInicio && vDataFim && (vHorasPerdidas === "" || vHorasPerdidas === null)) {

      // Formata as datas para passar para a função (evitando problemas com Date objects do Sheets)
      let dtIniStr = formatarData(vDataInicio);
      let dtFimStr = formatarData(vDataFim);

      if (dtIniStr && dtFimStr) {
        const horasCalculadas = calcularHorasUteis(dtIniStr, dtFimStr);
        // Escreve o resultado de volta na planilha!
        horasPerdidasCell.setValue(horasCalculadas);
      }
    }
  }

  const numColumns = config.fields.length;
  // A aba EPI tem 13 colunas, as demais dependem da configuração
  const columnsToFetch =
    sheetName === "Controle EPI e Fardamento" ? 13 : numColumns;

  // Lemos a linha inteira (agora já vai incluir as horas recém-calculadas, se foi o caso)
  const rowData = sheet.getRange(row, 1, 1, columnsToFetch).getValues()[0];
  const payload = buildPayload(sheetName, rowData);

  if (payload) {
    upsertRecord(config.tableName, config.nameField, payload);
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
    if (data.length <= 1) return; // Só tem cabeçalho

    const columnsToFetch =
      sheetName === "Controle EPI e Fardamento" ? 13 : config.fields.length;

    // Começa do índice 1 para pular o cabeçalho
    for (let i = 1; i < data.length; i++) {
      // Pega os dados exatos até a quantidade de colunas que a tabela precisa
      const rowData = data[i].slice(0, columnsToFetch);

      const payload = buildPayload(sheetName, rowData);
      if (!payload || !payload[config.nameField]) continue; // Pula linhas vazias sem nome

      upsertRecord(config.tableName, config.nameField, payload);

      // Pequena pausa para não estourar os limites da API
      Utilities.sleep(100);
    }
  });

  try {
    SpreadsheetApp.getUi().alert(
      "Sincronização completa de todas as abas finalizada com sucesso!"
    );
  } catch (e) {
    console.log("Sincronização completa de todas as abas finalizada com sucesso! (UI não disponível)");
  }
}

// ==========================================
// 3. WEBHOOK UNIFICADO (Supabase -> Planilha)
// ==========================================
function doPost(e) {
  try {
    const data = JSON.parse(e.postData.contents);
    const type = data.type; // 'INSERT', 'UPDATE', or 'DELETE'
    const record = data.record;
    const oldRecord = data.old_record;
    const table = data.table;

    let targetSheetName = "";
    let nomeBusca = null;
    let fields = [];

    // Mapeamento dinâmico
    if (table === "funcionarios_epi") {
      targetSheetName = "Controle EPI e Fardamento";
      nomeBusca =
        type === "DELETE"
          ? oldRecord
            ? oldRecord.nome
            : null
          : record
            ? record.nome
            : null;
      fields = SHEET_CONFIG[targetSheetName].fields;
    } else if (table === "rh_movimentacoes") {
      targetSheetName = "movimentacoes";
      nomeBusca =
        type === "DELETE"
          ? oldRecord
            ? oldRecord.funcionario_nome
            : null
          : record
            ? record.funcionario_nome
            : null;
      fields = SHEET_CONFIG[targetSheetName].fields;
    } else if (table === "rh_absenteismo") {
      targetSheetName = "absenteismo";
      nomeBusca =
        type === "DELETE"
          ? oldRecord
            ? oldRecord.funcionario_nome
            : null
          : record
            ? record.funcionario_nome
            : null;
      fields = SHEET_CONFIG[targetSheetName].fields;
    } else if (table === "rh_ferias") {
      targetSheetName = "ferias";
      nomeBusca =
        type === "DELETE"
          ? oldRecord
            ? oldRecord.funcionario_nome
            : null
          : record
            ? record.funcionario_nome
            : null;
      fields = SHEET_CONFIG[targetSheetName].fields;
    } else if (table === "epi_funcao") {
      targetSheetName = "epi_funcao";
      nomeBusca =
        type === "DELETE"
          ? oldRecord
            ? oldRecord.funcao
            : null
          : record
            ? record.funcao
            : null;
      fields = SHEET_CONFIG[targetSheetName].fields;
    }

    if (!targetSheetName)
      return ContentService.createTextOutput("Tabela não mapeada").setMimeType(
        ContentService.MimeType.TEXT,
      );

    const sheet =
      SpreadsheetApp.getActiveSpreadsheet().getSheetByName(targetSheetName);
    if (!sheet)
      return ContentService.createTextOutput("Aba não encontrada").setMimeType(
        ContentService.MimeType.TEXT,
      );

    if (!nomeBusca)
      return ContentService.createTextOutput(
        "Chave (nome/função) não fornecida pelo Supabase",
      ).setMimeType(ContentService.MimeType.TEXT);

    const allData = sheet.getDataRange().getValues();
    let rowToUpdate = -1;

    // A coluna de busca
    let colNameIndex = 0;
    if (table === "funcionarios_epi") colNameIndex = 1;
    if (table === "rh_absenteismo") colNameIndex = 1; // nome está na coluna B (index 1) na nova config de absenteismo

    for (let i = 1; i < allData.length; i++) {
      if (targetSheetName === "absenteismo") {
          // Na aba de absenteismo, o ideal é achar pelo ID se tiver, senão Nome + Data_Inicio
          let idPlanilha = allData[i][0]; // Coluna A (index 0)
          let nomePlanilha = allData[i][1]; // Coluna B (index 1)
          let dataInicioPlanilha = allData[i][2]; // Coluna C (index 2)

          if (record.id && idPlanilha == record.id) {
              rowToUpdate = i + 1;
              break;
          }

          // Se não encontrou por ID, mas o nome e a data_inicio batem (para poder preencher o ID gerado)
          if (nomePlanilha === nomeBusca && record.data_inicio) {
              // Comparar a data_inicio
              let dataPlanilhaFormatada = "";
              if (dataInicioPlanilha instanceof Date) {
                  dataPlanilhaFormatada = dataInicioPlanilha.toISOString().split("T")[0];
              } else if (typeof dataInicioPlanilha === "string") {
                  // converter dd/mm/yyyy pra yyyy-mm-dd
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
          // Lógica original para as outras abas
          if (allData[i][colNameIndex] === nomeBusca) {
              rowToUpdate = i + 1;
              break;
          }
      }
    }

    if (type === "DELETE") {
      if (rowToUpdate !== -1) {
        sheet.deleteRow(rowToUpdate);
        return ContentService.createTextOutput(
          JSON.stringify({ status: "success", action: "deleted" }),
        ).setMimeType(ContentService.MimeType.JSON);
      }
      return ContentService.createTextOutput(
        JSON.stringify({
          status: "ignored",
          message: "Linha não encontrada para deletar",
        }),
      ).setMimeType(ContentService.MimeType.JSON);
    }

    const existingRow =
      rowToUpdate !== -1
        ? sheet.getRange(rowToUpdate, 1, 1, fields.length).getValues()[0]
        : Array(fields.length).fill("");

    const newRowData = fields.map((field, index) => {
      if (targetSheetName === "epi_funcao" && field !== "funcao") {
        // Conversão de volta de booleano para SIM/NÃO
        if (record.hasOwnProperty(field)) {
          return record[field] ? "SIM" : "NÃO";
        } else {
          return existingRow[index];
        }
      } else {
        // Se a data vier no formato YYYY-MM-DD do banco, converter para DD/MM/YYYY para a planilha (opcional, ou o Google Sheets cuida disso)
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
      return ContentService.createTextOutput(
        JSON.stringify({ status: "success", action: "updated" }),
      ).setMimeType(ContentService.MimeType.JSON);
    } else {
      sheet.appendRow(newRowData);
      return ContentService.createTextOutput(
        JSON.stringify({ status: "success", action: "inserted" }),
      ).setMimeType(ContentService.MimeType.JSON);
    }
  } catch (error) {
    return ContentService.createTextOutput(
      JSON.stringify({ status: "error", message: error.message }),
    ).setMimeType(ContentService.MimeType.JSON);
  }
}
