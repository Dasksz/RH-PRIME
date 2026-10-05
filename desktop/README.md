# RH PRIME — Aplicativo Windows (prévia de preparação)

Esta versão separa PDFs com texto, identifica colaboradores no Supabase e permite selecionar todos os documentos prontos ou somente alguns. Não envia documentos, não movimenta pastas e não ativa processamento em segundo plano. Essas integrações ainda não estão concluídas.

O RH PRIME continua no GitHub Pages. Não é necessário Node.js para usar o aplicativo empacotado. O Python e as bibliotecas são incluídos pelo processo de compilação; a execução do código-fonte exige Python e `pip install -r requirements.txt`.

## Execução do código-fonte

Em Windows, na pasta desktop:

```powershell
py -m venv .venv
.\.venv\Scripts\python -m pip install -r requirements.txt
.\.venv\Scripts\python run.py
```

É necessário login de administrador RH PRIME. O aplicativo salva o token de renovação no cofre do Windows, não a senha. A opção de desconectar remove o token local. O provedor pode exigir novo login após revogação ou expiração. Os PDFs e o manifesto ficam em `%LOCALAPPDATA%\RHPrime\lotes`; não são apagados ao desconectar.

Escolha a quantidade de páginas por documento e carregue o PDF. Cada página precisa identificar a mesma pessoa dentro de cada grupo. Continuação sem identificação, PDF digitalizado sem texto, homônimos ou colaborador desligado exigem revisão. Não há OCR nesta prévia. Não se presume que uma página sem identificação pertença ao colaborador anterior.

## Facilita Ponto

O produto oficial anuncia documentos para assinatura no portal do colaborador, acompanhamento de status e comprovantes: https://facilitaponto.com.br/assinatura-simplificada

A documentação técnica da API de documentos ainda não foi obtida. `rhprime/providers.py` contém apenas o contrato INTERNO e bloqueia chamadas reais. Nenhum endpoint, método de autenticação ou capacidade de API foi presumido.

Solicitar ao fornecedor:

- Documentação de API para envio de PDF ao colaborador e disponibilidade no plano contratado.
- Autenticação, ambiente de testes, identificação de empresa e colaborador (ID, CPF ou matrícula).
- Tipos, tamanho máximo e regras de documentos fechados/publicados.
- Envio individual/em lote, chave de idempotência e tratamento de duplicidades.
- Consulta de status, notificações/webhooks com validação e limites de requisições.
- Download do documento assinado e comprovante; cancelamento/substituição.

Fluxo desejado: PDF → separação/identificação → conferência e seleção → fila → API Facilita Ponto → entrega e assinatura pelo Facilita Ponto → status e arquivo assinado no RH PRIME/Drive. O canal Facilita Ponto não deve disparar paralelamente o mesmo documento pelo n8n sem escolha explícita do operador.

## Validação

```powershell
$env:PYTHONPATH='.'
py -m unittest discover -s tests -v
```

Testes não acessam contas reais nem enviam documentos. O executável Windows precisa ser compilado e testado no Windows antes de ser tratado como versão final. A migração `../rh_automacoes.sql` é um rascunho separado e não é necessária para esta prévia; não aplicá-la para executar o preparador.
