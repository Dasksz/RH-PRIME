import importlib.util
from pathlib import Path
import hashlib
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

    def test_folha_uses_singular(self):
        self.assertIn('Sua folha de ponto, referente a 10/2026, está disponível', avisos.mensagem('Ana', 'FOLHA DE PONTO', '10/2026'))
    def test_offline_check_prevents_any_send_or_log(self):
        pd.DataFrame([self.row]).to_excel(self.root / 'Relatorio_Mapeamento.xlsx', sheet_name='Prontos para Envio', index=False)
        with patch.object(avisos.Path, 'cwd', return_value=self.root), patch.object(avisos, 'TIPO_DOCUMENTO', 'FOLHA DE PONTO'), patch.object(avisos, 'MES', '10'), patch.object(avisos, 'ANO', '2026'), patch.dict(avisos.os.environ, {'N8N_RH_WEBHOOK_URL':'http://example.test/webhook/rh'}), patch('builtins.input', side_effect=['A', 'SIM']), patch.object(avisos.socket, 'create_connection', side_effect=TimeoutError()), patch.object(avisos, 'enviar_aviso') as send:
            with self.assertRaisesRegex(ValueError, 'Tailscale'):
                avisos.iniciar_envio()
            send.assert_not_called()
            self.assertFalse((self.root / 'avisos_facilita.json').exists())

    def test_declining_confirmation_sends_nothing(self):
        pd.DataFrame([self.row]).to_excel(self.root / 'Relatorio_Mapeamento.xlsx', sheet_name='Prontos para Envio', index=False)
        with patch.object(avisos.Path, 'cwd', return_value=self.root), patch.object(avisos, 'TIPO_DOCUMENTO', 'HOLERITE'), patch.object(avisos, 'MES', '09'), patch.object(avisos, 'ANO', '2026'), patch('builtins.input', side_effect=['A', 'NAO']), patch.object(avisos, 'enviar_aviso') as send:
            avisos.iniciar_envio()
            send.assert_not_called()

    def archive_report(self, phone):
        filename = '01234567890-HOLERITE - ANA SILVA 09-2026.pdf'
        path = self.root / 'PDFs_Separados' / filename
        path.write_bytes(b'%PDF-1.4\nfixture')
        pd.DataFrame([{**self.row, 'Arquivo Gerado': filename, 'WhatsApp': phone}]).to_excel(
            self.root / 'Relatorio_Mapeamento.xlsx', sheet_name='Prontos para Envio', index=False)
        return path

    def fake_drive(self):
        service = Mock()
        folders = {
            avisos.PASTA_ATIVOS: [dict(id='employee', name='Ana Silva', mimeType=avisos.MIME_PASTA)],
            'employee': [dict(id='category', name='HOLERITE', mimeType=avisos.MIME_PASTA)],
        }

        def list_files(q, **kwargs):
            parent = q.split("'")[1]
            return Mock(execute=lambda: {'files': folders.get(parent, [])[:]})

        def create(body, media_body=None, **kwargs):
            parent = body['parents'][0]
            item = dict(body, id=f'created-{service.files().create.call_count}')
            if media_body is not None:
                content = media_body.getbytes(0, media_body.size())
                item.update(mimeType='application/pdf', sha256Checksum=hashlib.sha256(content).hexdigest())
            folders.setdefault(parent, []).append(item)
            return Mock(execute=lambda: item)

        service.files().list.side_effect = list_files
        service.files().create.side_effect = create
        return service, folders

    def test_drive_only_archives_in_month_and_skips_identical_pdf_on_repeat(self):
        path = self.archive_report('')
        service, folders = self.fake_drive()
        with patch.multiple(avisos, TIPO_DOCUMENTO='HOLERITE', MES='09', ANO='2026'), \
                patch.object(avisos, 'autenticar_drive', return_value=service), \
                patch.object(avisos, 'verificar_conexao') as connection, \
                patch.object(avisos, 'enviar_aviso') as send, patch('builtins.input', side_effect=['B', 'B']):
            avisos.processar_lote(self.root)
            avisos.processar_lote(self.root)
            connection.assert_not_called()
            send.assert_not_called()
        year = folders['category'][0]
        month = folders[year['id']][0]
        self.assertEqual((year['name'], month['name']), ('2026', '09.2026'))
        self.assertEqual([file['name'] for file in folders[month['id']]], [path.name])
        self.assertEqual(service.files().create.call_count, 3)

    def test_both_requires_archive_confirmation_before_notifying(self):
        self.archive_report('11999999999')
        service, folders = self.fake_drive()
        folders[avisos.PASTA_ATIVOS].append(dict(id='ambiguous', name='ANA SILVA', mimeType=avisos.MIME_PASTA))
        folders[avisos.PASTA_EX] = [dict(id='former', name='ANA SILVA', mimeType=avisos.MIME_PASTA)]
        with patch.multiple(avisos, TIPO_DOCUMENTO='HOLERITE', MES='09', ANO='2026'), \
                patch.object(avisos, 'autenticar_drive', return_value=service), \
                patch.object(avisos, 'verificar_conexao'), patch.object(avisos, 'enviar_aviso', return_value='accepted') as send, \
                patch.dict(avisos.os.environ, {'N8N_RH_WEBHOOK_URL': 'http://example.test/webhook/rh'}), \
                patch('builtins.input', side_effect=['C', 'C', 'SIM']):
            avisos.processar_lote(self.root)
            send.assert_not_called()
            service.files().create.assert_not_called()
            folders[avisos.PASTA_ATIVOS].pop()
            avisos.processar_lote(self.root)
            send.assert_called_once()
            self.assertEqual(service.files().create.call_count, 3)

    def test_drive_only_finds_employee_in_former_root_when_report_says_active(self):
        path = self.archive_report('')
        service, folders = self.fake_drive()
        folders[avisos.PASTA_EX] = folders.pop(avisos.PASTA_ATIVOS)
        with patch.multiple(avisos, TIPO_DOCUMENTO='HOLERITE', MES='09', ANO='2026'), \
                patch.object(avisos, 'autenticar_drive', return_value=service), \
                patch.object(avisos, 'enviar_aviso') as send, patch('builtins.input', return_value='B'):
            avisos.processar_lote(self.root)
            send.assert_not_called()
        year = folders['category'][0]
        month = folders[year['id']][0]
        self.assertEqual((year['name'], month['name']), ('2026', '09.2026'))
        self.assertEqual(folders[month['id']][0]['name'], path.name)


if __name__ == '__main__':
    unittest.main()
