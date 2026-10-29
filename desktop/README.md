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

Testes não acessam contas reais nem enviam documentos. O executável Windows precisa ser compilado e testado no Windows antes de ser tratado como versão final. A migração `../supabase/sql/rh_automacoes.sql` é um rascunho separado e não é necessária para esta prévia; não aplicá-la para executar o preparador.

## Instalação da prévia compilada

No GitHub Actions, abra a execução concluída de **RH PRIME Windows preview**, baixe o artefato **RHPrime-Windows-preview** e extraia todo o ZIP. Execute `Instalar.cmd`. Ele copia os arquivos para `%LOCALAPPDATA%\Programs\RHPrime` e cria um atalho na área de trabalho, sem instalar Node ou Python globalmente. Não inicia serviços nem altera Docker/n8n. Feche o aplicativo antes de atualizar. O envio ao Facilita Ponto continua bloqueado nesta prévia.

## Nomes dos PDFs preparados

Informe o tipo e a competência antes de separar. Os novos PDFs usam o CPF do cadastro, apenas com os 11 dígitos, preservando zeros à esquerda:

`CPF-TIPO - NOME DO COLABORADOR MM-AAAA.pdf`

Exemplos: `52998224725-HOLERITE - ANA MARIA SILVA 09-2026.pdf`, `52998224725-FOLHA DE PONTO - ANA MARIA SILVA 09-2026.pdf`. O tipo é editável para outros documentos. No aplicativo Python, informes anuais também aceitam competência `AAAA`. Na página web, a exportação para o Facilita Ponto também aceita competência anual `AAAA`.

O CPF vem do colaborador identificado no cadastro, nunca do CNPJ da empresa. Cadastro sem CPF de 11 dígitos exige revisão: o PDF fica como `REVISAR_<id>.pdf` e não pode ser selecionado como pronto. Documentos repetidos na mesma preparação recebem ` (2)`, ` (3)` antes de `.pdf` para preservar todas as páginas. Arquivos antigos não são renomeados.

Na página Documentos web, os selecionados são baixados em ZIP para carregamento manual no Facilita Ponto. Nenhum PDF dessa nova exportação é enviado ao Drive. Depois da publicação manual, um administrador confirma a disponibilidade e autoriza um aviso por colaborador com o portal, CPF e código da empresa `032612`.

O script separado em `../automations/python/1_Preparar_Holerites.py` foi recuperado da versão de trabalho anterior. Preserva a preparação original (incluindo OCR e relatório; PDFs gerados sem senha), acrescentando CPF- ao nome e gerando uma segunda etapa que envia apenas avisos do portal. O arquivo `2_Avisar_Facilita.py` também pode ser usado em lotes existentes. O fluxo n8n antigo permanece arquivado em `RH PRIME.json`.
