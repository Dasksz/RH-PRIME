(function (global) {
  'use strict';

  const h = React.createElement;
  const detailLabels = {ano: 'Ano', modelo: 'Modelo', descricao: 'Descrição', nenhum: 'Sem complemento'};
  const actionLabels = {entrada: 'Entrada', ajuste: 'Saída de estoque', entrega: 'Entrega', devolucao: 'Devolução', baixa: 'Baixa por perda ou extravio'};
  const destinations = {disponivel: 'Reintegrado ao estoque', avariado: 'Retido para conferência'};
  const branchOptions = ['FILIAL 5', 'FILIAL 8'];
  const escape = value => String(value ?? '').replace(/[&<>"']/g, c => ({'&':'&amp;', '<':'&lt;', '>':'&gt;', '"':'&quot;', "'":'&#39;'})[c]);
  const formatDate = value => value.split('-').reverse().join('/');
  const option = (value, text) => h('option', {value, key: value}, text);
  const field = (label, input) => h('label', null, label, input);
  const button = (label, props = {}) => h('button', {type: 'button', ...props}, label);
  const describe = (name, variant) => [name, variant].filter(Boolean).join(' · ');
  const normalizeTypeName = name => (name || '').trim().toLowerCase();

  function table(headers, rows, empty) {
    return h('div', {className: 'rh-asset-scroll'}, h('table', null,
      h('thead', null, h('tr', null, headers.map(title => h('th', {scope: 'col', key: title}, title)))),
      h('tbody', null, rows.length ? rows : h('tr', null, h('td', {colSpan: headers.length}, empty)))));
  }

  function cells(key, values) {
    return h('tr', {key}, values.map((value, index) => h('td', {key: index}, value)));
  }

  async function readEvents(client, employeeId) {
    if (!employeeId) return RH.result(client.rpc('rh_asset_stock_history'));
    const events = [];
    for (let offset = 0; ; offset += 1000) {
      const page = await RH.result(client.from('rh_asset_events').select('*')
        .eq('funcionario_id', employeeId).order('data', {ascending: false})
        .order('created_at', {ascending: false}).order('id').range(offset, offset + 999));
      events.push(...page);
      if (page.length < 1000) return events;
    }
  }

  function deliveryBalances(events) {
    const returned = new Map();
    for (const event of events) {
      if (event.entrega_id) returned.set(event.entrega_id, (returned.get(event.entrega_id) || 0) + event.quantidade);
    }
    return events.filter(event => event.acao === 'entrega').map(event => ({
      ...event, restante: event.quantidade - (returned.get(event.id) || 0)
    }));
  }

  function documentHtml(event) {
    const doc = event.ficha;
    const escapeFields = object => Object.fromEntries(Object.entries(object).map(([key, value]) => [key, escape(value)]));
    const company = escapeFields(doc.empresa);
    const employee = escapeFields(doc.colaborador);
    const admission = doc.colaborador.admissao;
    const detail = escape(doc.variante ? detailLabels[doc.detalhe] + ' — ' + doc.variante : '—');
    const cell = 'padding:6px 8px;border:1px solid #111!important;overflow-wrap:anywhere';
    return `
      <div class="rh-asset-document" style="width:1080px;background:white;color:#111;font:13px/1.35 Arial,sans-serif;padding:24px;box-sizing:border-box">
        <div data-ficha-pagina>
          <div style="display:grid;grid-template-columns:repeat(2,minmax(0,1fr));border:1px solid #111;text-align:center;overflow-wrap:anywhere">
            <div style="padding:10px 14px;border-right:1px solid #111">
              <strong style="font-size:16px">${company.nome}</strong><br>
              <strong>CNPJ:</strong> ${company.cnpj}<br><strong>Endereço:</strong> ${company.endereco}
            </div>
            <div style="display:flex;align-items:center;justify-content:center;padding:10px 14px">
              <strong style="font-size:18px">FICHA INDIVIDUAL DE ENTREGA DE EQUIPAMENTOS</strong>
            </div>
          </div>
          <div style="border:1px solid #111;margin:6px 0 12px;overflow-wrap:anywhere">
            <div style="display:grid;grid-template-columns:3fr 1fr 1.35fr;gap:12px;padding:5px 8px;border-bottom:1px solid #111">
              <div><strong>Nome:</strong> ${employee.nome}</div>
              <div><strong>CPF:</strong> ${employee.cpf}</div>
              <div><strong>Data de admissão:</strong> ${admission ? escape(formatDate(admission)) : 'Não informada'}</div>
            </div>
            <div style="display:grid;grid-template-columns:1.25fr 2.5fr 1fr;gap:12px;padding:5px 8px">
              <div><strong>Setor:</strong> ${employee.setor}</div>
              <div><strong>Função:</strong> ${employee.cargo}</div>
              <div><strong>Unidade:</strong> ${employee.unidade}</div>
            </div>
          </div>
          <div style="border:1px solid #111;margin-bottom:8px;padding:8px;overflow-wrap:anywhere">
            <strong style="color:#b91c1c">TERMO DE RESPONSABILIDADE</strong>
            <p style="margin:4px 0">Comprometo-me a utilizar o equipamento para o trabalho, zelar por sua guarda e conservação, comunicar prontamente perda, extravio ou dano e devolvê-lo quando solicitado ou ao término do vínculo. O desgaste normal decorrente do uso regular fica excluído.</p>
            <p style="margin:0">Em caso de perda ou dano, eventual ressarcimento será limitado ao prejuízo efetivamente comprovado, após apuração da responsabilidade. O custo atualizado de reparo ou reposição por item equivalente poderá servir de referência documentada, consideradas as condições e a vida útil do bem entregue. Eventual desconto salarial observará o art. 462, § 1º, da CLT e as normas coletivas aplicáveis, mediante ajuste prévio e culpa comprovada ou dolo comprovado.</p>
          </div>
          <table style="width:100%;table-layout:fixed;border-collapse:collapse;color:#111">
            <colgroup><col style="width:17%"><col style="width:34%"><col style="width:39%"><col style="width:10%"></colgroup>
            <thead>
              <tr><th colspan="4" style="${cell};background:#003399;color:white;text-align:center">EQUIPAMENTO ENTREGUE</th></tr>
              <tr style="background:#f1f1f1;text-align:center">
                <th scope="col" style="${cell}">Data da entrega</th><th scope="col" style="${cell}">Equipamento</th>
                <th scope="col" style="${cell}">Ano / modelo / descrição</th><th scope="col" style="${cell}">Qtd.</th>
              </tr>
            </thead>
            <tbody>
              <tr>
                <td style="${cell};text-align:center">${formatDate(event.data)}</td><td style="${cell}">${escape(doc.item)}</td>
                <td style="${cell}">${detail}</td><td style="${cell};text-align:center">${event.quantidade}</td>
              </tr>
              ${event.observacao ? '<tr><td colspan="4" style="' + cell + '"><strong>Observação:</strong> ' + escape(event.observacao) + '</td></tr>' : ''}
            </tbody>
          </table>
          <div style="border:1px solid #111;margin-top:12px;padding:8px">
            <div style="background:#f7f7f7;border:1px solid #aaa;padding:10px">
              <strong style="color:#002060">TERMO DE RECEBIMENTO DE EQUIPAMENTO</strong>
              <p style="margin:4px 0 0">Declaro que recebi e conferi o equipamento acima.</p>
              <div style="display:flex;align-items:flex-end;justify-content:space-between;margin-top:32px">
                <span><strong>Data:</strong> ____/____/________</span>
                <span style="width:50%;border-top:1px solid #111;padding-top:4px;text-align:center">Assinatura do colaborador</span>
              </div>
            </div>
          </div>
          <p style="margin:4px 0 0;font-size:10px;color:#333">Registro ${escape(event.id)}</p>
        </div>
      </div>`;
  }

  async function download(event) {
    const container = document.createElement('div');
    container.className = 'rh-equipment-pdf-host';
    container.setAttribute('aria-hidden', 'true');
    container.innerHTML = documentHtml(event);
    document.body.append(container);
    try {
      await RHFichaPadrao.savePdf(container.firstElementChild, {
        margin: 5, filename: 'Ficha_Entrega_Equipamentos_' + event.data + '_' + event.id + '.pdf',
        image: {type: 'jpeg', quality: .98},
        html2canvas: {scale: 2, scrollX: 0, scrollY: 0},
        jsPDF: {unit: 'mm', format: 'a4', orientation: 'landscape'}
      });
    } finally {
      container.remove();
    }
  }

  function Module({client, employee, onSaved, registrationTarget}) {
    const [data, setData] = React.useState(null);
    const [busy, setBusy] = React.useState(false);
    const [error, setError] = React.useState('');
    const [notice, setNotice] = React.useState('');
    const defaultEditor = employee ? 'entrega' : null;
    const [editing, setEditing] = React.useState(defaultEditor);
    const [draft, setDraft] = React.useState(() => ({data: RH.today(), quantidade: 1}));
    const [proofEdit, setProofEdit] = React.useState(null);
    const request = React.useRef(null);
    const inFlight = React.useRef(false);
    const stockDialog = React.useRef(null);
    const stockEditorOpen = !employee && Boolean(editing);
    const employeeId = employee?.id;

    async function load() {
      const [access, types, stock, events, variants] = await Promise.all([
        RH.result(client.rpc('rh_asset_access')),
        RH.fetchAll(client, 'rh_asset_types', '*', 'id'),
        RH.fetchAll(client, 'rh_asset_stock', '*', 'id'),
        readEvents(client, employeeId),
        employeeId ? [] : RH.fetchAll(client, 'rh_asset_variants')
      ]);
      setData({access, types: types.sort((a, b) => a.nome.localeCompare(b.nome, 'pt-BR')), stock, events, variants});
    }

    React.useEffect(() => { load().catch(err => setError(err.message)); }, [client, employeeId]);

    React.useLayoutEffect(() => {
      const dialog = stockDialog.current;
      if (!dialog) return;
      if (stockEditorOpen) {
        if (!dialog.open) dialog.showModal();
        dialog.querySelector('input, select')?.focus();
      } else if (dialog.open) {
        dialog.close();
      }
    }, [editing, stockEditorOpen]);

    async function run(task, reload = false) {
      if (inFlight.current) return;
      inFlight.current = true;
      setBusy(true);
      setError('');
      setNotice('');
      try {
        await task();
        if (reload) {
          setNotice(editing === 'tipo' ? 'Tipo de equipamento cadastrado.' : 'Registro salvo.');
          try {
            await load();
          } catch (err) {
            setError('Registro salvo. Falha ao atualizar a tela: ' + err.message);
          }
        }
      } catch (err) {
        setError(err.message);
      } finally {
        inFlight.current = false;
        setBusy(false);
      }
    }

    function start(action, previous = {}) {
      request.current = null;
      setError('');
      setNotice('');
      setEditing(action);
      setDraft({data: RH.today(), quantidade: 1, ...previous});
    }

    function resetEditor() {
      request.current = null;
      setEditing(defaultEditor);
      setDraft({data: RH.today(), quantidade: 1});
    }

    function change(values) {
      request.current = null;
      if (editing === 'tipo') setError('');
      setDraft(old => ({...old, ...values}));
    }

    function cancelStockEditor() {
      setError('');
      resetEditor();
    }

    function manageType(type, remove) {
      if (remove && !window.confirm('Excluir o tipo “' + type.nome + '” e seus modelos sem estoque associado?')) return;
      run(async () => {
        await RH.result(client.rpc('rh_asset_manage_type', {
          p_id: type.id, p_name: draft.nome?.trim() || type.nome,
          p_detail: draft.detalhe || type.detalhe, p_delete: remove
        }));
        resetEditor();
      }, true);
    }

    function submit(event) {
      event.preventDefault();
      if (typeEditor && (existingType || !draft.nome?.trim())) return;
      if (editing === 'editar-tipo') {
        manageType(selectedType, false);
        return;
      }
      run(async () => {
        if (editing === 'tipo') {
          try {
            await RH.result(client.from('rh_asset_types').insert({nome: draft.nome.trim(), detalhe: draft.detalhe}));
          } catch (err) {
            if (err.code !== '23505') throw err;
            setError('Já existe um tipo com esse nome. Use o cadastro existente para registrar uma entrada.');
            try { await load(); } catch { /* A mensagem de duplicidade continua disponível. */ }
            return;
          }
        } else if (editing === 'editar-variante') {
          await RH.result(client.rpc('rh_asset_rename_variant', {
            p_id: draft.variante_id, p_previous: draft.variante_anterior, p_name: draft.variante
          }), true);
        } else {
          request.current ||= crypto.randomUUID();
          await RH.result(client.rpc(editing === 'variante' ? 'rh_asset_register_variant' : 'rh_asset_event', {
            p_id: request.current,
            p: {...draft, acao: editing, quantidade: Number(draft.quantidade), funcionario_id: employeeId}
          }));
        }
        if (editing === 'entrega' && onSaved) onSaved();
        resetEditor();
      }, true);
    }

    function saveProof(event, delivery) {
      event.preventDefault();
      run(async () => {
        await RH.result(client.rpc('rh_asset_proof', {
          p_event: delivery.id, p_previous: delivery.comprovante || '', p_link: proofEdit.link.trim()
        }));
        setProofEdit(null);
      }, true);
    }

    const heading = h('div', {className: 'rh-asset-actions'},
      h('h2', null, 'Estoque de equipamentos'),
      button('Atualizar equipamentos', {disabled: busy, onClick: () => run(load)}));
    if (!data) {
      if (employee) return h('div', {className: 'rh-equip-empty', role: error ? 'alert' : 'status'},
        error || 'Carregando equipamentos…',
        error && button('Tentar novamente', {className: 'rh-equip-action', disabled: busy, onClick: () => run(load)}));
      return h('section', {className: 'rh-asset-panel'}, heading,
        h('p', {role: error ? 'alert' : 'status'}, error || 'Carregando equipamentos…'));
    }

    const {access, types, stock, events, variants} = data;
    const typeEditor = editing === 'tipo' || editing === 'editar-tipo';
    const existingType = typeEditor && types.find(type =>
      type.id !== draft.tipo_id && normalizeTypeName(type.nome) === normalizeTypeName(draft.nome));
    const linkedTypes = new Set(stock.map(item => item.tipo_id));
    const variantsByType = new Map();
    for (const item of variants) {
      if (!variantsByType.has(item.tipo_id)) variantsByType.set(item.tipo_id, []);
      variantsByType.get(item.tipo_id).push(item);
    }
    const typeById = new Map(types.map(type => [type.id, type]));
    const stockById = new Map(stock.map(item => [item.id, item]));
    const describeStock = item => item ? describe(typeById.get(item.tipo_id)?.nome, item.variante) : 'Equipamento';
    const available = stock.filter(item => item.filial === employee?.unidade && item.quantidade > 0)
      .sort((a, b) => describeStock(a).localeCompare(describeStock(b), 'pt-BR'));
    const deliveries = deliveryBalances(events);
    const selectedType = typeById.get(draft.tipo_id);
    const selectedStock = stockById.get(draft.estoque_id);
    const selectedDelivery = deliveries.find(item => item.id === draft.entrega_id);
    const canEdit = employee ? access.entrega : access.estoque;
    const isStockEdit = editing === 'entrada' || editing === 'ajuste';
    const registeringVariant = editing === 'variante';
    const renamingVariant = editing === 'editar-variante';
    const hasInitialStock = registeringVariant && Number(draft.quantidade) > 0;
    const detailLocked = editing === 'editar-tipo' && (linkedTypes.has(draft.tipo_id) || variantsByType.has(draft.tipo_id));
    const isReturning = editing === 'devolucao' || editing === 'baixa';
    const max = editing === 'entrega' ? selectedStock?.quantidade : isReturning ? selectedDelivery?.restante : 10000;
    const input = (key, options) => h('input', {
      value: draft[key] ?? '',
      onChange: event => change({[key]: event.target.value}),
      ...options
    });
    const select = (key, options, onChange = value => change({[key]: value}), disabled = false) => h('select', {
      required: true, disabled, value: draft[key] || '', onChange: event => onChange(event.target.value)
    }, option('', 'Selecione'), options);

    const variantInput = field(detailLabels[selectedType?.detalhe] || 'Modelo ou versão', input('variante', {
      required: true, maxLength: selectedType?.detalhe === 'ano' ? 4 : 120,
      list: renamingVariant ? undefined : 'rh-asset-variant-options',
      pattern: selectedType?.detalhe === 'ano' ? '[1-9][0-9]{3}' : undefined,
      inputMode: selectedType?.detalhe === 'ano' ? 'numeric' : undefined
    }));
    const editorFields = (renamingVariant ? [variantInput] : typeEditor ? [
          field('Nome do tipo', input('nome', {required: true, maxLength: 80, placeholder: 'Ex.: Notebook'})),
          field('Informação exigida na entrada', select('detalhe', [
            option('nenhum', 'Nenhuma'), option('ano', 'Ano'), option('modelo', 'Modelo'), option('descricao', 'Descrição')
          ], undefined, detailLocked)),
          detailLocked && h('p', null, 'A informação exigida é usada pelos modelos ou saldos já cadastrados.')
        ] : [
          (isStockEdit || registeringVariant) && field('Tipo', select('tipo_id',
            types.filter(type => !registeringVariant || type.detalhe !== 'nenhum').map(type => option(type.id, type.nome)),
            tipo_id => change({tipo_id, variante: ''}))),
          (isStockEdit || registeringVariant) && selectedType && selectedType.detalhe !== 'nenhum' && variantInput,
          (isStockEdit || hasInitialStock) && field('Filial', select('filial', branchOptions.map(branch => option(branch, branch)))),
          editing === 'entrega' && field('Equipamento', select('estoque_id',
            available.map(item => option(item.id, describeStock(item))))),
          (!registeringVariant || hasInitialStock) && field('Data', input('data', {type: 'date', required: true, max: RH.today(), min: selectedDelivery?.data})),
          field(registeringVariant ? 'Quantidade inicial (0 para somente cadastrar)' : 'Quantidade',
            input('quantidade', {type: 'number', required: true, min: registeringVariant ? 0 : 1, max: Math.min(max ?? 10000, 10000)})),
          editing === 'devolucao' && field('Destino', select('destino', Object.entries(destinations).map(([id, name]) => option(id, name)))),
          (!registeringVariant || hasInitialStock) && field(isReturning || editing === 'ajuste' ? 'Motivo / condição' : 'Observação', input('observacao', {
            maxLength: 1000, required: isReturning || editing === 'ajuste'
          })),
          editing === 'entrega' && field('Link do comprovante (opcional)', input('comprovante', {
            type: 'url', maxLength: 2000, placeholder: 'https://…'
          }))
        ]).map((element, index) => element && React.cloneElement(element, {key: index}));
    const editor = canEdit && h('dialog', {
      ref: stockDialog, className: 'rh-asset-dialog', 'aria-labelledby': 'rh-asset-dialog-title',
      onCancel: event => {
        event.preventDefault();
        if (!inFlight.current) cancelStockEditor();
      }
    }, stockEditorOpen && h('form', {onSubmit: submit, key: editing},
      h('h2', {id: 'rh-asset-dialog-title'},
        ({tipo: 'Cadastrar tipo de equipamento', 'editar-tipo': 'Editar tipo de equipamento', variante: 'Cadastrar modelo ou versão', 'editar-variante': 'Editar modelo ou versão'})[editing]
          || 'Registrar ' + actionLabels[editing].toLowerCase()),
      editing === 'tipo' && h('p', {className: 'muted'}, 'Cadastre o tipo uma vez. Use Cadastrar modelo ou versão para adicionar um modelo ou ano.'),
      h('fieldset', {disabled: busy, className: 'rh-asset-editor-fields'}, editorFields),
      h('datalist', {id: 'rh-asset-variant-options'}, (variantsByType.get(draft.tipo_id) || [])
        .map(({variante}) => option(variante, variante))),
      existingType && h('p', {role: 'status', className: 'rh-asset-existing'},
        'O tipo ', h('strong', null, existingType.nome), ' já está cadastrado.'),
      error && !existingType && h('p', {role: 'alert', className: 'error'}, error),
      h('div', {className: 'rh-asset-actions rh-asset-dialog-actions'},
        button('Cancelar', {className: 'secondary', disabled: busy, onClick: cancelStockEditor}),
        existingType && editing === 'tipo'
          ? button('Registrar entrada', {disabled: busy, onClick: () => start('entrada', {tipo_id: existingType.id})})
          : button(renamingVariant ? 'Salvar nome' : typeEditor || registeringVariant ? 'Salvar cadastro' : 'Salvar movimentação', {
            type: 'submit', disabled: busy || (typeEditor && (!draft.nome?.trim() || !!existingType))
          }))));

    if (employee) {
      const returns = new Map();
      for (const event of events) {
        if (!event.entrega_id) continue;
        if (!returns.has(event.entrega_id)) returns.set(event.entrega_id, []);
        returns.get(event.entrega_id).push(event);
      }
      const stockCaption = selectedStock?.variante
        ? detailLabels[typeById.get(selectedStock.tipo_id)?.detalhe] + ' ' + selectedStock.variante
        : '';
      const stockLink = h('a', {href: 'estoque.html#asset-stock', target: '_blank', rel: 'noopener'}, 'Ver estoque ↗');
      return h(React.Fragment, null,
        error && h('p', {role: 'alert', className: 'rh-equip-error'}, error),
        notice && h('p', {role: 'status', className: 'rh-equip-notice'}, notice),
        canEdit && h('section', {className: 'rh-equip-card ' + (isReturning ? '' : 'rh-equip-add')},
          h('h3', null, isReturning ? actionLabels[editing] + ' — ' + describe(selectedDelivery?.ficha.item, selectedDelivery?.ficha.variante) : 'Adicionar equipamento'),
          h('form', {key: editing, onSubmit: submit}, h('fieldset', {disabled: busy, className: isReturning ? undefined : 'rh-equip-add-fields'},
            h('div', {className: 'rh-equip-fields'}, editorFields),
            !isReturning && h('div', {className: 'rh-equip-stock', 'aria-live': 'polite'},
              h('div', {className: 'rh-equip-stock-info'},
                h('span', {className: 'rh-equip-stock-count'},
                  selectedStock ? h(React.Fragment, null, h('strong', null, selectedStock.quantidade),
                    selectedStock.quantidade === 1 ? 'un. disponível' : 'un. disponíveis') :
                    available.length ? 'Selecione um equipamento' : 'Sem equipamentos disponíveis'),
                h('span', {className: 'rh-equip-stock-location'},
                  [employee.unidade || 'Filial não cadastrada', stockCaption].filter(Boolean).join(' · '))),
              h('div', {className: 'rh-equip-stock-details'}, stockLink)),
            isReturning ? h('div', {className: 'rh-equip-actions'},
              button('Salvar movimentação', {type: 'submit', className: 'rh-equip-primary'}),
              button('Cancelar', {className: 'rh-equip-action', onClick: resetEditor})) :
              button('Salvar entrega', {type: 'submit', disabled: !selectedStock?.quantidade})))),
        h('section', {className: 'rh-equip-history'},
          h('div', {className: 'rh-equip-actions'}, h('h3', null, 'Histórico Salvo'),
            button('Atualizar', {className: 'rh-equip-action', disabled: busy, onClick: () => run(load)})),
          !deliveries.length && h('div', {className: 'rh-equip-empty'}, 'Nenhum registro encontrado.'),
          h('div', {className: 'rh-equip-history-grid'}, deliveries.map((item, index) =>
            h('section', {className: 'rh-equip-card rh-equip-history-group', key: item.id},
              h('div', {className: 'rh-equip-history-heading'},
                h(global.RHEquipment.HistoryStatus),
                h('div', null, h('h4', null, index === 0 ? 'Última Entrega' : 'Entrega Anterior'),
                  h('p', null, formatDate(item.data)))),
              h('strong', {className: 'rh-equip-items-label'}, 'Item:'),
              h('ul', null, h('li', null,
                h('span', null, describe(item.ficha.item, item.ficha.variante) + ' — Qtd: ' + item.quantidade + ' · Em posse: ' + item.restante),
                item.observacao && h('small', null, 'Observação: ' + item.observacao),
                (returns.get(item.id) || []).map(event => h('small', {key: event.id},
                  [actionLabels[event.acao], formatDate(event.data), 'Qtd. ' + event.quantidade, destinations[event.destino], event.observacao].filter(Boolean).join(' · '))))),
              h('div', {className: 'rh-equip-actions'},
                button('Gerar Ficha (PDF)', {className: 'rh-equip-action rh-equip-document', disabled: busy, onClick: () => run(() => download(item))}),
                /^https?:\/\//i.test(item.comprovante || '') &&
                  h('a', {href: item.comprovante, target: '_blank', rel: 'noopener noreferrer'}, 'Ver comprovante'),
                canEdit && button(item.comprovante ? 'Editar link' : 'Adicionar comprovante', {
                  className: 'rh-equip-action', disabled: busy,
                  onClick: () => setProofEdit({id: item.id, link: item.comprovante || ''})
                }),
                canEdit && item.restante > 0 && [
                  button('Devolver', {key: 'return', className: 'rh-equip-action rh-equip-return', disabled: busy || isReturning, onClick: () => start('devolucao', {entrega_id: item.id})}),
                  button('Registrar baixa', {key: 'loss', className: 'rh-equip-action', disabled: busy || isReturning, onClick: () => start('baixa', {entrega_id: item.id})})
                ]),
              proofEdit?.id === item.id && h('form', {onSubmit: event => saveProof(event, item)},
                h('fieldset', {disabled: busy},
                  field('Link do comprovante', h('input', {
                    type: 'url', maxLength: 2000, placeholder: 'https://…', value: proofEdit.link,
                    onChange: event => setProofEdit({...proofEdit, link: event.target.value})
                  })),
                  h('div', {className: 'rh-equip-actions'},
                    button('Salvar link', {type: 'submit', className: 'rh-equip-action'}),
                    button('Cancelar link', {className: 'rh-equip-action', onClick: () => setProofEdit(null)})))))))));
    }

    return h('section', {className: 'rh-asset-panel'}, heading,
      canEdit && registrationTarget && ReactDOM.createPortal(button('Cadastrar equipamento', {
        disabled: busy, onClick: () => start('tipo', {detalhe: 'nenhum'})
      }), registrationTarget),
      canEdit && h('div', {className: 'rh-asset-actions'},
        !registrationTarget && button('Cadastrar equipamento', {disabled: busy, onClick: () => start('tipo', {detalhe: 'nenhum'})}),
        button('Cadastrar modelo ou versão', {disabled: busy, onClick: () => start('variante', {quantidade: 0})}),
        button('Registrar entrada', {disabled: busy, onClick: () => start('entrada')}),
        button('Registrar saída', {disabled: busy, onClick: () => start('ajuste')})),
      editor,
      error && !stockEditorOpen && h('p', {role: 'alert', className: 'rh-asset-error'}, error),
      notice && h('p', {role: 'status'}, notice),
      h('h3', null, 'Tipos cadastrados'),
      table(['Tipo', 'Informação exigida', 'Modelos ou versões', ...(canEdit ? ['Ações'] : [])],
        types.map(type => cells(type.id, [
          type.nome, detailLabels[type.detalhe], variantsByType.has(type.id) ?
            h('div', {className: 'rh-asset-actions'}, [...variantsByType.get(type.id)]
              .sort((a, b) => a.variante.localeCompare(b.variante, 'pt-BR')).map(item =>
                canEdit ? button(item.variante + ' · Editar', {
                  key: item.id, className: 'secondary', disabled: busy,
                  onClick: () => start('editar-variante', {
                    tipo_id: type.id, variante_id: item.id, variante_anterior: item.variante, variante: item.variante
                  })
                }) : h('span', {key: item.id}, item.variante))) : '—',
          ...(canEdit ? [h('div', {className: 'rh-asset-actions'},
            button('Editar', {disabled: busy, onClick: () => start('editar-tipo', {tipo_id: type.id, nome: type.nome, detalhe: type.detalhe})}),
            type.detalhe !== 'nenhum' && button('Cadastrar modelo ou versão', {className: 'secondary', disabled: busy,
              onClick: () => start('variante', {tipo_id: type.id, quantidade: 0})}),
            linkedTypes.has(type.id) ? h('small', null, 'Vinculado ao estoque') :
              button('Excluir', {className: 'secondary', disabled: busy, onClick: () => manageType(type, true)}))] : [])
        ])), 'Nenhum tipo cadastrado.'),
      h('h3', null, 'Saldo por filial'),
      table(['Item', 'Filial', 'Disponível'], [...stock].sort((a, b) => describeStock(a).localeCompare(describeStock(b), 'pt-BR') || a.filial.localeCompare(b.filial))
        .map(item => cells(item.id, [describeStock(item), item.filial, item.quantidade])), 'Registre uma entrada para informar o estoque físico.'),
      access.estoque && h(React.Fragment, null,
        h('h3', null, 'Últimas movimentações de equipamentos'),
        table(['Data', 'Item', 'Movimento', 'Quantidade', 'Saldo após', 'Filial'],
          events.map(event => {
            const item = stockById.get(event.estoque_id);
            return cells(event.id, [formatDate(event.data), describeStock(item),
              [actionLabels[event.acao], destinations[event.destino]].filter(Boolean).join(' · '), event.quantidade,
              event.saldo_estoque, item?.filial]);
          }), 'Nenhuma movimentação registrada.')));
  }

  global.RHAssets = {Module, deliveryBalances, documentHtml};
})(window);
