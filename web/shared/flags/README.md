# Bandeiras locais (offline)

Servidas pelo próprio MOJ para funcionar em contests com internet limitada.

- `country/<iso2>.svg` — bandeiras de países. Fonte: [flag-icons](https://github.com/lipis/flag-icons) (licença MIT).
- `br/<uf>.svg` — bandeiras dos 27 estados do Brasil. Fonte: Wikimedia Commons (domínio público / CC).
- `index.json` — manifesto `{countries:[{code,name}], br_states:[{code,name}]}` usado pelos seletores.

Resolução de código: `XX` (país ISO-2) ou `BR-UF` (estado). Ver `web/shared/flags.js`.
Para atualizar/recachear, re-baixe de flag-icons / Wikimedia Commons com um User-Agent
descritivo e regenere o `index.json` (o manifesto é o que os seletores leem — SVG novo que não
entre nele não aparece na lista).
