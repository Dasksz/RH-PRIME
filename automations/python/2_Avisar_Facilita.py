"""Etapa 2: avisos de assinatura. Não envia PDFs nem acessa o Drive."""
import hashlib
import json
import os
from pathlib import Path
import random
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
    return (f'Olá, {nome}!\n\nAqui é do RH. Seus documentos de {tipo}, referentes a '
            f'{referencia}, estão disponíveis no Facilita Ponto para visualização e assinatura.\n\n'
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
        if 200 <= response.status_code < 300:
            try:
                body = response.json()
            except ValueError:
                body = None
            if isinstance(body, dict) and (body.get('error') or body.get('accepted') is False):
                return 'uncertain'
            state[key]['status'] = 'accepted'
            salvar_estado(log_path, state)
            return 'accepted'
    except requests.RequestException:
        pass
    return 'uncertain'


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
    url = os.environ.get('N8N_RH_WEBHOOK_URL', '').strip() or input('URL do webhook n8n RH usado na etapa anterior: ').strip()
    if not re.fullmatch(r'https?://[^\s?#]+/webhook/[A-Za-z0-9_-]+', url):
        raise ValueError('URL de webhook inválida.')
    for index, person in enumerate(selected):
        result = enviar_aviso(person, url, log_path, state)
        print(person['nome'] + ': ' + result)
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
