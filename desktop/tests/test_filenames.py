import unittest
from rhprime.filenames import document_filename
from rhprime.identity import ReviewRequired

class FilenameTests(unittest.TestCase):
    def test_kinds_and_leading_zero(self):
        employee = dict(cpf='012.345.678-90', nome='José da Silva')
        for kind in ['HOLERITE', 'FOLHA DE PONTO', 'INFORME DE RENDIMENTOS', 'OUTRO DOCUMENTO']:
            self.assertEqual(document_filename(employee, kind, '09/2026'), f'01234567890-{kind} - JOSÉ DA SILVA 09-2026.pdf')
        self.assertEqual(document_filename(employee, 'HOLERITES', '09/2026'), '01234567890-HOLERITE - JOSÉ DA SILVA 09-2026.pdf')
        self.assertEqual(document_filename(employee, 'INFORME DE RENDIMENTOS', '2025'), '01234567890-INFORME DE RENDIMENTOS - JOSÉ DA SILVA 2025.pdf')
    def test_rejects_cnpj_missing_cpf_and_invalid_period(self):
        for cpf in ['', '12345678901234', '00000000000']:
            with self.assertRaises(ReviewRequired): document_filename(dict(cpf=cpf, nome='Ana Silva'), 'HOLERITE', '09/2026')
        for period in ['', '13/2026', '../../2026']:
            with self.assertRaises(ReviewRequired): document_filename(dict(cpf='01234567890', nome='Ana Silva'), 'HOLERITE', period)
    def test_no_path_components(self):
        name = document_filename(dict(cpf='01234567890', nome='Ana/../Silva'), '../RECIBO', '09/2026')
        self.assertNotIn('/', name)
        self.assertNotIn(chr(92), name)
