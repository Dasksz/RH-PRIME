"""Etapa 2: arquivamento no Drive e avisos de assinatura no WhatsApp."""
from contextlib import contextmanager
import hashlib
from io import BytesIO
import json
import os
from pathlib import Path
import random
import socket
from urllib.parse import urlsplit
import re
import time
import unicodedata
from datetime import datetime, timezone
import pandas as pd
import requests

PORTAL = 'https://sistema.facilitaponto.com.br/portal'
EMPRESA = '032612'
TIPO_DOCUMENTO = '{tipo_documento}'
MES = '{mes_competencia}'
ANO = '{ano_competencia}'
PASTA_ATIVOS = '195JwYHEJdRY1u5DEL7tB7dSHn16DRVb4'
PASTA_EX = '1v2Pt5YWqnW_bWRA9R7l6OQeMM7G_Tlrm'
MIME_PASTA = 'application/vnd.google-apps.folder'


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


def preparar_avisos(frame, root, tipo, referencia, para_drive=False):
    """Agrupa PDFs por CPF. Avisos exigem vínculo ativo e WhatsApp válido."""
    people, errors, blocked = {}, [], set()
    root = Path(root).resolve()
    for _, row in frame.fillna('').iterrows():
        vinculo = row.get('Tipo', 'Ativo')
        if vinculo != 'Ativo' and not (para_drive and vinculo == 'Ex-Funcionario'):
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
            nome = str(row.get('Nome', '')).strip()
            phone = '' if para_drive else telefone(row.get('WhatsApp', ''))
            if para_drive:
                validar_nome_pdf(filename, nome, cpf, tipo, referencia)
            person = people.setdefault(cpf, {'cpf': cpf, 'nome': nome, 'vinculo': vinculo,
                                            'phone': phone, 'files': [], 'paths': {}})
            if person['phone'] != phone:
                raise ValueError('Telefones divergentes para o mesmo CPF.')
            if para_drive and (normalizar(person['nome']) != normalizar(nome) or person['vinculo'] != vinculo):
                raise ValueError('Nome ou vínculo divergente para o mesmo CPF.')
            file_key = (filename, hashlib.sha256(path.read_bytes()).hexdigest())
            person['files'].append(file_key)
            person['paths'][file_key] = path
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


def normalizar(value):
    value = unicodedata.normalize('NFKD', value).upper()
    value = ''.join(c for c in value if not unicodedata.combining(c))
    return ' '.join(re.findall(r'[A-Z0-9]+', value))


def categoria_drive(tipo):
    return 'HOLERITE' if normalizar(tipo) in ('HOLERITE', 'HOLERITES') else tipo


def validar_nome_pdf(filename, nome, cpf, tipo, referencia):
    if not normalizar(nome):
        raise ValueError('Nome ausente no relatório.')
    prefix = re.match(r'^(\d{11})\s*-\s*', filename)
    if prefix and prefix[1] != cpf:
        raise ValueError('O CPF no nome do PDF não confere com o relatório.')
    stem = Path(filename[prefix.end():] if prefix else filename).stem
    expected = {normalizar(f'{tipo} - {nome} {referencia}')}
    if categoria_drive(tipo) == 'HOLERITE':
        expected.update(normalizar(value) for value in (
            f'HOLERITE - {nome} {referencia}', f'{nome} HOLERITES {referencia}',
            f'HOLERITES - {nome} {referencia}',
        ))
    if normalizar(stem) not in expected:
        raise ValueError('Confira o tipo, o nome e a competência indicados no PDF.')


def autenticar_drive(root):
    from google.auth.transport.requests import Request
    from google.oauth2.credentials import Credentials
    from google_auth_oauthlib.flow import InstalledAppFlow
    from googleapiclient.discovery import build

    scope = ['https://www.googleapis.com/auth/drive']
    locations = (root, root.parent)
    token = next((p / 'token.json' for p in locations if (p / 'token.json').is_file()), None)
    creds = Credentials.from_authorized_user_file(str(token), scope) if token else None
    if not creds or not creds.valid:
        if creds and creds.refresh_token:
            try:
                creds.refresh(Request())
            except Exception:
                creds = None
        if not creds or not creds.valid:
            config = next((p / 'credenciais_drive.json' for p in locations
                           if (p / 'credenciais_drive.json').is_file()), None)
            if config is None:
                raise ValueError('Coloque credenciais_drive.json na pasta do lote ou na pasta do preparador.')
            creds = InstalledAppFlow.from_client_secrets_file(str(config), scope).run_local_server(port=0)
            token = token or config.with_name('token.json')
        salvar_estado(token, json.loads(creds.to_json()))
    return build('drive', 'v3', credentials=creds, cache_discovery=False)


def listar_drive(servico, parent, apenas_pastas=False):
    query = f"'{parent}' in parents and trashed = false"
    if apenas_pastas:
        query += f" and mimeType = '{MIME_PASTA}'"
    page = None
    while True:
        result = servico.files().list(q=query, fields='nextPageToken,files(id,name,mimeType,sha256Checksum)',
                                      pageSize=1000, pageToken=page, supportsAllDrives=True,
                                      includeItemsFromAllDrives=True).execute()
        yield from result.get('files', [])
        page = result.get('nextPageToken')
        if not page:
            return


def pasta_colaborador(pastas, person):
    matches = []
    for pasta in pastas:
        ids = re.findall(r'(?<!\d)\d{3}\.?\d{3}\.?\d{3}-?\d{2}(?!\d)', pasta['name'])
        nome = pasta['name'].replace(ids[0], '', 1) if len(ids) == 1 else pasta['name']
        if normalizar(nome) != normalizar(person['nome']):
            continue
        if not ids or re.sub(r'\D', '', ids[0]) == person['cpf']:
            matches.append(pasta)
    if len(matches) > 1:
        raise ValueError('Há mais de uma pasta correspondente ao colaborador. Confira no Drive.')
    return matches[0]['id'] if matches else None


def subpasta_drive(servico, parent, name, aliases=()):
    folders = list(listar_drive(servico, parent, apenas_pastas=True))
    names = {normalizar(value) for value in (name, *aliases)}
    matches = [folder for folder in folders if normalizar(folder['name']) in names]
    if len(matches) > 1:
        raise ValueError(f'Pastas duplicadas para {name}. Confira no Drive.')
    if matches:
        return matches[0]['id']
    return servico.files().create(body={'name': name, 'mimeType': MIME_PASTA, 'parents': [parent]},
                                  fields='id', supportsAllDrives=True).execute()['id']


def arquivar_pdf(servico, parent, filename, digest, path):
    from googleapiclient.http import MediaIoBaseUpload

    files = list(listar_drive(servico, parent))
    if any(f.get('mimeType') == 'application/pdf' and f.get('sha256Checksum') == digest for f in files):
        return 'já arquivado'
    same_name = [f for f in files if f['name'].casefold() == filename.casefold()]
    if len(same_name) == 1 and same_name[0].get('mimeType') == 'application/pdf' and not same_name[0].get('sha256Checksum'):
        original = servico.files().get_media(fileId=same_name[0]['id'], supportsAllDrives=True).execute()
        if hashlib.sha256(original).hexdigest() == digest:
            return 'já arquivado'
    if same_name:
        raise ValueError('Já existe um arquivo com esse nome e conteúdo diferente ou não verificado.')
    content = path.read_bytes()
    if hashlib.sha256(content).hexdigest() != digest or not content.startswith(b'%PDF-'):
        raise ValueError('O PDF local mudou ou não é válido.')
    media = MediaIoBaseUpload(BytesIO(content), mimetype='application/pdf', resumable=True)
    result = servico.files().create(body={'name': filename, 'parents': [parent]}, media_body=media,
                                    fields='id,parents,sha256Checksum', supportsAllDrives=True).execute()
    remote_digest = result.get('sha256Checksum')
    if not remote_digest and result.get('id'):
        uploaded = servico.files().get_media(fileId=result['id'], supportsAllDrives=True).execute()
        remote_digest = hashlib.sha256(uploaded).hexdigest()
    if parent not in result.get('parents', []) or remote_digest != digest:
        raise ValueError('O Drive não confirmou o destino e o conteúdo do PDF.')
    return 'arquivado'


def arquivar_lote(servico, people, tipo, referencia):
    from googleapiclient.errors import HttpError

    month, _, year = referencia.rpartition('/')
    category = categoria_drive(tipo)
    roots = {'Ativo': (PASTA_ATIVOS, 'ATIVOS'), 'Ex-Funcionario': (PASTA_EX, 'EX-FUNCIONARIOS')}
    folders, seen, archived = {}, {}, set()
    for person in people:
        key = (person['vinculo'], normalizar(person['nome']))
        seen[key] = seen.get(key, 0) + 1
    for person in people:
        try:
            key = (person['vinculo'], normalizar(person['nome']))
            if seen[key] > 1:
                raise ValueError('Há colaboradores com o mesmo nome no lote. Confira as pastas.')
            vinculo = person['vinculo']
            outro_vinculo = 'Ex-Funcionario' if vinculo == 'Ativo' else 'Ativo'
            for busca in (vinculo, outro_vinculo):
                if busca != vinculo and (busca, key[1]) in seen:
                    raise ValueError('Há um homônimo no outro grupo do lote. Confira a pasta antes de arquivar.')
                base, root_name = roots[busca]
                if base not in folders:
                    folders[base] = list(listar_drive(servico, base, apenas_pastas=True))
                target = pasta_colaborador(folders[base], person)
                if target:
                    if busca != vinculo:
                        print(f'{person["nome"]} · pasta localizada em {root_name}.')
                    break
            else:
                raise ValueError('Nenhuma pasta correspondente em ATIVOS ou EX-FUNCIONARIOS.')
            if category == 'FOLHA DE PONTO':
                target = subpasta_drive(servico, target, 'JORNADA E SEGURANÇA')
            aliases = ('HOLERITES',) if category == 'HOLERITE' else ()
            target = subpasta_drive(servico, target, category, aliases)
            target = subpasta_drive(servico, target, year)
            target = subpasta_drive(servico, target, f'{month or "ANUAL"}.{year}', (month,) if month else ())
            for (filename, digest), path in person['paths'].items():
                status = arquivar_pdf(servico, target, filename, digest, path)
                print(f'{person["nome"]} · Drive: {status}.')
            archived.add(person['id'])
        except (ValueError, OSError, HttpError) as error:
            detail = f'Google Drive respondeu HTTP {error.resp.status}.' if isinstance(error, HttpError) else str(error)
            print(f'REVISAR DRIVE · {person["nome"]}: {detail}')
    return archived


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


@contextmanager
def trava_lote(root):
    with (root / '.processamento_lote.lock').open('a+b') as lock:
        try:
            if os.name == 'nt':
                import msvcrt
                lock.seek(0)
                msvcrt.locking(lock.fileno(), msvcrt.LK_NBLCK, 1)
            else:
                import fcntl
                fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except OSError as error:
            raise ValueError('Este lote já está sendo processado em outra janela.') from error
        yield


def processar_lote(root):
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
    print('\n[A] Avisar pelo WhatsApp\n[B] Arquivar PDFs no Google Drive\n[C] Arquivar e avisar')
    modo = input('Escolha A, B ou C (Enter = A): ').strip().upper() or 'A'
    if modo not in ('A', 'B', 'C'):
        raise ValueError('Escolha A, B ou C.')
    if modo in ('B', 'C'):
        with pd.ExcelFile(report) as workbook:
            archive_frame = frame
            if 'Ex-Funcionarios' in workbook.sheet_names:
                former = pd.read_excel(workbook, sheet_name='Ex-Funcionarios', dtype=str)
                former['Tipo'] = 'Ex-Funcionario'
                archive_frame = pd.concat([frame, former], ignore_index=True)
        documents, errors = preparar_avisos(archive_frame, root, tipo, referencia, para_drive=True)
        for error in errors:
            print('REVISAR DRIVE: ' + error)
        archived = arquivar_lote(autenticar_drive(root), documents, tipo, referencia) if documents else set()
        print(f'{len(archived)} de {len(documents)} colaboradores com arquivamento confirmado.')
        if modo == 'B':
            return
    people, errors = preparar_avisos(frame, root, tipo, referencia)
    for error in errors:
        print('REVISAR: ' + error)
    log_path = root / 'avisos_facilita.json'
    state = json.loads(log_path.read_text(encoding='utf-8')) if log_path.exists() else {}
    selected = [p for p in people if p['id'] not in state]
    already_notified = len(people) - len(selected)
    if modo == 'C':
        blocked = [p for p in selected if p['id'] not in archived]
        for person in blocked:
            print(f'REVISAR: {person["nome"]} aguarda confirmação do arquivamento antes do aviso.')
        selected = [p for p in selected if p['id'] in archived]
    print(f'\n{len(selected)} colaboradores com PDF gerado aguardam aviso. '
          f'{already_notified} já constam no histórico de avisos.')
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
    url = os.environ.get('N8N_RH_WEBHOOK_URL', '').strip() or input('URL do webhook n8n RH usado na etapa anterior: ').strip()
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


def iniciar_envio():
    root = Path.cwd()
    with trava_lote(root):
        processar_lote(root)


if __name__ == '__main__':
    try:
        iniciar_envio()
    except (ValueError, OSError, KeyError, ImportError) as error:
        print('Não foi possível processar o lote: ' + str(error))
    input('Pressione ENTER para fechar...')
