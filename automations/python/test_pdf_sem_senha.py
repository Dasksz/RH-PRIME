"""Verifica o bloco real de separação sem executar login, OCR ou envio."""
import ast
from io import BytesIO
from pathlib import Path
from tempfile import TemporaryDirectory
import unittest
from PyPDF2 import PdfReader, PdfWriter


class PdfSemSenhaTests(unittest.TestCase):
    def test_preparador_nao_aplica_criptografia(self):
        tree = ast.parse(Path(__file__).with_name('1_Preparar_Holerites.py').read_text(encoding='utf-8'))
        self.assertFalse(any(isinstance(n, ast.Call) and isinstance(n.func, ast.Attribute) and n.func.attr == 'encrypt' for n in ast.walk(tree)))

    def test_bloco_real_salva_paginas_sem_senha(self):
        source = Path(__file__).with_name('1_Preparar_Holerites.py').read_text(encoding='utf-8')
        lines = source.splitlines()
        start = next(i for i, line in enumerate(lines) if line.strip() == 'escritor_pdf = PdfWriter()')
        end = next(i for i in range(start, len(lines)) if lines[i].strip() == 'escritor_pdf.write(arquivo_saida)')
        import textwrap
        block = compile(textwrap.dedent('\n'.join(lines[start:end+1])), 'separacao-real', 'exec')
        input_writer = PdfWriter()
        for width in (100, 200, 300):
            input_writer.add_blank_page(width=width, height=400)
        stream = BytesIO()
        input_writer.write(stream)
        reader = PdfReader(stream)
        with TemporaryDirectory() as folder:
            target = Path(folder) / '01234567890-FOLHA DE PONTO.pdf'
            exec(block, dict(PdfWriter=PdfWriter, pdf_fatiador=reader, i=0,
                            paginas_por_funcionario=2, total_paginas=3,
                            cpf_encontrado='01234567890', caminho_salvar=target))
            result = PdfReader(target)
            self.assertFalse(result.is_encrypted)
            self.assertEqual(len(result.pages), 2)
            self.assertEqual([int(p.mediabox.width) for p in result.pages], [100, 200])


if __name__ == '__main__':
    unittest.main()
