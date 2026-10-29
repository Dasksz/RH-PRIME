import os
import re
import time
import pandas as pd
import unicodedata
from datetime import datetime

try:
    import pdfplumber
    import pytesseract
    from PyPDF2 import PdfWriter, PdfReader

    # Auto-configuração do Tesseract no Windows caso não esteja no PATH
    if os.name == 'nt':
        tesseract_padrao = r'C:\Program Files\Tesseract-OCR\tesseract.exe'
        if os.path.exists(tesseract_padrao):
            pytesseract.pytesseract.tesseract_cmd = tesseract_padrao

    from google.oauth2.credentials import Credentials
    from google_auth_oauthlib.flow import InstalledAppFlow
    from google.auth.transport.requests import Request
    from googleapiclient.discovery import build
except ImportError:
    print("❌ Erro: Bibliotecas ausentes. Abra o CMD e digite:")
    print("pip install pdfplumber PyPDF2 pandas requests openpyxl pytesseract")
    print("⚠️ ATENÇÃO: Para leitura de PDFs como imagem (OCR), você também precisa instalar o Tesseract-OCR no Windows.")
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
CODIGO_ROBO_DISPARO = r'''
"""Etapa 2: avisos de assinatura. Não envia PDFs nem acessa o Drive."""
import hashlib
import json
import os
from pathlib import Path
import random
import socket
from urllib.parse import urlsplit
import re
import time
from datetime import datetime, timezone
import pandas as pd
import requests

PORTAL = 'https://sistema.facilitaponto.com.br/portal'
EMPRESA = '032612'
TIPO_DOCUMENTO = '{tipo_documento}'
MES = '{mes_competencia}'
ANO = '{ano_competencia}'


def telefone(value):
    value = re.sub(r'@(?:c\.us|s\.whatsapp\.net)$', '', str(value or '').strip())
    value = re.sub(r'\D', '', re.sub(r'\.0$', '', value))
    if len(value) in (10, 11):
        value = '55' + value
    if not re.fullmatch(r'55[1-9]\d\d{8,9}', value):
        raise ValueError('WhatsApp inválido no relatório. Corrija antes de avisar.')
    return value + '@c.us'


def mensagem(nome, tipo, referencia):
    assunto = (f'Sua folha de ponto, referente a {referencia}, está disponível' if tipo.strip().upper() == 'FOLHA DE PONTO'
               else f'Seus documentos de {tipo}, referentes a {referencia}, estão disponíveis')
    return (f'Olá, {nome}!\n\nAqui é do RH. {assunto} no Facilita Ponto para visualização e assinatura.\n\n'
            f'Acesse o Portal do Colaborador:\n{PORTAL}\n\n'
            f'Faça login com seu CPF (somente números) e o código da empresa: {EMPRESA}.\n'
            'Após entrar, abra os documentos disponíveis e conclua a assinatura.\n\n'
            'Em caso de dificuldade, procure o RH.')


def preparar_avisos(frame, root, tipo, referencia):
    """Só inclui colaboradores ativos com PDFs gerados; um aviso por pessoa."""
    people, errors, blocked = {}, [], set()
    root = Path(root).resolve()
    for _, row in frame.fillna('').iterrows():
        if row.get('Tipo', 'Ativo') != 'Ativo':
            continue
        try:
            cpf = re.sub(r'\D', '', str(row.get('CPF Completo', '')))
            if len(cpf) != 11 or len(set(cpf)) == 1:
                raise ValueError('CPF ausente ou inválido no relatório.')
            if cpf in blocked:
                continue
            filename = str(row.get('Arquivo Gerado', ''))
            if not filename or Path(filename).name != filename or not filename.lower().endswith('.pdf'):
                raise ValueError('Nome do PDF inválido.')
            path = (root / str(row.get('Pasta Local', 'PDFs_Separados')) / filename).resolve()
            if not path.is_relative_to(root) or not path.is_file():
                raise ValueError('PDF gerado não encontrado neste lote.')
            phone = telefone(row.get('WhatsApp', ''))
            person = people.setdefault(cpf, {'cpf': cpf, 'nome': str(row.get('Nome', '')),
                                            'phone': phone, 'files': []})
            if person['phone'] != phone:
                raise ValueError('Telefones divergentes para o mesmo CPF.')
            person['files'].append((filename, hashlib.sha256(path.read_bytes()).hexdigest()))
        except ValueError as error:
            errors.append(str(row.get('Nome', '')) + ': ' + str(error))
            # Não liberar pessoa com mapeamento inconsistente.
            if 'cpf' in locals():
                people.pop(cpf, None)
                blocked.add(cpf)
    for person in people.values():
        person['message'] = mensagem(person['nome'], tipo, referencia)
        key = [EMPRESA, PORTAL, person['cpf'], tipo, referencia, sorted(set(person['files']))]
        person['id'] = hashlib.sha256(json.dumps(key, ensure_ascii=False).encode()).hexdigest()
    return list(people.values()), errors


def salvar_estado(path, state):
    temp = path.with_suffix('.tmp')
    temp.write_text(json.dumps(state, ensure_ascii=False, indent=2), encoding='utf-8')
    temp.replace(path)


def enviar_aviso(person, url, log_path, state, post=requests.post):
    """Registra antes da chamada; resultado incerto nunca é reenviado sozinho."""
    key = person['id']
    if key in state:
        return 'skipped'
    state[key] = {'status': 'uncertain', 'nome': person['nome'],
                  'at': datetime.now(timezone.utc).isoformat()}
    salvar_estado(log_path, state)
    try:
        response = post(url, json={'chatId': person['phone'], 'caption': person['message'],
                                   'session': 'default'},
                        headers={'X-Idempotency-Key': key}, timeout=40, allow_redirects=False)
        state[key]['http_status'] = response.status_code
        if 200 <= response.status_code < 300:
            try:
                body = response.json()
            except ValueError:
                body = None
            if isinstance(body, dict) and (body.get('error') or body.get('accepted') is False):
                state[key]['error'] = 'O n8n respondeu com erro.'
                salvar_estado(log_path, state)
                return 'uncertain'
            state[key]['status'] = 'accepted'
            salvar_estado(log_path, state)
            return 'accepted'
    except requests.RequestException as error:
        state[key]['error'] = type(error).__name__
    salvar_estado(log_path, state)
    return 'uncertain'


def verificar_conexao(url):
    destino = urlsplit(url)
    try:
        with socket.create_connection((destino.hostname, destino.port or (443 if destino.scheme == 'https' else 80)), timeout=5):
            pass
    except OSError as error:
        raise ValueError('Sem conexão com o servidor n8n. Conecte o Tailscale/rede privada e confira se o n8n está disponível. Nenhum novo aviso foi tentado nesta execução.') from error


def iniciar_envio():
    root = Path.cwd()
    report = root / 'Relatorio_Mapeamento.xlsx'
    if not report.is_file():
        raise ValueError('Execute esta etapa dentro da pasta do lote que contém Relatorio_Mapeamento.xlsx.')
    frame = pd.read_excel(report, sheet_name='Prontos para Envio', dtype=str).fillna('')
    tipo = TIPO_DOCUMENTO if not TIPO_DOCUMENTO.startswith('{') else input('Tipo do documento: ').strip()
    referencia = (ANO if MES == 'ANUAL' else MES + '/' + ANO)
    if '{' in referencia:
        referencia = input('Competência (MM/AAAA ou AAAA): ').strip()
    if not tipo or not re.fullmatch(r'(?:0[1-9]|1[0-2])/[0-9]{4}|[0-9]{4}', referencia):
        raise ValueError('Informe tipo e competência válidos.')
    people, errors = preparar_avisos(frame, root, tipo, referencia)
    for error in errors:
        print('REVISAR: ' + error)
    log_path = root / 'avisos_facilita.json'
    state = json.loads(log_path.read_text(encoding='utf-8')) if log_path.exists() else {}
    selected = [p for p in people if p['id'] not in state]
    print(f'\n{len(selected)} colaboradores com PDF gerado aguardam aviso. '
          f'{len(people)-len(selected)} já constam no histórico de avisos.')
    print('Aceito confirma apenas a resposta do n8n, não a entrega ou assinatura.')
    if not selected:
        return
    for person in selected:
        print(' - ' + person['nome'])
    print('\nMODELO:\n' + selected[0]['message'])
    print('\nPrimeiro carregue os PDFs no Facilita Ponto e disponibilize-os para assinatura.')
    if input('Confirma que TODOS os documentos acima já estão disponíveis e autoriza os avisos? Digite SIM: ').strip().upper() != 'SIM':
        print('Nenhuma mensagem enviada.')
        return
    url = os.environ.get('N8N_RH_WEBHOOK_URL', 'http://100.90.6.30:5679/webhook/holerites').strip() or input('URL do webhook n8n RH usado na etapa anterior: ').strip()
    if not re.fullmatch(r'https?://[^\s?#]+/webhook/[A-Za-z0-9_-]+', url):
        raise ValueError('URL de webhook inválida.')
    verificar_conexao(url)
    for index, person in enumerate(selected):
        result = enviar_aviso(person, url, log_path, state)
        print(person['nome'] + ': ' + result)
        if result == 'uncertain':
            detail = state[person['id']]
            print('Diagnóstico: HTTP ' + str(detail.get('http_status', 'sem resposta')) + ' · ' + detail.get('error', 'Resposta sem confirmação válida.'))
        if result == 'uncertain':
            print('Resultado incerto: confira o histórico do n8n. O envio foi interrompido para revisão.')
            break
        if index < len(selected)-1:
            time.sleep(random.randint(45, 90) if (index+1) % 5 == 0 else random.randint(15, 25))


if __name__ == '__main__':
    try:
        iniciar_envio()
    except (ValueError, OSError, KeyError) as error:
        print('Não foi possível iniciar os avisos: ' + str(error))
    input('Pressione ENTER para fechar...')
'''

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

    mapa_acentos = {
        'ç': 'c', 'ñ': 'n',
        'á': 'a', 'à': 'a', 'â': 'a', 'ã': 'a', 'ä': 'a',
        'é': 'e', 'è': 'e', 'ê': 'e', 'ë': 'e',
        'í': 'i', 'ì': 'i', 'î': 'i', 'ï': 'i',
        'ó': 'o', 'ò': 'o', 'ô': 'o', 'õ': 'o', 'ö': 'o',
        'ú': 'u', 'ù': 'u', 'û': 'u', 'ü': 'u'
    }
    for orig, dest in mapa_acentos.items():
        texto = texto.replace(orig, dest)

    texto = ''.join(c for c in unicodedata.normalize('NFD', texto) if unicodedata.category(c) != 'Mn')
    return " ".join(texto.split())

def comparar_nomes_flexivel(nome_busca, texto_alvo):
    if not nome_busca or not texto_alvo: return False
    n_busca = normalizar_texto(nome_busca)
    n_alvo = normalizar_texto(texto_alvo)
    n_busca = re.sub(r'[^a-z0-9]', '', n_busca)
    n_alvo = re.sub(r'[^a-z0-9]', '', n_alvo)
    return n_busca in n_alvo

def extrair_cpf_do_texto(texto):
    if not texto: return None
    padrao = re.findall(r'\d{3}\.\d{3}\.\d{3}-\d{2}', texto)
    if padrao: return padrao[0].replace('.', '').replace('-', '')
    return None

def formatar_numero_whatsapp(numero_bruto):
    texto = str(numero_bruto).strip()
    if texto.lower() in ('', 'nan', 'none'):
        return None
    texto = re.sub(r'\.0$', '', texto)
    texto = re.sub(r'@(?:c\.us|s\.whatsapp\.net)$', '', texto)
    numero = re.sub(r'\D', '', texto)
    if numero.startswith('0055') and len(numero) in (14, 15):
        numero = numero[2:]
    if numero.startswith('55') and len(numero) in (12, 13):
        numero = numero[2:]
    if len(numero) not in (10, 11) or not 11 <= int(numero[:2]) <= 99:
        return None
    assinante = numero[2:]
    # Celulares antigos: DDD + oito digitos, iniciados por 6, 7, 8 ou 9.
    if len(assinante) == 8 and assinante[0] in '6789':
        numero = numero[:2] + '9' + assinante
    return '55' + numero + '@c.us'

def preparar_lote():
    print("=========================================================")
    print("  FASE 1: PREPARADOR DE DOCUMENTOS E MAPEAMENTO DE DADOS ")
    print("=========================================================\n")

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

                    falta_numero = (tipo == 'Ativo' and wpp in ['nan', 'none', '', 'null', '<na>'])
                    falhou_registro = arq_gerado in arquivos_com_falha

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

    if tipo_documento == "HOLERITE": prefixo_pasta = "Lote_Envio_"
    elif tipo_documento == "INFORME DE RENDIMENTOS": prefixo_pasta = "Lote_Informes_"
    elif tipo_documento == "FOLHA DE PONTO": prefixo_pasta = "Lote_Pontos_"
    elif tipo_documento == "AVISO DE FÉRIAS": prefixo_pasta = "Lote_Ferias_"
    else: prefixo_pasta = "Lote_Documentos_"

    nome_pasta_lote = datetime.now().strftime(f"{prefixo_pasta}%d-%m-%Y_%Hh%M")

    pasta_pdfs_separados = os.path.join(nome_pasta_lote, "PDFs_Separados")
    pasta_pdfs_ex = os.path.join(nome_pasta_lote, "PDFs_Ex_Funcionarios")
    pasta_sem_dono = os.path.join(nome_pasta_lote, "PDFs_Sem_Dono")

    os.makedirs(pasta_pdfs_separados, exist_ok=True)
    print(f"📁 Pasta de Lote criada: {nome_pasta_lote}\n")

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

            # --- FALLBACK OCR ---
            usou_ocr = False
            # Se não encontrou o CPF e o texto parece estar vazio ou não tem sentido
            if not cpf_encontrado and len(texto_norm) < 30:
                print(f"   [Pág {i+1}] Texto não encontrado ou muito curto. Tentando ler via OCR...")
                try:
                    # Gera uma imagem em memória (requer ImageMagick/Ghostscript nativo do pdfplumber/wand)
                    imagem = pagina_principal.to_image(resolution=200).original
                    # config customizada: '--psm 6' assume um bloco unico de texto (bom para holerites)
                    # porem 'por' pode não estar instalado, entao removemos lang ou testamos
                    texto_ocr = pytesseract.image_to_string(imagem, lang='por+eng') # Remova o lang= se der erro de idioma não encontrado
                    texto_pagina = texto_ocr
                    texto_norm = normalizar_texto(texto_pagina)
                    cpf_encontrado = extrair_cpf_do_texto(texto_pagina)
                    usou_ocr = True
                except pytesseract.pytesseract.TesseractNotFoundError:
                    print(f"   ❌ ERRO OCR: Tesseract não está instalado ou configurado no PATH do Windows.")
                    print(f"   Faça o download do Tesseract e adicione às Variáveis de Ambiente.")
                except Exception as e_ocr:
                    print(f"   ❌ ERRO OCR ao processar pág {i+1}: {e_ocr}")

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
                        if nome_norm and len(nome_norm) > 5 and comparar_nomes_flexivel(nome_planilha, texto_pagina):
                            funcionario = df.iloc[[index]]
                            cpf_encontrado = str(linha['CPF_LIMPO'])
                            break

            if funcionario.empty:
                for nome_ex in pastas_ex_funcionarios:
                    if len(nome_ex) > 5 and comparar_nomes_flexivel(nome_ex, texto_pagina):
                        nome_ex_encontrado = nome_ex
                        is_ex = True
                        break

            if funcionario.empty and not is_ex:
                print(f"⚠️ Pág {i + 1}: Sem correspondência na Planilha ou no Drive. A mover para 'PDFs_Sem_Dono'.")
                os.makedirs(pasta_sem_dono, exist_ok=True)
                nome_arquivo_sem_dono = f"{tipo_documento}_Pagina_{i + 1}_SemDono.pdf"
                caminho_salvar_sem_dono = os.path.join(pasta_sem_dono, nome_arquivo_sem_dono)

                escritor_pdf_sd = PdfWriter()
                for j in range(i, min(i + paginas_por_funcionario, total_paginas)):
                    escritor_pdf_sd.add_page(pdf_fatiador.pages[j])
                with open(caminho_salvar_sem_dono, "wb") as arquivo_saida_sd:
                    escritor_pdf_sd.write(arquivo_saida_sd)
                continue

            chave_rastreio = cpf_encontrado if not is_ex else nome_ex_encontrado

            if chaves_pendentes is not None:
                if chave_rastreio not in chaves_pendentes:
                    continue

            if is_ex:
                nome = nome_ex_encontrado
                whatsapp = ""
                pasta_alvo = pasta_pdfs_ex
                os.makedirs(pasta_alvo, exist_ok=True)
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

            # Matrícula = CPF puro, sem espaços antes ou depois do hífen.
            matricula_pdf = re.sub(r'\D', '', str(cpf_encontrado or ''))
            if len(matricula_pdf) == 11:
                nome_arquivo_pdf = f"{matricula_pdf}-{nome_arquivo_pdf}"
            else:
                print(f"   ⚠️ CPF ausente: confira a matrícula do PDF de {nome}.")

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

            caminho_salvar = os.path.join(pasta_alvo, nome_arquivo_pdf)

            escritor_pdf = PdfWriter()
            for j in range(i, min(i + paginas_por_funcionario, total_paginas)):
                escritor_pdf.add_page(pdf_fatiador.pages[j])

            # PDFs do lote são salvos sem senha para importação no Facilita Ponto.

            with open(caminho_salvar, "wb") as arquivo_saida:
                escritor_pdf.write(arquivo_saida)

            if is_ex:
                wpp_status = "Ex-Funcionário"
            else:
                wpp_status = "✅ Com WhatsApp" if whatsapp else "⚠️ SEM WHATSAPP NA PLANILHA"

            print(f"✂️ Extraído sem senha ({tipo_func}): {nome_arquivo_pdf} -> [{wpp_status}]")

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
