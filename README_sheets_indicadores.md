# Integração Google Sheets - Indicadores RH e Férias

Este script permite que as abas de indicadores (Turnover, Absenteísmo e Férias) no seu Google Sheets sejam enviadas automaticamente para o Supabase.

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
// 6. GATILHOS AUTOMÁTICOS PARA EDIÇÃO BIdirecional
// ==========================================
// Esta função roda quando você edita a planilha do google sheets e envia a mudança para o Supabase
function syncIndicadoresOnEdit(e) {
  if (!e || !e.range) return;
  const sheet = e.source.getActiveSheet();
  const sheetName = sheet.getName();
  
  if (['movimentacoes', 'absenteismo', 'ferias'].includes(sheetName)) {
    // Para simplificar, quando houver edição, a gente dispara o sync total daquela aba (ou de todas).
    // Para ambientes muito grandes seria melhor um Upsert específico para a linha, mas o syncAll 
    // garante a integridade já que deleta e re-escreve rapidamente.
    syncIndicadores();
  }
}
```

### 6. Como configurar a automação (Trigger Bidirecional da Planilha para o Supabase)
Para que as alterações feitas nas abas do Google Sheets subam *imediatamente* para o banco (assim como você tem na aba `Controle EPI e Fardamento`):
1. No Apps Script, clique no ícone do **Relógio** (Triggers / Acionadores) na barra lateral esquerda.
2. Clique em **"+ Adicionar Acionador"** no canto inferior direito.
3. Configure da seguinte forma:
   - Escolha qual função executar: **`syncIndicadoresOnEdit`**
   - Escolha o tipo de implantação: `Testes / Head`
   - Selecione a origem do evento: `Da planilha`
   - Selecione o tipo de evento: `Ao editar`
4. Clique em **Salvar**. (Se pedir permissões do Google, permita).
