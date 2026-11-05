# Fichas manuais: autorização pelo WhatsApp

A lista de **Registros de ponto → Fichas manuais** controla os destinatários. Às 7h de Brasília, o destinatário administrativo configurado recebe a pergunta com os nomes e a competência. **1** autoriza a etapa; **2** recusa. O prazo é até as 18h. Sem resposta, há **uma única repetição no dia seguinte, às 7h**, inclusive em fim de semana ou feriado. Sem resposta até as 18h da segunda tentativa, a etapa termina sem envio; somente a próxima etapa programada gera nova solicitação. Recusa ou autorização interrompem a repetição.

O destinatário é cadastrado em **Administração → Gerenciador de Tabelas → Perfis e acessos → Destinatário das notificações**. Selecione a conta administradora, preencha WhatsApp com DDD (ou vincule o colaborador), marque **Receber por WhatsApp** e salve. A rotina reutiliza esse cadastro; não cria uma segunda configuração de número.

As datas usam segunda a sexta, feriados nacionais e da Bahia, excluindo pontos facultativos. A parcial cai no dia útil mais próximo do dia 15; em empate, o posterior. A ficha completa é cobrada no último dia útil. A nova ficha PDF é oferecida no primeiro dia útil do mês. Feriados municipais não são presumidos a partir do texto livre da cidade.

Em novembro/2026 as fichas já foram enviadas pelo RH. O histórico marca essa informação sem afirmar aceite do WhatsApp nem inventar uma data de entrega. Próximas perguntas: **16/11/2026, às 7h**, parcial; **30/11/2026, às 7h**, ficha completa. O primeiro pedido de envio de novo PDF é **01/12/2026, às 7h**.

O agendador consulta a resposta a cada cinco minutos, somente na conversa do administrador e enquanto houver uma pergunta confirmada e pendente. Aceita apenas 1 ou 2 recebidos do número configurado, depois da pergunta e até o vencimento; ignora mensagens antigas, de outros números e enviadas pelo próprio robô. A primeira resposta válida encerra a decisão. A consulta pode terminar até dez minutos depois das 18h para capturar respostas que chegaram dentro do prazo; respostas enviadas depois das 18h continuam inválidas. O processamento de um aceite no limite do horário tem até trinta minutos para concluir. Não usa outros chats nem interfere em outros fluxos do n8n.

Existe somente uma pergunta pendente por vez. Uma repetição da cobrança final no primeiro dia do mês seguinte tem prioridade sobre a pergunta da nova ficha. Esta última aguarda a decisão ou o encerramento da anterior, podendo ser apresentada depois. A autorização continua vinculada à competência e à etapa indicadas na pergunta; não vale para outras etapas.

Após a autorização, a lista e o vínculo ativo são reconferidos. Quem foi removido não recebe os próximos envios. Quem foi acrescentado depois da pergunta entra nas próximas solicitações. Desligados e cadastros com telefone inválido não recebem. A pergunta vale para os inscritos listados; a mesma resposta ou etapa não pode criar envios duplicados.

A ficha é um PDF A4 individual, sem senha, anexado pelo WAHA; usa o mesmo modelo do download do painel. CPF, função, empresa e cidade são obtidos no momento da geração. Não cria PDF público no Drive e não preenche os horários. A mensagem final pede concluir a ficha após a saída, quando ainda houver expediente no dia.

O painel mostra autorização e histórico de envios. **Aceito pelo WhatsApp** não comprova leitura, assinatura ou devolução da ficha preenchida. Falhas e respostas sem identificação de mensagem ficam separadas; envios incertos não são repetidos automaticamente. Após a etapa, o RH recebe um resumo por colaborador. A chave geral pausa pedidos e envios; retirar alguém da lista cancela suas pendências sem apagar o histórico.

O workflow dedicado é **RH PRIME — Fichas manuais de ponto**, `tAvrAWqT8C5qDycG`. O cron `rh_ponto_fichas` roda a cada cinco minutos e chama o webhook com autorização temporária de uso único. A função `admin-notifications` valida cada capacidade no banco, gera o anexo quando necessário e registra a resposta. Credenciais WAHA permanecem na credencial já existente do n8n. Dados de execução bem-sucedida, falha e execuções manuais não são salvos pelo novo fluxo, preservando o conteúdo do PDF e da conversa.

Estrutura inicial: `supabase/sql/rh_ponto_fichas_automaticas.sql`, `rh_ponto_fichas_aprovacao.sql`, `rh_ponto_fichas_clock.sql`, `rh_ponto_fichas_finalizar.sql`, `rh_ponto_fichas_dispatch_fix.sql` e `rh_ponto_fichas_repeticao.sql`, nessa ordem. A rotina é ativada depois de configurar o webhook publicado. O processamento de notificações administrativas e experiência mantém seu comportamento anterior.

Validação: `node --test tests/rh_ponto_fichas*.test.cjs` e `tests/ponto_fichas_aprovacao_rollback.sql` (transação desfeita, sem enviar WhatsApp). Testa autorização, recusa, expiração, remetente, horário, repetição, remoção e preservação do histórico. O teste de integração do webhook usa uma capacidade inválida, bloqueada antes do WhatsApp.
