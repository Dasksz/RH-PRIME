import importlib.util
from pathlib import Path
from tempfile import TemporaryDirectory
import unittest
from unittest.mock import Mock, patch
import pandas as pd
import requests

spec = importlib.util.spec_from_file_location('avisos', Path(__file__).with_name('2_Avisar_Facilita.py'))
avisos = importlib.util.module_from_spec(spec)
spec.loader.exec_module(avisos)


class AvisosTests(unittest.TestCase):
    def setUp(self):
        self.temp = TemporaryDirectory()
        self.root = Path(self.temp.name)
        (self.root / 'PDFs_Separados').mkdir()
        (self.root / 'PDFs_Separados' / '01234567890-HOLERITE.pdf').write_bytes(b'pdf-test')
        self.row = {'Nome': 'ANA SILVA', 'CPF Completo': '012.345.678-90', 'WhatsApp': '11999999999',
                    'Arquivo Gerado': '01234567890-HOLERITE.pdf', 'Pasta Local': 'PDFs_Separados', 'Tipo': 'Ativo'}

    def tearDown(self):
        self.temp.cleanup()

    def people(self, rows=None):
        return avisos.preparar_avisos(pd.DataFrame(rows or [self.row]), self.root, 'HOLERITE', '09/2026')

    def test_only_generated_active_pdfs_and_one_notice_per_person(self):
        rows = [self.row, self.row, {**self.row, 'Tipo': 'Ex-Funcionario'},
                {**self.row, 'CPF Completo': '11144477735', 'Arquivo Gerado': 'missing.pdf'}]
        people, errors = self.people(rows)
        self.assertEqual(len(people), 1)
        self.assertEqual(len(errors), 1)
        self.assertIn('032612', people[0]['message'])
        self.assertIn('CPF', people[0]['message'])
        self.assertIn(avisos.PORTAL, people[0]['message'])
        self.assertNotIn('drive.google', people[0]['message'])
        self.assertNotIn('5 PRIMEIROS', people[0]['message'])

    def test_inconsistent_mapping_remains_blocked(self):
        people, _ = self.people([self.row, {**self.row, 'WhatsApp': '21999999999'}, self.row])
        self.assertEqual(people, [])

    def test_text_only_payload_and_no_repeat(self):
        person = self.people()[0][0]
        post = Mock(return_value=Mock(status_code=200, json=lambda: {'id': 'test'}))
        state, log = {}, self.root / 'avisos.json'
        self.assertEqual(avisos.enviar_aviso(person, 'http://example.test/webhook/rh', log, state, post), 'accepted')
        self.assertEqual(set(post.call_args.kwargs['json']), {'chatId', 'caption', 'session'})
        self.assertEqual(avisos.enviar_aviso(person, 'http://example.test/webhook/rh', log, state, post), 'skipped')
        self.assertEqual(post.call_count, 1)

    def test_timeout_is_durable_and_never_retried(self):
        person = self.people()[0][0]
        post = Mock(side_effect=requests.Timeout())
        state, log = {}, self.root / 'avisos.json'
        self.assertEqual(avisos.enviar_aviso(person, 'http://example.test/webhook/rh', log, state, post), 'uncertain')
        self.assertIn('uncertain', log.read_text())
        self.assertEqual(avisos.enviar_aviso(person, 'http://example.test/webhook/rh', log, state, post), 'skipped')
        self.assertEqual(post.call_count, 1)

    def test_declining_confirmation_sends_nothing(self):
        pd.DataFrame([self.row]).to_excel(self.root / 'Relatorio_Mapeamento.xlsx', sheet_name='Prontos para Envio', index=False)
        with patch.object(avisos.Path, 'cwd', return_value=self.root), patch.object(avisos, 'TIPO_DOCUMENTO', 'HOLERITE'), patch.object(avisos, 'MES', '09'), patch.object(avisos, 'ANO', '2026'), patch('builtins.input', return_value='NAO'), patch.object(avisos, 'enviar_aviso') as send:
            avisos.iniciar_envio()
            send.assert_not_called()


if __name__ == '__main__':
    unittest.main()
