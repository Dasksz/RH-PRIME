"""Aplicativo de preparação e revisão. Integração Facilita Ponto ainda indisponível."""
import queue
import threading
import tkinter as tk
from tkinter import ttk, filedialog, messagebox
import webbrowser
from .batches import prepare_batch, select_documents
from .config import load_config
from .database import Database
from .providers import FacilitaPonto

class Application:
    def __init__(self, root):
        self.root, self.config = root, load_config()
        self.db = Database(self.config)
        self.documents, self.folder = [], None
        self.events = queue.Queue()
        self.busy = False
        root.title('RH PRIME — Preparação de documentos (prévia)')
        root.geometry('1000x680')
        root.minsize(720, 500)
        root.columnconfigure(0, weight=1)
        root.rowconfigure(1, weight=1)
        self.status = tk.StringVar(value='Entre na sua conta ou carregue a sessão salva para preparar documentos.')
        header = ttk.Frame(root, padding=16)
        header.grid(row=0, column=0, sticky='ew')
        ttk.Label(header, text='RH PRIME | Documentos', font=('Segoe UI', 19, 'bold')).pack(side='left')
        ttk.Button(header, text='Abrir sistema web', command=lambda: webbrowser.open(self.config['web_url'])).pack(side='right')
        tabs = ttk.Notebook(root)
        tabs.grid(row=1, column=0, sticky='nsew', padx=16)
        account, batch = ttk.Frame(tabs, padding=16), ttk.Frame(tabs, padding=16)
        tabs.add(account, text='Conta')
        tabs.add(batch, text='Preparar e revisar')
        self.email, self.password = tk.StringVar(), tk.StringVar()
        for label, var, mask in [('E-mail RH PRIME',self.email,''),('Senha',self.password,'•')]:
            ttk.Label(account, text=label).pack(anchor='w', pady=(8,2))
            ttk.Entry(account, textvariable=var, show=mask, width=48).pack(anchor='w')
        ttk.Button(account, text='Entrar e salvar sessão neste computador', command=self.login).pack(anchor='w', pady=12)
        ttk.Button(account, text='Usar sessão salva', command=lambda: self.run(self.restore, lambda _: self.status.set('Sessão restaurada.'))).pack(anchor='w')
        ttk.Button(account, text='Desconectar e apagar sessão salva', command=lambda: self.run(self.db.logout, lambda _: self.status.set('Sessão local removida.'))).pack(anchor='w', pady=12)
        ttk.Label(account, text='A senha não é salva. O token de renovação fica no cofre de credenciais do Windows.', wraplength=600).pack(anchor='w')
        ttk.Label(account, text='Facilita Ponto: aguardando documentação e liberação da API.\nEsta prévia não envia documentos, não move pastas e não roda em segundo plano.', wraplength=600).pack(anchor='w', pady=20)
        toolbar = ttk.Frame(batch)
        toolbar.pack(fill='x')
        ttk.Label(toolbar, text='Páginas por documento:').pack(side='left')
        self.pages = tk.StringVar(value='1')
        ttk.Spinbox(toolbar, from_=1, to=100, width=5, textvariable=self.pages).pack(side='left', padx=6)
        ttk.Button(toolbar, text='Escolher PDF e separar', command=self.prepare).pack(side='left', padx=8)
        ttk.Label(batch, text='Selecione linhas com Ctrl ou Shift. “Todos” considera apenas documentos identificados e prontos.\nPDFs sem texto ou com identificação ambígua ficam para revisão.', wraplength=850).pack(anchor='w', pady=10)
        frame = ttk.Frame(batch)
        frame.pack(fill='both', expand=True)
        frame.columnconfigure(0, weight=1)
        frame.rowconfigure(0, weight=1)
        self.table = ttk.Treeview(frame, columns=('name','pages','state','reason'), show='headings', selectmode='extended')
        for col, title, width in [('name','Colaborador',230),('pages','Páginas',70),('state','Situação',100),('reason','Revisão necessária',350)]:
            self.table.heading(col, text=title)
            self.table.column(col, width=width, minwidth=60)
        self.table.grid(row=0, column=0, sticky='nsew')
        bar = ttk.Scrollbar(frame, orient='vertical', command=self.table.yview)
        bar.grid(row=0, column=1, sticky='ns')
        horizontal = ttk.Scrollbar(frame, orient='horizontal', command=self.table.xview)
        horizontal.grid(row=1, column=0, sticky='ew')
        self.table.configure(yscrollcommand=bar.set, xscrollcommand=horizontal.set)
        buttons = ttk.Frame(batch)
        buttons.pack(fill='x', pady=12)
        ttk.Button(buttons, text='Selecionar todos os prontos', command=self.select_all).pack(side='left')
        ttk.Button(buttons, text='Limpar seleção', command=lambda: self.table.selection_remove(self.table.selection())).pack(side='left', padx=8)
        ttk.Button(buttons, text='Conferir seleção', command=self.preview).pack(side='left')
        ttk.Button(buttons, text='Enviar ao Facilita Ponto — pendente', state='disabled').pack(side='right')
        ttk.Label(root, textvariable=self.status, wraplength=950, padding=16).grid(row=2, column=0, sticky='ew')
        root.after(100, self.poll)

    def run(self, task, success):
        if self.busy:
            return
        self.busy = True
        self.status.set('Processando…')
        def execute():
            try: self.events.put((success, task(), None))
            except Exception as error: self.events.put((None, None, str(error)))
        threading.Thread(target=execute, daemon=True).start()

    def poll(self):
        try:
            callback, result, error = self.events.get_nowait()
            self.busy = False
            if error:
                self.status.set(error)
                messagebox.showerror('RH PRIME', error)
            else: callback(result)
        except queue.Empty: pass
        self.root.after(100, self.poll)

    def restore(self):
        self.db.token()
        profiles = self.db.rows('profiles', {'id':'eq.' + self.db.session['user']['id']})
        if not profiles or profiles[0]['status'] != 'admin':
            self.db.logout()
            raise ValueError('Este aplicativo exige uma conta administradora aprovada.')

    def login(self):
        email, password = self.email.get().strip(), self.password.get()
        self.password.set('')
        self.run(lambda: self.db.login(email,password), lambda _: self.status.set('Conta conectada. Sessão salva neste computador.'))

    def prepare(self):
        if self.busy: return
        try: count = int(self.pages.get())
        except ValueError:
            messagebox.showerror('Páginas', 'Informe um número inteiro positivo.')
            return
        source = filedialog.askopenfilename(filetypes=[('Documentos PDF','*.pdf')])
        if not source: return
        def task():
            self.restore()
            employees = self.db.rows('funcionarios_epi', {'select':'id,nome,cpf,data_desligamento'})
            return prepare_batch(source, employees, self.config['work_dir'], count)
        self.run(task, self.show_batch)

    def show_batch(self, result):
        self.folder, self.documents = result
        self.table.delete(*self.table.get_children())
        for doc in self.documents:
            self.table.insert('', 'end', iid=doc.id, values=(doc.employee_name, f'{doc.first_page}–{doc.last_page}', 'Pronto' if doc.status=='prepared' else 'Revisar',doc.reason))
        self.status.set(f'{len(self.documents)} documentos separados. Pasta: {self.folder}. Nenhum envio realizado.')

    def select_all(self):
        self.table.selection_set([d.id for d in select_documents(self.documents)])

    def preview(self):
        selected = set(self.table.selection())
        docs = [d for d in self.documents if d.id in selected]
        if not docs:
            messagebox.showinfo('Seleção', 'Selecione pelo menos um documento pronto.')
            return
        if any(d.status != 'prepared' for d in docs):
            messagebox.showwarning('Seleção', 'A seleção contém documentos que exigem revisão. Remova-os da seleção.')
            return
        messagebox.showinfo('Conferência', f'{len(docs)} documentos de {len({d.employee_id for d in docs})} colaboradores.\n\n' + FacilitaPonto.reason)

def main():
    root = tk.Tk()
    Application(root)
    root.mainloop()

if __name__ == '__main__': main()
