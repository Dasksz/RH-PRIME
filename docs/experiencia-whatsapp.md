# Avisos de contrato de experiência

No Portal Admin → Gerenciador de Tabelas → Perfis, configure o perfil do supervisor, coordenador ou gerente: informe o WhatsApp com DDD e marque **Receber avisos de experiência**. O WhatsApp também pode ser informado na criação da conta; o RH aprova o papel e ativa os avisos posteriormente.

Em **Experiência — gestor do colaborador**, busque o colaborador, selecione seu gestor específico e salve. O gestor precisa estar aprovado e ter acesso à filial/setor do colaborador. Não há atribuição automática para todos os gestores da área. Remover o vínculo interrompe os avisos pendentes.

A rotina verifica diariamente às 08h de Brasília. O prazo total é de 90 dias corridos após a admissão, dividido em dois períodos de 45 dias:

| Aviso | Quando começa | Término do período |
|---|---|---|
| Primeiro período | 38 dias após a admissão | 45 dias após a admissão |
| Segundo período | 83 dias após a admissão | 90 dias após a admissão |

Cada aviso é independente: o envio do primeiro não impede o segundo. Um aviso por colaborador/data de admissão/período, somente ao gestor vinculado. Se a configuração ocorrer após o dia do aviso, a rotina recupera o primeiro entre os dias 38 e 44 e o segundo entre os dias 83 e 89. Não envia aviso retroativo depois do fim do respectivo período. Datas inválidas e colaboradores desligados são ignorados.

A mensagem identifica o período e contém nome, função, filial/setor, admissão, término previsto e dias restantes naquele período. Nas datas de aviso, faltam sete dias para o término. O painel mantém o status. `aceito` significa que o WAHA aceitou a solicitação; não confirma leitura. `incerto` exige conferência no n8n antes de reenvio.

## Integração

Aplicar `rh_experiencia.sql` e, em seguida, `rh_experiencia_periodos.sql`. A atualização preserva o histórico dos avisos antigos como segundo período e invalida capacidades pendentes não utilizadas. Reutiliza o fluxo publicado **RH PRIME — Notificações administrativas** e a função `admin-notifications`; não exige alteração no n8n, Apps Script ou Google Sheets.

O evento possui token de uso único com validade de 10 minutos. No envio, o banco confere novamente gestor, telefone, aprovação, acesso à área, desligamento, data de admissão e período correspondente.

Teste atual: `tests/rh_experiencia_periodos.sql`, com rollback e sem chamadas externas. O teste `tests/rh_experiencia.sql` documenta apenas a regra anterior e deve ser executado antes da atualização de períodos. Prévia das telas com dados fictícios: `tests/experience_preview.html`.

