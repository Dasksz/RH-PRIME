# Estilos do sistema

As páginas usam `rh-utilities.css`, gerado com Tailwind CSS 3.4.17. Não há compilação de estilos no navegador nem dependência de cdn.tailwindcss.com.

Após alterar classes nos HTMLs ou JavaScript, gere novamente o CSS com a CLI oficial da mesma versão:

```sh
tailwindcss -c tailwind.config.cjs -i tailwind-input.css -o rh-utilities.css --minify
```

A CLI independente da versão 3.4.17 está em https://github.com/tailwindlabs/tailwindcss/releases/tag/v3.4.17. Execute a partir da raiz do repositório. Publique o CSS gerado junto das páginas. Preserve a ordem: utilitários antes de rh-responsive.css e rh-theme.css.
