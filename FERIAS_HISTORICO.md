# Férias: períodos, histórico e documentos

Abra **Férias → Histórico e registros** do colaborador. Escolha **Registrar férias deste período** ou **Registrar / programar férias**. O seletor mostra os anos e as datas completas, calculadas pela admissão. Selecionar 2024–2025 preenche o início e o fim aquisitivos; informe somente a data real da saída, os dias de gozo e de abono e a situação. O último dia de gozo e o retorno são calculados pelos dias corridos.

Para férias antigas, escolha **Registrar gozo já concluído**. “Sem registro” indica ausência de informação no sistema, não que a pessoa deixou de tirar férias. Não foram inventadas datas de gozo. Confira o direito de cada período com o DP. Se o resumo anterior já tem dias gozados/abonados, esses dias já entram no saldo: use **Revisar direito e resumo anterior** para retirar o total que será substituído por lançamentos detalhados e evitar duplicação.

**Programar** reserva dias; **Confirmar gozo concluído** deve ser usado depois do término e da conferência do gozo. **Estornar / cancelar** exige motivo e mantém o registro no histórico. Dias reservados, gozados e abonados aparecem separadamente. O sistema bloqueia excesso de saldo, abono acima de um terço e sobreposição de datas. Fracionamento exige concordância; registros históricos fora do padrão precisam de justificativa e revisão do DP. Antecipação antes da aquisição completa requer tratamento específico, não está habilitada neste fluxo.

Os períodos seguem o aniversário de admissão, independentemente de o saldo anterior estar quitado. O próximo período aparece automaticamente. A provisão é uma estimativa por meses completos; não desconta horas de faltas automaticamente. Afastamentos, alterações do direito e datas excepcionais devem ser conferidos pelo DP. Diferenças entre o prazo recebido da planilha e a referência anual ficam sinalizadas com o original preservado.

## Documentos e WhatsApp

Em cada período cadastrado, **Anexar link de documento** vincula um aviso, recibo ou comprovante real, opcionalmente a uma programação/saída. Nenhum arquivo fictício é criado. O administrador também pode usar **Importar PDF do computador**: a importação reaproveita a identificação por nome/CPF, bloqueia documentos de outro colaborador e associa o PDF ao período. A competência MM/AAAA é a organização do arquivo no Drive; o vínculo ao período aquisitivo é armazenado separadamente.

Anexar/importar não envia mensagens. **Conferir e autorizar WhatsApp** mostra destinatário, link e texto e exige confirmação. O processamento depende da instalação/configuração de `RH_Documentos_N8N.gs`, vínculo da pasta, webhook e token de produção e ativação da fila. O fluxo de intervalo existente é reaproveitado. Um link real precisa estar acessível ao colaborador; o sistema não abre permissões do Drive automaticamente. “Aceito pelo n8n” não comprova entrega ou assinatura. Testes desta atualização não enviaram mensagens reais.

**Registrar devolução assinada** guarda o link do arquivo devolvido após conferência do RH. Esse registro é manual, não certifica assinatura. Campos de provedor/referência estão reservados para uma integração futura; a API e os eventos do Facilita Ponto ainda precisam da documentação do fornecedor.

## Banco e planilha

As tabelas `rh_ferias_periodos`, `rh_ferias_lancamentos`, `rh_ferias_documentos` e `rh_ferias_eventos` guardam os detalhes e a trilha de alterações, com acesso por perfil aprovado. O envio de mensagens requer administrador. A migração preservou 99 resumos vinculados com datas utilizáveis; cadastros ausentes ou inconsistentes continuam para revisão.

A tabela antiga `rh_ferias` continua como resumo legado. Quando um período desse resumo passa a ser controlado pelos novos lançamentos, sua projeção de saldo/programação é atualizada, e mudanças de férias vindas do resumo da planilha são bloqueadas para não apagar o histórico. A aba antiga não representa múltiplos períodos e múltiplas saídas. Faça os lançamentos detalhados no RH PRIME. **Exportar histórico CSV** permite consultar todos os períodos e lançamentos, inclusive cancelados, na planilha.

## Validação

27 testes de identidade, Drive e cálculo de férias; transações SQL com rollback para criação histórica, saldo, estorno, permissões e preparação de documento; navegador com serviços simulados em 390, 820 e 1240 px, claro/escuro, seletor com preenchimento automático e sem rolagem horizontal. Dados de teste e mensagens não foram persistidos/enviados. RLS habilitado nas quatro tabelas, gravações diretas pelo navegador bloqueadas e RPCs sem acesso anônimo.

Referências para conferência do DP: [CLT](https://www.planalto.gov.br/ccivil_03/decreto-lei/del5452.htm), especialmente arts. 130, 134, 135, 143 e 145; [TST — Férias](https://www.tst.jus.br/en/ferias1). A rotina não substitui avaliação de afastamentos, regras coletivas ou particularidades do contrato.

## Alertas de vencimento

Na tabela principal, **Prazo / situação** mostra férias vencidas, vencendo em até 30 dias, entre 31 e 90 dias ou dentro do prazo. A data é o prazo concessivo do período adquirido com saldo pendente confirmado. Hoje entra em “até 30 dias”, e somente datas anteriores a hoje são vencidas. A lista ordena os prazos confirmados mais antigos primeiro; o filtro permite consultar vencidas e a vencer. Os dois novos indicadores contam colaboradores ativos, não a quantidade de períodos; o mesmo colaborador pode ter um período vencido e outro a vencer.

Períodos sem cadastro, resumos legados ainda não conferidos e datas divergentes aparecem como **Histórico para conferência**, com data de referência quando disponível, sem gerar alertas de vencimento confirmados. Registre o gozo antigo ou revise/confirme o resumo para que o saldo represente a situação real. Um período confirmado pode gerar alerta mesmo que outro período do colaborador ainda precise de revisão; a pendência continua visível. Programações reservam dias mas não eliminam o alerta antes da confirmação de gozo.
