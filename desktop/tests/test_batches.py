import tempfile
import unittest
from pathlib import Path
from pypdf import PdfWriter, PdfReader
from rhprime.batches import prepare_batch, select_documents
from rhprime.identity import ReviewRequired
from rhprime.providers import FacilitaPonto, IntegrationUnavailable

class BatchTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        self.source = self.root / 'source.pdf'
        writer = PdfWriter()
        for _ in range(4): writer.add_blank_page(width=200, height=200)
        with self.source.open('wb') as f: writer.write(f)
        self.employees = [dict(id='a', nome='ANA MARIA SILVA', cpf='529.982.247-25'), dict(id='b', nome='BRUNO JOSE SANTOS', cpf='11144477735')]
    def tearDown(self): self.temp.cleanup()
    def prepare(self, texts, size=1):
        return prepare_batch(self.source, self.employees, self.root, size, lambda i, _: texts[i], document_type='HOLERITE', period='09/2026')
    def test_only_identified_active_are_selectable(self):
        self.employees[1]['data_desligamento'] = '2026-01-01'
        folder, docs = self.prepare(['ANA MARIA SILVA','BRUNO JOSE SANTOS','texto sem identificação','ANA MARIA SILVA'])
        self.assertEqual(len(select_documents(docs)), 2)
        self.assertEqual(select_documents(docs, []), [])
        self.assertEqual(len(select_documents(docs, ['a'])), 2)
        with self.assertRaises(ReviewRequired): select_documents(docs, ['b'])
        self.assertTrue((folder / 'manifest.json').exists())
        self.assertEqual(len(PdfReader(folder / docs[0].filename).pages), 1)
    def test_filename_and_duplicate_preserve_both_pdfs(self):
        folder, docs = self.prepare(['ANA MARIA SILVA'] * 4)
        self.assertEqual(docs[0].filename, '52998224725-HOLERITE - ANA MARIA SILVA 09-2026.pdf')
        self.assertEqual(docs[1].filename, '52998224725-HOLERITE - ANA MARIA SILVA 09-2026 (2).pdf')
        self.assertEqual(len({d.filename for d in docs}), 4)
        for doc in docs:
            self.assertEqual(len(PdfReader(folder / doc.filename).pages), 1)
    def test_missing_cpf_blocks_prepared_status(self):
        self.employees[0].pop('cpf')
        _, docs = self.prepare(['ANA MARIA SILVA'] * 4)
        self.assertEqual(select_documents(docs), [])
        self.assertTrue(all(d.filename.startswith('REVISAR_') and 'CPF' in d.reason for d in docs))
    def test_cross_employee_page_group_blocked(self):
        _, docs = self.prepare(['ANA MARIA SILVA','BRUNO JOSE SANTOS'] * 2, 2)
        self.assertEqual(select_documents(docs), [])
    def test_unidentified_continuation_requires_review(self):
        _, docs = self.prepare(['ANA MARIA SILVA','continuação'] * 2, 2)
        self.assertEqual(select_documents(docs), [])
    def test_ambiguous_names_blocked(self):
        self.employees.append(dict(id='c', nome='ANA MARIA SILVA', cpf='529.982.247-25'))
        _, docs = self.prepare(['ANA MARIA SILVA'] * 4)
        self.assertEqual(select_documents(docs), [])
    def test_incomplete_group_rejected(self):
        with self.assertRaises(ReviewRequired): self.prepare([''] * 4, 3)
    def test_facilita_never_fakes_success(self):
        with self.assertRaises(IntegrationUnavailable): FacilitaPonto().submit(None)

if __name__ == '__main__': unittest.main()
