import os
import re
import time
import pandas as pd
import unicodedata
from datetime import datetime

try:
    import pdfplumber
    from PyPDF2 import PdfWriter, PdfReader
    from google.oauth2.credentials import Credentials
    from google_auth_oauthlib.flow import InstalledAppFlow
    from google.auth.transport.requests import Request
    from googleapiclient.discovery import build
except ImportError:
    print("❌ Erro: Bibliotecas ausentes. Abra o CMD e digite:")
    print("pip install pdfplumber PyPDF2 pandas requests openpyxl")
    print("pip install google-api-python-client google-auth-httplib2 google-auth-oauthlib")
    os.system("pause")
    exit()

# =======================================================================
# AUTENTICAÇÃO DO DRIVE PARA A FASE 1 (Ler nomes de Ex-Funcionários)
# =======================================================================
def autenticar_drive_fase1():
    escopos = ['https://www.googleapis.com/auth/drive']
    creds = None
    if os.path.exists('token.json'):
        creds = Credentials.from_authorized_user_file('token.json', escopos)
    if not creds or not creds.valid:
        if creds and creds.expired and creds.refresh_token:
            try: creds.refresh(Request())
            except Exception:
                flow = InstalledAppFlow.from_client_secrets_file('credenciais_drive.json', escopos)
                creds = flow.run_local_server(port=0)
        else:
            flow = InstalledAppFlow.from_client_secrets_file('credenciais_drive.json', escopos)
            creds = flow.run_local_server(port=0)
        with open('token.json', 'w') as token:
            token.write(creds.to_json())
    try:
        return build('drive', 'v3', credentials=creds)
    except Exception as e:
        print(f"❌ Erro Drive Fase 1: {e}")
        return None

def mapear_ex_funcionarios(servico, id_pasta_ex):
    print("📡 A mapear lista de Ex-Funcionários no Google Drive...")
    pastas = []
    page_token = None
    while True:
        query = f"'{id_pasta_ex}' in parents and mimeType='application/vnd.google-apps.folder' and trashed=false"
        res = servico.files().list(q=query, spaces='drive', fields='nextPageToken, files(id, name)', pageToken=page_token, supportsAllDrives=True, includeItemsFromAllDrives=True).execute()
        for f in res.get('files', []):
            pastas.append(f.get('name'))
        page_token = res.get('nextPageToken', None)
        if not page_token:
            break
    print(f"✅ {len(pastas)} pastas de Ex-Funcionários mapeadas com sucesso.")
    return pastas

# =======================================================================
# CÓDIGO FONTE DO ROBÔ 2 (Será gerado dentro da nova pasta)
# =======================================================================
CODIGO_ROBO_DISPARO = """import os
import time
import json
import pandas as pd
import requests
import hashlib
import random
import unicodedata
from datetime import datetime
from google.oauth2.credentials import Credentials
from google_auth_oauthlib.flow import InstalledAppFlow
from google.auth.transport.requests import Request
from googleapiclient.discovery import build
from googleapiclient.http import MediaFileUpload

# ⚙️ CONFIGURAÇÕES DO GOOGLE DRIVE ⚙️
ARQUIVO_CREDENCIAS = '../credenciais_drive.json'
ARQUIVO_TOKEN = '../token.json'
ID_PASTA_ATIVOS = "195JwYHEJdRY1u5DEL7tB7dSHn16DRVb4"
ID_PASTA_EX_FUNCIONARIOS = "1v2Pt5YWqnW_bWRA9R7l6OQeMM7G_Tlrm"
TIPO_DOCUMENTO = "{tipo_documento}"

def remover_acentos(texto):
    if not texto: return ""
    texto = str(texto).strip()
    return ''.join(c for c in unicodedata.normalize('NFD', texto) if unicodedata.category(c) != 'Mn')

def autenticar_drive():
    escopos = ['https://www.googleapis.com/auth/drive']
    creds = None
    if os.path.exists(ARQUIVO_TOKEN):
        creds = Credentials.from_authorized_user_file(ARQUIVO_TOKEN, escopos)
    if not creds or not creds.valid:
        if creds and creds.expired and creds.refresh_token:
            try: creds.refresh(Request())
            except Exception:
                flow = InstalledAppFlow.from_client_secrets_file(ARQUIVO_CREDENCIAS, escopos)
                creds = flow.run_local_server(port=0)
        else:
            print("\\n=========================================================")
            print("🔐 ATENÇÃO: O seu navegador web vai abrir agora.")
            print("👉 Faça login com o seu email do Google Drive para autorizar o robô.")
            print("=========================================================\\n")
            flow = InstalledAppFlow.from_client_secrets_file(ARQUIVO_CREDENCIAS, escopos)
            creds = flow.run_local_server(port=0)
        with open(ARQUIVO_TOKEN, 'w') as token:
            token.write(creds.to_json())
    try:
        return build('drive', 'v3', credentials=creds)
    except Exception as e:
        print(f"❌ Erro ao construir o serviço do Drive: {e}")
        return None

def obter_ou_criar_pasta_funcionario(servico, nome_pasta, id_ativos, id_ex):
    nome_escaped = nome_pasta.replace("'", "\'")
    nome_sem_acento = remover_acentos(nome_pasta).replace("'", "\'")

    # Busca por ex-funcionários
    query_ex = f"(name='{nome_escaped}' or name='{nome_sem_acento}') and '{id_ex}' in parents and mimeType='application/vnd.google-apps.folder' and trashed=false"
    res_ex = servico.files().list(q=query_ex, spaces='drive', fields='files(id, name)', supportsAllDrives=True, includeItemsFromAllDrives=True).execute()
    itens_ex = res_ex.get('files', [])
    if itens_ex: return itens_ex[0].get('id')

    # Busca por ativos
    query_ativos = f"(name='{nome_escaped}' or name='{nome_sem_acento}') and '{id_ativos}' in parents and mimeType='application/vnd.google-apps.folder' and trashed=false"
    res_ativos = servico.files().list(q=query_ativos, spaces='drive', fields='files(id, name)', supportsAllDrives=True, includeItemsFromAllDrives=True).execute()
    itens_ativos = res_ativos.get('files', [])
    if itens_ativos: return itens_ativos[0].get('id')

    print(f"   📂 A criar nova pasta: {nome_pasta} em ATIVOS...")
    metadados = {
        'name': nome_pasta,
        'parents': [id_ativos],
        'mimeType': 'application/vnd.google-apps.folder'
    }
    pasta = servico.files().create(body=metadados, fields='id', supportsAllDrives=True).execute()
    return pasta.get('id')

def obter_ou_criar_pasta(servico, nome_pasta, id_pai):
    query = f"name='{nome_pasta}' and '{id_pai}' in parents and mimeType='application/vnd.google-apps.folder' and trashed=false"
    resultados = servico.files().list(q=query, spaces='drive', fields='files(id, name)', supportsAllDrives=True, includeItemsFromAllDrives=True).execute()
    itens = resultados.get('files', [])

    if not itens:
        print(f"   📂 A criar subpasta: {nome_pasta}...")
        metadados = {
            'name': nome_pasta,
            'parents': [id_pai],
            'mimeType': 'application/vnd.google-apps.folder'
        }
        pasta = servico.files().create(body=metadados, fields='id', supportsAllDrives=True).execute()
        return pasta.get('id')
    return itens[0].get('id')

def iniciar_envio():
    print("=========================================================")
    print("  ROBÔ DE UPLOAD (DRIVE Pessoal) E DISPARO VIA N8N       ")
    print("=========================================================\\n")

    arquivo_excel = "Relatorio_Mapeamento.xlsx"
    url_webhook_n8n = "http://100.90.6.30:5679/webhook/holerites"
    sessao_waha = "default"

    if not os.path.exists(arquivo_excel):
        print("❌ Erro: Planilha 'Relatorio_Mapeamento.xlsx' não encontrada!")
        input("Pressione ENTER para sair...")
        return

    print("🔐 A ligar ao Google Drive...")
    servico_drive = autenticar_drive()
    if not servico_drive:
        input("Pressione ENTER para sair...")
        return

    print("📊 A ler a base de dados validada...")
    df_list = []
    try: df_list.append(pd.read_excel(arquivo_excel, sheet_name="Prontos para Envio", dtype=str))
    except: pass
    try: df_list.append(pd.read_excel(arquivo_excel, sheet_name="Ex-Funcionarios", dtype=str))
    except: pass

    if not df_list:
        print(f"❌ Erro ao ler a planilha.")
        input("Pressione ENTER para sair...")
        return

    df = pd.concat(df_list, ignore_index=True)

    # ==========================================================
    # NOVO MENU DE FILTRO NA HORA DO DISPARO
    # ==========================================================
    print("\\n---------------------------------------------------------")
    print("📋 O QUE VOCÊ DESEJA PROCESSAR NESTE DISPARO?")
    print("[1] TODOS (Ativos e Ex-Funcionários)")
    print("[2] APENAS ATIVOS (Upload no Drive + Envio no WhatsApp)")
    print("[3] APENAS EX-FUNCIONÁRIOS (Apenas Upload no Drive, sem WhatsApp)")
    opcao_alvo = input("👉 Escolha 1, 2 ou 3 (ENTER para TODOS): ").strip()

    if opcao_alvo == '2':
        df = df[df['Tipo'] == 'Ativo']
        print("🎯 MODO: Apenas Ativos.")
    elif opcao_alvo == '3':
        df = df[df['Tipo'] == 'Ex-Funcionario']
        print("🎯 MODO: Apenas Ex-Funcionários.")
    else:
        print("🎯 MODO: Todos os registros.")

    if df.empty:
        print("\\n⚠️ Não há registros na planilha para a opção escolhida.")
        input("Pressione ENTER para sair...")
        return
    print("---------------------------------------------------------\\n")

    sucessos = 0
    erros = 0
    removidos = 0

    # Contador para a pausa longa
    mensagens_enviadas_sessao = 0

    print("🚀 A iniciar processo de Upload e Disparos...\\n")

    for index, linha in df.iterrows():
        nome = str(linha['Nome'])
        whatsapp = str(linha.get('WhatsApp', ''))
        nome_arquivo = str(linha['Arquivo Gerado'])
        pasta_local = str(linha.get('Pasta Local', 'PDFs_Separados'))
        tipo_func = str(linha.get('Tipo', 'Ativo'))

        caminho_pdf = os.path.join(pasta_local, nome_arquivo)
        nome_arquivo_log = f"COMPROVANTE - {nome_arquivo.replace('.pdf', '.txt')}"
        caminho_log_temp = os.path.join(pasta_local, nome_arquivo_log)
        caminho_sucessos_ex = os.path.join(pasta_local, "uploads_concluidos.txt")

        if not os.path.exists(caminho_pdf):
            print(f"⏭️ PULO: O PDF de {nome} foi retirado da pasta.")
            removidos += 1
            continue

        ja_processado = False
        if os.path.exists(caminho_log_temp):
            ja_processado = True
        elif os.path.exists(caminho_sucessos_ex):
            try:
                with open(caminho_sucessos_ex, "r", encoding="utf-8") as f_suc:
                    if nome_arquivo in f_suc.read():
                        ja_processado = True
            except: pass

        if ja_processado:
            print(f"⏭️ PULO: {nome} já foi processado com sucesso anteriormente.")
            sucessos += 1
            continue

        # Bloqueio Apenas para Ativos sem WhatsApp
        if tipo_func == 'Ativo' and (whatsapp == 'nan' or whatsapp == 'None' or not whatsapp):
            print(f"❌ ERRO: {nome} (Ativo) está sem número de WhatsApp válido.")
            erros += 1
            with open("falhas_envio.txt", "a", encoding="utf-8") as f_falha: f_falha.write(nome_arquivo + "\\n")
            continue

        print(f"A processar: {nome} [{tipo_func}]...")

        try:
            # --- 1. NAVEGAR NAS PASTAS DO GOOGLE DRIVE COM INTELIGÊNCIA ---
            id_pasta_funcionario = obter_ou_criar_pasta_funcionario(servico_drive, nome, ID_PASTA_ATIVOS, ID_PASTA_EX_FUNCIONARIOS)

            if TIPO_DOCUMENTO == "FOLHA DE PONTO":
                id_pasta_intermediaria = obter_ou_criar_pasta(servico_drive, "JORNADA E SEGURANÇA", id_pasta_funcionario)
                id_pasta_tipo = obter_ou_criar_pasta(servico_drive, TIPO_DOCUMENTO, id_pasta_intermediaria)
            else:
                id_pasta_tipo = obter_ou_criar_pasta(servico_drive, TIPO_DOCUMENTO, id_pasta_funcionario)

            id_pasta_ano = obter_ou_criar_pasta(servico_drive, "{ano_competencia}", id_pasta_tipo)
            id_pasta_mes = obter_ou_criar_pasta(servico_drive, "{mes_competencia}.{ano_competencia}", id_pasta_ano)

            # --- 2. BUSCA ROBUSTA NA PASTA (EVITA DUPLICADOS) ---
            query_pasta = f"'{id_pasta_mes}' in parents and trashed=false"
            res_pasta = servico_drive.files().list(q=query_pasta, spaces='drive', fields='files(id, name, webViewLink)', supportsAllDrives=True, includeItemsFromAllDrives=True).execute()
            arquivos_na_pasta = res_pasta.get('files', [])

            id_ficheiro = None
            link_pdf = None

            # Procura exatamente o nosso arquivo na lista daquela pasta
            for arq in arquivos_na_pasta:
                if arq.get('name') == nome_arquivo:
                    id_ficheiro = arq.get('id')
                    link_pdf = arq.get('webViewLink')
                    break

            if id_ficheiro:
                print("   ☁️ Ficheiro já existe no Drive. A atualizar (substituir) para evitar duplicados...")
                media = MediaFileUpload(caminho_pdf, mimetype='application/pdf')
                ficheiro = servico_drive.files().update(fileId=id_ficheiro, media_body=media, fields='id, webViewLink', supportsAllDrives=True).execute()
                link_pdf = ficheiro.get('webViewLink')
            else:
                print("   ☁️ A enviar ficheiro novo para o Drive...")
                metadados_ficheiro = {'name': nome_arquivo, 'parents': [id_pasta_mes]}
                media = MediaFileUpload(caminho_pdf, mimetype='application/pdf')
                ficheiro = servico_drive.files().create(body=metadados_ficheiro, media_body=media, fields='id, webViewLink', supportsAllDrives=True).execute()
                id_ficheiro = ficheiro.get('id')
                link_pdf = ficheiro.get('webViewLink')

            # --- 3. DAR PERMISSÃO DE LEITURA AO LINK ---
            servico_drive.permissions().create(
                fileId=id_ficheiro,
                body={'type': 'anyone', 'role': 'reader'},
                supportsAllDrives=True
            ).execute()

            # --- 4. ENVIO DE WHATSAPP (Apenas se tiver número e for Ativo) ---
            if tipo_func == 'Ativo' and whatsapp and whatsapp != 'nan' and whatsapp != 'None':
                if "{mes_competencia}" == "ANUAL":
                    texto_referencia = "referente a {ano_competencia}"
                else:
                    texto_referencia = "referente a {mes_competencia}.{ano_competencia}"

                pronome = "A sua" if TIPO_DOCUMENTO == "FOLHA DE PONTO" else "O seu"

                mensagem = (f"Olá, *{nome}*!\\n\\n"
                            f"Aqui é do Setor de RH. {pronome} {TIPO_DOCUMENTO} {texto_referencia} já está disponível.\\n\\n"
                            f"🔒 *DOCUMENTO PROTEGIDO*\\n"
                            f"Para garantir a sua privacidade (LGPD), o ficheiro possui uma senha.\\n"
                            f"👉 A senha são os *5 PRIMEIROS NÚMEROS DO SEU CPF* (Apenas os números).\\n\\n"
                            f"📄 *Acesse o seu documento aqui:*\\n{link_pdf}\\n\\n"
                            f"⚠️ *MUITO IMPORTANTE:* Por favor, responda a esta mensagem com um *OK* ou *RECEBIDO* para confirmarmos a entrega no nosso sistema.\\n\\n"
                            f"Um excelente dia!")

                dados = { 'chatId': whatsapp, 'caption': mensagem, 'session': sessao_waha }
                resposta = requests.post(url_webhook_n8n, json=dados)

                if resposta.status_code in [200, 201]:
                    print("  ✅ Sucesso! Ficheiro guardado e Mensagem enviada para o n8n.")
                    sucessos += 1
                    mensagens_enviadas_sessao += 1

                    id_msg_whatsapp = "N/A"
                    try:
                        dados_resposta = resposta.json()
                        if isinstance(dados_resposta, list) and len(dados_resposta) > 0: id_msg_whatsapp = dados_resposta[0].get("id", "N/A")
                        elif isinstance(dados_resposta, dict): id_msg_whatsapp = dados_resposta.get("id", "N/A")
                    except: pass

                    # LOG COMPLETO DE WHATSAPP
                    try:
                        hash_pdf = hashlib.sha256()
                        with open(caminho_pdf, "rb") as f_pdf:
                            for byte_block in iter(lambda: f_pdf.read(4096), b""): hash_pdf.update(byte_block)
                        assinatura_digital = hash_pdf.hexdigest()

                        data_hora_atual = datetime.now().strftime("%d/%m/%Y %H:%M:%S")
                        conteudo_log = (f"=========================================\\n"
                                        f"COMPROVANTE DE ENVIO DE DOCUMENTO (RH PRIME)\\n"
                                        f"=========================================\\n"
                                        f"Data e Hora do Disparo: {data_hora_atual}\\n"
                                        f"Funcionário: {nome}\\n"
                                        f"WhatsApp Destino: {whatsapp}\\n"
                                        f"Arquivo de Referência: {nome_arquivo} (CRIPTOGRAFADO)\\n"
                                        f"Assinatura Criptográfica do PDF (SHA-256):\\n{assinatura_digital}\\n\\n"
                                        f"CONTEÚDO DA MENSAGEM ENVIADA:\\n"
                                        f"-----------------------------------------\\n"
                                        f"{mensagem}\\n"
                                        f"-----------------------------------------\\n"
                                        f"REGISTRO DE ENTREGA DO SERVIDOR (COMPROVAÇÃO):\\n"
                                        f"Status HTTP: {resposta.status_code}\\n"
                                        f"ID Oficial da Transmissão (WhatsApp/WAHA): {id_msg_whatsapp}\\n"
                                        f"Resposta Bruta do Servidor: {resposta.text.strip()}\\n"
                                        f"=========================================\\n"
                                        f"Documento gerado automaticamente com rastreabilidade técnica.")

                        with open(caminho_log_temp, "w", encoding="utf-8") as f_log:
                            f_log.write(conteudo_log)

                        print("   📝 A guardar comprovante auditável no Drive...")

                        id_log_existente = None
                        for arq in arquivos_na_pasta:
                            if arq.get('name') == nome_arquivo_log:
                                id_log_existente = arq.get('id')
                                break

                        media_log = MediaFileUpload(caminho_log_temp, mimetype='text/plain')
                        if id_log_existente:
                            servico_drive.files().update(fileId=id_log_existente, media_body=media_log, supportsAllDrives=True).execute()
                        else:
                            metadados_log = {'name': nome_arquivo_log, 'parents': [id_pasta_mes]}
                            servico_drive.files().create(body=metadados_log, media_body=media_log, fields='id', supportsAllDrives=True).execute()

                    except Exception as err_log:
                        print(f"  ⚠️ Aviso: A mensagem foi enviada, mas falhou ao guardar o log no Drive: {err_log}")
                else:
                    print(f"  ❌ O Drive funcionou, mas houve falha no n8n (Status: {resposta.status_code})")
                    erros += 1
                    with open("falhas_envio.txt", "a", encoding="utf-8") as f_falha: f_falha.write(nome_arquivo + "\\n")

            else:
                # É EX-FUNCIONARIO (Upload Silencioso)
                sucessos += 1
                print("  ✅ Sucesso! Ficheiro organizado no Drive da empresa (Sem disparo de WhatsApp).")
                with open(caminho_sucessos_ex, "a", encoding="utf-8") as f_suc: f_suc.write(nome_arquivo + "\\n")

        except Exception as e:
            print(f"  ❌ Erro durante o processo de {nome}: {e}")
            erros += 1
            with open("falhas_envio.txt", "a", encoding="utf-8") as f_falha: f_falha.write(nome_arquivo + "\\n")

        # --- SISTEMA ANTI-BLOQUEIO DO WHATSAPP (APENAS PARA ATIVOS E PROGRESSIVO) ---
        if tipo_func == 'Ativo':
            if mensagens_enviadas_sessao > 0 and mensagens_enviadas_sessao % 5 == 0:
                # Pausa longa a cada 5 mensagens
                tempo_espera = random.randint(45, 90)
                print(f"   ⏳ Pausa longa anti-bloqueio: aguardando {tempo_espera} segundos após 5 envios...")
            else:
                # Pausa base maior
                tempo_espera = random.randint(15, 25)
                print(f"   ⏳ Pausa anti-bloqueio: aguardando {tempo_espera} segundos antes do próximo...")

            time.sleep(tempo_espera)

    print("\\n=========================================================")
    print("RESUMO DO LOTE:")
    print(f"✅ Processados com sucesso: {sucessos}")
    print(f"❌ Erros no processo: {erros}")
    print(f"🗑️ Removidos manualmente: {removidos}")
    print("=========================================================\\n")
    input("Pressione ENTER para sair...")

if __name__ == "__main__":
    iniciar_envio()
"""

CODIGO_BAT_DISPARO = """@echo off
title Disparar Documentos - Fase 2
color 0A
echo ===================================================
echo     INICIANDO UPLOAD DRIVE E DISPARO DE MENSAGENS
echo ===================================================
echo.
python 2_Enviar_WhatsApp.py
echo.
echo ===================================================
pause
"""

def normalizar_texto(texto):
    if not texto: return ""
    texto = str(texto).lower().strip()
    texto = ''.join(c for c in unicodedata.normalize('NFD', texto) if unicodedata.category(c) != 'Mn')
    return " ".join(texto.split())

def extrair_cpf_do_texto(texto):
    if not texto: return None
    padrao = re.findall(r'\d{3}\.\d{3}\.\d{3}-\d{2}', texto)
    if padrao: return padrao[0].replace('.', '').replace('-', '')
    return None

def formatar_numero_whatsapp(numero_bruto):
    numero_limpo = re.sub(r'\D', '', str(numero_bruto))
    if not numero_limpo or numero_limpo == 'nan': return None

    # Remove o 55 temporariamente caso já venha na string para padronizar a contagem
    if numero_limpo.startswith('55') and len(numero_limpo) >= 12:
        numero_limpo = numero_limpo[2:]

    if not numero_limpo.startswith('55'): numero_limpo = '55' + numero_limpo
    return f"{numero_limpo}@c.us"

def preparar_lote():
    print("=========================================================")
    print("  FASE 1: PREPARADOR DE DOCUMENTOS E MAPEAMENTO DE DADOS ")
    print("=========================================================\n")

    # ==========================================================
    # MENU DE GESTÃO DE LOTES
    # ==========================================================
    chaves_pendentes = None
    print("🛠️  O QUE VOCÊ DESEJA FAZER AGORA?")
    print("[1] LOTE NOVO: Fatiar todos os PDFs e criar nova pasta de envios.")
    print("[2] EXTRAIR PENDENTES: Vasculha um Lote Antigo e cria uma Nova Pasta SÓ com quem falhou.")
    print("[3] ATUALIZAR LOTE ANTIGO: Injeta o código novo numa pasta que já existe.")
    opcao_modo = input("👉 Escolha 1, 2 ou 3: ").strip()

    if opcao_modo not in ['1', '2', '3']:
        print("\n❌ Opção inválida. Operação cancelada.")
        input("Pressione ENTER para sair...")
        return

    print("\n---------------------------------------------------------")
    print("📋 QUAL O TIPO DE DOCUMENTO NESTE LOTE?")
    print("[1] HOLERITE")
    print("[2] INFORME DE RENDIMENTOS")
    print("[3] AVISO DE FÉRIAS")
    print("[4] FOLHA DE PONTO")
    print("[5] OUTRO")
    opcao_doc = input("👉 Escolha de 1 a 5 (Padrão: 1): ").strip()

    tipo_documento = "HOLERITE"
    paginas_por_funcionario = 1

    if opcao_doc == '2':
        tipo_documento = "INFORME DE RENDIMENTOS"
        paginas_por_funcionario = 2
    elif opcao_doc == '3':
        tipo_documento = "AVISO DE FÉRIAS"
        paginas_por_funcionario = 1
    elif opcao_doc == '4':
        tipo_documento = "FOLHA DE PONTO"
        paginas_por_funcionario = 1
    elif opcao_doc == '5':
        tipo_documento = input("👉 Digite o nome do documento (ex: RECIBO DE FERIAS): ").strip().upper()

    print("\n---------------------------------------------------------")
    print(f"📄 QUANTAS PÁGINAS CADA '{tipo_documento}' TEM POR FUNCIONÁRIO?")
    print(f"[1] 1 Página por pessoa")
    print(f"[2] 2 Páginas por pessoa (Ex: Informes)")
    print(f"[3] Outro valor")
    opcao_pag = input(f"👉 Escolha (Pressione ENTER para manter {paginas_por_funcionario}): ").strip()

    if opcao_pag == '1': paginas_por_funcionario = 1
    elif opcao_pag == '2': paginas_por_funcionario = 2
    elif opcao_pag == '3':
        val = input("👉 Digite o número exato de páginas por funcionário: ").strip()
        try: paginas_por_funcionario = int(val)
        except: pass

    print("\n---------------------------------------------------------")

    if opcao_modo == '3':
        pastas_lote = [d for d in os.listdir('.') if os.path.isdir(d) and d.startswith('Lote_')]
        pastas_lote.sort(reverse=True)
        if not pastas_lote:
            print("\n❌ Nenhuma pasta de Lote encontrada no diretório.")
            input("Pressione ENTER para sair...")
            return
        print("\n📂 Pastas de Lotes Anteriores encontradas:")
        for i, p in enumerate(pastas_lote): print(f"[{i+1}] {p}")

        idx = input("\n👉 Digite o número da pasta que você deseja atualizar: ").strip()
        try:
            pasta_escolhida = pastas_lote[int(idx)-1]
            caminho_pdfs = os.path.join(pasta_escolhida, "PDFs_Separados")
            mes_lote, ano_lote = "", ""
            if os.path.exists(caminho_pdfs):
                pdfs = [f for f in os.listdir(caminho_pdfs) if f.endswith('.pdf')]
                if pdfs:
                    padrao = re.search(r'(\d{2})[_\-](\d{4})\.pdf$', pdfs[0])
                    if padrao:
                        mes_lote = padrao.group(1)
                        ano_lote = padrao.group(2)
            if not mes_lote or not ano_lote:
                print("\n⚠️ Não consegui identificar o mês/ano dessa pasta automatically.")
                entrada = input("👉 Por favor, digite manualmente no formato MM-AAAA (ex: 03-2026): ")
                try:
                    mes_lote, ano_lote = entrada.split('-')
                    mes_lote = mes_lote.strip()
                    ano_lote = ano_lote.strip()
                except:
                    print("❌ Erro de formato. Cancelado.")
                    return

            codigo_robo_final = CODIGO_ROBO_DISPARO.replace("{ano_competencia}", ano_lote).replace("{mes_competencia}", mes_lote).replace("{tipo_documento}", tipo_documento)
            with open(os.path.join(pasta_escolhida, "2_Enviar_WhatsApp.py"), "w", encoding="utf-8") as f:
                f.write(codigo_robo_final)

            print(f"\n✅ SUCESSO! A pasta '{pasta_escolhida}' foi atualizada.")
            input("\nPressione ENTER para sair...")
            return

        except (ValueError, IndexError):
            print("\n❌ Opção inválida. Operação cancelada.")
            input("Pressione ENTER para sair...")
            return

    elif opcao_modo == '2':
        pastas_lote = [d for d in os.listdir('.') if os.path.isdir(d) and d.startswith('Lote_')]
        pastas_lote.sort(reverse=True)
        if not pastas_lote:
            print("\n❌ Nenhuma pasta de Lote encontrada no diretório.")
            input("Pressione ENTER para sair...")
            return
        print("\n📂 Pastas de Lotes Anteriores encontradas:")
        for i, p in enumerate(pastas_lote): print(f"[{i+1}] {p}")

        idx = input("\n👉 Digite o número da pasta que tem o relatório antigo: ").strip()
        try:
            pasta_escolhida = pastas_lote[int(idx)-1]
            caminho_relatorio_antigo = os.path.join(pasta_escolhida, "Relatorio_Mapeamento.xlsx")

            if not os.path.exists(caminho_relatorio_antigo):
                print(f"\n❌ O arquivo não existe: {caminho_relatorio_antigo}")
                input("Pressione ENTER para sair...")
                return

            print(f"\n📖 Lendo o relatório antigo: {caminho_relatorio_antigo}...")

            print("🔐 Conectando ao Google Drive para a Prova Real...")
            servico_fase1 = autenticar_drive_fase1()
            print("🕵️ Auditando arquivos diretamente no Drive (Isso evita reenvios desnecessários)...")

            arquivos_com_falha = []
            caminho_falhas = os.path.join(pasta_escolhida, "falhas_envio.txt")
            if os.path.exists(caminho_falhas):
                with open(caminho_falhas, "r", encoding="utf-8") as f_falhas:
                    for linha_falha in f_falhas:
                        if linha_falha.strip(): arquivos_com_falha.append(linha_falha.strip())

            chaves_pendentes = []
            df_list_antigo = []
            try: df_list_antigo.append(pd.read_excel(caminho_relatorio_antigo, sheet_name="Prontos para Envio", dtype=str))
            except: pass
            try: df_list_antigo.append(pd.read_excel(caminho_relatorio_antigo, sheet_name="Ex-Funcionarios", dtype=str))
            except: pass

            if df_list_antigo:
                df_antigo = pd.concat(df_list_antigo, ignore_index=True)
                for _, linha in df_antigo.iterrows():
                    wpp = str(linha.get('WhatsApp', '')).strip().lower()
                    tipo = str(linha.get('Tipo', 'Ativo'))
                    arq_gerado = str(linha.get('Arquivo Gerado', ''))
                    pasta_local = str(linha.get('Pasta Local', 'PDFs_Separados'))

                    cpf_limpo = re.sub(r'\D', '', str(linha.get('CPF Completo', ''))).zfill(11)
                    chave = cpf_limpo if tipo == 'Ativo' else str(linha.get('Nome', ''))

                    # 1. Ativos sem WhatsApp na planilha original
                    falta_numero = (tipo == 'Ativo' and wpp in ['nan', 'none', '', 'null', '<na>'])

                    # 2. Arquivo listado explicitamente no falhas_envio.txt
                    falhou_registro = arq_gerado in arquivos_com_falha

                    # 3. Falta do arquivo físico de comprovante na pasta antiga (Local)
                    faltou_comprovante_local = False
                    if tipo == 'Ativo':
                        nome_log = f"COMPROVANTE - {arq_gerado.replace('.pdf', '.txt')}"
                        caminho_comprovante = os.path.join(pasta_escolhida, pasta_local, nome_log)
                        if not os.path.exists(caminho_comprovante):
                            faltou_comprovante_local = True
                    else:
                        caminho_suc_ex = os.path.join(pasta_escolhida, pasta_local, "uploads_concluidos.txt")
                        achou_ex = False
                        if os.path.exists(caminho_suc_ex):
                            try:
                                with open(caminho_suc_ex, "r", encoding="utf-8") as f_ex:
                                    if arq_gerado in f_ex.read():
                                        achou_ex = True
                            except: pass
                        if not achou_ex:
                            faltou_comprovante_local = True

                    # Se localmente parece que falhou, tira a "Prova Real" no Drive
                    if falta_numero or falhou_registro or faltou_comprovante_local:
                        ja_esta_no_drive = False

                        if servico_fase1 and arq_gerado and str(arq_gerado) != 'nan':
                            nome_busca = f"COMPROVANTE - {arq_gerado.replace('.pdf', '.txt')}" if tipo == 'Ativo' else arq_gerado
                            nome_busca_escaped = nome_busca.replace("'", "\\'")

                            try:
                                nome_busca_sem_acento = ''.join(c for c in unicodedata.normalize('NFD', nome_busca) if unicodedata.category(c) != 'Mn').replace("'", "\\'")
                                query_drive = f"(name='{nome_busca_escaped}' or name='{nome_busca_sem_acento}') and trashed=false"
                                res_drive = servico_fase1.files().list(q=query_drive, spaces='drive', fields='files(id)', supportsAllDrives=True, includeItemsFromAllDrives=True).execute()
                                if res_drive.get('files', []):
                                    ja_esta_no_drive = True
                            except:
                                pass

                        if not ja_esta_no_drive:
                            chaves_pendentes.append(chave)
                        else:
                            print(f"   ✅ {linha.get('Nome', 'Funcionário')} já possui comprovante no Drive. Ignorando.")

            chaves_pendentes = list(set(chaves_pendentes))
            if not chaves_pendentes:
                print("\n✅ Incrível! Todos os funcionários desse lote já tinham WhatsApp e foram enviados.")
                input("Pressione ENTER para sair...")
                return

            print(f"🎯 Foi identificado que {len(chaves_pendentes)} pessoas ficaram pendentes ou falharam.")
            print("O robô vai vasculhar o PDF gigante e extrair APENAS essas pessoas!\n")

        except (ValueError, IndexError):
            print("\n❌ Opção inválida. Operação cancelada.")
            input("Pressione ENTER para sair...")
            return

    url_google_sheets = "https://docs.google.com/spreadsheets/d/1wJJu3N-lehjZaQw2JtfWLXdss6YbVP1JbfveDzWkGRg/export?format=csv"

    arquivos_locais = [f for f in os.listdir('.') if os.path.isfile(f) and f.lower().endswith('.pdf')]
    if not arquivos_locais:
        print("❌ Erro: Nenhum PDF encontrado na pasta!")
        print("Coloque o PDF com todas as páginas aqui e rode novamente.")
        input("Pressione ENTER para sair...")
        return

    arquivo_pdf_gigante = None
    palavra_chave = tipo_documento.split()[0].lower()
    pdfs_sugeridos = [f for f in arquivos_locais if palavra_chave in f.lower()]

    if len(pdfs_sugeridos) == 1: arquivo_pdf_gigante = pdfs_sugeridos[0]
    elif len(arquivos_locais) == 1: arquivo_pdf_gigante = arquivos_locais[0]
    else:
        print(f"📄 Encontrei {len(arquivos_locais)} arquivos PDF na pasta. Qual deles contém os {tipo_documento}s?")
        for i, pdf in enumerate(arquivos_locais): print(f"[{i+1}] {pdf}")
        idx_pdf = input("👉 Digite o número correspondente: ").strip()
        try: arquivo_pdf_gigante = arquivos_locais[int(idx_pdf)-1]
        except:
            print("❌ Opção inválida. Operação cancelada.")
            input("Pressione ENTER para sair...")
            return

    print(f"\n📄 Arquivo base selecionado para processamento: {arquivo_pdf_gigante}")

    mes_lote = ""
    ano_lote = ""

    padrao_data = re.search(r'(\d{2})[_\-](\d{4})', arquivo_pdf_gigante)
    padrao_ano = re.search(r'(20\d{2})', arquivo_pdf_gigante)

    if padrao_data:
        mes_lote = padrao_data.group(1)
        ano_lote = padrao_data.group(2)
        print(f"📅 Competência identificada automaticamente: Mês {mes_lote} | Ano {ano_lote}\n")
    elif padrao_ano and tipo_documento == "INFORME DE RENDIMENTOS":
        ano_lote = padrao_ano.group(1)
        mes_lote = "ANUAL"
        print(f"📅 Competência identificada automaticamente: {mes_lote} | Ano {ano_lote}\n")
    else:
        print("\n⚠️ Aviso: Não consegui identificar a data no nome do arquivo PDF.")
        if tipo_documento == "INFORME DE RENDIMENTOS":
            entrada = input("👉 Por favor, digite o ANO (ex: 2025): ").strip()
            ano_lote = entrada
            mes_lote = "ANUAL"
        else:
            entrada = input("👉 Por favor, digite manualmente no formato MM-AAAA (ex: 03-2026): ").strip()
            try:
                mes_lote, ano_lote = entrada.split('-')
                mes_lote = mes_lote.strip()
                ano_lote = ano_lote.strip()
            except:
                print("❌ Erro de formato. O arquivo ficará sem data no nome.")

    prefixo_pasta = "Lote_Envio_" if tipo_documento == "HOLERITE" else "Lote_Informes_"
    nome_pasta_lote = datetime.now().strftime(f"{prefixo_pasta}%d-%m-%Y_%Hh%M")

    pasta_pdfs_separados = os.path.join(nome_pasta_lote, "PDFs_Separados")
    pasta_pdfs_ex = os.path.join(nome_pasta_lote, "PDFs_Ex_Funcionarios")
    pasta_sem_dono = os.path.join(nome_pasta_lote, "PDFs_Sem_Dono")

    os.makedirs(pasta_pdfs_separados, exist_ok=True)
    # AS PASTAS ABAIXO SÓ SERÃO CRIADAS SE FOREM NECESSÁRIAS DURANTE O LOOP!
    # os.makedirs(pasta_pdfs_ex, exist_ok=True)
    # os.makedirs(pasta_sem_dono, exist_ok=True)
    print(f"📁 Pasta de Lote criada: {nome_pasta_lote}\n")

    # Mapear Ex-Funcionários do Drive ANTES de fatiar o PDF
    # Se o serviço já foi iniciado na Prova Real, não precisa autenticar de novo
    if 'servico_fase1' not in locals() or not servico_fase1:
        servico_fase1 = autenticar_drive_fase1()

    pastas_ex_funcionarios = []
    if servico_fase1:
        pastas_ex_funcionarios = mapear_ex_funcionarios(servico_fase1, "1v2Pt5YWqnW_bWRA9R7l6OQeMM7G_Tlrm")

    print("📡 A baixar lista do Google Sheets...")
    try:
        df = pd.read_csv(url_google_sheets, dtype=str)
        df['CPF'] = df['CPF'].astype(str).str.replace(r'\.0$', '', regex=True)
        df['CPF_LIMPO'] = df['CPF'].str.replace(r'\D', '', regex=True).str.zfill(11)
    except Exception as e:
        print(f"❌ Erro ao baixar a planilha: {e}")
        input("Pressione ENTER para sair...")
        return

    print("🔍 A fatiar PDF e analisar páginas...\n")

    encontrados = []
    nao_encontrados_pdf = []
    cpfs_achados_no_pdf = []

    with pdfplumber.open(arquivo_pdf_gigante) as pdf_leitor:
        pdf_fatiador = PdfReader(arquivo_pdf_gigante)
        total_paginas = len(pdf_leitor.pages)

        for i in range(0, total_paginas, paginas_por_funcionario):
            pagina_principal = pdf_leitor.pages[i]
            texto_pagina = pagina_principal.extract_text()
            if not texto_pagina: texto_pagina = ""

            cpf_encontrado = extrair_cpf_do_texto(texto_pagina)
            texto_norm = normalizar_texto(texto_pagina)

            funcionario = pd.DataFrame()
            is_ex = False
            nome_ex_encontrado = None

            if cpf_encontrado:
                funcionario = df[df['CPF_LIMPO'] == cpf_encontrado]

            if funcionario.empty:
                for index, linha in df.iterrows():
                    nome_planilha = str(linha['Nome Completo do Funcionário'])
                    if nome_planilha != 'nan' and nome_planilha.strip() != '':
                        nome_norm = normalizar_texto(nome_planilha)
                        if nome_norm and len(nome_norm) > 5 and nome_norm in texto_norm:
                            funcionario = df.iloc[[index]]
                            cpf_encontrado = str(linha['CPF_LIMPO'])
                            break

            # SE NÃO ACHOU NOS ATIVOS, PROCURA NOS EX-FUNCIONARIOS DO DRIVE
            if funcionario.empty:
                for nome_ex in pastas_ex_funcionarios:
                    if normalizar_texto(nome_ex) in texto_norm and len(nome_ex) > 5:
                        nome_ex_encontrado = nome_ex
                        is_ex = True
                        break

            # SE REALMENTE NÃO ACHOU EM LUGAR NENHUM (SEM DONO)
            if funcionario.empty and not is_ex:
                print(f"⚠️ Pág {i + 1}: Sem correspondência na Planilha ou no Drive. A mover para 'PDFs_Sem_Dono'.")
                os.makedirs(pasta_sem_dono, exist_ok=True) # Cria só se precisar!
                nome_arquivo_sem_dono = f"{tipo_documento}_Pagina_{i + 1}_SemDono.pdf"
                caminho_salvar_sem_dono = os.path.join(pasta_sem_dono, nome_arquivo_sem_dono)

                escritor_pdf_sd = PdfWriter()
                for j in range(i, min(i + paginas_por_funcionario, total_paginas)):
                    escritor_pdf_sd.add_page(pdf_fatiador.pages[j])
                with open(caminho_salvar_sem_dono, "wb") as arquivo_saida_sd:
                    escritor_pdf_sd.write(arquivo_saida_sd)
                continue

            # --- CHEGANDO AQUI, ACHOU UM FUNCIONÁRIO (ATIVO OU EX) ---

            chave_rastreio = cpf_encontrado if not is_ex else nome_ex_encontrado

            # --- FILTRO DO MODO RECUPERAÇÃO ---
            if chaves_pendentes is not None:
                if chave_rastreio not in chaves_pendentes:
                    continue
            # ----------------------------------

            if is_ex:
                nome = nome_ex_encontrado
                whatsapp = ""
                pasta_alvo = pasta_pdfs_ex
                os.makedirs(pasta_alvo, exist_ok=True) # Cria só se precisar!
                pasta_local_relatorio = "PDFs_Ex_Funcionarios"
                tipo_func = "Ex-Funcionario"
                cpf_formatado = f"{cpf_encontrado[:3]}.{cpf_encontrado[3:6]}.{cpf_encontrado[6:9]}-{cpf_encontrado[9:]}" if cpf_encontrado else "N/A"
            else:
                nome = str(funcionario.iloc[0]['Nome Completo do Funcionário']).strip()
                telefone_bruto = funcionario.iloc[0]['WHATSAPP']
                whatsapp = formatar_numero_whatsapp(telefone_bruto)
                pasta_alvo = pasta_pdfs_separados
                pasta_local_relatorio = "PDFs_Separados"
                tipo_func = "Ativo"
                cpf_formatado = f"{cpf_encontrado[:3]}.{cpf_encontrado[3:6]}.{cpf_encontrado[6:9]}-{cpf_encontrado[9:]}"

            if mes_lote and ano_lote:
                if mes_lote == "ANUAL": nome_arquivo_pdf = f"{tipo_documento} - {nome} {ano_lote}.pdf"
                else: nome_arquivo_pdf = f"{tipo_documento} - {nome} {mes_lote}-{ano_lote}.pdf"
            else:
                nome_arquivo_pdf = f"{tipo_documento} - {nome}.pdf"

            # --- NOVA INTELIGÊNCIA: VERIFICAÇÃO DIRETA NO DRIVE (LOTE NOVO) ---
            ja_esta_no_drive = False
            if opcao_modo == '1' and servico_fase1:
                nome_busca = f"COMPROVANTE - {nome_arquivo_pdf.replace('.pdf', '.txt')}" if tipo_func == 'Ativo' else nome_arquivo_pdf
                nome_busca_escaped = nome_busca.replace("'", "\\'")
                try:
                    nome_busca_sem_acento = ''.join(c for c in unicodedata.normalize('NFD', nome_busca) if unicodedata.category(c) != 'Mn').replace("'", "\\'")
                    query_drive = f"(name='{nome_busca_escaped}' or name='{nome_busca_sem_acento}') and trashed=false"
                    res_drive = servico_fase1.files().list(q=query_drive, spaces='drive', fields='files(id)', supportsAllDrives=True, includeItemsFromAllDrives=True).execute()
                    if res_drive.get('files', []):
                        ja_esta_no_drive = True
                except:
                    pass

            if ja_esta_no_drive:
                print(f"   ⏭️  Pulado ({tipo_func}): {nome_arquivo_pdf} -> [✅ Já concluído no Drive]")
                if chave_rastreio not in cpfs_achados_no_pdf:
                    cpfs_achados_no_pdf.append(chave_rastreio)
                continue
            # ------------------------------------------------------------------

            caminho_salvar = os.path.join(pasta_alvo, nome_arquivo_pdf)

            escritor_pdf = PdfWriter()
            for j in range(i, min(i + paginas_por_funcionario, total_paginas)):
                escritor_pdf.add_page(pdf_fatiador.pages[j])

            # APLICAR SENHA AO PDF (Os 5 primeiros números do CPF)
            if cpf_encontrado and len(cpf_encontrado) >= 5:
                senha_pdf = cpf_encontrado[:5]
                escritor_pdf.encrypt(senha_pdf)

            with open(caminho_salvar, "wb") as arquivo_saida:
                escritor_pdf.write(arquivo_saida)

            # NOVA MENSAGEM COM O STATUS VISUAL DO WHATSAPP!
            if is_ex:
                wpp_status = "Ex-Funcionário"
            else:
                wpp_status = "✅ Com WhatsApp" if whatsapp else "⚠️ SEM WHATSAPP NA PLANILHA"

            print(f"✂️ Extraído e Protegido ({tipo_func}): {nome_arquivo_pdf} -> [{wpp_status}]")

            if chave_rastreio not in cpfs_achados_no_pdf:
                encontrados.append({
                    'Nome': nome,
                    'CPF Completo': cpf_formatado,
                    'WhatsApp': whatsapp,
                    'Pasta Local': pasta_local_relatorio,
                    'Tipo': tipo_func,
                    'Arquivo Gerado': nome_arquivo_pdf
                })
                cpfs_achados_no_pdf.append(chave_rastreio)

    # Identificação dos que faltaram (Apenas para Ativos)
    if chaves_pendentes is None:
        for index, linha in df.iterrows():
            cpf_planilha = str(linha['CPF_LIMPO'])
            if cpf_planilha not in cpfs_achados_no_pdf and cpf_planilha != '00000000000':
                cpf_p_formatado = f"{cpf_planilha[:3]}.{cpf_planilha[3:6]}.{cpf_planilha[6:9]}-{cpf_planilha[9:]}"
                nao_encontrados_pdf.append({
                    'Nome': str(linha['Nome Completo do Funcionário']),
                    'CPF Completo': cpf_p_formatado,
                    'Motivo': f'{tipo_documento} não estava dentro do PDF gigante'
                })
    else:
        for chave_p in chaves_pendentes:
            if chave_p not in cpfs_achados_no_pdf:
                nao_encontrados_pdf.append({
                    'Nome': 'Pendente não identificado',
                    'CPF Completo': chave_p,
                    'Motivo': 'Não encontrado no PDF nesta rodada de recuperação'
                })

    caminho_excel = os.path.join(nome_pasta_lote, "Relatorio_Mapeamento.xlsx")
    df_todos_encontrados = pd.DataFrame(encontrados)

    with pd.ExcelWriter(caminho_excel, engine='openpyxl') as writer:
        if not df_todos_encontrados.empty:
            df_ativos = df_todos_encontrados[df_todos_encontrados['Tipo'] == 'Ativo']
            df_ex = df_todos_encontrados[df_todos_encontrados['Tipo'] == 'Ex-Funcionario']

            if not df_ativos.empty: df_ativos.to_excel(writer, sheet_name='Prontos para Envio', index=False)
            else: pd.DataFrame(columns=['Nome', 'CPF Completo', 'WhatsApp', 'Pasta Local', 'Tipo', 'Arquivo Gerado']).to_excel(writer, sheet_name='Prontos para Envio', index=False)

            if not df_ex.empty: df_ex.to_excel(writer, sheet_name='Ex-Funcionarios', index=False)
        else:
            pd.DataFrame(columns=['Nome', 'CPF Completo', 'WhatsApp', 'Pasta Local', 'Tipo', 'Arquivo Gerado']).to_excel(writer, sheet_name='Prontos para Envio', index=False)

        if nao_encontrados_pdf:
            pd.DataFrame(nao_encontrados_pdf).to_excel(writer, sheet_name='Nao Encontrados', index=False)

    codigo_robo_final = CODIGO_ROBO_DISPARO.replace("{ano_competencia}", ano_lote).replace("{mes_competencia}", mes_lote).replace("{tipo_documento}", tipo_documento)

    with open(os.path.join(nome_pasta_lote, "2_Enviar_WhatsApp.py"), "w", encoding="utf-8") as f:
        f.write(codigo_robo_final)

    with open(os.path.join(nome_pasta_lote, "Disparar_Holerites.bat"), "w", encoding="utf-8") as f:
        f.write(CODIGO_BAT_DISPARO)

    print("\n✅ PREPARAÇÃO CONCLUÍDA!")
    input("Pressione ENTER para fechar...")

if __name__ == "__main__":
    preparar_lote()
