# 🛠️ Como Resolver o Erro do Tesseract OCR no Windows

Se você viu a mensagem `ERRO OCR: Tesseract não está instalado ou configurado no PATH do Windows`, isso acontece porque o Python precisa de um programa externo para ler os PDFs como imagens, e ele não conseguiu achar esse programa.

Siga os passos abaixo para resolver:

### Passo 1: Fazer o Download e Instalar o Tesseract
1. Acesse o site de download: [https://github.com/UB-Mannheim/tesseract/wiki](https://github.com/UB-Mannheim/tesseract/wiki)
2. Baixe o instalador 64-bits (ex: `tesseract-ocr-w64-setup-5.5.0.xxxx.exe`).
3. Abra o arquivo baixado e instale normalmente (vá clicando em "Next"). **Não altere a pasta padrão de instalação** (deixe como `C:\Program Files\Tesseract-OCR`).

### Passo 2: Instalar as Bibliotecas do Python
Abra o **PowerShell** e cole o comando abaixo:
```powershell
pip install pdfplumber PyPDF2 pandas requests openpyxl pytesseract google-api-python-client google-auth-httplib2 google-auth-oauthlib
```

### Passo 3: Configurar o PATH Automaticamente (Se o erro persistir)
Mesmo instalando, o Windows pode não avisar o Python onde o Tesseract está. Para arrumar isso facilmente, abra o **PowerShell como Administrador** e cole este comando inteiro e aperte ENTER:

```powershell
$tesseractPath = "C:\Program Files\Tesseract-OCR"
$currentPath = [Environment]::GetEnvironmentVariable("Path", [EnvironmentVariableTarget]::Machine)
if ($currentPath -notmatch [regex]::Escape($tesseractPath)) {
    [Environment]::SetEnvironmentVariable("Path", $currentPath + ";" + $tesseractPath, [EnvironmentVariableTarget]::Machine)
    Write-Host "Tesseract adicionado ao PATH com sucesso! Feche e abra o CMD/PowerShell novamente." -ForegroundColor Green
} else {
    Write-Host "O Tesseract já estava no PATH." -ForegroundColor Yellow
}
```

**⚠️ Importante:** Após rodar esse comando, você DEVE fechar a janela do CMD ou PowerShell que estava usando para rodar o robô e abrir uma nova. Só assim o Windows atualiza as configurações.

Feito isso, execute seu script de holerites novamente!
