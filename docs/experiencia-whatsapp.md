# Avisos de contrato de experiência

No Portal Admin → Gerenciador de Tabelas → Perfis, configure o perfil do supervisor, coordenador ou gerente: informe o WhatsApp com DDD e marque **Receber avisos de experiência**. O WhatsApp também pode ser informado na criação da conta; o RH aprova o papel e ativa os avisos posteriormente.

Em **Experiência — gestor do colaborador**, busque o colaborador, selecione seu gestor específico e salve. O gestor precisa estar aprovado e ter acesso à filial/setor do colaborador. Não há atribuição automática para todos os gestores da área. Remover o vínculo interrompe os avisos pendentes.

A rotina verifica diariamente às 08h de Brasília. Calcula 90 dias corridos após a admissão e avisa a partir de 80 dias após a admissão, uma vez por colaborador/data de admissão. Se o vínculo ou telefone for cadastrado entre o dia 80 e o dia 89, o aviso pode sair na próxima verificação. Após 90 dias, não envia aviso retroativo. Datas inválidas e colaboradores desligados são ignorados.

A mensagem contém nome, função, filial/setor, admissão, término previsto e dias restantes. O painel mantém o status do envio. `aceito` significa que o WAHA aceitou a solicitação; não confirma leitura pelo destinatário. `incerto` exige conferência no n8n antes de qualquer reenvio para evitar duplicados.

## Integração

`rh_experiencia.sql` adiciona os campos e agendas ao Supabase. Reutiliza o fluxo publicado **RH PRIME — Notificações administrativas** e a função `admin-notifications`. O evento possui token de uso único com validade de 10 minutos. No momento do envio, o banco confere novamente gestor, telefone, aprovação, acesso à área, desligamento e data de admissão.

O prazo de 90 dias é o padrão operacional desta automação. Para contratos com duração diferente, essa regra precisa ser ajustada antes de habilitar os avisos.

Teste de banco: `tests/rh_experiencia.sql`, com rollback e sem chamadas HTTP. Prévia das telas com dados fictícios: `tests/experience_preview.html`.
