"""Prepara PDFs localmente, sem transmitir documentos a terceiros."""
from dataclasses import dataclass, asdict
from pathlib import Path
import hashlib
import json
import re
import uuid
from pypdf import PdfReader, PdfWriter
from .identity import identify_text, ReviewRequired

@dataclass
class Document:
    id: str
    employee_id: str | None
    employee_name: str
    filename: str
    first_page: int
    last_page: int
    sha256: str
    status: str
    reason: str = ''

def prepare_batch(source, employees, output_root, pages_per_document=1, extract_text=None):
    if not isinstance(pages_per_document, int) or pages_per_document < 1:
        raise ValueError('Informe um número inteiro positivo de páginas por documento.')
    reader = PdfReader(source)
    if reader.is_encrypted:
        raise ReviewRequired('Desbloqueie o PDF de origem antes de preparar o lote.')
    if not reader.pages or len(reader.pages) % pages_per_document:
        raise ReviewRequired('O total de páginas não corresponde ao agrupamento. Revise antes de separar.')
    output = Path(output_root) / str(uuid.uuid4())
    output.mkdir(parents=True, exist_ok=False)
    documents = []
    for first in range(0, len(reader.pages), pages_per_document):
        pages = reader.pages[first:first + pages_per_document]
        employee = None
        reason = ''
        try:
            # Uma página ambígua nunca é incorporada ao documento de outra pessoa.
            identities = []
            for offset, page in enumerate(pages):
                text = extract_text(first + offset, page) if extract_text else page.extract_text() or ''
                identities.append(identify_text(text, employees))
            if len({e['id'] for e in identities}) != 1:
                raise ReviewRequired('O grupo contém documentos de colaboradores diferentes.')
            employee = identities[0]
            if employee.get('data_desligamento'):
                raise ReviewRequired('Colaborador desligado: envio bloqueado para revisão.')
        except ReviewRequired as error:
            reason = str(error)
        document_id = str(uuid.uuid4())
        label = employee['nome'] if employee else 'REVISAR'
        safe_name = re.sub(r'[^\w .-]', '_', label).strip(' .')[:100] or 'documento'
        filename = f'{safe_name}_{document_id}.pdf'
        writer = PdfWriter()
        for page in pages:
            writer.add_page(page)
        with (output / filename).open('wb') as target:
            writer.write(target)
        digest = hashlib.sha256((output / filename).read_bytes()).hexdigest()
        documents.append(Document(document_id, employee['id'] if employee else None,
            label, filename, first + 1, first + len(pages), digest,
            'review' if reason else 'prepared', reason))
    manifest = {'version': 1, 'batch_id': output.name, 'documents': [asdict(d) for d in documents]}
    (output / 'manifest.json').write_text(json.dumps(manifest, ensure_ascii=False, indent=2), encoding='utf-8')
    return output, documents

def select_documents(documents, employee_ids=None):
    """None seleciona todos os elegíveis; conjunto vazio não seleciona ninguém."""
    eligible = [d for d in documents if d.status == 'prepared' and d.employee_id]
    if employee_ids is None:
        return eligible
    wanted = set(employee_ids)
    available = {d.employee_id for d in eligible}
    if wanted - available:
        raise ReviewRequired('A seleção contém colaborador sem documento pronto neste lote.')
    return [d for d in eligible if d.employee_id in wanted]
