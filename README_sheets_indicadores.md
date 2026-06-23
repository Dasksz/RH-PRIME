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
      "tipo_movimentacao",
      "motivo_saida",
      "mes_ref",
    ],
  },
  absenteismo: {
    tableName: "rh_absenteismo",
    nameField: "funcionario_nome",
    fields: [
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

// Função para extrair mês/ano
function getMesRefFromDate(dateStr) {
  if (!dateStr) return null;
  const parts = dateStr.split("-"); // YYYY-MM-DD
  if (parts.length === 3) {
    return `${parts[1]}/${parts[0]}`; // MM/YYYY
  }
  return null;
}

// Função para calcular horas perdidas
function calcularHorasPerdidas(inicioStr, fimStr) {
  if (!inicioStr || !fimStr) return 0;

  // Assumes YYYY-MM-DD format
  const inicio = new Date(inicioStr + "T00:00:00");
  const fim = new Date(fimStr + "T00:00:00");

  if (inicio > fim) return 0;

  let horas = 0;
  let atual = new Date(inicio);

  while (atual <= fim) {
    const diaSemana = atual.getDay(); // 0 = Domingo, 1 = Segunda, ..., 6 = Sábado
    if (diaSemana >= 1 && diaSemana <= 5) { // Segunda a Sexta
      horas += 8;
    } else if (diaSemana === 6) { // Sábado
      horas += 4;
    }
    // Domingo (0) não soma horas

    atual.setDate(atual.getDate() + 1);
  }

  return horas;
}

// ==========================================
// FUNÇÕES DE SINCRONIZAÇÃO LINEAR
// ==========================================

// Atualiza ou Insere um registro no Supabase
function upsertRecord(tableName, nameField, payload) {
  const nomeValue = payload[nameField];
  if (!nomeValue) return;

  try {
    const existingUrl = `${SUPABASE_URL}/rest/v1/${tableName}?${nameField}=eq.${encodeURIComponent(nomeValue)}`;
    // Only select the id if it's not epi_funcao (which uses funcao as PK and doesn't have an id)
    const urlWithSelect =
      tableName === "epi_funcao" ? existingUrl : `${existingUrl}&select=id`;

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
        patchUrl += `funcao=eq.${encodeURIComponent(nomeValue)}`;
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
      console.log(`Atualizado registro de ${nomeValue} na tabela ${tableName}`);
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
        `Inserido novo registro de ${nomeValue} na tabela ${tableName}`,
      );
    }
  } catch (error) {
    console.error(
      `Erro ao sincronizar ${nomeValue} na tabela ${tableName}: O payload era `,
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

      // Se for data ou uma string que se parece com data DD/MM/YYYY, formatamos com formatarData (que retorna YYYY-MM-DD)
      if (
        val instanceof Date ||
        (typeof val === "string" && /\d{1,2}\/\d{1,2}\/\d{4}/.test(val))
      ) {
        payload[field] = formatarData(val);
      } else if (
        val === "" ||
        val === null ||
        val === undefined ||
        (typeof val === "string" && val.trim() === "")
      ) {
        // Não enviamos a chave se o valor for nulo/vazio para evitar erros de not-null no Supabase
        // payload[field] = null;
      } else {
        if (config.tableName === "rh_movimentacoes") {
          if (field === "tipo_movimentacao" && val)
            val = String(val).toLowerCase().trim();
          if (field === "motivo_saida" && val)
            val = String(val).toLowerCase().trim();
        }
        if (config.tableName === "rh_absenteismo") {
          if (field === "horas_previstas") {
             if (val === "" || val === null || val === undefined || isNaN(Number(val))) {
                val = 220; // Default inteligente
             }
          }
          if (field === "horas_perdidas" && isNaN(Number(val))) {
            val = null;
          }
        }
        if (
          typeof val === "number" &&
          (field === "mes_ref" ||
            field === "funcionario_nome" ||
            field === "motivo")
        ) {
          val = String(val);
        }

        // Só adiciona ao payload se não foi convertido para nulo pelas regras acima
        if (val !== null) {
          payload[field] = val;
        }
      }
    });

    // Lógica Específica para Absenteísmo: calcular horas perdidas e mes_ref
    if (sheetName === "absenteismo") {
        if (payload.data_inicio) {
            // Extrai mes_ref da data inicio
            payload.mes_ref = getMesRefFromDate(payload.data_inicio);

            if (payload.data_fim) {
                // Se o usuário já tiver preenchido manualmente horas perdidas na planilha,
                // decidimos sobrescrever caso haja data_fim ou manter o da planilha se não houver
                payload.horas_perdidas = calcularHorasPerdidas(payload.data_inicio, payload.data_fim);
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

  const numColumns = config.fields.length;
  // A aba EPI tem 13 colunas, as demais dependem da configuração
  const columnsToFetch =
    sheetName === "Controle EPI e Fardamento" ? 13 : numColumns;

  const rowData = sheet.getRange(row, 1, 1, columnsToFetch).getValues()[0];
  const payload = buildPayload(sheetName, rowData);

  if (payload) {
    upsertRecord(config.tableName, config.nameField, payload);

    // Se for absenteismo, escreve de volta as horas perdidas calculadas na planilha (opcional)
    if (sheetName === "absenteismo" && payload.horas_perdidas !== undefined) {
        // A coluna de horas_perdidas é a 5 (índice 4 no array fields)
        const horasPerdidasCol = config.fields.indexOf("horas_perdidas") + 1;
        if (horasPerdidasCol > 0) {
            sheet.getRange(row, horasPerdidasCol).setValue(payload.horas_perdidas);
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

  SpreadsheetApp.getUi().alert(
    "Sincronização completa de todas as abas finalizada com sucesso!",
  );
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

    for (let i = 1; i < allData.length; i++) {
      if (allData[i][colNameIndex] === nomeBusca) {
        rowToUpdate = i + 1;
        break;
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

---

## 📝 Guia de Preenchimento das Planilhas

Para que o Front-End (Painel de Indicadores) funcione corretamente, os dados devem ser preenchidos exatamente nos padrões abaixo. Atenção especial para os campos `tipo_movimentacao` e `motivo_saida`, que **devem** seguir as palavras-chave exatas.

### Aba: `movimentacoes`

Colunas esperadas na linha 1: `funcionario_nome`, `data_admissao`, `data_desligamento`, `tipo_movimentacao`, `motivo_saida`, `mes_ref`

**Regras:**
* `tipo_movimentacao`: Preencher **apenas** com a palavra `entrada` ou `saida`
* `motivo_saida` (Se for saída): Preencher **apenas** com a palavra `voluntario` (ex: pediu demissão) ou `involuntario` (ex: empresa demitiu)
* `data_desligamento` e `motivo_saida`: Deixar **em branco** no caso de `entrada` (Admissão)
* As datas podem ser preenchidas no formato **DD/MM/YYYY** (O sistema converterá automaticamente para o formato que o banco de dados aceita).

| funcionario_nome | data_admissao | data_desligamento | tipo_movimentacao | motivo_saida | mes_ref |
| :--- | :--- | :--- | :--- | :--- | :--- |
| João da Silva | 15/01/2021 | 20/10/2023 | saida | voluntario | 10/2023 |
| Maria Oliveira | 05/11/2023 | | entrada | | 11/2023 |
| Carlos Souza | 10/05/2020 | 25/10/2023 | saida | involuntario | 10/2023 |

---

### Aba: `absenteismo`

Colunas esperadas na linha 1: `funcionario_nome`, `data_inicio`, `data_fim`, `horas_previstas`, `horas_perdidas`, `motivo`

**Regras Inteligentes do Sistema:**
* A coluna `horas_previstas` assumirá **automaticamente 220 horas** caso você deixe a célula em branco. Mas se precisar, você pode preencher manualmente um valor diferente.
* Se você preencher `data_inicio` e `data_fim` (formato DD/MM/YYYY), o sistema calculará as `horas_perdidas` **automaticamente** (8h/dia útil, 4h/sábado, 0h/domingo).
* Se for apenas um atraso de algumas horas, você deixa `data_fim` em branco e preenche manualmente as `horas_perdidas` (ex: `2`).
* A coluna de `mes_ref` foi removida da planilha e agora é detectada automaticamente a partir da `data_inicio`.
* **Afastamentos longos (que viram o mês):** Divida em duas linhas. Ex: Se afastou de 15/10 a 15/11, crie uma linha de 15/10 a 31/10 e outra linha de 01/11 a 15/11. Isso garante que o cálculo das taxas seja proporcional ao mês exato.

| funcionario_nome | data_inicio | data_fim | horas_previstas | horas_perdidas | motivo |
| :--- | :--- | :--- | :--- | :--- | :--- |
| João da Silva | 10/10/2023 | 11/10/2023 | 220 | 16 | Atestado médico |
| Maria Oliveira | 05/11/2023 | | 220 | 2 | Atraso justificado |
| Carlos Souza | 12/11/2023 | 12/11/2023 | 220 | 8 | Dores musculoesqueléticas |

---

### Aba: `ferias`

Colunas esperadas na linha 1: `funcionario_nome`, `data_inicio_aquisitivo`, `data_fim_aquisitivo`, `data_vencimento`, `dias_direito`, `dias_gozados`, `status`

| funcionario_nome | data_inicio_aquisitivo | data_fim_aquisitivo | data_vencimento | dias_direito | dias_gozados | status |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| Carlos Souza | 10/03/2021 | 09/03/2022 | 09/03/2023 | 30 | 30 | Concluído |
| Maria Oliveira | 05/11/2023 | 04/11/2024 | 04/11/2025 | 30 | 0 | Pendente |
