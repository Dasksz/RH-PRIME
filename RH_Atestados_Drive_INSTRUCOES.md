# Atestados e comparecimentos no Drive

Destino: **pasta do colaborador / ATESTADOS / ano da data do documento**.
Pastas existentes são reutilizadas. Não são criadas pastas de mês.

O formulário gera o nome com o cadastro do colaborador:

- `ATESTADO - 10.09 1 DIA - JULIO ESPIRITO SANTO NASCIMENTO NETO.pdf`
- `ATESTADO - 10.09 2 DIAS - JULIO ESPIRITO SANTO NASCIMENTO NETO.jpg`
- `COMPARECIMENTO 21.08 - JULIO ESPIRITO SANTO NASCIMENTO NETO.pdf`

## Ativar a cópia automática

1. Abra o projeto **RH PRIME** no Google Apps Script, o mesmo que já contém `RH_Drive_Automacoes`.
2. Clique no **+** ao lado de Arquivos e escolha **Script**. Nomeie o novo arquivo `RH_Atestados_Drive`.
3. Apague o conteúdo inicial e cole todo o conteúdo de `RH_Atestados_Drive.gs`. Salve.
4. Na lista de funções, escolha **instalarAtestadosDriveRH** e clique em **Executar**. Autorize o acesso, se for solicitado.

Não substitua os arquivos existentes. Não é necessária uma nova chave ou outra implantação web: o novo gatilho executa o código salvo no projeto. São usadas as propriedades `SUPABASE_URL` e `SUPABASE_KEY` já cadastradas.

Depois da instalação, a fila é verificada a cada minuto. No registro da falta, o sistema mostra o andamento; **Conferir no Drive** aparece depois de o arquivo, nome, destino e conteúdo terem sido confirmados.

## Uso

Anexe PDF, JPG ou PNG de até 10 MB. Escolha **Atestado** ou **Comparecimento**. Confira a data do documento; ela determina o ano da pasta e a data no nome. Para atestados, informe os dias ou deixe em branco para usar os dias corridos do período. Para comparecimento, confira as horas perdidas no formulário: elas não são extraídas da imagem ou do PDF.

Se não houver vínculo com a pasta do colaborador, o processador procura uma pasta existente nas raízes autorizadas. Só registra o vínculo quando encontra uma única correspondência. Em caso de ausência de pasta ou homônimos, faça o vínculo nas automações e use **Tentar arquivar novamente** no registro da falta.

Os arquivos não recebem compartilhamento público. O processador interrompe o envio se detectar acesso por qualquer pessoa ou por domínio na pasta/arquivo de atestados. A visualização pelo sistema continua usando a cópia privada com as permissões de acesso ao colaborador.

Trocar ou remover o anexo do registro não apaga um documento que já foi arquivado no Drive. O histórico no Drive é preservado. Alterar a data ou o nome do mesmo anexo atualiza sua organização no Drive sem duplicar esse arquivo.

## Verificação realizada

Os testes usaram arquivos fictícios e serviços simulados para verificar reutilização de pastas, organização apenas por ano, nomes, integridade e tentativas repetidas. As permissões e a fila foram testadas no banco com rollback. Nenhum atestado real foi enviado durante esses testes. O envio real ao Drive depende da instalação acima.
