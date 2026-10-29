# RH PRIME

Sistema de recursos humanos: colaboradores, equipamentos, férias, indicadores e preparação de documentos para assinatura.

[Abrir o sistema](https://dasksz.github.io/RH-PRIME/) · [Documentos para assinatura](https://dasksz.github.io/RH-PRIME/documentos-web.html)

## Onde encontrar cada parte

| Pasta | Conteúdo |
| --- | --- |
| [assets/](assets/) | JavaScript, CSS e imagens usados pelas páginas |
| [docs/](docs/) | Guias de instalação, configuração e uso |
| [automations/python/](automations/python/) | Preparação de PDFs e avisos do Facilita Ponto |
| [integrations/google-apps-script/](integrations/google-apps-script/) | Sincronização, Drive e processador de mensagens |
| [n8n/](n8n/) | Fontes dos fluxos; versões antigas em `legacy/` |
| [supabase/functions/](supabase/functions/) | Código das funções de servidor |
| [supabase/migrations/](supabase/migrations/) | Migrações versionadas existentes |
| [supabase/sql/](supabase/sql/) | Scripts SQL de instalação e manutenção; preservar a ordem indicada nos guias |
| [desktop/](desktop/) | Aplicativo Windows e seus testes |
| [tests/](tests/) | Testes do site e das integrações |
| [build/](build/) | Configuração e entrada de compilação dos estilos |

As páginas HTML permanecem na raiz para preservar os links publicados e o GitHub Pages. O manifesto e o service worker também ficam na raiz para manter o escopo da instalação.

## Guias principais

- [PDFs e avisos do Facilita Ponto](docs/DOCUMENTOS_WEB_N8N.md)
- [Automações web](docs/AUTOMACOES_WEB.md)
- [Aplicativo Windows](desktop/README.md)
- [Estilos](docs/ESTILOS.md)
- [Equipamentos](docs/equipamentos.md)
- [Perfis e notificações](docs/perfis-e-notificacoes.md)

## Desenvolvimento

Para servir o site localmente, execute `python -m http.server 8000` na raiz. Os testes JavaScript usam `node --test tests/*.test.cjs`. Para o aplicativo Windows, consulte `desktop/README.md`.

Mudanças de localização no repositório não alteram os scripts já instalados no Google, fluxos n8n ou o banco. Consulte os guias antes de aplicar SQL: arquivos de migração e configuração fazem parte do histórico operacional.

Credenciais, tokens, relatórios de colaboradores, PDFs gerados e logs locais não devem ser adicionados ao Git.
