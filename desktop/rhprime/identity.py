"""Identificação determinística; ambiguidades nunca escolhem o primeiro registro."""
import re
import unicodedata
from string import Formatter

class ReviewRequired(ValueError):
    pass

def digits(value):
    return re.sub(r'\D', '', str(value or ''))

def normalize(value):
    text = unicodedata.normalize('NFKD', str(value or ''))
    return ' '.join(re.sub(r'[^A-Z0-9 ]', ' ', ''.join(c for c in text if not unicodedata.combining(c)).upper()).split())

def valid_cpf(value):
    cpf = digits(value)
    if len(cpf) != 11 or len(set(cpf)) == 1:
        return False
    for size in (9, 10):
        digit = (sum(int(cpf[i]) * (size + 1 - i) for i in range(size)) * 10) % 11
        if int(cpf[size]) != (0 if digit == 10 else digit):
            return False
    return True

def folder_identity(name):
    matches = re.findall(r'(?<!\d)\d{3}\.?\d{3}\.?\d{3}-?\d{2}(?!\d)', name)
    cpf = digits(matches[-1]) if matches else ''
    for part in matches:
        name = name.replace(part, '')
    return normalize(name), cpf

def select_folder(folders, employee):
    linked = employee.get('drive_folder_id')
    if linked:
        matches = [f for f in folders if f['id'] == linked]
        if len(matches) != 1:
            raise ReviewRequired('A pasta vinculada não está nas raízes autorizadas. Revise o vínculo.')
        return matches[0]
    marked = [f for f in folders if f.get('appProperties', {}).get('rh_employee_id') == employee['id']]
    if len(marked) == 1:
        return marked[0]
    if len(marked) > 1:
        raise ReviewRequired('Mais de uma pasta possui o mesmo vínculo.')
    cpf = digits(employee.get('cpf'))
    found = []
    for f in folders:
        owner = f.get('appProperties', {}).get('rh_employee_id')
        if owner and owner != employee['id']:
            continue
        name, folder_cpf = folder_identity(f['name'])
        if folder_cpf and cpf and folder_cpf != cpf:
            continue
        if (cpf and folder_cpf == cpf) or name == normalize(employee['nome']):
            found.append(f)
    if len(found) > 1:
        raise ReviewRequired('Pastas homônimas ou duplicadas. Vincule o ID correto antes de continuar.')
    return found[0] if found else None

def identify_text(text, employees):
    cpfs = {digits(v) for v in re.findall(r'(?<!\d)\d{3}\.?\d{3}\.?\d{3}-?\d{2}(?!\d)', text)}
    cpfs = {v for v in cpfs if valid_cpf(v)}
    if cpfs:
        matches = [e for e in employees if digits(e.get('cpf')) in cpfs]
        if len(matches) == 1:
            return matches[0]
        raise ReviewRequired('CPF sem cadastro único ou múltiplos colaboradores no documento.')
    normalized = ' ' + normalize(text) + ' '
    matches = [e for e in employees if len(normalize(e['nome'])) > 5 and ' ' + normalize(e['nome']) + ' ' in normalized]
    if len(matches) != 1:
        raise ReviewRequired('Nome ausente ou ambíguo. Revise a identificação.')
    return matches[0]

def phone_number(value):
    value = digits(value)
    if len(value) in (10, 11):
        value = '55' + value
    if not re.fullmatch(r'55[1-9]\d\d{8,9}', value):
        raise ReviewRequired('WhatsApp inválido. Corrija o cadastro; nenhum dígito será inventado.')
    return value

def render_message(template, values):
    for _, field, spec, conversion in Formatter().parse(template):
        if field is not None and (field not in {'nome', 'tipo', 'competencia', 'link'} or spec or conversion):
            raise ReviewRequired('Variável de mensagem não permitida.')
    result = template.format(**values).strip()
    if not result or len(result) > 8000:
        raise ReviewRequired('Mensagem vazia ou longa demais.')
    return result
