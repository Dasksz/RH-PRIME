import re

with open("admin.html", "r", encoding="utf-8") as f:
    content = f.read()

# Replace Icon definitions to include Building2, Users, Download, Upload
old_icons = """const LogOut = (p) => (
        <Icon {...p}>
          <path d="M9 21H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h4" />
          <polyline points="16 17 21 12 16 7" />
          <line x1="21" y1="12" x2="9" y2="12" />
        </Icon>
      );"""

new_icons = """const LogOut = (p) => (
        <Icon {...p}>
          <path d="M9 21H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h4" />
          <polyline points="16 17 21 12 16 7" />
          <line x1="21" y1="12" x2="9" y2="12" />
        </Icon>
      );
      const Building2 = (p) => (
        <Icon {...p}>
          <path d="M6 22V4a2 2 0 0 1 2-2h8a2 2 0 0 1 2 2v18Z" />
          <path d="M6 12H4a2 2 0 0 0-2 2v6a2 2 0 0 0 2 2h2" />
          <path d="M18 9h2a2 2 0 0 1 2 2v9a2 2 0 0 1-2 2h-2" />
          <path d="M10 6h4" />
          <path d="M10 10h4" />
          <path d="M10 14h4" />
          <path d="M10 18h4" />
        </Icon>
      );
      const Users = (p) => (
        <Icon {...p}>
          <path d="M16 21v-2a4 4 0 0 0-4-4H6a4 4 0 0 0-4 4v2" />
          <circle cx="9" cy="7" r="4" />
          <path d="M22 21v-2a4 4 0 0 0-3-3.87" />
          <path d="M16 3.13a4 4 0 0 1 0 7.75" />
        </Icon>
      );
      const Download = (p) => (
        <Icon {...p}>
          <path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4" />
          <polyline points="7 10 12 15 17 10" />
          <line x1="12" y1="15" x2="12" y2="3" />
        </Icon>
      );
      const Upload = (p) => (
        <Icon {...p}>
          <path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4" />
          <polyline points="17 8 12 3 7 8" />
          <line x1="12" y1="3" x2="12" y2="15" />
        </Icon>
      );"""

content = content.replace(old_icons, new_icons)

# Replace Navigation bar buttons
old_nav = """              <nav className="flex items-center gap-2 bg-slate-900/80 p-1.5 rounded-2xl border border-slate-700/60">
                <button
                  onClick={() => setActiveSection("logs")}
                  className={`px-4 py-2 rounded-xl text-xs font-bold transition-all flex items-center gap-2 ${
                    activeSection === "logs"
                      ? "bg-red-600 text-white shadow-md"
                      : "text-slate-400 hover:text-white hover:bg-slate-800"
                  }`}
                >
                  <History size={16} />
                  <span>Logs de Alterações</span>
                </button>

                <button
                  onClick={() => setActiveSection("tables")}
                  className={`px-4 py-2 rounded-xl text-xs font-bold transition-all flex items-center gap-2 ${
                    activeSection === "tables"
                      ? "bg-red-600 text-white shadow-md"
                      : "text-slate-400 hover:text-white hover:bg-slate-800"
                  }`}
                >
                  <Database size={16} />
                  <span>Gerenciador de Tabelas</span>
                </button>

                <button
                  onClick={() => setActiveSection("password")}
                  className={`px-4 py-2 rounded-xl text-xs font-bold transition-all flex items-center gap-2 ${
                    activeSection === "password"
                      ? "bg-red-600 text-white shadow-md"
                      : "text-slate-400 hover:text-white hover:bg-slate-800"
                  }`}
                >
                  <Key size={16} />
                  <span>Senha do Sistema</span>
                </button>

                <button
                  onClick={handleLogout}
                  className="px-4 py-2 rounded-xl text-xs font-bold transition-all flex items-center gap-2 text-red-400 hover:text-red-300 hover:bg-red-500/10 border border-red-500/20"
                  title="Sair do sistema"
                >
                  <LogOut size={16} />
                  <span>Sair</span>
                </button>
              </nav>"""

new_nav = """              <nav className="flex flex-wrap items-center gap-2 bg-slate-900/80 p-1.5 rounded-2xl border border-slate-700/60">
                <button
                  onClick={() => setActiveSection("logs")}
                  className={`px-3 py-2 rounded-xl text-xs font-bold transition-all flex items-center gap-1.5 ${
                    activeSection === "logs"
                      ? "bg-red-600 text-white shadow-md"
                      : "text-slate-400 hover:text-white hover:bg-slate-800"
                  }`}
                >
                  <History size={16} />
                  <span>Logs</span>
                </button>

                <button
                  onClick={() => setActiveSection("empresas")}
                  className={`px-3 py-2 rounded-xl text-xs font-bold transition-all flex items-center gap-1.5 ${
                    activeSection === "empresas"
                      ? "bg-red-600 text-white shadow-md"
                      : "text-slate-400 hover:text-white hover:bg-slate-800"
                  }`}
                >
                  <Building2 size={16} />
                  <span>Empresas</span>
                </button>

                <button
                  onClick={() => setActiveSection("carga_massa")}
                  className={`px-3 py-2 rounded-xl text-xs font-bold transition-all flex items-center gap-1.5 ${
                    activeSection === "carga_massa"
                      ? "bg-red-600 text-white shadow-md"
                      : "text-slate-400 hover:text-white hover:bg-slate-800"
                  }`}
                >
                  <Upload size={16} />
                  <span>Exportação / Importação</span>
                </button>

                <button
                  onClick={() => setActiveSection("tables")}
                  className={`px-3 py-2 rounded-xl text-xs font-bold transition-all flex items-center gap-1.5 ${
                    activeSection === "tables"
                      ? "bg-red-600 text-white shadow-md"
                      : "text-slate-400 hover:text-white hover:bg-slate-800"
                  }`}
                >
                  <Database size={16} />
                  <span>Gerenciador de Tabelas</span>
                </button>

                <button
                  onClick={() => setActiveSection("password")}
                  className={`px-3 py-2 rounded-xl text-xs font-bold transition-all flex items-center gap-1.5 ${
                    activeSection === "password"
                      ? "bg-red-600 text-white shadow-md"
                      : "text-slate-400 hover:text-white hover:bg-slate-800"
                  }`}
                >
                  <Key size={16} />
                  <span>Senha</span>
                </button>

                <button
                  onClick={handleLogout}
                  className="px-3 py-2 rounded-xl text-xs font-bold transition-all flex items-center gap-1.5 text-red-400 hover:text-red-300 hover:bg-red-500/10 border border-red-500/20"
                  title="Sair do sistema"
                >
                  <LogOut size={16} />
                  <span>Sair</span>
                </button>
              </nav>"""

content = content.replace(old_nav, new_nav)

with open("admin.html", "w", encoding="utf-8") as f:
    f.write(content)

print("Navigation patched in admin.html")
