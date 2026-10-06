# Migração de chaves — 06/10/2026

O site, o código do aplicativo desktop e a função admin-notifications usam a chave publicável padrão (`sb_publishable_`). A função aceita exclusivamente a autorização temporária de cada evento, validada pelo banco. Os fluxos n8n conferidos não contêm chaves Supabase legadas. O aplicativo desktop já instalado, se usado, precisa ser atualizado com o novo código antes da desativação da anon.

Os três arquivos Apps Script do repositório foram ajustados para a nova chave secreta. Ela é enviada no cabeçalho apikey; o cabeçalho Authorization continua reservado ao OAuth do Google e aos tokens JWT nas chamadas que ainda usam a chave legada durante a transição. A configuração inicial não restaura uma chave privilegiada no código.

## Etapa no projeto Apps Script

O código do repositório não atualiza automaticamente o projeto Apps Script instalado.

1. Substitua o conteúdo de `AUTOMAÇÃO PL RH.gs` pelo arquivo `google_apps_script_atualizado.js` deste repositório.
2. Substitua também `RH_Drive_Automacoes.gs` e `RH_Documentos_N8N.gs` pelos arquivos correspondentes deste repositório.
3. Em Configurações do projeto → Propriedades do script → Editar propriedades, substitua somente o valor de `SUPABASE_KEY` pela chave secreta nova que começa com `sb_secret_`. Mantenha `SUPABASE_URL` e as demais propriedades.
4. Salve e execute `verificarConexaoSupabaseRH`. Esse teste consulta as três conexões REST sem alterar registros nem enviar mensagens. Deve exibir: “Conexão REST com a nova chave secreta validada.”
5. Em Implantar → Gerenciar implantações → Editar, selecione Nova versão e implante mantendo a URL existente. Não crie outra implantação.
6. Confira login no site, consulta de colaboradores e uma execução normal dos sincronizadores e documentos no Apps Script. Só então desative as chaves legadas anon e service_role no painel Supabase. Não troque nem revogue a chave de assinatura JWT dos usuários para fazer esta migração.

Não cole a chave secreta no site, no GitHub ou em mensagens. A chave publicável do site já foi substituída; nenhuma colagem manual dela é necessária.

Documentação: https://supabase.com/docs/guides/getting-started/migrating-to-new-api-keys
