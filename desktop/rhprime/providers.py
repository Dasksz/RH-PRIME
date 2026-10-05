"""Contrato interno. Não representa endpoints oficiais do Facilita Ponto."""
from dataclasses import dataclass
from pathlib import Path
from typing import Protocol

class IntegrationUnavailable(RuntimeError):
    pass

@dataclass(frozen=True)
class Submission:
    document_id: str
    employee_id: str
    external_employee_id: str
    path: Path
    kind: str
    period: str
    idempotency_key: str

@dataclass(frozen=True)
class Receipt:
    external_document_id: str
    status: str  # accepted não significa delivered nem signed

class DocumentProvider(Protocol):
    def submit(self, submission: Submission) -> Receipt: ...
    def status(self, external_document_id: str) -> Receipt: ...
    def download_signed(self, external_document_id: str, destination: Path) -> Path: ...

class FacilitaPonto:
    available = False
    reason = ('Integração pendente da documentação oficial da API do Facilita Ponto, '
              'liberação do plano contratado e credenciais de integração.')

    def submit(self, submission):
        raise IntegrationUnavailable(self.reason)

    def status(self, external_document_id):
        raise IntegrationUnavailable(self.reason)

    def download_signed(self, external_document_id, destination):
        raise IntegrationUnavailable(self.reason)
