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
    const detail = escape(doc.variante ? detailLabels[doc.detalhe] + ' — ' + doc.variante : '—');
    return `
      <div class="rh-asset-document" style="width:1080px;background:white;color:#111;font:14px/1.45 Arial,sans-serif;padding:24px;box-sizing:border-box">
        <div data-ficha-pagina>
          <header style="display:flex;align-items:center;justify-content:space-between;gap:24px;border:1px solid #111;padding:14px">
            <div><strong>${company.nome}</strong><br>CNPJ ${company.cnpj}<br>${company.endereco}</div>
            <strong style="font-size:18px">FICHA INDIVIDUAL DE ENTREGA DE EQUIPAMENTOS</strong>
          </header>
          <div style="border:1px solid #111;margin:12px 0;padding:12px">
            <strong>Colaborador</strong> ${employee.nome} · <strong>CPF</strong> ${employee.cpf}<br>
            <strong>Função</strong> ${employee.cargo} · <strong>Setor</strong> ${employee.setor} · <strong>Unidade</strong> ${employee.unidade}
          </div>
          <table style="width:100%;border-collapse:collapse">
            <thead><tr style="background:#003399;color:white;text-align:left">
              <th style="padding:8px">Data da entrega</th><th>Equipamento</th><th>Ano / modelo / descrição</th><th>Qtd.</th>
            </tr></thead>
            <tbody><tr style="border:1px solid #111">
              <td style="padding:8px">${formatDate(event.data)}</td><td>${escape(doc.item)}</td><td>${detail}</td><td>${event.quantidade}</td>
            </tr></tbody>
          </table>
          ${event.observacao ? '<p style="overflow-wrap:anywhere"><strong>Observação</strong> ' + escape(event.observacao) + '</p>' : ''}
          <div style="border:1px solid #111;margin-top:16px;padding:14px">
            <strong style="color:#002060">TERMO DE RECEBIMENTO E RESPONSABILIDADE</strong>
            <p>Declaro que recebi e conferi o equipamento acima. Comprometo-me a utilizá-lo para o trabalho, zelar por sua guarda e conservação, comunicar prontamente perda, extravio ou dano e devolvê-lo quando solicitado ou ao término do vínculo. O desgaste normal decorrente do uso regular fica excluído.</p>
            <p>Em caso de perda ou dano, eventual ressarcimento será limitado ao prejuízo efetivamente comprovado, após apuração da responsabilidade. O custo atualizado de reparo ou reposição por item equivalente poderá servir de referência documentada, consideradas as condições e a vida útil do bem entregue. Eventual desconto salarial observará o art. 462, § 1º, da CLT e as normas coletivas aplicáveis, mediante ajuste prévio e culpa comprovada ou dolo comprovado.</p>
            <div style="display:flex;align-items:flex-start;justify-content:space-between;margin-top:44px">
              <span>Data ____/____/________</span>
              <span style="width:50%;border-top:1px solid #111;text-align:center">Assinatura do colaborador</span>
            </div>
          </div>
          <p style="font-size:10px;color:#333">Registro ${escape(event.id)}</p>
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

  function Module({client, employee}) {
    const [data, setData] = React.useState(null);
    const [busy, setBusy] = React.useState(false);
    const [error, setError] = React.useState('');
    const [notice, setNotice] = React.useState('');
    const [editing, setEditing] = React.useState(null);
    const [draft, setDraft] = React.useState({});
    const request = React.useRef(null);
    const inFlight = React.useRef(false);
    const employeeId = employee?.id;

    async function load() {
      const [access, types, stock, events] = await Promise.all([
        RH.result(client.rpc('rh_asset_access')),
        RH.fetchAll(client, 'rh_asset_types', '*', 'id'),
        RH.fetchAll(client, 'rh_asset_stock', '*', 'id'),
        readEvents(client, employeeId)
      ]);
      setData({access, types: types.sort((a, b) => a.nome.localeCompare(b.nome, 'pt-BR')), stock, events});
    }

    React.useEffect(() => { load().catch(err => setError(err.message)); }, [client, employeeId]);

    async function run(task, reload = false) {
      if (inFlight.current) return;
      inFlight.current = true;
      setBusy(true);
      setError('');
      setNotice('');
      try {
        await task();
        if (reload) {
          setNotice('Registro salvo.');
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

    function change(values) {
      request.current = null;
      setDraft(old => ({...old, ...values}));
    }

    function submit(event) {
      event.preventDefault();
      run(async () => {
        if (editing === 'tipo') {
          await RH.result(client.from('rh_asset_types').insert({nome: draft.nome.trim(), detalhe: draft.detalhe}));
        } else {
          request.current ||= crypto.randomUUID();
          await RH.result(client.rpc('rh_asset_event', {
            p_id: request.current,
            p: {...draft, acao: editing, quantidade: Number(draft.quantidade), funcionario_id: employeeId}
          }));
        }
        setEditing(null);
        request.current = null;
      }, true);
    }

    const heading = h('div', {className: 'rh-asset-actions'},
      h('h2', null, employee ? 'Entrega de equipamentos' : 'Estoque de equipamentos'),
      button('Atualizar equipamentos', {disabled: busy, onClick: () => run(load)}));
    if (!data) {
      return h('section', {className: 'rh-asset-panel'}, heading,
        h('p', {role: error ? 'alert' : 'status'}, error || 'Carregando equipamentos…'));
    }

    const {access, types, stock, events} = data;
    const typeById = new Map(types.map(type => [type.id, type]));
    const stockById = new Map(stock.map(item => [item.id, item]));
    const describeStock = item => item ? describe(typeById.get(item.tipo_id)?.nome, item.variante) : 'Equipamento';
    const available = stock.filter(item => item.filial === employee?.unidade && item.quantidade > 0)
      .sort((a, b) => describeStock(a).localeCompare(describeStock(b), 'pt-BR'));
    const deliveries = deliveryBalances(events);
    const deliveryById = new Map(deliveries.map(item => [item.id, item]));
    const selectedType = typeById.get(draft.tipo_id);
    const selectedStock = stockById.get(draft.estoque_id);
    const selectedDelivery = deliveryById.get(draft.entrega_id);
    const canEdit = employee ? access.entrega : access.estoque;
    const isStockEdit = editing === 'entrada' || editing === 'ajuste';
    const isReturning = editing === 'devolucao' || editing === 'baixa';
    const max = editing === 'entrega' ? selectedStock?.quantidade : isReturning ? selectedDelivery?.restante : 10000;
    const input = (key, options) => h('input', {
      value: draft[key] ?? '',
      onChange: event => change({[key]: event.target.value}),
      ...options
    });
    const select = (key, options, onChange = value => change({[key]: value})) => h('select', {
      required: true, value: draft[key] || '', onChange: event => onChange(event.target.value)
    }, option('', 'Selecione'), options);

    const editor = editing && h('form', {onSubmit: submit, key: editing},
      h('fieldset', {disabled: busy, className: 'rh-asset-fields'},
        h('legend', null, editing === 'tipo' ? 'Cadastrar tipo de equipamento' : actionLabels[editing]),
        editing === 'tipo' ? [
          field('Nome do tipo', input('nome', {required: true, maxLength: 80})),
          field('Informação obrigatória', select('detalhe', [
            option('nenhum', 'Nenhuma'), option('ano', 'Ano'), option('modelo', 'Modelo'), option('descricao', 'Descrição')
          ]))
        ] : [
          isStockEdit && field('Tipo', select('tipo_id', types.map(type => option(type.id, type.nome)),
            tipo_id => change({tipo_id, variante: ''}))),
          isStockEdit && selectedType && selectedType.detalhe !== 'nenhum' &&
            field(detailLabels[selectedType.detalhe], input('variante', {
              required: true, maxLength: selectedType.detalhe === 'ano' ? 4 : 120,
              pattern: selectedType.detalhe === 'ano' ? '[1-9][0-9]{3}' : undefined,
              inputMode: selectedType.detalhe === 'ano' ? 'numeric' : undefined
            })),
          isStockEdit && field('Filial', select('filial', branchOptions.map(branch => option(branch, branch)))),
          editing === 'entrega' && field('Item em estoque', select('estoque_id',
            available.map(item => option(item.id, describeStock(item) + ' · ' + item.quantidade + ' disponível(is)')))),
          editing === 'entrega' && selectedStock?.variante &&
            h('p', null, detailLabels[typeById.get(selectedStock.tipo_id)?.detalhe] + ' · ' + selectedStock.variante),
          isReturning && h('p', null, describe(selectedDelivery?.ficha.item, selectedDelivery?.ficha.variante)),
          field('Data', input('data', {type: 'date', required: true, max: RH.today(), min: selectedDelivery?.data})),
          field('Quantidade', input('quantidade', {type: 'number', required: true, min: 1, max: Math.min(max ?? 10000, 10000)})),
          editing === 'devolucao' && field('Destino', select('destino', Object.entries(destinations).map(([id, name]) => option(id, name)))),
          field(isReturning || editing === 'ajuste' ? 'Motivo / condição' : 'Observação', input('observacao', {
            maxLength: 1000, required: isReturning || editing === 'ajuste'
          }))
        ].filter(Boolean).map((element, index) => React.cloneElement(element, {key: index})),
        h('div', {className: 'rh-asset-actions'},
          button('Salvar', {type: 'submit'}),
          button('Cancelar', {onClick: () => setEditing(null)}))));

    return h('section', {className: 'rh-asset-panel'}, heading,
      employee && h('p', null, 'Filial de entrega · ' + (employee.unidade || 'Não cadastrada')),
      canEdit && h('div', {className: 'rh-asset-actions'},
        employee ? button('Registrar entrega', {disabled: busy || !available.length, onClick: () => start('entrega')}) : [
          button('Cadastrar tipo', {key: 'type', disabled: busy, onClick: () => start('tipo', {detalhe: 'nenhum'})}),
          button('Registrar entrada', {key: 'in', disabled: busy, onClick: () => start('entrada')}),
          button('Registrar saída', {key: 'out', disabled: busy, onClick: () => start('ajuste')})
        ]),
      employee && canEdit && !available.length && h('p', null, 'Sem equipamentos disponíveis na filial. ',
        h('a', {href: 'estoque.html#asset-stock'}, 'Consultar estoque de equipamentos')),
      editor,
      error && h('p', {role: 'alert', className: 'rh-asset-error'}, error),
      notice && h('p', {role: 'status'}, notice),
      employee ? h(React.Fragment, null,
        h('h3', null, 'Equipamentos em posse'),
        table(['Item', 'Data da entrega', 'Em posse', 'Ações'], deliveries.filter(item => item.restante > 0).map(item =>
          cells(item.id, [describe(item.ficha.item, item.ficha.variante), formatDate(item.data), item.restante,
            canEdit && h('div', {className: 'rh-asset-actions'},
              button('Devolver', {disabled: busy, onClick: () => start('devolucao', {entrega_id: item.id})}),
              button('Registrar baixa', {disabled: busy, onClick: () => start('baixa', {entrega_id: item.id})}))])
        ), 'Nenhum equipamento em posse.')) : h(React.Fragment, null,
        h('h3', null, 'Tipos cadastrados'),
        h('p', null, types.map(type => type.nome).join(' · ') || 'Nenhum tipo cadastrado.'),
        h('h3', null, 'Saldo por filial'),
        table(['Item', 'Filial', 'Disponível'], [...stock].sort((a, b) => describeStock(a).localeCompare(describeStock(b), 'pt-BR') || a.filial.localeCompare(b.filial))
          .map(item => cells(item.id, [describeStock(item), item.filial, item.quantidade])), 'Registre uma entrada para informar o estoque físico.')),
      (employee || access.estoque) && h(React.Fragment, null,
        h('h3', null, employee ? 'Histórico de entregas e devoluções' : 'Últimas movimentações de equipamentos'),
        table(['Data', 'Item', 'Movimento', 'Quantidade', employee ? 'Observação' : 'Saldo após', employee ? 'Ficha' : 'Filial'],
          events.map(event => {
            const original = event.ficha || deliveryById.get(event.entrega_id)?.ficha;
            const item = stockById.get(event.estoque_id);
            return cells(event.id, [formatDate(event.data), original ? describe(original.item, original.variante) : describeStock(item),
              [actionLabels[event.acao], destinations[event.destino]].filter(Boolean).join(' · '), event.quantidade,
              employee ? event.observacao || '—' : event.saldo_estoque,
              employee ? (event.ficha && button('Baixar ficha (PDF)', {disabled: busy, onClick: () => run(() => download(event))})) : item?.filial]);
          }), 'Nenhuma movimentação registrada.')));
  }

  global.RHAssets = {Module, deliveryBalances, documentHtml};
})(window);
