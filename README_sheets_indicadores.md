# Integração Google Sheets - Indicadores RH e Férias

Este script permite que as abas de indicadores (Turnover, Absenteísmo e Férias) no seu Google Sheets sejam enviadas automaticamente para o Supabase.

### 1. Preparar o Google Sheets
Crie 3 abas novas na sua planilha com os seguintes nomes EXATOS:
- `movimentacoes`
- `absenteismo`
- `ferias`

### 2. Formato das Colunas (Aba "movimentacoes")
- **A**: `funcionario_nome` (Ex: Joao da Silva)
- **B**: `data_admissao` (Ex: 2024-01-15)
- **C**: `data_desligamento` (Ex: 2024-05-10)
- **D**: `tipo_movimentacao` (entrada ou saida)
- **E**: `motivo_saida` (voluntario ou involuntario)
- **F**: `mes_ref` (Ex: 2024-05)

### 3. Formato das Colunas (Aba "absenteismo")
- **A**: `funcionario_nome` (Ex: Joao da Silva)
- **B**: `mes_ref` (Ex: 2024-05)
- **C**: `horas_previstas` (Ex: 220)
- **D**: `horas_perdidas` (Ex: 8.5)
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
Vá em `Extensões > Apps Script` e crie um novo arquivo `indicadores.gs`. Cole o código abaixo:

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
    rows.forEach(row => {
      let obj = {};
      let isEmpty = true;
      config.fields.forEach((field, index) => {
        let val = row[index];
        if (val !== "" && val !== undefined) isEmpty = false;
        
        // Conversão de data do formato Google Sheets para YYYY-MM-DD
        if (val instanceof Date) {
          obj[field] = val.toISOString().split('T')[0];
        } else if (field === 'motivo_saida' && val === '') {
           obj[field] = null; // evita erro de constraint
        } else {
          obj[field] = val;
        }
      });
      if (!isEmpty) payload.push(obj);
    });

    if (payload.length > 0) {
      const insertUrl = `${SUPABASE_URL_INDICADORES}/rest/v1/${config.tableName}`;
      const optionsInsert = {
        method: "post",
        headers: {
          "apikey": SUPABASE_KEY_INDICADORES,
          "Authorization": `Bearer ${SUPABASE_KEY_INDICADORES}`,
          "Content-Type": "application/json",
          "Prefer": "return=minimal"
        },
        payload: JSON.stringify(payload),
        muteHttpExceptions: true
      };
      
      const res = UrlFetchApp.fetch(insertUrl, optionsInsert);
      console.log(`Tabela ${config.tableName} sync: `, res.getResponseCode());
    }
  });
}
```
