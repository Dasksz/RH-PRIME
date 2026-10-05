# RH PRIME — revisão e instalação (04/10/2026)

O banco e a planilha foram corrigidos diretamente. Este repositório contém o front-end ajustado e o Apps Script completo para substituir o código vinculado à planilha.

## Instalar o Apps Script

1. Abra a planilha → **Extensões → Apps Script**. Substitua o código de sincronização pelo arquivo completo `google_apps_script_atualizado.js`. Evite manter funções homônimas em outros arquivos do projeto. O script de assinaturas de documentos é outro projeto: não substitua esse projeto por este sincronizador.
2. Salve e execute `configurarCredenciaisRH`. A URL do banco, chave de servidor, ID da planilha e URL da implantação estão preenchidos. As propriedades já existentes são preservadas.
3. Execute `prepararEstruturaRH` e autorize os acessos. Essa função faz outra cópia de segurança antes de conferir os cabeçalhos.
4. Execute `sincronizarBancoParaPlanilha` para conferir o estado do banco. **Não execute o envio em massa antes dessa conferência.**
5. Execute `instalarGatilhoRH`. Remova gatilhos de edição de outras contas/projetos antigos que continuem executando o sincronizador anterior; esta função só vê os gatilhos da sua conta neste projeto.
6. Em **Implantar → Gerenciar implantações → Editar**, publique uma **nova versão da implantação existente**, executando como você e com acesso **Qualquer pessoa**, preservando a URL atual. Esse acesso permite ao webhook chegar ao sincronizador; os dados do banco continuam protegidos pelas políticas de autenticação.
7. Execute `ativarWebhooksRH`. Ela só ativa os oito webhooks depois de verificar que a URL responde com a versão nova (`2026-10-04-rh2`). Se criar outra implantação/URL, a URL dos webhooks no banco também precisará ser atualizada: use a implantação existente neste procedimento.
8. Confira uma edição de nome no front-end e uma edição de campo não sensível na planilha. As duas devem manter o mesmo `id`. Confira também programação de férias, horas manuais de ausência e baixa de devolução.

Até concluir os passos 6 e 7, os webhooks de banco → planilha ficam **suspensos**. Isso impede que a versão antiga execute exclusões durante a atualização. O site e o banco continuam funcionando. Não foi possível editar diretamente o projeto implantado de Apps Script nesta conexão.

## Correções aplicadas

- Identidade por UUID do cadastro e vínculo `funcionario_id`; preenchimento de CPFs apenas em correspondências únicas, sem conflito de CPF existente.
- Nome/CPF editados no cadastro são propagados para movimentações, férias, ausências, arquivo de desligados e devoluções.
- Cadastro/admissão e desligamento geram as alterações relacionadas na mesma transação do banco. Erros cancelam a operação inteira.
- Desligamento preserva o cadastro, férias e afastamentos para consulta histórica. O controle de entrega de EPI apresenta os cadastros ativos.
- Mudanças pela aba de movimentações atualizam o cadastro principal. Demais registros vinculados validam a identidade e completam CPF/vínculo ao selecionar um colaborador existente.
- Horas manuais, inclusive zero, são preservadas. Indicadores dividem ausências que atravessam meses proporcionalmente aos dias de trabalho, mantendo o total informado, e consideram a carga do vínculo. A carga registrada numa ausência histórica não é reescrita ao editar o cadastro atual.
- Abrir a tela de férias passou a ser somente leitura. Ao fechar/avançar um período por uma ação de edição, o período anterior é arquivado, incluindo o lançamento final de gozo/abono.
- Acesso ao RH exige perfil aprovado. Área administrativa exige perfil `admin`; usuário comum não pode alterar a própria aprovação. Empresas e regras de EPI podem ser consultadas por aprovados e administradas apenas pelo administrador.
- A conta existente identificada unicamente como Daniel César passou a `admin`; os outros aprovados continuam operacionais. A senha administrativa compartilhada foi substituída pela autenticação da conta. Alterar senha agora usa Supabase Auth.
- Auditoria de gravações confirmadas no banco, com IDs e valores anteriores/novos. A limpeza automática de logs antigos foi suspensa para preservar a trilha.
- Atualização das telas por Realtime, retorno à janela e foco; publicação das tabelas relevantes no Realtime.
- Apps Script trata linhas coladas em conjunto, remoção por `old_record`, renomeações sem duplicar linhas, campos limpos, colunas de programação, histórico, checklists e falhas HTTP. Eventos atrasados consultam o estado atual do banco antes de escrever.
- Ajustes de toque, foco, campos no celular, tabelas e limites de altura dos modais em telefone/tablet.

## Planilha

Backup anterior às edições: `Controle_EPI_Fardamento_Prime_BACKUP_2026-10-04`.

| Aba | Ajuste |
|---|---|
| Controle EPI e Fardamento | X:Z: ID, desligamento e motivo; A:W preservadas |
| movimentacoes | E:H: CPF, ID, vínculo e carga; uma duplicata idêntica teve A:D limpas, sem excluir a linha inteira |
| absenteismo | H:K: CPF, carga, mês e vínculo; dois registros do banco ausentes na planilha foram incluídos |
| ferias | H:Q: abono, CPF, ID, saldo, programação, retorno, histórico e vínculo |
| epi_funcao | Duas linhas de cabeçalho congeladas; o cabeçalho importado como função foi removido do banco |
| devolucoes_pendentes | Nova aba com dados e checklist |
| empresas | Nova aba com as três empresas |
| desligados | Nova aba com os 70 registros históricos |

Fuso corrigido para `America/Sao_Paulo`. IDs técnicos recebem avisos de proteção nas abas existentes; CPF é texto para manter zeros iniciais. Colunas não mapeadas, validações e formatos existentes foram preservados.

Nem todos os registros históricos permitem recuperar CPF com segurança: após a correção, ainda havia 70 movimentações, 2 registros de férias e 4 ausências sem CPF válido. Eles foram preservados para conferência manual. Não invente CPFs para preencher essas lacunas.

## Validação

23 verificações simuladas do Apps Script e 6 verificações das utilidades passaram. Os sete blocos React/JSX compilam. Migrações incluíram testes transacionais de admissão, renomeação, desligamento, vínculo e histórico; pessoas fictícias foram revertidas. Testes de RLS confirmaram leitura dos aprovados, bloqueio dos pendentes e impedimento de autoelevação para administrador.

As sete telas foram renderizadas e conferidas no navegador nas larguras 390, 820 e 1440 pixels (21 verificações), com dados fictícios. O formulário de cadastro também foi aberto no celular para conferir campos, rolagem e acesso ao rodapé. `tests/layout_preview.html` oferece essa prévia com **dados fictícios**. Não deve ser usado como sistema de produção. A validação visual e a sincronização na implantação real são etapas distintas; esta última exige instalar o Apps Script acima.

## Aplicativo e envio de documentos

É viável reutilizar o sistema como aplicativo instalável. Uma PWA permite instalar pelo navegador em dispositivos compatíveis, com interface adaptada à tela. Um APK Android pode ser empacotado com Capacitor; um instalador Windows pode usar Tauri. APK é o formato Android, e o PC requer seu próprio instalador.

A integração de documentos deve usar uma tarefa no servidor: escolher colaborador/documento → registrar pedido → preparar PDF → enviar pelo fluxo autorizado → registrar resultado/assinatura e oferecer nova tentativa sem duplicar o envio. Chaves de envio e privilégios administrativos ficam no servidor. O aplicativo pode vir com URLs, identificadores e preferências preenchidos, com uma configuração inicial para login e conexões.

O arquivo `AUTOMACAO_ENVIO_DE_DOCUMENTOS/1_Preparar_Holerites.py` contém JSON de fluxo n8n, igual a `RH PRIME.json`: não é um programa Python executável. O empacotamento precisa primeiro distinguir o fluxo n8n, o lançador local e o Apps Script de assinatura. Não foi gerado APK/EXE nem realizado envio de documentos nesta revisão.

Referências: [instalação de PWA](https://developer.mozilla.org/en-US/docs/Web/Progressive_web_apps/Guides/Making_PWAs_installable), [Capacitor](https://capacitorjs.com/docs), [instaladores Windows/Tauri](https://v2.tauri.app/distribute/windows-installer/).

## Pendência de segurança no serviço de autenticação

A verificação de segurança do Supabase ficou com um aviso: a proteção contra senhas já vazadas está desativada. Essa opção ainda deve ser conferida no painel de Auth; não foi alterada nesta revisão. [Orientação oficial](https://supabase.com/docs/guides/auth/password-security#password-strength-and-leaked-password-protection).

## Credencial incluída a pedido do proprietário

A chave `service_role` está no arquivo completo por instrução expressa do proprietário, que aceitou a exposição temporária no repositório público. Ela deve ser **trocada após a instalação**. Apagar o arquivo não remove a chave do histórico Git nem de cópias externas. Após a troca, atualize `SUPABASE_KEY` nas Propriedades do script, retire o valor de `RH_CONFIG_INICIAL` e remova o segredo do histórico. Nunca copie esse arquivo para o front-end, PWA, APK ou instalador.


## Correção do recebimento parcial e férias — 04/10/2026

Versão do Apps Script: `2026-10-04-rh3`. Substitua o código completo pelo arquivo atualizado, salve e execute novamente **RH PRIME Sync → Receber banco na planilha**. Atualize também a versão da implantação Web App existente, mantendo a URL.

- Removidas as validações de CNPJ herdadas incorretamente pelas colunas técnicas X:Z. A validação real de CNPJ em W foi preservada.
- A lista de movimentações agora aceita `entrada`. O motivo de afastamento já existente no banco foi acrescentado à lista de absenteísmo. O recebimento amplia apenas listas de motivos com valores confirmados no banco.
- Datas antigas no formato `Date.toString()` são aceitas preservando seu dia civil e rejeitando datas inexistentes.
- Tiago da Paixão dos Santos: CPF e vínculo recuperados do cadastro único e gravados em férias no banco e na planilha.
- Karina Ribeiro Mendonça: desligamento em 27/07/2026 reconhecido pela tela apesar da diferença de acento no nome. Registro de férias preservado como histórico, com nota na planilha. CPF permanece pendente porque também falta no histórico de desligamento.

As verificações locais cobrem as regressões de validação, data antiga, comparação de nomes e filtro de desligados. A execução final do Apps Script depende da atualização manual na extensão da planilha.
