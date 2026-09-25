with open("admin.html", "r", encoding="utf-8") as f:
    content = f.read()

# 1. State variables in AdminApp
old_states = """        // Table Viewer State
        const [availableTables] = useState(["""

new_states = """        // Empresas Management State
        const [empresas, setEmpresas] = useState([]);
        const [empresasLoading, setEmpresasLoading] = useState(false);
        const [isEmpresaModalOpen, setIsEmpresaModalOpen] = useState(false);
        const [editingEmpresa, setEditingEmpresa] = useState(null);
        const [empresaFormData, setEmpresaFormData] = useState({ nome: "", cnpj: "", endereco: "" });
        const [empresaSearch, setEmpresaSearch] = useState("");

        // Carga em Massa State
        const [importFile, setImportFile] = useState(null);
        const [importType, setImportType] = useState("colaboradores"); // "colaboradores" ou "empresas"
        const [importPreview, setImportPreview] = useState([]);
        const [importErrors, setImportErrors] = useState([]);
        const [isImporting, setIsImporting] = useState(false);
        const [importSuccessMsg, setImportSuccessMsg] = useState("");
        const fileInputRef = useRef(null);

        // Table Viewer State
        const [availableTables] = useState(["""

content = content.replace(old_states, new_states)

# 2. Effects & Handlers for Empresas and Carga em Massa
old_effect = """        useEffect(() => {
          if (activeSection === "tables") {
            fetchTableData(selectedTableName);
          }
        }, [activeSection, selectedTableName]);"""

new_effect_and_handlers = """        useEffect(() => {
          if (activeSection === "tables") {
            fetchTableData(selectedTableName);
          } else if (activeSection === "empresas") {
            fetchEmpresas();
          }
        }, [activeSection, selectedTableName]);

        async function fetchEmpresas() {
          setEmpresasLoading(true);
          try {
            const { data, error } = await supabase
              .from("empresas")
              .select("*")
              .order("id", { ascending: true });
            if (error) throw error;
            setEmpresas(data || []);
          } catch (e) {
            console.error("Erro ao carregar empresas:", e);
          } finally {
            setEmpresasLoading(false);
          }
        }

        const handleOpenEmpresaModal = (emp = null) => {
          if (emp) {
            setEditingEmpresa(emp);
            setEmpresaFormData({ nome: emp.nome || "", cnpj: emp.cnpj || "", endereco: emp.endereco || "" });
          } else {
            setEditingEmpresa(null);
            setEmpresaFormData({ nome: "", cnpj: "", endereco: "" });
          }
          setIsEmpresaModalOpen(true);
        };

        const handleSaveEmpresa = async (e) => {
          e.preventDefault();
          if (!empresaFormData.nome.trim()) {
            alert("O nome da empresa é obrigatório.");
            return;
          }

          try {
            if (editingEmpresa) {
              const { error } = await supabase
                .from("empresas")
                .update({
                  nome: empresaFormData.nome.trim().toUpperCase(),
                  cnpj: empresaFormData.cnpj.trim(),
                  endereco: empresaFormData.endereco.trim(),
                })
                .eq("id", editingEmpresa.id);
              if (error) throw error;

              await supabase.from("sistema_logs").insert([
                {
                  tabela_afetada: "empresas",
                  tipo_operacao: "UPDATE",
                  descricao: `Empresa atualizada: ${empresaFormData.nome.trim().toUpperCase()}`,
                  dados_anteriores: editingEmpresa,
                  dados_novos: empresaFormData,
                },
              ]);
            } else {
              const payload = {
                nome: empresaFormData.nome.trim().toUpperCase(),
                cnpj: empresaFormData.cnpj.trim(),
                endereco: empresaFormData.endereco.trim(),
              };
              const { error } = await supabase.from("empresas").insert([payload]);
              if (error) throw error;

              await supabase.from("sistema_logs").insert([
                {
                  tabela_afetada: "empresas",
                  tipo_operacao: "INSERT",
                  descricao: `Nova empresa cadastrada: ${empresaFormData.nome.trim().toUpperCase()}`,
                  dados_novos: payload,
                },
              ]);
            }

            alert("Empresa salva com sucesso!");
            setIsEmpresaModalOpen(false);
            fetchEmpresas();
          } catch (err) {
            console.error("Erro ao salvar empresa:", err);
            alert("Erro ao salvar empresa no banco de dados.");
          }
        };

        const handleDeleteEmpresa = async (emp) => {
          if (!window.confirm(`Deseja realmente excluir a empresa "${emp.nome}"?`)) return;

          try {
            const { error } = await supabase.from("empresas").delete().eq("id", emp.id);
            if (error) throw error;

            await supabase.from("sistema_logs").insert([
              {
                tabela_afetada: "empresas",
                tipo_operacao: "DELETE",
                descricao: `Empresa excluída: ${emp.nome}`,
                dados_anteriores: emp,
              },
            ]);

            alert("Empresa excluída com sucesso!");
            fetchEmpresas();
          } catch (err) {
            console.error("Erro ao excluir empresa:", err);
            alert("Erro ao excluir empresa.");
          }
        };

        // EXPORT EXCEL MODEL HANDLERS WITH SHEETJS
        const handleExportModeloColaboradores = () => {
          if (typeof XLSX === "undefined") {
            alert("Biblioteca SheetJS não carregada.");
            return;
          }

          const headers = [
            "CPF (Apenas dígitos)*",
            "Nome Completo*",
            "Data Admissão (DD/MM/YYYY)*",
            "Data Nascimento (DD/MM/YYYY)",
            "Sexo (M/F)",
            "Função*",
            "Setor*",
            "Unidade (FILIAL 1 / FILIAL 5 / FILIAL 8)*",
            "Empresa / Local de Registro*",
            "Jornada Semanal (40 ou 44 horas)*",
            "Tamanho Farda (PP/P/M/G/GG/EXG)",
            "Tamanho Calça (P/M/G/40/42...)",
            "Tamanho Calçado (38/40/42...)",
            "WhatsApp (com DDD)"
          ];

          const rowExemplo = [
            "12345678901",
            "JOAO DA SILVA EXEMPLO",
            "15/01/2023",
            "10/05/1990",
            "M",
            "MOTORISTA DE CAMINHAO",
            "TRANSPORTE",
            "FILIAL 5",
            "NUNES & VIEIRA LOGISTICA LTDA",
            44,
            "G",
            "42",
            "41",
            "73999998888"
          ];

          const wsData = [headers, rowExemplo];
          const ws = XLSX.utils.aoa_to_sheet(wsData);

          // Header Comments/Guidelines
          const comments = [
            "Informe apenas os 11 dígitos numéricos do CPF, sem pontos ou traço. Ex: 12345678901.",
            "Nome completo em maiúsculas sem abreviações excessivas.",
            "Data no formato DD/MM/YYYY. Ex: 15/01/2023.",
            "Data no formato DD/MM/YYYY. Ex: 10/05/1990.",
            "Informe M para Masculino ou F para Feminino.",
            "Cargo / Função principal do colaborador.",
            "Setor de trabalho. Ex: TRANSPORTE, ARMAZEM, COMERCIAL.",
            "Unidade de lotação: FILIAL 1, FILIAL 5 ou FILIAL 8.",
            "Razão social da empresa cadastrada no sistema.",
            "Informe a carga horária semanal: 40 horas (fechará 200h/mês) ou 44 horas (fechará 220h/mês).",
            "Tamanho da blusa/farda: PP, P, M, G, GG, EXG.",
            "Tamanho da calça: P, M, G, 38, 40, 42, etc.",
            "Tamanho do calçado de segurança: 38, 39, 40, 41, 42, etc.",
            "Número com DDD apenas dígitos. Ex: 73999998888."
          ];

          comments.forEach((comment, colIdx) => {
            const cellAddress = XLSX.utils.encode_cell({ r: 0, c: colIdx });
            if (!ws[cellAddress]) return;
            ws[cellAddress].c = [{ a: "PRIME RH", t: comment }];
          });

          // Set column widths
          ws["!cols"] = headers.map(() => ({ wch: 28 }));

          const wb = XLSX.utils.book_new();
          XLSX.utils.book_append_sheet(wb, ws, "Modelo_Colaboradores");
          XLSX.writeFile(wb, "Modelo_Cadastro_Massa_Colaboradores.xlsx");
        };

        const handleExportModeloEmpresas = () => {
          if (typeof XLSX === "undefined") {
            alert("Biblioteca SheetJS não carregada.");
            return;
          }

          const headers = [
            "Nome / Razão Social*",
            "CNPJ*",
            "Endereço Completo"
          ];

          const rowExemplo = [
            "EXEMPLO LOGISTICA E DISTRIBUICAO LTDA",
            "12.345.678/0001-99",
            "Rua Principal, 100, Bairro Centro, Itabuna/BA"
          ];

          const wsData = [headers, rowExemplo];
          const ws = XLSX.utils.aoa_to_sheet(wsData);

          const comments = [
            "Razão Social ou Nome Fantasia completo da Empresa.",
            "CNPJ formatado ou apenas dígitos. Ex: 12.345.678/0001-99.",
            "Endereço completo da unidade / matriz."
          ];

          comments.forEach((comment, colIdx) => {
            const cellAddress = XLSX.utils.encode_cell({ r: 0, c: colIdx });
            if (!ws[cellAddress]) return;
            ws[cellAddress].c = [{ a: "PRIME RH", t: comment }];
          });

          ws["!cols"] = [{ wch: 40 }, { wch: 25 }, { wch: 50 }];

          const wb = XLSX.utils.book_new();
          XLSX.utils.book_append_sheet(wb, ws, "Modelo_Empresas");
          XLSX.writeFile(wb, "Modelo_Cadastro_Massa_Empresas.xlsx");
        };

        // IMPORT EXCEL FILE HANDLER
        const handleFileChange = (e) => {
          const file = e.target.files[0];
          if (!file) return;

          setImportFile(file);
          setImportPreview([]);
          setImportErrors([]);
          setImportSuccessMsg("");

          const reader = new FileReader();
          reader.onload = (evt) => {
            try {
              const bstr = evt.target.result;
              const wb = XLSX.read(bstr, { type: "binary" });
              const wsName = wb.SheetNames[0];
              const ws = wb.Sheets[wsName];
              const rawData = XLSX.utils.sheet_to_json(ws, { header: 1 });

              if (rawData.length < 2) {
                setImportErrors(["A planilha selecionada não possui linhas de dados."]);
                return;
              }

              // Filter out header line (index 0)
              const rowsData = rawData.slice(1).filter((r) => r.length > 0 && r.some((cell) => cell !== null && cell !== ""));

              if (importType === "colaboradores") {
                const parsed = [];
                const errs = [];

                rowsData.forEach((row, idx) => {
                  const lineNum = idx + 2; // account for header and 1-based indexing
                  const cpf = String(row[0] || "").replace(/\D/g, "");
                  const nome = String(row[1] || "").trim().toUpperCase();
                  const admissao = String(row[2] || "").trim();
                  const nascimento = String(row[3] || "").trim();
                  const sexo = String(row[4] || "M").trim().toUpperCase();
                  const funcao = String(row[5] || "").trim().toUpperCase();
                  const setor = String(row[6] || "").trim().toUpperCase();
                  const unidade = String(row[7] || "FILIAL 5").trim().toUpperCase();
                  const local_registro = String(row[8] || "NUNES & VIEIRA LOGISTICA LTDA").trim().toUpperCase();
                  const jornadaSemanal = Number(row[9]) || 44;
                  const tamanho_farda = String(row[10] || "M").trim().toUpperCase();
                  const calca = String(row[11] || "M").trim().toUpperCase();
                  const calcado = String(row[12] || "40").trim();
                  const whatsapp = String(row[13] || "").trim();

                  // Calculate carga_horaria
                  const carga_horaria = Number(jornadaSemanal) === 40 ? 200 : 220;

                  if (!cpf || cpf.length !== 11) {
                    errs.push(`Linha ${lineNum}: CPF inválido ou ausente ("${row[0]}"). Deve possuir exatamente 11 dígitos.`);
                  }
                  if (!nome) {
                    errs.push(`Linha ${lineNum}: Nome é obrigatório.`);
                  }
                  if (!admissao) {
                    errs.push(`Linha ${lineNum}: Data de admissão é obrigatória.`);
                  }

                  parsed.push({
                    lineNum,
                    cpf,
                    nome,
                    admissao,
                    nascimento,
                    sexo: sexo === "F" ? "F" : "M",
                    funcao,
                    setor,
                    unidade,
                    local_registro,
                    carga_horaria,
                    jornadaSemanal,
                    tamanho_farda,
                    calca,
                    calcado,
                    whatsapp,
                  });
                });

                setImportPreview(parsed);
                setImportErrors(errs);
              } else {
                // Empresas
                const parsed = [];
                const errs = [];

                rowsData.forEach((row, idx) => {
                  const lineNum = idx + 2;
                  const nome = String(row[0] || "").trim().toUpperCase();
                  const cnpj = String(row[1] || "").trim();
                  const endereco = String(row[2] || "").trim();

                  if (!nome) {
                    errs.push(`Linha ${lineNum}: Razão Social / Nome da empresa é obrigatório.`);
                  }

                  parsed.push({ lineNum, nome, cnpj, endereco });
                });

                setImportPreview(parsed);
                setImportErrors(errs);
              }
            } catch (err) {
              console.error("Erro ao ler arquivo Excel:", err);
              setImportErrors(["Erro ao ler arquivo Excel. Verifique se o formato está correto."]);
            }
          };

          reader.readAsBinaryString(file);
        };

        const handleConfirmImport = async () => {
          if (importPreview.length === 0) return;
          if (importErrors.length > 0) {
            if (!window.confirm(`Existem ${importErrors.length} alerta(s) de validação. Deseja prosseguir ignorando linhas com erros?`)) return;
          }

          setIsImporting(true);
          setImportSuccessMsg("");

          try {
            let insertedCount = 0;

            if (importType === "colaboradores") {
              const validItems = importPreview.filter((item) => item.cpf && item.cpf.length === 11 && item.nome && item.admissao);

              for (const item of validItems) {
                // 1. Upsert funcionarios_epi
                const payloadEpi = {
                  cpf: item.cpf,
                  nome: item.nome,
                  admissao: item.admissao,
                  nascimento: item.nascimento,
                  sexo: item.sexo,
                  funcao: item.funcao,
                  setor: item.setor,
                  unidade: item.unidade,
                  local_registro: item.local_registro,
                  carga_horaria: item.carga_horaria,
                  tamanho_farda: item.tamanho_farda,
                  calca: item.calca,
                  calcado: item.calcado,
                  whatsapp: item.whatsapp,
                  validacao: "☑ OK",
                };

                const { error: epiErr } = await supabase
                  .from("funcionarios_epi")
                  .upsert(payloadEpi, { onConflict: "cpf" });

                if (epiErr) {
                  console.error(`Erro ao importar ${item.nome}:`, epiErr);
                  continue;
                }

                // 2. Insert rh_movimentacoes if not exists
                let admIso = item.admissao;
                if (item.admissao.includes("/")) {
                  const p = item.admissao.split("/");
                  if (p.length === 3) admIso = `${p[2]}-${p[1]}-${p[0]}`;
                }

                await supabase.from("rh_movimentacoes").insert([
                  {
                    funcionario_nome: item.nome,
                    cpf: item.cpf,
                    data_admissao: admIso,
                  },
                ]);

                insertedCount++;
              }

              // Log bulk import
              await supabase.from("sistema_logs").insert([
                {
                  tabela_afetada: "funcionarios_epi",
                  tipo_operacao: "INSERT",
                  descricao: `Carga em massa realizada: ${insertedCount} colaboradores importados/atualizados.`,
                },
              ]);

              setImportSuccessMsg(`Carga em massa concluída com sucesso! ${insertedCount} colaboradores processados.`);
            } else {
              // Empresas Import
              const validItems = importPreview.filter((item) => item.nome);

              for (const item of validItems) {
                const payload = {
                  nome: item.nome,
                  cnpj: item.cnpj,
                  endereco: item.endereco,
                };

                const { error } = await supabase.from("empresas").insert([payload]);
                if (error) {
                  console.error(`Erro ao importar empresa ${item.nome}:`, error);
                  continue;
                }
                insertedCount++;
              }

              await supabase.from("sistema_logs").insert([
                {
                  tabela_afetada: "empresas",
                  tipo_operacao: "INSERT",
                  descricao: `Carga em massa realizada: ${insertedCount} empresas cadastradas.`,
                },
              ]);

              setImportSuccessMsg(`Carga em massa concluída! ${insertedCount} empresas cadastradas com sucesso.`);
            }

            setImportPreview([]);
            setImportFile(null);
            if (fileInputRef.current) fileInputRef.current.value = "";
          } catch (err) {
            console.error("Erro no processo de importação:", err);
            alert("Erro durante a importação em massa: " + err.message);
          } finally {
            setIsImporting(false);
          }
        };"""

content = content.replace(old_effect, new_effect_and_handlers)

# 3. Main content rendered sections for Empresas & Import/Export
old_main_end = """              {/* SECTION 2: GERENCIADOR DE TABELAS */}"""

new_sections = """              {/* SECTION: GESTÃO DE EMPRESAS */}
              {activeSection === "empresas" && (
                <div className="space-y-6 animate-fadeIn">
                  <div className="bg-slate-800/80 p-5 rounded-2xl border border-slate-700/80 shadow-sm flex flex-col sm:flex-row items-center justify-between gap-4">
                    <div>
                      <h2 className="text-lg font-bold text-white flex items-center gap-2">
                        <Building2 size={22} className="text-red-500" /> Cadastro & Gestão de Empresas / Filiais
                      </h2>
                      <p className="text-slate-400 text-xs mt-1">
                        Cadastre e edite as razões sociais, CNPJs e endereços das empresas para vincular colaboradores e emitir fichas.
                      </p>
                    </div>

                    <button
                      onClick={() => handleOpenEmpresaModal(null)}
                      className="px-4 py-2.5 rounded-xl bg-red-600 hover:bg-red-500 text-white font-bold text-xs shadow-md transition-all flex items-center gap-2 shrink-0"
                    >
                      <Plus size={16} /> Nova Empresa
                    </button>
                  </div>

                  {/* Empresas List */}
                  <div className="bg-slate-800/80 rounded-2xl border border-slate-700/80 shadow-md overflow-hidden">
                    <div className="p-4 bg-slate-900/60 border-b border-slate-700 flex items-center justify-between">
                      <div className="relative w-72">
                        <Search size={16} className="absolute left-3.5 top-1/2 -translate-y-1/2 text-slate-400" />
                        <input
                          type="text"
                          value={empresaSearch}
                          onChange={(e) => setEmpresaSearch(e.target.value)}
                          placeholder="Buscar por razão social ou CNPJ..."
                          className="w-full pl-9 pr-4 py-2 rounded-xl bg-slate-900 border border-slate-700 text-xs text-slate-200 focus:outline-none focus:ring-2 focus:ring-red-500"
                        />
                      </div>
                      <span className="text-xs text-slate-400 font-medium">{empresas.length} empresa(s) cadastrada(s)</span>
                    </div>

                    {empresasLoading ? (
                      <div className="p-12 text-center text-slate-400 text-sm">Carregando lista de empresas...</div>
                    ) : empresas.length === 0 ? (
                      <div className="p-12 text-center text-slate-400 text-sm">Nenhuma empresa cadastrada.</div>
                    ) : (
                      <div className="overflow-x-auto">
                        <table className="w-full text-left text-xs text-slate-300">
                          <thead className="bg-slate-900 text-slate-400 uppercase tracking-wider font-bold border-b border-slate-700">
                            <tr>
                              <th className="p-4">ID</th>
                              <th className="p-4">Razão Social / Nome Fantasia</th>
                              <th className="p-4">CNPJ</th>
                              <th className="p-4">Endereço Completo</th>
                              <th className="p-4 text-center w-28">Ações</th>
                            </tr>
                          </thead>
                          <tbody className="divide-y divide-slate-700/60 font-medium">
                            {empresas
                              .filter((e) => {
                                const s = empresaSearch.toLowerCase();
                                return (
                                  !s ||
                                  (e.nome && e.nome.toLowerCase().includes(s)) ||
                                  (e.cnpj && e.cnpj.includes(s)) ||
                                  (e.endereco && e.endereco.toLowerCase().includes(s))
                                );
                              })
                              .map((emp) => (
                                <tr key={emp.id} className="hover:bg-slate-700/40 transition-colors">
                                  <td className="p-4 font-mono text-slate-400">{emp.id}</td>
                                  <td className="p-4 font-bold text-white">{emp.nome}</td>
                                  <td className="p-4 font-mono text-amber-300 font-bold">{emp.cnpj || "-"}</td>
                                  <td className="p-4 text-slate-300">{emp.endereco || "-"}</td>
                                  <td className="p-4 text-center">
                                    <div className="flex items-center justify-center gap-1.5">
                                      <button
                                        onClick={() => handleOpenEmpresaModal(emp)}
                                        className="p-1.5 rounded-lg bg-blue-600/20 hover:bg-blue-600/40 text-blue-300 border border-blue-500/30 transition-all"
                                        title="Editar Empresa"
                                      >
                                        <Edit size={14} />
                                      </button>
                                      <button
                                        onClick={() => handleDeleteEmpresa(emp)}
                                        className="p-1.5 rounded-lg bg-red-600/20 hover:bg-red-600/40 text-red-300 border border-red-500/30 transition-all"
                                        title="Excluir Empresa"
                                      >
                                        <Trash2 size={14} />
                                      </button>
                                    </div>
                                  </td>
                                </tr>
                              ))}
                          </tbody>
                        </table>
                      </div>
                    )}
                  </div>
                </div>
              )}

              {/* SECTION: EXPORTAÇÃO E IMPORTAÇÃO EM MASSA */}
              {activeSection === "carga_massa" && (
                <div className="space-y-6 animate-fadeIn">
                  {/* Export Header Cards */}
                  <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
                    {/* Card Export Colaboradores */}
                    <div className="bg-slate-800/80 p-6 rounded-3xl border border-slate-700/80 shadow-md space-y-4 flex flex-col justify-between">
                      <div>
                        <div className="w-12 h-12 rounded-2xl bg-blue-600/20 border border-blue-500/30 flex items-center justify-center text-blue-400 mb-3">
                          <Users size={26} />
                        </div>
                        <h3 className="text-lg font-black text-white">1. Exportar Planilha Modelo de Colaboradores</h3>
                        <p className="text-xs text-slate-400 mt-1 leading-relaxed">
                          Baixe a planilha Excel padronizada com cabeçalhos estruturados, primeira linha com dados de exemplo e comentários em cada coluna explicando como deve ser preenchida.
                        </p>
                      </div>

                      <button
                        onClick={handleExportModeloColaboradores}
                        className="w-full py-3 rounded-xl bg-blue-600 hover:bg-blue-500 text-white font-bold text-xs shadow-md transition-all flex items-center justify-center gap-2"
                      >
                        <Download size={16} /> Download Modelo Excel (Colaboradores)
                      </button>
                    </div>

                    {/* Card Export Empresas */}
                    <div className="bg-slate-800/80 p-6 rounded-3xl border border-slate-700/80 shadow-md space-y-4 flex flex-col justify-between">
                      <div>
                        <div className="w-12 h-12 rounded-2xl bg-emerald-600/20 border border-emerald-500/30 flex items-center justify-center text-emerald-400 mb-3">
                          <Building2 size={26} />
                        </div>
                        <h3 className="text-lg font-black text-white">2. Exportar Planilha Modelo de Empresas</h3>
                        <p className="text-xs text-slate-400 mt-1 leading-relaxed">
                          Baixe a planilha Excel para preenchimento de novas empresas/filiais (Razão Social, CNPJ e Endereço) para importação em lote no sistema.
                        </p>
                      </div>

                      <button
                        onClick={handleExportModeloEmpresas}
                        className="w-full py-3 rounded-xl bg-emerald-600 hover:bg-emerald-500 text-white font-bold text-xs shadow-md transition-all flex items-center justify-center gap-2"
                      >
                        <Download size={16} /> Download Modelo Excel (Empresas)
                      </button>
                    </div>
                  </div>

                  {/* Upload and Mass Import Area */}
                  <div className="bg-slate-800/80 p-6 md:p-8 rounded-3xl border border-slate-700/80 shadow-xl space-y-6">
                    <div className="border-b border-slate-700/80 pb-4 flex flex-col sm:flex-row items-start sm:items-center justify-between gap-4">
                      <div>
                        <h3 className="text-lg font-black text-white flex items-center gap-2">
                          <Upload size={22} className="text-red-500" /> Carga em Massa (Importação de Dados)
                        </h3>
                        <p className="text-xs text-slate-400 mt-0.5">
                          Selecione o tipo de dado e envie o arquivo Excel preenchido para alimentar o banco automaticamente.
                        </p>
                      </div>

                      <div className="flex bg-slate-900 p-1 rounded-xl border border-slate-700">
                        <button
                          onClick={() => {
                            setImportType("colaboradores");
                            setImportPreview([]);
                            setImportErrors([]);
                          }}
                          className={`px-3 py-1.5 rounded-lg text-xs font-bold transition-all ${
                            importType === "colaboradores" ? "bg-red-600 text-white shadow-xs" : "text-slate-400 hover:text-white"
                          }`}
                        >
                          Colaboradores
                        </button>
                        <button
                          onClick={() => {
                            setImportType("empresas");
                            setImportPreview([]);
                            setImportErrors([]);
                          }}
                          className={`px-3 py-1.5 rounded-lg text-xs font-bold transition-all ${
                            importType === "empresas" ? "bg-red-600 text-white shadow-xs" : "text-slate-400 hover:text-white"
                          }`}
                        >
                          Empresas
                        </button>
                      </div>
                    </div>

                    {/* File Drop Area */}
                    <div className="border-2 border-dashed border-slate-600 hover:border-red-500/60 rounded-2xl p-8 text-center bg-slate-900/50 transition-colors">
                      <input
                        type="file"
                        ref={fileInputRef}
                        accept=".xlsx, .xls, .csv"
                        onChange={handleFileChange}
                        className="hidden"
                        id="excel-upload-input"
                      />
                      <label htmlFor="excel-upload-input" className="cursor-pointer flex flex-col items-center justify-center space-y-3">
                        <div className="w-16 h-16 rounded-full bg-red-600/10 border border-red-500/30 flex items-center justify-center text-red-500">
                          <Upload size={30} />
                        </div>
                        <div>
                          <p className="text-sm font-bold text-white">Clique para selecionar o arquivo Excel (.xlsx)</p>
                          <p className="text-xs text-slate-400 mt-1">Suporta arquivos .xlsx, .xls ou .csv no modelo exportado</p>
                        </div>
                      </label>
                      {importFile && (
                        <p className="text-xs font-mono font-bold text-amber-400 mt-3 bg-slate-900 px-3 py-1.5 rounded-lg inline-block border border-slate-700">
                          Arquivo selecionado: {importFile.name} ({(importFile.size / 1024).toFixed(1)} KB)
                        </p>
                      )}
                    </div>

                    {/* Success Message */}
                    {importSuccessMsg && (
                      <div className="p-4 rounded-xl bg-emerald-500/20 border border-emerald-500/30 text-emerald-300 text-xs font-bold flex items-center gap-2">
                        <CheckCircle2 size={18} /> {importSuccessMsg}
                      </div>
                    )}

                    {/* Errors / Warnings List */}
                    {importErrors.length > 0 && (
                      <div className="p-4 rounded-xl bg-amber-500/10 border border-amber-500/30 space-y-2">
                        <span className="text-xs font-bold text-amber-400 uppercase tracking-wider block flex items-center gap-1.5">
                          <AlertCircle size={16} /> Avisos de Validação ({importErrors.length})
                        </span>
                        <ul className="text-xs text-slate-300 space-y-1 list-disc pl-5 max-h-40 overflow-y-auto font-mono">
                          {importErrors.map((err, i) => (
                            <li key={i}>{err}</li>
                          ))}
                        </ul>
                      </div>
                    )}

                    {/* Import Preview Table */}
                    {importPreview.length > 0 && (
                      <div className="space-y-4">
                        <div className="flex items-center justify-between">
                          <h4 className="text-xs font-bold uppercase tracking-wider text-slate-400">
                            Pré-visualização da Carga ({importPreview.length} registro(s) prontos)
                          </h4>
                          <button
                            onClick={handleConfirmImport}
                            disabled={isImporting}
                            className="px-6 py-2.5 rounded-xl bg-red-600 hover:bg-red-500 text-white font-bold text-xs shadow-lg transition-all flex items-center gap-2"
                          >
                            {isImporting ? (
                              <span className="w-4 h-4 border-2 border-white border-t-transparent rounded-full animate-spin"></span>
                            ) : (
                              <CheckCircle2 size={16} />
                            )}
                            Confirmar Importação em Massa
                          </button>
                        </div>

                        <div className="bg-slate-900/80 rounded-2xl border border-slate-700 overflow-hidden max-h-80 overflow-y-auto">
                          <table className="w-full text-left text-xs text-slate-300">
                            <thead className="bg-slate-950 text-slate-400 uppercase tracking-wider font-bold sticky top-0 border-b border-slate-800">
                              <tr>
                                <th className="p-3">Linha</th>
                                {importType === "colaboradores" ? (
                                  <>
                                    <th className="p-3">CPF</th>
                                    <th className="p-3">Nome Completo</th>
                                    <th className="p-3">Função</th>
                                    <th className="p-3">Setor</th>
                                    <th className="p-3">Unidade</th>
                                    <th className="p-3">Local Registro</th>
                                    <th className="p-3">Jornada/Carga</th>
                                  </>
                                ) : (
                                  <>
                                    <th className="p-3">Razão Social / Nome</th>
                                    <th className="p-3">CNPJ</th>
                                    <th className="p-3">Endereço</th>
                                  </>
                                )}
                              </tr>
                            </thead>
                            <tbody className="divide-y divide-slate-800/80 font-mono">
                              {importPreview.map((item, idx) => (
                                <tr key={idx} className="hover:bg-slate-800/50">
                                  <td className="p-3 text-slate-500">{item.lineNum}</td>
                                  {importType === "colaboradores" ? (
                                    <>
                                      <td className="p-3 text-amber-300 font-bold">{item.cpf}</td>
                                      <td className="p-3 font-bold text-white">{item.nome}</td>
                                      <td className="p-3">{item.funcao}</td>
                                      <td className="p-3">{item.setor}</td>
                                      <td className="p-3">{item.unidade}</td>
                                      <td className="p-3 text-slate-400">{item.local_registro}</td>
                                      <td className="p-3 text-emerald-400 font-bold">{item.jornadaSemanal}h/sem ({item.carga_horaria}h/mês)</td>
                                    </>
                                  ) : (
                                    <>
                                      <td className="p-3 font-bold text-white">{item.nome}</td>
                                      <td className="p-3 text-amber-300 font-bold">{item.cnpj}</td>
                                      <td className="p-3 text-slate-300">{item.endereco}</td>
                                    </>
                                  )}
                                </tr>
                              ))}
                            </tbody>
                          </table>
                        </div>
                      </div>
                    )}
                  </div>
                </div>
              )}

              {/* SECTION 2: GERENCIADOR DE TABELAS */}"""

content = content.replace(old_main_end, new_sections)

# 4. Modals for Empresa Create/Edit
old_modal_end = """            {/* Modal for editing table row */}"""

new_empresa_modal = """            {/* Modal for creating/editing empresa */}
            {isEmpresaModalOpen && (
              <div className="fixed inset-0 bg-slate-950/80 backdrop-blur-xs flex items-center justify-center p-4 z-50 animate-fadeIn">
                <div className="bg-slate-900 rounded-3xl p-6 md:p-8 max-w-lg w-full shadow-2xl border border-slate-700 space-y-5">
                  <div className="flex items-center justify-between border-b border-slate-800 pb-4">
                    <h3 className="font-extrabold text-white text-lg flex items-center gap-2">
                      <Building2 size={20} className="text-red-500" />
                      {editingEmpresa ? "Editar Empresa" : "Cadastrar Nova Empresa"}
                    </h3>
                    <button
                      onClick={() => setIsEmpresaModalOpen(false)}
                      className="text-slate-400 hover:text-white p-1 rounded-lg hover:bg-slate-800 transition-colors"
                    >
                      <X size={20} />
                    </button>
                  </div>

                  <form onSubmit={handleSaveEmpresa} className="space-y-4">
                    <div>
                      <label className="block text-xs font-bold text-slate-300 uppercase tracking-wider mb-1">
                        Razão Social / Nome da Empresa *
                      </label>
                      <input
                        type="text"
                        required
                        placeholder="Ex: PRIME DISTRIBUICAO LTDA"
                        value={empresaFormData.nome}
                        onChange={(e) => setEmpresaFormData({ ...empresaFormData, nome: e.target.value })}
                        className="w-full px-4 py-2.5 rounded-xl bg-slate-950 border border-slate-800 text-xs text-slate-100 uppercase focus:outline-none focus:ring-2 focus:ring-red-500 font-medium"
                      />
                    </div>

                    <div>
                      <label className="block text-xs font-bold text-slate-300 uppercase tracking-wider mb-1">
                        CNPJ *
                      </label>
                      <input
                        type="text"
                        required
                        placeholder="Ex: 52.522.019/0001-00"
                        value={empresaFormData.cnpj}
                        onChange={(e) => setEmpresaFormData({ ...empresaFormData, cnpj: e.target.value })}
                        className="w-full px-4 py-2.5 rounded-xl bg-slate-950 border border-slate-800 text-xs text-slate-100 font-mono focus:outline-none focus:ring-2 focus:ring-red-500"
                      />
                    </div>

                    <div>
                      <label className="block text-xs font-bold text-slate-300 uppercase tracking-wider mb-1">
                        Endereço Completo
                      </label>
                      <textarea
                        rows={2}
                        placeholder="Ex: Avenida America, S/N - Iguape. CEP: 45658-460. Ilhéus/BA."
                        value={empresaFormData.endereco}
                        onChange={(e) => setEmpresaFormData({ ...empresaFormData, endereco: e.target.value })}
                        className="w-full px-4 py-2.5 rounded-xl bg-slate-950 border border-slate-800 text-xs text-slate-100 focus:outline-none focus:ring-2 focus:ring-red-500 font-medium"
                      />
                    </div>

                    <div className="flex items-center justify-end gap-3 pt-3 border-t border-slate-800">
                      <button
                        type="button"
                        onClick={() => setIsEmpresaModalOpen(false)}
                        className="px-4 py-2.5 rounded-xl border border-slate-700 text-slate-300 text-xs font-bold hover:bg-slate-800 transition-colors"
                      >
                        Cancelar
                      </button>
                      <button
                        type="submit"
                        className="px-5 py-2.5 rounded-xl bg-red-600 hover:bg-red-500 text-white text-xs font-bold shadow-md transition-all flex items-center gap-1.5"
                      >
                        <CheckCircle2 size={16} />
                        Salvar Empresa
                      </button>
                    </div>
                  </form>
                </div>
              </div>
            )}

            {/* Modal for editing table row */}"""

content = content.replace(old_modal_end, new_empresa_modal)

with open("admin.html", "w", encoding="utf-8") as f:
    f.write(content)

print("full_patch_admin complete!")
