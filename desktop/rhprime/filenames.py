"""Nomes de documentos: CPF-TIPO - NOME MM-AAAA.pdf."""
import re
import unicodedata
from .identity import digits, ReviewRequired


def safe_label(value):
    value = unicodedata.normalize('NFC', str(value or '')).upper()
    value = re.sub(r'[^\w .-]', '_', value)
    return ' '.join(value.split()).strip(' .')[:100].strip(' .')


def document_context(document_type, period):
    kind = safe_label(document_type)
    kind = {'HOLERITES': 'HOLERITE', 'RECIBOS': 'RECIBO'}.get(kind, kind)
    period = str(period or '').strip()
    if not kind:
        raise ReviewRequired('Informe o tipo do documento.')
    if not re.fullmatch(r'(?:0[1-9]|1[0-2])[/\-][0-9]{4}|[0-9]{4}', period):
        raise ReviewRequired('Informe a competência em MM/AAAA ou AAAA para documentos anuais.')
    return kind, period.replace('/', '-')


def document_filename(employee, document_type, period):
    kind, period = document_context(document_type, period)
    cpf = digits(employee.get('cpf'))
    if not re.fullmatch(r'[0-9]{11}', cpf) or len(set(cpf)) == 1:
        raise ReviewRequired('CPF ausente ou inválido no cadastro. Corrija antes de salvar o documento definitivo.')
    name = safe_label(employee.get('nome'))
    if not name:
        raise ReviewRequired('Nome ausente no cadastro.')
    return f'{cpf}-{kind} - {name} {period}.pdf'
