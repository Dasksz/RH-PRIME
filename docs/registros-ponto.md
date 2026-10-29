# Registros de ponto — Facilita Ponto

Acesse `registros-ponto.html` pela Administração, pelo menu compartilhado ou pela área de absenteísmo. A página lê somente o Supabase. O botão Sincronizar chama `ponto-sync`, que consulta o fornecedor pelo CPF de 11 dígitos, armazena as marcações no banco e devolve apenas o resultado da importação. A senha de integração e a chave da empresa ficam criptografadas no Vault e só podem ser recuperadas pelo servidor.

## Jornada e compensação

O padrão confirmado pelo RH é 44 horas semanais, 528 minutos por dia, de segunda a sexta. Campos de jornada ausentes foram preenchidos nos cadastros existentes, sem sobrescrever valores preenchidos; um gatilho preserva o padrão para novos cadastros. Ajustes individuais de apuração podem ser salvos no detalhe do colaborador.

O ciclo vai de 26 do mês anterior a 25 do mês de fechamento. Após o dia 25, a página abre o ciclo em andamento que termina no mês seguinte. As semanas são de segunda a domingo. A diferença de um dia pode ser compensada por outros dias da mesma semana: 1h a menos e 1h a mais resultam em saldo semanal zero.

Somente semanas encerradas e sem inconsistências produzem extra/débito semanal consolidado. A semana é atribuída ao ciclo que contém seu domingo, evitando contar o saldo duas vezes. O detalhe mostra os dias de contexto fora do ciclo. Quando ainda não há semanas fechadas, o indicador principal mostra a variação parcial dos dias completos, explicitamente em apuração. Hoje e dias futuros não viram faltas ou débitos definitivos.

Feriados nacionais/BA do calendário existente e férias cadastradas ajustam a meta. Ponto facultativo não é folga automática. São usados segundos nos cálculos e horas/minutos no painel. Não há cálculo de adicionais de 50%/100%, nem lançamento automático em folha de pagamento ou no absenteísmo.

## Faltas e justificativas

O histórico começa em setembro/2026. Conforme orientação do RH, dias úteis sem marcação anteriores a **26/10/2026**, dentro do vínculo do colaborador, são justificados por corte de implantação e não geram débito. Essa regularização não afirma que houve uma falta real nem cria registros individuais falsos no absenteísmo; é uma regra explícita no painel.

Após o corte, um dia encerrado, previsto na jornada e consultado com sucesso, sem marcações e sem justificativa, aparece como falta sem justificativa cadastrada. Se a consulta falhou ou nunca foi feita, o dia fica sem dados para conferência. Marcações pendentes/rejeitadas, entradas sem saída e lançamentos de absenteísmo conflitantes não são fechados automaticamente.

Os indicadores de faltas são botões: exibem as datas e, ao selecionar uma data, os colaboradores. A contagem representa colaborador/dia, respeitando setor, filial, período e demais filtros. Ao salvar uma classificação, os indicadores e a lista aberta são recalculados.

O administrador pode classificar pelo indicador ou pelo espelho, como justificada, injustificada ou pendente. A observação é opcional; quando vazia, grava-se um texto explícito de classificação pelo RH. Abonar é uma opção separada: uma justificativa sem abono não apaga o débito; com abono, a jornada não realizada é compensada na meta semanal. Todas as revisões são auditadas com data e responsável, preservando batidas e lançamentos existentes.

Comprovantes opcionais: até cinco fotos JPG/PNG/WebP ou PDFs por envio, com 10 MB cada. O bucket `rh-ponto-comprovantes` é privado e somente administradores podem enviar e baixar anexos. `rh_ponto_anexos` registra vínculo, nome, tipo, tamanho, data e autor; o banco valida a existência do upload e o vínculo com o colaborador/dia. Arquivos vinculados são imutáveis e não têm exclusão na interface. Downloads autenticados não geram links públicos. Não há alteração automática no absenteísmo.

A classificação é salva antes dos anexos. Uma falha de upload é informada como gravação parcial, mantém o formulário aberto e permite conferir os arquivos já anexados antes de tentar os restantes. A estrutura complementar está em `../supabase/sql/rh_ponto_comprovantes.sql`.

## Persistência e proteção

- `rh_ponto_marcacoes`: batidas e situação do fornecedor.
- `rh_ponto_consultas`: histórico de consultas e fotografia original da resposta.
- `rh_ponto_jornadas`: ajustes individuais para esta apuração.
- `rh_ponto_ocorrencias` e histórico: classificações/revisões do RH.
- `rh_ponto_config`: corte de faltas, início do histórico e fuso.

As tabelas têm RLS por colaborador/área; sincronização e classificação exigem administrador. Credenciais não são retornadas ao navegador, mesmo para administradores. O SQL público é invoker; rotinas privilegiadas ficam em `rh_internal`, com permissões restritas.

A função usa o contrato GET documentado e o hash SHA1 exigido pelo fornecedor. As datas/horas sem fuso recebidas são tratadas como horários locais de São Paulo/Bahia. Jornada noturna com entrada e saída em datas diferentes fica para conferência nesta versão. Mudanças de tipo/situação inesperadas bloqueiam a substituição do período. Sem ID externo estável, a fotografia do período é reconciliada atomicamente, com histórico; uma falha nunca apaga dados anteriores.

## Operação

A integração não envia WhatsApp nem altera dados no Facilita Ponto. Somente consulta e grava no Supabase. Cada chamada autenticada aceita até três colaboradores e um período de até 63 dias; a tela divide os lotes, mostra progresso e limita consultas até hoje. O acesso ao fornecedor ocorre no servidor, sem depender do Tailscale do computador.

As credenciais são provisionadas no Vault pelos nomes `rh_facilita_empresa` e `rh_facilita_senha_sha1`; não coloque valores em código ou migrações. A Edge Function usa as chaves privadas do ambiente Supabase, nunca do navegador. A implantação mantém `verify_jwt=true` e valida novamente a sessão e o perfil administrativo.

Scripts de estrutura: `../supabase/sql/rh_ponto.sql` e `../supabase/sql/rh_ponto_ocorrencias.sql`, nessa ordem, já aplicados no RH PRIME. Função: `../supabase/functions/ponto-sync/index.ts`.

Testes: `node --test tests/rh_ponto.test.cjs tests/rh_ponto_edge.test.cjs`. Foram verificados compensação, corte, abono, autenticação, gravação idempotente, preservação em erro e auditoria. A suíte geral conserva três falhas anteriores em testes alheios a este fluxo.
