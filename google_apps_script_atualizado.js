/**
 * ==============================================================================
 * SISTEMA DE SINCRONIZAÇÃO AUTOMÁTICA DE RH - GOOGLE SHEETS & SUPABASE (RH PRIME)
 * ==============================================================================
 */

const SUPABASE_URL = "https://gcksbfstheavpfgcdndb.supabase.co";
const SUPABASE_KEY = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Imdja3NiZnN0aGVhdnBmZ2NkbmRiIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc3Nzc1MDcyNywiZXhwIjoyMDkzMzI2NzI3fQ.yuYxAYnllivwnR7fKzEAfgUIdLEAQZjIBAPrWfQh0IY";

/**
 * Cria menu personalizado na planilha
 */
function onOpen() {
  const ui = SpreadsheetApp.getUi();
  ui.createMenu("RH Prime Sync")
    .addItem("🔄 Sincronizar Tudo com Banco de Dados", "sincronizarTudoSupabase")
    .addItem("👕 Atualizar Controle de EPI e Fardamento", "sincronizarControleEPI")
    .addToUi();
}

/**
 * Helper para formatar data do banco (YYYY-MM-DD) para formato visual da planilha (DD/MM/YYYY)
 */
function formatarDataParaPlanilha(val) {
  if (!val) return "";
  if (val instanceof Date) {
    const d = val.getDate().toString().padStart(2, "0");
    const m = (val.getMonth() + 1).toString().padStart(2, "0");
    const y = val.getFullYear();
    return `${d}/${m}/${y}`;
  }
  if (typeof val === "string" && /^\d{4}-\d{2}-\d{2}/.test(val)) {
    const parts = val.split("T")[0].split("-");
    return `${parts[2]}/${parts[1]}/${parts[0]}`;
  }
  return val;
}

/**
 * Determina o CNPJ do Local de Registro baseado no nome do local ou lista de empresas
 */
function obterCnpjLocalRegistro(localRegistro, empresasList) {
  if (!localRegistro) {
    const def = empresasList && empresasList.find((e) => e.nome && e.nome.toUpperCase().includes("NUNES"));
    return def && def.cnpj ? def.cnpj : "48.986.353/0001-39";
  }

  const str = localRegistro.toString().trim().toUpperCase();

  if (empresasList && empresasList.length > 0) {
    for (let i = 0; i < empresasList.length; i++) {
      const emp = empresasList[i];
      if (emp.nome && emp.cnpj) {
        const empNome = emp.nome.trim().toUpperCase();
        if (str.includes(empNome) || empNome.includes(str)) {
          return emp.cnpj;
        }
      }
    }
  }

  if (str.includes("JEQUIÉ") || str.includes("JEQUIE") || str.includes("0002-82")) {
    const eq = empresasList && empresasList.find((e) => e.cnpj && e.cnpj.includes("0002-82"));
    return eq && eq.cnpj ? eq.cnpj : "52.522.019/0002-82";
  }

  if (str.includes("ILHÉUS") || str.includes("ILHEUS") || str.includes("0001-00")) {
    const eq = empresasList && empresasList.find((e) => e.cnpj && e.cnpj.includes("0001-00"));
    return eq && eq.cnpj ? eq.cnpj : "52.522.019/0001-00";
  }

  if (str.includes("NUNES") || str.includes("ITABUNA") || str.includes("VIEIRA") || str.includes("0001-39")) {
    const eq = empresasList && empresasList.find((e) => e.cnpj && e.cnpj.includes("0001-39"));
    return eq && eq.cnpj ? eq.cnpj : "48.986.353/0001-39";
  }

  return "48.986.353/0001-39";
}

/**
 * Função principal para sincronizar a aba 'Controle EPI e Fardamento' com os dados do Supabase
 */
function sincronizarControleEPI() {
  const ss = SpreadsheetApp.getActiveSpreadsheet();
  const sheet = ss.getSheetByName("Controle EPI e Fardamento");

  if (!sheet) {
    try {
      SpreadsheetApp.getUi().alert("Aba 'Controle EPI e Fardamento' não foi encontrada!");
    } catch(e) {
      console.log("Aba 'Controle EPI e Fardamento' não foi encontrada!");
    }
    return;
  }

  const options = {
    method: "get",
    headers: {
      "apikey": SUPABASE_KEY,
      "Authorization": "Bearer " + SUPABASE_KEY,
      "Content-Type": "application/json"
    },
    muteHttpExceptions: true
  };

  // Fetch de empresas para vinculo do CNPJ
  let empresas = [];
  try {
    const urlEmpresas = SUPABASE_URL + "/rest/v1/empresas?select=*";
    const respEmpresas = UrlFetchApp.fetch(urlEmpresas, options);
    if (respEmpresas.getResponseCode() === 200) {
      empresas = JSON.parse(respEmpresas.getContentText());
    }
  } catch(err) {
    console.log("Erro ao buscar lista de empresas: " + err.message);
  }

  // Fetch de dados do banco Supabase
  const url = SUPABASE_URL + "/rest/v1/funcionarios_epi?select=*";

  try {
    const response = UrlFetchApp.fetch(url, options);
    if (response.getResponseCode() !== 200) {
      try {
        SpreadsheetApp.getUi().alert("Erro ao conectar ao Supabase: " + response.getContentText());
      } catch(e) {
        console.error("Erro ao conectar ao Supabase: " + response.getContentText());
      }
      return;
    }

    const funcionarios = JSON.parse(response.getContentText());

    // Mapeia funcionários por CPF limpo e por Nome maiúsculo
    const mapaPorCPF = {};
    const mapaPorNome = {};
    funcionarios.forEach(f => {
      if (f.cpf) {
        mapaPorCPF[limparCPF(f.cpf)] = f;
      }
      if (f.nome) {
        mapaPorNome[f.nome.trim().toUpperCase()] = f;
      }
    });

    const lastRow = sheet.getLastRow();
    if (lastRow < 2) {
      try {
        SpreadsheetApp.getUi().alert("Nenhum dado encontrado na planilha.");
      } catch(e) {
        console.log("Nenhum dado encontrado na planilha.");
      }
      return;
    }

    // Obtém a lista completa de dados (linha 2 em diante, 23 colunas A ate W)
    const rangeData = sheet.getRange(2, 1, lastRow - 1, 23).getValues();

    let atualizados = 0;

    for (let i = 0; i < rangeData.length; i++) {
      const row = rangeData[i];
      const nomePlanilha = row[1] ? row[1].toString().trim().toUpperCase() : "";
      const cpfPlanilha = row[2] ? limparCPF(row[2]) : "";

      const dados = (cpfPlanilha && mapaPorCPF[cpfPlanilha]) || (nomePlanilha && mapaPorNome[nomePlanilha]);
      if (!dados) continue;

      const linha = i + 2;

      // Preenchimento alinhado com a sequência exata das colunas da planilha:
      // Col 1 (A): ADMISSÃO
      // Col 2 (B): NOME COMPLETO DO FUNCIONÁRIO
      // Col 3 (C): CPF
      // Col 4 (D): FUNÇÃO
      // Col 5 (E): SETOR
      // Col 6 (F): UNIDADE
      // Col 7 (G): DATA ÚLTIMA ENTREGA (EPI)
      // Col 8 (H): EPI (ENTREGUE/VERIFICADOS)
      // Col 9 (I): LINK COMPROVANTE (EPI)
      // Col 10 (J): DATA ÚLTIMA ENTREGA (FARDAMENTO)
      // Col 11 (K): FARDAMENTO (ENTREGUE/VERIFICADOS)
      // Col 12 (L): LINK COMPROVANTE (FARDAMENTO)
      // Col 13 (M): CHECK / VALIDAÇÃO
      // Col 14 (N): LOCAL DO REGISTRO
      // Col 15 (O): WHATSAPP
      // Col 16 (P): NASCIMENTO
      // Col 17 (Q): CARGA HORÁRIA
      // Col 18 (R): SEXO
      // Col 19 (S): TAMANHO FARDA
      // Col 20 (T): CALÇA
      // Col 21 (U): CALÇADO
      // Col 23 (W): CNPJ - LOCAL DE REGISTRO

      if (dados.admissao !== undefined && dados.admissao !== null) sheet.getRange(linha, 1).setValue(formatarDataParaPlanilha(dados.admissao));
      if (dados.nome !== undefined && dados.nome !== null) sheet.getRange(linha, 2).setValue(dados.nome);
      if (dados.cpf !== undefined && dados.cpf !== null) sheet.getRange(linha, 3).setValue("'" + limparCPF(dados.cpf));
      if (dados.funcao !== undefined && dados.funcao !== null) sheet.getRange(linha, 4).setValue(dados.funcao);
      if (dados.setor !== undefined && dados.setor !== null) sheet.getRange(linha, 5).setValue(dados.setor);
      if (dados.unidade !== undefined && dados.unidade !== null) sheet.getRange(linha, 6).setValue(dados.unidade);
      if (dados.epi_data !== undefined && dados.epi_data !== null) sheet.getRange(linha, 7).setValue(formatarDataParaPlanilha(dados.epi_data));
      if (dados.epi_itens !== undefined && dados.epi_itens !== null) sheet.getRange(linha, 8).setValue(dados.epi_itens);
      if (dados.epi_link !== undefined && dados.epi_link !== null) sheet.getRange(linha, 9).setValue(dados.epi_link);
      if (dados.fardamento_data !== undefined && dados.fardamento_data !== null) sheet.getRange(linha, 10).setValue(formatarDataParaPlanilha(dados.fardamento_data));
      if (dados.fardamento_itens !== undefined && dados.fardamento_itens !== null) sheet.getRange(linha, 11).setValue(dados.fardamento_itens);
      if (dados.fardamento_link !== undefined && dados.fardamento_link !== null) sheet.getRange(linha, 12).setValue(dados.fardamento_link);
      if (dados.validacao !== undefined && dados.validacao !== null) sheet.getRange(linha, 13).setValue(dados.validacao);
      if (dados.local_registro !== undefined && dados.local_registro !== null) sheet.getRange(linha, 14).setValue(dados.local_registro);
      if (dados.whatsapp !== undefined && dados.whatsapp !== null) sheet.getRange(linha, 15).setValue("'" + dados.whatsapp);
      if (dados.nascimento !== undefined && dados.nascimento !== null) sheet.getRange(linha, 16).setValue(formatarDataParaPlanilha(dados.nascimento));
      if (dados.carga_horaria !== undefined && dados.carga_horaria !== null) sheet.getRange(linha, 17).setValue(Number(dados.carga_horaria) || 220);
      if (dados.sexo !== undefined && dados.sexo !== null) sheet.getRange(linha, 18).setValue(dados.sexo);
      if (dados.tamanho_farda !== undefined && dados.tamanho_farda !== null) sheet.getRange(linha, 19).setValue(dados.tamanho_farda);
      if (dados.calca !== undefined && dados.calca !== null) sheet.getRange(linha, 20).setValue(dados.calca);
      if (dados.calcado !== undefined && dados.calcado !== null) sheet.getRange(linha, 21).setValue(dados.calcado);

      // Coluna W (23): CNPJ - LOCAL DE REGISTRO
      const locReg = dados.local_registro || row[13];
      const cnpjVal = obterCnpjLocalRegistro(locReg, empresas);
      sheet.getRange(linha, 23).setValue("'" + cnpjVal);

      atualizados++;
    }

    try {
      SpreadsheetApp.getUi().alert("Sincronização concluída! " + atualizados + " colaboradores foram atualizados com sucesso.");
    } catch(e) {
      console.log("Sincronização concluída! " + atualizados + " colaboradores foram atualizados com sucesso.");
    }

  } catch (error) {
    try {
      SpreadsheetApp.getUi().alert("Ocorreu um erro durante a execução: " + error.toString());
    } catch(e) {
      console.error("Ocorreu um erro durante a execução: " + error.toString());
    }
  }
}

/**
 * Função executada automaticamente ao alterar valores na planilha (Gatilho onEdit)
 */
function onEdit(e) {
  if (!e) return;
  const range = e.range;
  const sheet = range.getSheet();
  const sheetName = sheet.getName();

  const row = range.getRow();
  const col = range.getColumn();

  // Ignora cabeçalho
  if (row < 2) return;

  if (sheetName === "Controle EPI e Fardamento") {
    const nomeFuncionario = sheet.getRange(row, 2).getValue(); // Coluna B
    if (nomeFuncionario) {
      // Mapeamento das colunas da planilha para colunas da tabela Supabase funcionarios_epi
      const mapaColunasSupabase = {
        1: "admissao",
        2: "nome",
        3: "cpf",
        4: "funcao",
        5: "setor",
        6: "unidade",
        7: "epi_data",
        8: "epi_itens",
        9: "epi_link",
        10: "fardamento_data",
        11: "fardamento_itens",
        12: "fardamento_link",
        13: "validacao",
        14: "local_registro",
        15: "whatsapp",      // Coluna O (15)
        16: "nascimento",    // Coluna P (16)
        17: "carga_horaria", // Coluna Q (17)
        18: "sexo",          // Coluna R (18)
        19: "tamanho_farda", // Coluna S (19)
        20: "calca",          // Coluna T (20)
        21: "calcado"        // Coluna U (21)
      };

      if (mapaColunasSupabase[col]) {
        const campoSupabase = mapaColunasSupabase[col];
        let valor = range.getValue();

        // Se for carga horária, converter para número inteiro
        if (campoSupabase === "carga_horaria") {
          valor = parseInt(valor, 10) || 220;
        }

        atualizarCampoSupabase(nomeFuncionario, campoSupabase, valor);
      }

      // Se alterou LOCAL DO REGISTRO (Coluna N / 14), atualiza o CNPJ na Coluna W / 23
      if (col === 14) {
        const localRegEditado = range.getValue();
        const cnpjEditado = obterCnpjLocalRegistro(localRegEditado, []);
        sheet.getRange(row, 23).setValue("'" + cnpjEditado);
      }
    }
  }

  // Executa atualização do registro unificado para a linha alterada
  syncToSupabaseOnEdit(e);
}

/**
 * Atualiza um único campo de um colaborador no Supabase
 */
function atualizarCampoSupabase(nome, campo, valor) {
  if (!nome || !campo) {
    Logger.log("atualizarCampoSupabase: Chamada ignorada pois 'nome' ou 'campo' não foram fornecidos (ex: execução manual no editor).");
    return;
  }
  const nomeStr = String(nome).trim();
  if (!nomeStr) return;

  const url = SUPABASE_URL + "/rest/v1/funcionarios_epi?nome=eq." + encodeURIComponent(nomeStr);

  const payload = {};
  payload[campo] = valor;

  const options = {
    method: "patch",
    headers: {
      "apikey": SUPABASE_KEY,
      "Authorization": "Bearer " + SUPABASE_KEY,
      "Content-Type": "application/json",
      "Prefer": "return=minimal"
    },
    payload: JSON.stringify(payload),
    muteHttpExceptions: true
  };

  try {
    UrlFetchApp.fetch(url, options);
  } catch (err) {
    Logger.log("Erro ao enviar patch para Supabase: " + err.toString());
  }
}

/**
 * Sincronização geral
 */
function sincronizarTudoSupabase() {
  syncAllToSupabase();
  sincronizarControleEPI();
}

// ==========================================
// FUNÇÃO PARA CALCULAR HORAS ÚTEIS (ABSENTEÍSMO)
// ==========================================
function calcularHorasUteis(dataInicio, dataFim, cargaHoraria) {
  if (!dataInicio || !dataFim) return 0;

  let dInicio = dataInicio instanceof Date ? new Date(dataInicio) : new Date(dataInicio + "T00:00:00");
  let dFim = dataFim instanceof Date ? new Date(dataFim) : new Date(dataFim + "T00:00:00");

  if (isNaN(dInicio.getTime()) || isNaN(dFim.getTime()) || dInicio > dFim) {
    return 0;
  }

  // Carga horária padrão mensal de 220h => ~8h seg-sex, 4h sab. Se for outra carga proporcional, ajusta
  const fatorCarga = (cargaHoraria && !isNaN(Number(cargaHoraria)) && Number(cargaHoraria) > 0) ? (Number(cargaHoraria) / 220) : 1;

  let totalHoras = 0;
  let current = new Date(dInicio);

  while (current <= dFim) {
    const diaSemana = current.getDay();
    if (diaSemana >= 1 && diaSemana <= 5) {
      totalHoras += 8 * fatorCarga;
    } else if (diaSemana === 6) {
      totalHoras += 4 * fatorCarga;
    }
    current.setDate(current.getDate() + 1);
  }

  return Math.round(totalHoras * 10) / 10;
}

// Configuração das abas e suas tabelas
const SHEET_CONFIG = {
  "Controle EPI e Fardamento": {
    tableName: "funcionarios_epi",
    nameField: "cpf",
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
      "whatsapp",
      "nascimento",
      "carga_horaria",
      "sexo",
      "tamanho_farda",
      "calca",
      "calcado",
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
      "cpf",
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
      "cpf",
      "carga_horaria",
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
      "cpf",
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

// Limpa CPF mantendo apenas dígitos (chave/id de colaborador)
function limparCPF(cpfVal) {
  if (!cpfVal) return "";
  return cpfVal.toString().trim().replace(/\D/g, "");
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
      nome: rowData[1] ? rowData[1].toString().trim() : "",
      cpf: rowData[2] ? limparCPF(rowData[2]) : "",
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
      whatsapp: rowData[14] ? rowData[14].toString() : "",
      nascimento: formatarDataEPI(rowData[15]),
      carga_horaria: rowData[16] && !isNaN(Number(rowData[16])) ? Number(rowData[16]) : 220,
      sexo: rowData[17] ? rowData[17].toString() : "",
      tamanho_farda: rowData[18] ? rowData[18].toString() : "",
      calca: rowData[19] ? rowData[19].toString() : "",
      calcado: rowData[20] ? rowData[20].toString() : "",
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

      if (field === "cpf" && val) {
        val = limparCPF(val);
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
                payload[field] = `${parts[1].padStart(2, "0")}/${parts[2]}`;
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
            payload["horas_perdidas"] = calcularHorasUteis(payload["data_inicio"], payload["data_fim"], payload["carga_horaria"] || 220);
        }
    }
  }

  return payload;
}

// Sincroniza ativos de Movimentações -> Férias e Controle EPI e Fardamento automaticamente
function sincronizarAtivosParaFerias() {
  const ss = SpreadsheetApp.getActiveSpreadsheet();
  const movSheet = ss.getSheetByName("movimentacoes");
  const feriasSheet = ss.getSheetByName("ferias");
  const epiSheet = ss.getSheetByName("Controle EPI e Fardamento");
  if (!movSheet) return;

  const movData = movSheet.getDataRange().getValues();
  const feriasData = feriasSheet ? feriasSheet.getDataRange().getValues() : [];
  const epiData = epiSheet ? epiSheet.getDataRange().getValues() : [];

  const feriasNomesSet = new Set();
  for (let i = 1; i < feriasData.length; i++) {
    const nome = feriasData[i][0] ? feriasData[i][0].toString().trim().toUpperCase() : "";
    if (nome) feriasNomesSet.add(nome);
  }

  const epiCpfsSet = new Set();
  const epiNomesSet = new Set();
  for (let i = 1; i < epiData.length; i++) {
    const nome = epiData[i][1] ? epiData[i][1].toString().trim().toUpperCase() : "";
    const cpf = epiData[i][2] ? limparCPF(epiData[i][2]) : "";
    if (cpf) epiCpfsSet.add(cpf);
    if (nome) epiNomesSet.add(nome);
  }

  for (let i = 1; i < movData.length; i++) {
    const nome = movData[i][0] ? movData[i][0].toString().trim() : "";
    const dtAdmissaoVal = movData[i][1];
    const dtDesligamentoVal = movData[i][2];
    const cpfVal = movData[i][4] ? limparCPF(movData[i][4]) : "";

    if (nome && dtDesligamentoVal && dtDesligamentoVal.toString().trim() !== "") {
      // Se houver data de desligamento, garante que seja removido de férias e absenteísmo
      verificarETratarDesligamento(nome, dtDesligamentoVal);
      continue;
    }

    if (nome && dtAdmissaoVal && (!dtDesligamentoVal || dtDesligamentoVal.toString().trim() === "")) {
      const nomeUpper = nome.toUpperCase();
      let dtAdmissao = dtAdmissaoVal instanceof Date ? dtAdmissaoVal : new Date(formatarData(dtAdmissaoVal));
      if (isNaN(dtAdmissao.getTime())) continue;

      let dtIniStr = formatarData(dtAdmissao);

      // 1. Sincronizar em Férias
      if (feriasSheet && !feriasNomesSet.has(nomeUpper)) {
        let dtFimAquisitivo = addYears(dtAdmissao, 1);
        dtFimAquisitivo.setDate(dtFimAquisitivo.getDate() - 1);

        let dtVencimento = addMonths(dtFimAquisitivo, 11);

        let dtFimStr = formatarData(dtFimAquisitivo);
        let dtVencStr = formatarData(dtVencimento);

        feriasSheet.appendRow([nome, dtIniStr, dtFimStr, dtVencStr, 30, 0, "pendente", 0, cpfVal]);

        upsertRecord("rh_ferias", "funcionario_nome", {
          funcionario_nome: nome,
          cpf: cpfVal,
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

      // 2. Sincronizar em Controle EPI e Fardamento
      let epiRowIdx = -1;
      if (epiSheet && epiData.length > 1) {
        for (let j = 1; j < epiData.length; j++) {
          let cpfPlanilha = epiData[j][2] ? limparCPF(epiData[j][2]) : "";
          let nomePlanilha = epiData[j][1] ? epiData[j][1].toString().trim().toUpperCase() : "";
          if ((cpfVal && cpfPlanilha === cpfVal) || (nomeUpper && nomePlanilha === nomeUpper)) {
            epiRowIdx = j + 1;
            break;
          }
        }
      }

      if (epiSheet) {
        if (epiRowIdx === -1) {
          // [admissao, nome, cpf, funcao, setor, unidade, epi_data, epi_itens, epi_link, fardamento_data, fardamento_itens, fardamento_link, validacao, local_registro, whatsapp, nascimento, carga_horaria, sexo, tamanho_farda, calca, calcado]
          epiSheet.appendRow([dtIniStr, nome, cpfVal, "", "", "", "", "", "", "", "", "", "☑ OK", "", "", "", 220, "", "", "", ""]);

          upsertRecord("funcionarios_epi", "cpf", {
            cpf: cpfVal || nome,
            nome: nome,
            admissao: dtIniStr,
            carga_horaria: 220,
            validacao: "☑ OK"
          });

          if (cpfVal) epiCpfsSet.add(cpfVal);
          epiNomesSet.add(nomeUpper);
          console.log(`Criado registro de EPI e Fardamento automático para ${nome}`);
        } else {
          // Se já existe na planilha, verificar se campos essenciais como admissao, cpf ou validacao precisam ser preenchidos
          let rowData = epiData[epiRowIdx - 1];
          let updated = false;

          if (!rowData[0] || rowData[0].toString().trim() === "") {
            epiSheet.getRange(epiRowIdx, 1).setValue(dtIniStr); // Coluna A: Admissão
            updated = true;
          }
          if (cpfVal && (!rowData[2] || limparCPF(rowData[2]) === "")) {
            epiSheet.getRange(epiRowIdx, 3).setValue(cpfVal); // Coluna C: CPF
            updated = true;
          }
          if (!rowData[12] || rowData[12].toString().trim() === "") {
            epiSheet.getRange(epiRowIdx, 13).setValue("☑ OK"); // Coluna M: Validação
            updated = true;
          }

          if (updated) {
            upsertRecord("funcionarios_epi", "cpf", {
              cpf: cpfVal || limparCPF(rowData[2]) || nome,
              nome: rowData[1] ? rowData[1].toString().trim() : nome,
              admissao: dtIniStr,
              carga_horaria: rowData[16] || 220,
              validacao: "☑ OK"
            });
            console.log(`Atualizado registro de EPI e Fardamento com informações para ${nome}`);
          }
        }
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
          cpf: row[2] ? limparCPF(row[2]) : "",
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

  const sheet = e.source ? e.source.getActiveSheet() : e.range.getSheet();
  const sheetName = sheet.getName();
  const row = e.range.getRow();

  if (row <= 1) return;

  const config = SHEET_CONFIG[sheetName];
  if (!config) return;

  if (sheetName === "absenteismo") {
    const dataInicioCell = sheet.getRange(row, 3);
    const dataFimCell = sheet.getRange(row, 4);
    const horasPerdidasCell = sheet.getRange(row, 6);
    const cargaHorariaCell = sheet.getRange(row, 9);

    const vDataInicio = dataInicioCell.getValue();
    const vDataFim = dataFimCell.getValue();
    const vHorasPerdidas = horasPerdidasCell.getValue();
    const vCargaHoraria = cargaHorariaCell ? cargaHorariaCell.getValue() : 220;

    if (vDataInicio && vDataFim && (vHorasPerdidas === "" || vHorasPerdidas === null)) {
      let dtIniStr = formatarData(vDataInicio);
      let dtFimStr = formatarData(vDataFim);

      if (dtIniStr && dtFimStr) {
        const horasCalculadas = calcularHorasUteis(dtIniStr, dtFimStr, vCargaHoraria);
        horasPerdidasCell.setValue(horasCalculadas);
      }
    }
  }

  const numColumns = config.fields.length;
  const columnsToFetch = sheetName === "Controle EPI e Fardamento" ? 21 : numColumns;

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

    const columnsToFetch = sheetName === "Controle EPI e Fardamento" ? 21 : config.fields.length;

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
      nomeBusca = type === "DELETE" ? (oldRecord ? oldRecord.cpf || oldRecord.nome : null) : (record ? record.cpf || record.nome : null);
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

    if (!nomeBusca) return ContentService.createTextOutput("Chave (CPF/nome/função) não fornecida pelo Supabase").setMimeType(ContentService.MimeType.TEXT);

    const allData = sheet.getDataRange().getValues();
    let rowToUpdate = -1;

    let colNameIndex = 0;
    if (table === "funcionarios_epi") colNameIndex = 2; // Coluna C é CPF/Matricula
    if (table === "rh_absenteismo") colNameIndex = 1;

    for (let i = 1; i < allData.length; i++) {
      if (targetSheetName === "Controle EPI e Fardamento") {
        let cpfPlanilha = limparCPF(allData[i][2]);
        let nomePlanilha = allData[i][1] ? allData[i][1].toString().trim() : "";
        if (record && record.cpf && cpfPlanilha === limparCPF(record.cpf)) {
          rowToUpdate = i + 1;
          break;
        } else if (record && record.nome && nomePlanilha.toUpperCase() === record.nome.toUpperCase()) {
          rowToUpdate = i + 1;
          break;
        }
      } else if (targetSheetName === "absenteismo") {
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
                      dataPlanilhaFormatada = `${p[2]}-${p[1].padStart(2, "0")}-${p[0].padStart(2, "0")}`;
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

    // Se for funcionarios_epi, atualiza tambem o CNPJ na Coluna W (23) se disponivel no payload ou record
    if (targetSheetName === "Controle EPI e Fardamento" && record && record.local_registro) {
      const cnpjCalc = obterCnpjLocalRegistro(record.local_registro, []);
      sheet.getRange(rowToUpdate !== -1 ? rowToUpdate : sheet.getLastRow() + 1, 23).setValue("'" + cnpjCalc);
    }

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
