# Perfis, áreas e notificações

No administrativo, abra **Gerenciador de Tabelas → Perfis e acessos**. A tela permite aprovar, bloquear e configurar cada conta. Novos cadastros começam pendentes e sem acesso a áreas.

O papel identifica a responsabilidade: sem papel específico, supervisor, coordenador, gerente ou administrador. A autorização depende também da situação, das áreas e da permissão de consulta ou edição. Escolher um papel de supervisão não libera automaticamente todas as filiais.

Cada área é uma combinação de filial e setor. Por exemplo, FILIAL 5 + MERCHANDISING libera somente essa combinação. Uma filial sem setor libera seus setores; um setor sem filial libera esse setor nas filiais. Para autorizar áreas distintas, adicione linhas separadas. O banco verifica as regras em cada leitura e gravação, inclusive nas operações de férias. Um perfil não pode promover o próprio acesso. As contas já aprovadas conservaram o acesso existente nesta atualização.

## Avisos ao administrador

Em **Destinatário das notificações**, selecione a conta administradora. Opcionalmente vincule um colaborador para obter o nome e WhatsApp; sem vínculo, informe esses dados manualmente. Marque **Receber por WhatsApp** e salve. O número deve incluir DDD. O vínculo acompanha alterações posteriores do telefone do colaborador.

Novos cadastros e alterações autorizadas de colaboradores, faltas/atestados e férias geram avisos ao administrador, inclusive quando a ação é de supervisor, coordenador ou gerente. Os avisos informam responsável, colaborador, operação e campos operacionais alterados. O detalhamento anterior/posterior permanece no administrativo. Alterações automáticas sem usuário e propagação de sincronizações não geram avisos repetidos.

O canal começa com eventos novos quando ativado; os eventos anteriores permanecem no painel. Não há envio de e-mail. O canal WhatsApp fica desativado até o administrador informar o destinatário e ativá-lo. Não foi realizado teste de entrega para um número real nesta publicação.

O worker do Supabase executa a cada minuto e entrega eventos ao workflow [RH PRIME — Notificações administrativas](https://login.tail239ac4.ts.net:8443/workflow/Q1jAsYe7sL5EtZaV), no projeto pessoal PRIME DISTRIBUICAO do n8n RH. Usa a credencial WAHA já existente. Cada evento recebe autorização temporária de uso único; o fluxo obtém destinatário e mensagem do banco, evitando que o chamador escolha outros números ou mensagens. `aceito` indica aceite pelo WAHA, não confirmação de leitura. Envios sem confirmação ficam `incerto` e não são repetidos automaticamente.

## Banco e implantação

As migrações aplicadas são `profile_area_access_management`, `admin_whatsapp_notifications` e `admin_notification_events_refinement`. As fontes correspondentes estão em `rh_perfis_acessos.sql`, `rh_notificacoes_admin.sql` e `rh_notificacoes_refinamentos.sql`. A Edge Function `admin-notifications` usa a chave anônima do próprio ambiente, com autorização por evento validada no Postgres; não usa chave privilegiada no navegador ou workflow.

## Verificação

- Testes reais de RLS com transações revertidas: leitura por filial/setor, consulta sem gravação, edição permitida, rejeição de gravação fora da área, bloqueio de autopromoção, preservação do administrador e bloqueio de conta suspensa.
- Cadastro de teste revertido: perfil pendente sem áreas, aviso persistente e evento para administrador.
- Inclusão de atestado por supervisor, revertida: evento com responsável e colaborador.
- Autorização de evento, normalização de destinatário, bloqueio de duplicidade e registro do resultado, sem enviar mensagens.
- Teste Supabase → n8n → Edge Function: evento inválido bloqueado antes de executar o nó WAHA.
- Navegador com dados fictícios: configuração e gravação de perfis e destinatário manual em 320, 390, 430 e 1280 px; pesquisa filtrada com área visível reduzida; divisórias nos temas claro e escuro; logout com sucesso, falha e requisição pendente.

A busca preserva a altura da página durante a digitação e mantém o campo na área visível. O teste de teclado é uma simulação de viewport no Chrome; a confirmação final no Safari/iPhone depende de uso no aparelho. O logout limpa a sessão deste projeto e redireciona ao login mesmo em falha de rede. O botão de tema do login fica discreto no canto superior direito, com rótulo acessível e área de toque de 44 px.

## Vencimento de férias no histórico

O prazo concessivo aparece destacado ao lado do período aquisitivo, inclusive após o saldo ser quitado e nos períodos projetados. Não houve alteração do cálculo ou das datas cadastradas. Referências não conferidas continuam identificadas e avisos de divergência permanecem visíveis. Cada saída com datas mostra se o término ocorre até ou depois desse vencimento de referência. O CSV inclui o prazo concessivo. A verificação de navegador cobre períodos quitados com término anterior/posterior e períodos em formação/futuros.
