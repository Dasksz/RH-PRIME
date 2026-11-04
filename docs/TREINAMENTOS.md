# Cronograma de treinamentos

Página `treinamentos.html`, disponível no menu principal e na administração.

- Nove cursos importados do cronograma de outubro/novembro, com início em 07/12/2026.
- Programação exclusivamente de segunda a sexta. Cursos acima de quatro horas são divididos em etapas de até quatro horas, em datas distintas e ordenadas. O curso de operador de empilhadeira importado permanece como exceção de oito horas em um dia.
- As datas originais estão preservadas em `data_original`. O total de horas, o público e as empresas são mantidos. Todos os cursos importados começam como agendados.
- Administradores incluem, editam, mudam datas e registram conclusões. Usuários aprovados consultam e exportam PDF. Há controle de versão e histórico de alterações.
- O PDF usa os filtros atuais e mostra cada etapa com sua data e carga horária.

## Comprovantes

O formulário permite concluir sem anexos e adicionar documentos posteriormente. Formatos: PDF, JPG/JPEG, PNG, WEBP, DOCX, XLSX e TXT; até dez arquivos de 10 MB por envio. Observações são opcionais.

O envio passa pela função `training-evidence`, autenticada, e pela ação `training_upload` da implantação existente de Apps Script. Ambas conferem a sessão e o acesso administrativo. O Apps Script usa as propriedades existentes, sem novas credenciais no navegador. Conferem-se tamanho, SHA-256, assinatura básica do formato e metadados/MD5 do arquivo no Drive antes de confirmar o arquivamento. Repetir um envio usa a mesma identificação e não cria outra cópia.

Destino: **RH PRIME / SEGURANÇA DO TRABALHO / Registros de Treinamentos / ano / mês / treinamento**. Ano e mês correspondem à data de realização. A pasta raiz e o ano 2026 foram criados; as demais pastas surgem no envio. Permissões do Drive são preservadas.

Se um envio falhar, a conclusão permanece registrada e a interface mostra o comprovante pendente. Selecione o mesmo arquivo para tentar novamente. A data de realização fica protegida quando há comprovantes vinculados; a programação continua editável.

`rh_internal.training_operations` é um registro interno de repetição segura. Sua política é negar acesso direto: RLS habilitada, sem políticas, sem permissões para usuários. A ausência de política nessa tabela é intencional.

## Verificação

- `node --test tests/training_drive.test.cjs`: contrato das chamadas, organização das pastas, integridade, repetição após falha e autorização, com serviços simulados.
- `tests/training_schedule_rollback.sql`: exercitado no banco remoto, com reversão integral dos registros de teste; inclusão, etapas, versões, fins de semana, limite de horas, exceção da empilhadeira, conclusão, anexos, repetição e permissões.
- `tests/training_preview.html`: prévia isolada para verificar edição das etapas, conclusão e PDF sem modificar o banco.
- PDF gerado pela página e inspecionado visualmente em A4 horizontal, com as doze etapas em uma página.
- A implantação real de Apps Script foi verificada rejeitando sessão inválida. O envio real de um arquivo pelo navegador não foi validado, pois a extensão não permitiu selecionar arquivos locais; os testes da integração usam serviços simulados.
