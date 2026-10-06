# Busca da pasta de colaborador

Em Automações, o botão Buscar pasta consulta as raízes configuradas de ativos e ex-funcionários, com a conexão Google Drive do Apps Script. Não cria, move, compartilha pastas nem salva vínculos. A lista de tarefas começa recolhida. Configurações de pastas abre e fecha o módulo no topo da página.

Se o colaborador já possui vínculo, o ID aparece no campo com um link para conferir no Drive. A busca é destinada aos colaboradores sem vínculo. Uma correspondência preenche o campo; várias correspondências exigem escolha. Nenhuma correspondência deixa o preenchimento manual disponível. Após conferir, clique em Salvar vínculo para registrar o ID.

## Instalar no Apps Script

1. Substitua o conteúdo de AUTOMAÇÃO PL RH.gs pelo google_apps_script_atualizado.js deste pacote. Essa versão inclui o encaminhamento autenticado da busca e mantém a migração das chaves modernas.
2. Crie um novo arquivo de script chamado RH_Drive_Busca e cole RH_Drive_Busca.gs.
3. Mantenha RH_Drive_Automacoes.gs, RH_Documentos_N8N.gs e as propriedades já configuradas, incluindo SUPABASE_KEY.
4. Salve. Em Implantar → Gerenciar implantações → Editar, escolha Nova versão e implante mantendo a mesma URL.
5. Entre no site como administrador, escolha um colaborador sem vínculo e clique em Buscar pasta. Confira o link e só depois salve o vínculo.

A função drive-folder-lookup do Supabase já foi publicada. Ela valida a sessão e o perfil atual de administrador. O Apps Script repete essa autorização antes de consultar o Drive. Não há chaves novas para configurar.

Se a URL da implantação mudar futuramente, configure RH_APPS_SCRIPT_URL nos secrets da função do Supabase. A busca usa as mesmas raízes e regras de CPF/nome/vínculo que o processador; não varre pastas fora dessas raízes.

O teste completo com o Drive depende da instalação desses dois arquivos no projeto Apps Script, que não é atualizado automaticamente pelo GitHub.
