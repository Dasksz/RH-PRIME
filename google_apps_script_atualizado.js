/**
 * RH PRIME — sincronização por identidade estável, versão 2026-10-04.
 * A chave secreta deve existir somente nas Propriedades do script: SUPABASE_KEY.
 * Compatível com sb_secret_; nenhuma chave privilegiada é incluída no código.
 * Execute prepararEstruturaRH e instalarGatilhoRH antes de atualizar a implantação.
 */
const RH_TZ = 'America/Sao_Paulo';
const SHEET_CONFIG = {
  'Controle EPI e Fardamento': {
    tableName: 'funcionarios_epi', headerRow: 1, nameField: 'cpf',
    fields: ['admissao','nome','cpf','funcao','setor','unidade','epi_data','epi_itens','epi_link','fardamento_data','fardamento_itens','fardamento_link','validacao','local_registro','whatsapp','nascimento','carga_horaria','sexo','tamanho_farda','calca','calcado'],
    extra: ['id','data_desligamento','motivo_saida'], textDates: true
  },
  movimentacoes: {
    tableName: 'rh_movimentacoes', headerRow: 1, nameField: 'funcionario_nome',
    fields: ['funcionario_nome','data_admissao','data_desligamento','motivo_saida','cpf'], extra: ['id','funcionario_id','carga_horaria'], readOnly: ['funcionario_id']
  },
  absenteismo: {
    tableName: 'rh_absenteismo', headerRow: 1, nameField: 'id',
    fields: ['id','funcionario_nome','data_inicio','data_fim','horas_previstas','horas_perdidas','motivo','cpf','carga_horaria'], extra: ['mes_ref','funcionario_id'], readOnly: ['funcionario_id']
  },
  ferias: {
    tableName: 'rh_ferias', headerRow: 1, nameField: 'funcionario_nome',
    fields: ['funcionario_nome','data_inicio_aquisitivo','data_fim_aquisitivo','data_vencimento','dias_direito','dias_gozados','status','dias_abonados','cpf'],
    extra: ['id','dias_saldo','data_inicio_programada','dias_programados','data_fim_programada','data_retorno','historico_periodos','funcionario_id'], readOnly: ['dias_saldo','historico_periodos','funcionario_id']
  },
  epi_funcao: {
    tableName: 'epi_funcao', headerRow: 2, nameField: 'funcao',
    fields: ['funcao','capacete','protetor_auricular','colete_refletivo','protetor_dorsal','calca_faixa_refletiva','bota_marluvas','camisa_elma','regata_elma','camisa_copa','oculos_policarbonato'], extra: []
  },
  devolucoes_pendentes: {
    tableName: 'devolucoes_pendentes', headerRow: 1, nameField: 'funcionario_nome',
    fields: ['funcionario_nome','cpf','funcao','setor','unidade','local_registro','data_admissao','data_desligamento','epi_data','epi_itens','fardamento_data','fardamento_itens','status'], extra: ['id','itens_checked','funcionario_id'], readOnly: ['funcionario_id']
  },
  empresas: { tableName: 'empresas', headerRow: 1, nameField: 'cnpj', fields: ['nome','cnpj','endereco'], extra: ['id'] },
  desligados: {
    tableName: 'rh_desligados', headerRow: 1, nameField: 'cpf',
    fields: ['cpf','nome','funcao','setor','unidade','admissao','data_desligamento','motivo_saida','whatsapp','tamanho_farda','calcado','calca','sexo','carga_horaria','local_registro','epi_data','epi_itens','fardamento_data','fardamento_itens'], extra: ['id','funcionario_id'], readOnly: ['funcionario_id'], textDates: true
  }
};
const RH_DATES = ['admissao','nascimento','data_admissao','data_desligamento','data_inicio','data_fim','data_inicio_aquisitivo','data_fim_aquisitivo','data_vencimento','data_inicio_programada','data_fim_programada','data_retorno','epi_data','fardamento_data'];
const RH_NUMBERS = ['carga_horaria','horas_previstas','horas_perdidas','dias_direito','dias_gozados','dias_abonados','dias_programados','dias_saldo'];
const RH_JSON = ['itens_checked','historico_periodos'];

const RH_VERSION = "2026-10-04-rh3";
const RH_CONFIG_INICIAL = {
  "SUPABASE_URL": "https://gcksbfstheavpfgcdndb.supabase.co",
  "SPREADSHEET_ID": "1wJJu3N-lehjZaQw2JtfWLXdss6YbVP1JbfveDzWkGRg",
  "WEB_APP_URL": "https://script.google.com/macros/s/AKfycbxiOCFqmTythI4H9Lemp_b_9fsZcJrDZX-CBGWleVq0jV22EDtYASP5XmnWE5_7vqqg/exec"
};
function propriedadesRH() {
  const props = PropertiesService.getScriptProperties();
  Object.keys(RH_CONFIG_INICIAL).forEach(k => { if (!props.getProperty(k)) props.setProperty(k,RH_CONFIG_INICIAL[k]); });
  return props;
}
function configurarCredenciaisRH() { propriedadesRH(); }
function planilhaRH() {
  const id = propriedadesRH().getProperty('SPREADSHEET_ID');
  if (!id) throw new Error('Configure SPREADSHEET_ID nas Propriedades do script.');
  return SpreadsheetApp.openById(id);
}
function configPorTabelaRH(table) {
  const name = Object.keys(SHEET_CONFIG).find(n => SHEET_CONFIG[n].tableName === table);
  if (!name) throw new Error('Tabela não mapeada: ' + table);
  return { name: name, config: SHEET_CONFIG[name] };
}
function camposRH(config) { return config.fields.concat(config.extra || []); }
function normalizarNomeRH(value) { return String(value || '').normalize('NFD').replace(/[\u0300-\u036f]/g,'').trim().replace(/\s+/g,' ').toUpperCase(); }
function limparCPF(value) {
  if (value === null || value === undefined || value === '') return '';
  const digits = String(value).replace(/\D/g, '');
  return digits.length === 11 ? digits : '';
}
function formatoCpfRH(value) {
  if (value === null || value === undefined || value === '') return '';
  const cpf = limparCPF(value);
  if (!cpf) throw new Error('CPF precisa ter 11 dígitos; preserve zeros iniciais com formato Texto simples.');
  return cpf;
}
function formatarData(value) {
  if (value === null || value === undefined || value === '') return null;
  if (value instanceof Date) {
    if (isNaN(value.getTime())) throw new Error('Data inválida.');
    return Utilities.formatDate(value, RH_TZ, 'yyyy-MM-dd');
  }
  let s = String(value).trim();
  // Datas antigas foram gravadas como Date.toString(); preserva o dia civil explícito.
  const legacy = s.match(/^(?:Sun|Mon|Tue|Wed|Thu|Fri|Sat) (Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec) (\d{1,2}) (\d{4}) \d{2}:\d{2}:\d{2} GMT[+-]\d{4}(?: \(.*\))?$/);
  if (legacy) s = legacy[3] + '-' + String(['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'].indexOf(legacy[1])+1).padStart(2,'0') + '-' + legacy[2].padStart(2,'0');
  let match = s.match(/^(\d{1,2})\/(\d{1,2})\/(\d{4})$/);
  const iso = match ? match[3] + '-' + match[2].padStart(2,'0') + '-' + match[1].padStart(2,'0') : s;
  match = iso.match(/^(\d{4})-(\d{2})-(\d{2})$/);
  if (!match) throw new Error('Data deve ser DD/MM/AAAA ou AAAA-MM-DD.');
  const d = new Date(Date.UTC(Number(match[1]),Number(match[2])-1,Number(match[3])));
  if (d.toISOString().slice(0,10) !== iso) throw new Error('Data inexistente: ' + iso);
  return iso;
}
function formatarDataParaPlanilha(value) {
  const iso = formatarData(value);
  return iso ? iso.split('-').reverse().join('/') : '';
}
function numeroRH(value, field) {
  if (value === '' || value === null || value === undefined) return null;
  const n = typeof value === 'number' ? value : Number(String(value).trim().replace(',','.'));
  if (!Number.isFinite(n) || n < 0) throw new Error('Valor inválido em ' + field);
  if (!['horas_previstas','horas_perdidas'].includes(field) && !Number.isInteger(n)) throw new Error(field + ' precisa ser inteiro.');
  return n;
}
function calcularHorasUteis(inicio, fim, carga) {
  const a = formatarData(inicio), b = formatarData(fim);
  if (!a || !b || a > b) return 0;
  const factor = (Number(carga) > 0 ? Number(carga) : 220) / 220;
  let hours = 0;
  for (let d = new Date(a + 'T12:00:00Z'); d <= new Date(b + 'T12:00:00Z'); d.setUTCDate(d.getUTCDate()+1)) {
    const day = d.getUTCDay();
    hours += (day === 0 ? 0 : day === 6 ? 4 : 8) * factor;
  }
  return Math.round(hours * 100) / 100;
}
function requestRH(table, method, query, payload) {
  configPorTabelaRH(table); // lista permitida
  const props = propriedadesRH(), base = props.getProperty('SUPABASE_URL'), key = props.getProperty('SUPABASE_KEY');
  if (!base || !key) throw new Error('Configure SUPABASE_URL e SUPABASE_KEY nas Propriedades do script.');
  if (!/^https:\/\/[a-z0-9-]+\.supabase\.co\/?$/.test(base)) throw new Error('SUPABASE_URL inválida.');
  const options = { method: method, muteHttpExceptions: true, headers: Object.assign({ apikey: key, 'Content-Type': 'application/json', Prefer: 'return=representation' }, key.startsWith('sb_secret_') ? {} : { Authorization: 'Bearer ' + key }) };
  if (payload !== undefined) options.payload = JSON.stringify(payload);
  const response = UrlFetchApp.fetch(base.replace(/\/$/,'') + '/rest/v1/' + table + (query ? '?' + query : ''), options);
  const status = response.getResponseCode(), text = response.getContentText();
  if (status < 200 || status >= 300) throw new Error('Supabase: ' + method.toUpperCase() + ' ' + table + ' retornou HTTP ' + status + '. Verifique as Execuções.');
  if (!text) return [];
  const data = JSON.parse(text);
  if (!Array.isArray(data)) throw new Error('Resposta inesperada do Supabase para ' + table);
  return data;
}
function filtroRH(field, value) { return field + '=eq.' + encodeURIComponent(String(value)); }
function lerTabelaRH(table) {
  const list = [], key = table === 'epi_funcao' ? 'funcao' : 'id';
  for (let offset = 0; ; offset += 1000) {
    const page = requestRH(table,'get','select=*&order=' + key + '&limit=1000&offset=' + offset);
    list.push.apply(list,page);
    if (page.length < 1000) return list;
  }
}
function comLockRH(fn) {
  const lock = LockService.getScriptLock();
  if (!lock.tryLock(25000)) throw new Error('Outra sincronização está em execução. Tente novamente.');
  try { return fn(); } finally { lock.releaseLock(); }
}
function layoutRH(sheet, config, create) {
  const width = Math.max(sheet.getLastColumn(), camposRH(config).length);
  if (create && sheet.getMaxColumns() < width) sheet.insertColumnsAfter(sheet.getMaxColumns(), width - sheet.getMaxColumns());
  const headers = sheet.getRange(config.headerRow,1,1,width).getValues()[0], map = {};
  camposRH(config).forEach(field => {
    const matches = headers.map((h,i) => String(h).trim() === field ? i + 1 : 0).filter(Boolean);
    if (matches.length > 1) throw new Error('Cabeçalho duplicado: ' + field);
    if (matches.length) map[field] = matches[0];
  });
  // As 21 colunas originais de EPI mantêm os rótulos visuais e a posição.
  config.fields.forEach((field,i) => {
    if (map[field]) return;
    if (['funcionarios_epi','epi_funcao'].includes(config.tableName)) { map[field] = i+1; return; }
    if (create && (!headers[i] || String(headers[i]).trim() === field)) {
      map[field] = i+1; sheet.getRange(config.headerRow,i+1).setValue(field); headers[i] = field;
    }
  });
  camposRH(config).forEach(field => {
    if (map[field]) return;
    if (!create) throw new Error('Cabeçalho ' + field + ' ausente em ' + sheet.getName() + '. Execute prepararEstruturaRH.');
    let col = headers.length + 1;
    if (col > sheet.getMaxColumns()) sheet.insertColumnsAfter(sheet.getMaxColumns(),col-sheet.getMaxColumns());
    sheet.getRange(config.headerRow,col).setValue(field); headers.push(field); map[field] = col;
  });
  return map;
}
function objetoLinhaRH(sheet, row, map) {
  const values = sheet.getRange(row,1,1,Math.max.apply(null,Object.values(map))).getValues()[0], object = {};
  Object.keys(map).forEach(field => object[field] = values[map[field]-1]);
  return object;
}
function buildPayload(sheetName, rowData) {
  const config = SHEET_CONFIG[sheetName];
  if (!config) throw new Error('Aba não mapeada.');
  const raw = Array.isArray(rowData) ? Object.fromEntries(config.fields.map((f,i)=>[f,rowData[i]])) : rowData;
  const payload = {};
  camposRH(config).forEach(field => {
    if (!(field in raw) || (config.readOnly || []).includes(field)) return;
    let value = raw[field];
    if (field === 'id') { if (value !== '' && value != null) payload.id = value; return; }
    if (field === 'cpf') value = formatoCpfRH(value) || null;
    else if (RH_DATES.includes(field)) {
      const iso = formatarData(value);
      const textDate = (config.textDates && ['admissao','nascimento','epi_data','fardamento_data'].includes(field)) || ['epi_data','fardamento_data'].includes(field);
      value = textDate ? (iso ? iso.split('-').reverse().join('/') : '') : iso;
    } else if (RH_NUMBERS.includes(field)) value = numeroRH(value,field);
    else if (RH_JSON.includes(field)) value = value === '' || value == null ? null : typeof value === 'string' ? JSON.parse(value) : value;
    else if (config.tableName === 'epi_funcao' && field !== 'funcao') {
      if (value === true || value === false) {} else if (normalizarNomeRH(value) === 'SIM') value = true;
      else if (['NÃO','NAO',''].includes(normalizarNomeRH(value))) value = false;
      else throw new Error('EPI deve ser SIM ou NÃO: ' + field);
    } else if (field === 'motivo_saida') value = value ? String(value).trim().toLowerCase() : null;
    else value = value === null || value === undefined ? '' : String(value).trim();
    payload[field] = value;
  });
  const name = config.tableName === 'funcionarios_epi' || config.tableName === 'rh_desligados' ? 'nome' : 'funcionario_nome';
  if (name in payload && !payload[name]) throw new Error('Nome obrigatório.');
  if (config.tableName === 'epi_funcao' && (!payload.funcao || normalizarNomeRH(payload.funcao) === 'FUNCAO')) throw new Error('Linha de cabeçalho não é uma função.');
  if (config.tableName === 'funcionarios_epi' && !payload.cpf) throw new Error('CPF obrigatório no cadastro de EPI.');
  if (payload.data_inicio && payload.data_fim && payload.data_inicio > payload.data_fim) throw new Error('Data final anterior à inicial.');
  if (payload.data_admissao && payload.data_desligamento && payload.data_admissao > payload.data_desligamento) throw new Error('Desligamento anterior à admissão.');
  if (config.tableName === 'rh_absenteismo') {
    if (!payload.data_inicio || !payload.data_fim) throw new Error('Informe as duas datas do afastamento.');
    payload.mes_ref = payload.data_inicio.slice(5,7) + '/' + payload.data_inicio.slice(0,4);
    // Uma quantidade manual, inclusive zero, tem precedência sobre a estimativa.
    if (payload.horas_perdidas == null) payload.horas_perdidas = calcularHorasUteis(payload.data_inicio,payload.data_fim,payload.carga_horaria);
  }
  return payload;
}
function encontrarRegistroRH(config, payload) {
  const table = config.tableName;
  if (table === 'epi_funcao') return requestRH(table,'get',filtroRH('funcao',payload.funcao) + '&select=*');
  if (payload.id) return requestRH(table,'get',filtroRH('id',payload.id) + '&select=*');
  if (payload.cpf) {
    const found = requestRH(table,'get',filtroRH('cpf',payload.cpf) + '&select=*');
    if (table === 'rh_absenteismo') return found.filter(r => r.data_inicio === payload.data_inicio && r.data_fim === payload.data_fim && r.motivo === payload.motivo);
    if (found.length) return found;
  }
  if (table === 'empresas') return requestRH(table,'get',filtroRH('cnpj',payload.cnpj) + '&select=*');
  // Cadastros antigos sem CPF: vincula apenas quando o nome é único.
  const field = ['funcionarios_epi','rh_desligados'].includes(table) ? 'nome' : 'funcionario_nome';
  if (!payload[field]) return [];
  let found = requestRH(table,'get',filtroRH(field,payload[field]) + '&select=*');
  found = found.filter(r => !r.cpf || !payload.cpf || limparCPF(r.cpf) === payload.cpf);
  if (table === 'rh_absenteismo') found = found.filter(r => r.data_inicio === payload.data_inicio && r.data_fim === payload.data_fim && r.motivo === payload.motivo);
  return found;
}
function mesmosDadosRH(record, payload) {
  return Object.keys(payload).every(field => {
    let a = record[field], b = payload[field];
    if (RH_DATES.includes(field) && a && b) { a = formatarData(a); b = formatarData(b); }
    if (a && typeof a === 'object') return JSON.stringify(a) === JSON.stringify(b);
    return (a == null ? '' : String(a)) === (b == null ? '' : String(b));
  });
  
}
function upsertRecord(tableName, nameField, payload) {
  const config = configPorTabelaRH(tableName).config;
  const found = encontrarRegistroRH(config,payload);
  if (found.length > 1) throw new Error('Mais de um registro corresponde à linha em ' + tableName + '; vincule pelo id.');
  if (payload.id && !found.length) throw new Error('ID não encontrado; a linha pode ter sido excluída no sistema. Não será recriada automaticamente.');
  if (found.length && mesmosDadosRH(found[0],payload)) return found[0];
  const data = Object.assign({},payload); delete data.id;
  const records = found.length ? requestRH(tableName,'patch',filtroRH(tableName === 'epi_funcao' ? 'funcao' : 'id',tableName === 'epi_funcao' ? found[0].funcao : found[0].id),data) : requestRH(tableName,'post','',[data]);
  if (records.length !== 1) throw new Error('Gravação não confirmou exatamente um registro em ' + tableName);
  return records[0];
}
function correspondeLinhaRH(config, row, record) {
  if (config.tableName === 'epi_funcao') return normalizarNomeRH(row.funcao) === normalizarNomeRH(record.funcao);
  if (row.id && record.id) return String(row.id) === String(record.id);
  if (row.cpf && record.cpf && limparCPF(row.cpf) && limparCPF(row.cpf) === limparCPF(record.cpf)) {
    if (config.tableName !== 'rh_absenteismo') return true;
  }
  const field = ['funcionarios_epi','rh_desligados'].includes(config.tableName) ? 'nome' : config.tableName === 'empresas' ? 'cnpj' : 'funcionario_nome';
  if (!record[field] || normalizarNomeRH(row[field]) !== normalizarNomeRH(record[field])) return false;
  if (limparCPF(row.cpf) && limparCPF(record.cpf) && limparCPF(row.cpf) !== limparCPF(record.cpf)) return false;
  if (config.tableName === 'rh_absenteismo') return formatarData(row.data_inicio) === formatarData(record.data_inicio) && formatarData(row.data_fim) === formatarData(record.data_fim) && String(row.motivo || '').trim() === String(record.motivo || '').trim();
  return true;
}
function acharLinhaRH(sheet, config, map, record, oldRecord) {
  const matches = [];
  if (sheet.getLastRow() <= config.headerRow) return -1;
  const values = sheet.getRange(config.headerRow+1,1,sheet.getLastRow()-config.headerRow,Math.max.apply(null,Object.values(map))).getValues();
  values.forEach((values,i) => {
    const row = {}; Object.keys(map).forEach(f => row[f] = values[map[f]-1]);
    if (correspondeLinhaRH(config,row,record) || (oldRecord && correspondeLinhaRH(config,row,oldRecord))) matches.push(config.headerRow+1+i);
  });
  if (matches.length > 1) throw new Error('Linhas duplicadas em ' + sheet.getName() + '; nenhuma linha foi sobrescrita.');
  return matches.length ? matches[0] : -1;
}
function valorCelulaRH(field, value) {
  if (value == null) return '';
  if (RH_DATES.includes(field)) return formatarDataParaPlanilha(value);
  if (RH_JSON.includes(field)) return JSON.stringify(value);
  if (typeof value === 'boolean') return value ? 'SIM' : 'NÃO';
  return value;
}
function escreverRegistroRH(sheet, config, map, row, record) {
  // Grava somente campos mapeados. Preserva colunas auxiliares, fórmulas e formatação.
  const cells = Object.keys(map).filter(field => Object.prototype.hasOwnProperty.call(record,field))
    .map(field => ({field:field,col:map[field],value:valorCelulaRH(field,record[field])})).sort((a,b)=>a.col-b.col);
  cells.forEach(cell => {
    const range = sheet.getRange(row,cell.col);
    if ((config.extra || []).includes(cell.field)) range.clearDataValidations();
    // Valores confirmados no banco ampliam somente listas de motivos; demais regras permanecem.
    if (['motivo','motivo_saida'].includes(cell.field) && cell.value !== '') {
      const rule = range.getDataValidation();
      if (rule && rule.getCriteriaType() === SpreadsheetApp.DataValidationCriteria.VALUE_IN_LIST) {
        const args = rule.getCriteriaValues(), options = args[0].slice();
        if (!options.includes(String(cell.value))) range.setDataValidation(rule.copy().requireValueInList(options.concat(String(cell.value)),args[1] !== false).build());
      }
    }
  });
  const groups = [];
  cells.forEach(cell => {
    let group = groups[groups.length-1];
    if (!group || cell.col !== group.start+group.values.length) { group = {start:cell.col,values:[]}; groups.push(group); }
    group.values.push(cell.value);
  });
  groups.forEach(group => sheet.getRange(row,group.start,1,group.values.length).setValues([group.values]));
  if (config.tableName === 'funcionarios_epi') {
    if (!RH_EMPRESAS_CACHE) RH_EMPRESAS_CACHE = requestRH('empresas','get','select=*');
    const cnpj = obterCnpjLocalRegistro(record.local_registro,RH_EMPRESAS_CACHE);
    sheet.getRange(row,23).setNumberFormat('@').setValue(cnpj || '');
  }
}
let RH_EMPRESAS_CACHE = null;
function obterCnpjLocalRegistro(local, empresas) {
  const text = normalizarNomeRH(local);
  const match = (empresas || []).find(e => normalizarNomeRH(e.nome) === text);
  if (match) return match.cnpj;
  if (text.includes('NUNES') || text.includes('VIEIRA') || text.includes('0001-39')) return '48.986.353/0001-39';
  if (text.includes('JEQUIÉ') || text.includes('JEQUIE') || text.includes('0002-82')) return '52.522.019/0002-82';
  if (text.includes('ILHÉUS') || text.includes('ILHEUS') || text.includes('0001-00')) return '52.522.019/0001-00';
  return ''; // local desconhecido não recebe automaticamente o CNPJ de outra empresa
}
function sincronizarLinhaRH(sheet, row, config, map) {
  const raw = objetoLinhaRH(sheet,row,map);
  const required = config.tableName === 'epi_funcao' ? 'funcao' : config.tableName === 'empresas' ? 'nome' : ['funcionarios_epi','rh_desligados'].includes(config.tableName) ? 'nome' : 'funcionario_nome';
  if (!raw[required]) return 'vazia';
  const payload = buildPayload(sheet.getName(),raw);
  const record = upsertRecord(config.tableName,config.nameField,payload);
  escreverRegistroRH(sheet,config,map,row,record);
  return 'ok';
}
function syncToSupabaseOnEdit(e) {
  if (!e || !e.range) return;
  return comLockRH(() => {
    const sheet = e.range.getSheet(), config = SHEET_CONFIG[sheet.getName()];
    if (!config) return;
    if (sheet.getParent().getId() !== propriedadesRH().getProperty('SPREADSHEET_ID')) throw new Error('Planilha diferente da configurada.');
    const map = layoutRH(sheet,config,false), first = Math.max(config.headerRow+1,e.range.getRow()), last = e.range.getLastRow();
    const editable = Object.keys(map).filter(f => f !== 'id' && !(config.readOnly || []).includes(f));
    if (!editable.some(f => map[f] >= e.range.getColumn() && map[f] <= e.range.getLastColumn())) return;
    const errors = [];
    for (let row = first; row <= last; row++) {
      try { sincronizarLinhaRH(sheet,row,config,map); }
      catch (err) { errors.push('Linha ' + row + ': ' + err.message); }
    }
    if (errors.length) { sheet.getParent().toast(errors.join('\n'),'Sincronização não concluída',15); throw new Error(errors.join('\n')); }
  });
}
// Não usa gatilho simples para chamadas que exigem autorização.
function onEdit(e) { if (e && e.triggerUid) return syncToSupabaseOnEdit(e); }
function onOpen() {
  SpreadsheetApp.getUi().createMenu('RH Prime Sync')
    .addItem('Preparar estrutura (com backup)','prepararEstruturaRH')
    .addItem('Instalar gatilho de edição','instalarGatilhoRH')
    .addItem('Ativar webhooks após implantação','ativarWebhooksRH')
    .addSeparator().addItem('Enviar planilha para banco','syncAllToSupabase')
    .addItem('Receber banco na planilha','sincronizarBancoParaPlanilha')
    .addItem('Atualizar apenas EPI e fardamento','sincronizarControleEPI').addToUi();
}
function prepararEstruturaRH() {
  return comLockRH(() => {
    const ss = planilhaRH();
    const backup = DriveApp.getFileById(ss.getId()).makeCopy(ss.getName() + ' — backup RH ' + Utilities.formatDate(new Date(),RH_TZ,'yyyy-MM-dd HH-mm-ss'));
    propriedadesRH().setProperty('ULTIMO_BACKUP_RH',backup.getId());
    Object.keys(SHEET_CONFIG).forEach(name => {
      const config = SHEET_CONFIG[name]; let sheet = ss.getSheetByName(name);
      if (!sheet) { sheet = ss.insertSheet(name); if (config.headerRow === 2) sheet.getRange(1,1).setValue('Regras de EPI por função'); }
      const map = layoutRH(sheet,config,true);
      ['cpf','id','cnpj','whatsapp'].concat(RH_DATES).filter(f => map[f]).forEach(f => sheet.getRange(config.headerRow+1,map[f],Math.max(1,sheet.getMaxRows()-config.headerRow),1).setNumberFormat('@'));
      (config.extra || []).filter(f => map[f]).forEach(f => sheet.getRange(config.headerRow+1,map[f],Math.max(1,sheet.getMaxRows()-config.headerRow),1).clearDataValidations());
      sheet.setFrozenRows(config.headerRow);
    });
    ss.setSpreadsheetTimeZone(RH_TZ);
    ss.toast('Backup criado. Estrutura preparada. Receba os dados do banco antes de enviar a planilha.','RH PRIME',15);
  });
}
function instalarGatilhoRH() {
  const ss = planilhaRH(), handlers = ['onEdit','syncToSupabaseOnEdit'];
  ScriptApp.getProjectTriggers().forEach(t => {
    if (handlers.includes(t.getHandlerFunction()) && t.getTriggerSourceId() === ss.getId()) ScriptApp.deleteTrigger(t);
  });
  ScriptApp.newTrigger('syncToSupabaseOnEdit').forSpreadsheet(ss).onEdit().create();
  ss.toast('Um gatilho de edição instalado para esta conta.','RH PRIME',10);
}
function syncAllToSupabase() {
  return comLockRH(() => {
    const ss = planilhaRH(), errors = []; let count = 0;
    Object.keys(SHEET_CONFIG).forEach(name => {
      const sheet = ss.getSheetByName(name), config = SHEET_CONFIG[name];
      if (!sheet) { errors.push('Aba ausente: ' + name); return; }
      const map = layoutRH(sheet,config,false);
      for (let row = config.headerRow+1; row <= sheet.getLastRow(); row++) {
        try { if (sincronizarLinhaRH(sheet,row,config,map) === 'ok') count++; }
        catch (err) { errors.push(name + ', linha ' + row + ': ' + err.message); }
      }
    });
    if (errors.length) throw new Error(count + ' linhas confirmadas; ' + errors.length + ' erros: ' + errors.join('\n'));
    ss.toast(count + ' linhas confirmadas no banco.','RH PRIME',15);
    return count;
  });
}
function receberTabelaRH(ss, name) {
  const config = SHEET_CONFIG[name], sheet = ss.getSheetByName(name);
  if (!sheet) throw new Error('Aba ausente: ' + name);
  const map = layoutRH(sheet,config,false), records = lerTabelaRH(config.tableName);
  const errors = [];
  records.forEach(record => {
    if (config.tableName === 'epi_funcao' && normalizarNomeRH(record.funcao) === 'FUNCAO') return;
    try {
      let row = acharLinhaRH(sheet,config,map,record,null);
      if (row === -1) row = sheet.getLastRow()+1;
      escreverRegistroRH(sheet,config,map,row,record);
    } catch (err) { errors.push(err.message); }
  });
  if (errors.length) throw new Error(name + ': ' + errors.length + ' registros não atualizados. ' + errors.join('\n'));
  return records.length;
}
function sincronizarBancoParaPlanilha() {
  return comLockRH(() => {
    const ss = planilhaRH(); let count = 0; const errors = [];
    Object.keys(SHEET_CONFIG).forEach(name => {
      try { count += receberTabelaRH(ss,name); } catch (err) { errors.push(err.message); }
    });
    if (errors.length) throw new Error('Recebimento parcial; confira as Execuções: ' + errors.join('\n'));
    ss.toast(count + ' registros lidos. Linhas extras não foram apagadas; confira divergências.','RH PRIME',15);
    return count;
  });
}
function sincronizarControleEPI() { return comLockRH(() => receberTabelaRH(planilhaRH(),'Controle EPI e Fardamento')); }
// Mantém o nome antigo para botões existentes; não combina envio e recebimento.
function sincronizarTudoSupabase() { return syncAllToSupabase(); }
function respostaRH(data) { return ContentService.createTextOutput(JSON.stringify(data)).setMimeType(ContentService.MimeType.JSON); }
function doPost(e) {
  try {
    if (!e || !e.postData) throw new Error('Payload ausente.');
    const props = propriedadesRH(), token = props.getProperty('WEBHOOK_TOKEN');
    // Ative a propriedade somente após configurar o mesmo token na URL dos webhooks.
    if (token && (!e.parameter || e.parameter.token !== token)) throw new Error('Webhook não autorizado.');
    const data = JSON.parse(e.postData.contents);
    if (data.schema && data.schema !== 'public') throw new Error('Schema não permitido.');
    if (!['INSERT','UPDATE','DELETE'].includes(data.type)) throw new Error('Evento inválido.');
    return comLockRH(() => {
      const target = configPorTabelaRH(data.table), config = target.config;
      const ss = planilhaRH(), sheet = ss.getSheetByName(target.name);
      if (!sheet) throw new Error('Aba ausente: ' + target.name);
      const map = layoutRH(sheet,config,false), eventRecord = data.type === 'DELETE' ? data.old_record : data.record;
      if (!eventRecord) throw new Error('Registro ausente.');
      const pk = data.table === 'epi_funcao' ? 'funcao' : 'id';
      if (!eventRecord[pk]) throw new Error('Identidade do registro ausente.');
      // Lê o estado atual: eventos atrasados não sobrescrevem uma edição mais nova.
      const current = requestRH(data.table,'get',filtroRH(pk,eventRecord[pk]) + '&select=*');
      if (current.length > 1) throw new Error('Identidade duplicada no banco.');
      if (!current.length) {
        if (data.type !== 'DELETE') return respostaRH({status:'ignored',message:'Registro já excluído no banco'});
        const row = acharLinhaRH(sheet,config,map,eventRecord,null);
        if (row === -1) return respostaRH({status:'ignored',message:'Registro já ausente na planilha'});
        sheet.deleteRow(row);
        return respostaRH({status:'success',action:'deleted'});
      }
      const record = current[0];
      let row = acharLinhaRH(sheet,config,map,record,data.old_record);
      const action = row === -1 ? 'inserted' : 'updated';
      if (row === -1) row = sheet.getLastRow()+1;
      escreverRegistroRH(sheet,config,map,row,record);
      if (data.table === 'empresas') atualizarCnpjsRH(ss);
      return respostaRH({status:'success',action:action});
    });
  } catch (error) {
    console.error('RH Sync: ' + error.message);
    return respostaRH({status:'error',message:error.message});
  }
}

// Verifica a nova implantação antes de conectar os webhooks do banco.
function doGet() { return respostaRH({status:'ok',versao:RH_VERSION}); }
function ativarWebhooksRH() {
  const props=propriedadesRH();
  const deployed=UrlFetchApp.fetch(props.getProperty('WEB_APP_URL'),{muteHttpExceptions:true});
  let version; try { version=JSON.parse(deployed.getContentText()).versao; } catch (err) {}
  if(deployed.getResponseCode()!==200 || version!==RH_VERSION) throw new Error('Atualize a implantação Web App para esta versão, executando como você e com acesso Qualquer pessoa. Preserve a URL existente.');
  const key=props.getProperty('SUPABASE_KEY');
  const response=UrlFetchApp.fetch(props.getProperty('SUPABASE_URL')+'/rest/v1/rpc/rh_ativar_webhooks',{method:'post',contentType:'application/json',payload:'{}',headers:Object.assign({apikey:key},key.startsWith('sb_secret_')?{}:{Authorization:'Bearer '+key}),muteHttpExceptions:true});
  if(response.getResponseCode()<200 || response.getResponseCode()>=300) throw new Error('Não foi possível ativar webhooks. HTTP '+response.getResponseCode());
  planilhaRH().toast('Webhooks ativados. Teste uma edição em cada direção.','RH PRIME',10);
}

function atualizarCnpjsRH(ss) {
  const sheet=ss.getSheetByName('Controle EPI e Fardamento');
  if (!sheet || sheet.getLastRow()<2) return;
  RH_EMPRESAS_CACHE=requestRH('empresas','get','select=*');
  const config=SHEET_CONFIG['Controle EPI e Fardamento'],map=layoutRH(sheet,config,false),count=sheet.getLastRow()-1;
  const locals=sheet.getRange(2,map.local_registro,count,1).getValues();
  sheet.getRange(2,23,count,1).setValues(locals.map(row=>[obterCnpjLocalRegistro(row[0],RH_EMPRESAS_CACHE)]));
}

// Teste somente leitura, sem sincronização, criação de gatilhos ou envio de mensagens.
function verificarConexaoSupabaseRH() {
  const props=propriedadesRH(), key=props.getProperty('SUPABASE_KEY');
  if(!key || !key.startsWith('sb_secret_')) throw Error('Cole a nova chave sb_secret_ em SUPABASE_KEY nas Propriedades do script.');
  requestRH('funcionarios_epi','get','select=id&limit=0');
  if(typeof bancoDriveRH==='function') bancoDriveRH('rh_automation_settings','get','select=id&limit=0');
  if(typeof bancoDocumentosRH==='function') bancoDocumentosRH('rh_delivery_documents','get','select=id&limit=0');
  console.log('Conexão REST com a nova chave secreta validada. Nenhum dado foi alterado.');
}
