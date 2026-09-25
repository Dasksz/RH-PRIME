with open("colaboradores.html", "r", encoding="utf-8") as f:
    content = f.read()

# 1. Add empresas state to colaboradores.html
old_states = """        const [colaboradores, setColaboradores] = useState([]);
        const [movimentacoes, setMovimentacoes] = useState([]);"""

new_states = """        const [colaboradores, setColaboradores] = useState([]);
        const [movimentacoes, setMovimentacoes] = useState([]);
        const [empresas, setEmpresas] = useState([]);"""

content = content.replace(old_states, new_states)

# 2. Add fetchEmpresas into fetchData
old_fetch = """            const { data: movData, error: movErr } = await supabase
              .from("rh_movimentacoes")
              .select("*");

            if (movErr) throw movErr;

            setColaboradores(epiData || []);
            setMovimentacoes(movData || []);"""

new_fetch = """            const { data: movData, error: movErr } = await supabase
              .from("rh_movimentacoes")
              .select("*");

            if (movErr) throw movErr;

            const { data: empData, error: empErr } = await supabase
              .from("empresas")
              .select("*")
              .order("nome", { ascending: true });

            if (empErr) console.error("Erro ao carregar empresas:", empErr);

            setColaboradores(epiData || []);
            setMovimentacoes(movData || []);
            setEmpresas(empData || []);"""

content = content.replace(old_fetch, new_fetch)

# 3. Dynamic company select in Cadastrar modal
old_select_cad = """                      <div className="md:col-span-2">
                        <label className="block font-bold text-slate-700 uppercase mb-1">Local do Registro (Empresa)</label>
                        <select
                          value={formData.local_registro}
                          onChange={(e) => setEditFormData({ ...formData, local_registro: e.target.value })}
                          className="w-full p-2.5 bg-slate-50 border border-slate-200 rounded-xl focus:bg-white focus:ring-2 focus:ring-[#002060] text-sm"
                        >
                          <option value="NUNES & VIEIRA LOGISTICA LTDA">NUNES & VIEIRA LOGISTICA LTDA (Itabuna)</option>
                          <option value="PRIME DISTRIBUICAO LTDA - ILHÉUS ">PRIME DISTRIBUICAO LTDA - ILHÉUS</option>
                          <option value="PRIME DISTRIBUICAO LTDA - JEQUIÉ ">PRIME DISTRIBUICAO LTDA - JEQUIÉ</option>
                        </select>
                      </div>"""

new_select_cad = """                      <div className="md:col-span-2">
                        <label className="block font-bold text-slate-700 uppercase mb-1">Local do Registro (Empresa)</label>
                        <select
                          value={formData.local_registro}
                          onChange={(e) => setEditFormData({ ...formData, local_registro: e.target.value })}
                          className="w-full p-2.5 bg-slate-50 border border-slate-200 rounded-xl focus:bg-white focus:ring-2 focus:ring-[#002060] text-sm"
                        >
                          {empresas.length === 0 ? (
                            <>
                              <option value="NUNES & VIEIRA LOGISTICA LTDA">NUNES & VIEIRA LOGISTICA LTDA (Itabuna)</option>
                              <option value="PRIME DISTRIBUICAO LTDA - ILHÉUS ">PRIME DISTRIBUICAO LTDA - ILHÉUS</option>
                              <option value="PRIME DISTRIBUICAO LTDA - JEQUIÉ ">PRIME DISTRIBUICAO LTDA - JEQUIÉ</option>
                            </>
                          ) : (
                            empresas.map((e) => (
                              <option key={e.id} value={e.nome}>
                                {e.nome} {e.cnpj ? `(CNPJ: ${e.cnpj})` : ""}
                              </option>
                            ))
                          )}
                        </select>
                      </div>"""

content = content.replace(old_select_cad, new_select_cad)

with open("colaboradores.html", "w", encoding="utf-8") as f:
    f.write(content)

print("colaboradores.html updated with dynamic empresas!")
