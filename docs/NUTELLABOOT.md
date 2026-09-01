# Integração NUTELLABOOT (máquinas maratona linux)

O **nutellaboot** (produção: `https://nutellaboot.mdp.naquadah.com.br`) é o serviço que
gerencia as máquinas **mlinux** das sedes: boot pela rede, telemetria (specs, memória,
load, editores abertos), travamento de tela e comandos. O MOJ se integra a ele POR
CONTEST para três coisas: o **panorama do lado cliente** (como as máquinas se
comportaram na prova, por sede/país, com a MESMA hierarquia do placar), **comandos** nas
máquinas (admin em tudo; `.cstaff`/`.staff` nas da própria sede) e a **correlação
máquina↔time** (roster/binding).

## O modelo de dados do serviço (o que importa p/ o MOJ)

- Cada sede é uma **site-image** com id `26<cc><sede>` que casa com o prefixo de login
  dos times (`26brprcu` ↔ `teambrprcu001`). Existe a imagem de TESTE **`26tete`** —
  todo comando novo se valida NELA antes de tocar sede real.
- `GET /api/v1/site-images/{i}/machines`: por máquina, `status.hwinfo` (processador,
  núcleos, RAM), `sysresources`, `sysdisk`, `operations` (firewall, tela travada,
  `editors_time{<editor>: minutos}`), `binding` (o time vinculado — a correlação),
  `first/last_seen`, alertas.
- `GET …/machines/{mac}/samples[?since=<epoch>&until=<epoch>]`: a série (`{t, mem (% usada),
  ld (load1), sw (swap MB), hd (/home %), ed[] (editores abertos), fw}`) — o serviço devolve
  **400 pontos REAMOSTRADOS sobre o intervalo pedido**. Sem `since/until` eles se espalham pela
  vida da máquina (5 dias ⇒ 45 pontos na prova); o coletor pede a janela da coleta (~1/min).
- `status.hwinfo.machine_id` (+ `boot_id`, `image`) é o que o navegador do mlinux manda no
  User-Agent (`Mozilla/5.0 (MLinux/<imagem>/<machine_id>/<boot_id>) …`) — o **elo
  máquina↔time** (abaixo). `editors_time` é ACUMULADO desde a instalação: não mede a prova.
- `GET /site-images/{i}/roster`: `user_id` **é o login MOJ** — a ponte entre os mundos.
- Comandos: catálogo em `GET /site-images/{i}/commands` (`allowed`: cantouch,
  cleanhomenow, disablefirewall, donottouch, enablefirewall, mlpoweroff, mlreboot,
  precontest, resetcontaeditores); envio por POST **`{command: "<op>"}`** (campo `command`; resposta `{command_id, machines}`) em `/commands` (frota),
  `/site-images/{i}/commands` (sede) ou `…/machines/{mac}/commands` (máquina) — a
  máquina executa no próximo contato (poll).
- Auth: `Authorization: Bearer nb3a_…`. **A chave é PODEROSA** (a de produção é admin).
  O serviço sabe criar **service-keys ESCOPADAS** (`/api/v1/service-keys`: escopos
  `machines:read`, `commands:write`, `roster:write`… + lista de imagens) — quando
  houver uma por contest, troque: o MOJ só precisa de machines:read + commands:write +
  roster:read/write nas imagens do evento.

## Como o MOJ guarda e usa

- **Chave**: `contests/<c>/secrets/nutellaboot.key` (600) — NUNCA no conf (sourced/vai
  em export) e NUNCA em argv (o curl recebe o header por `-K <(printf …)`, molde do
  mojinho-api.sh). Configurada pelo painel **Operação → mlinux** (write-only: o GET só
  diz `configured`). A URL (não-segredo) vai no conf: `NUTELLABOOT_URL`.
- **Lib**: `server/api/v1/lib/nutella.sh` (`nb_configured`, `nb_curl`, `nb_url`,
  `nb_staff_regions`) — sourceada POR HANDLER (rota fria, fora do prelúdio do MOLDE).
- **Coletor**: `server/score/nutella-gen.sh <c> [out] [--reaggregate]` (standalone,
  destacado pelo painel) — baixa imagens/roster/máquinas/samples (xargs -P; ~2.6k requests
  na Maratona; samples com `since/until` = janela [início−1h, fim+1h]), guarda o BRUTO em
  `var/nutella-raw/` (`--reaggregate` refaz tudo dali, sem rede — mudança de view/agregado não
  depende do buffer do serviço), agrega POR SEDE e faz os rollups pela árvore de
  `regions.json` (nó casa por regex contra os logins do roster — o idioma do stats-gen).
  Sede da imagem = `.team.region` do store (fallback: fullname). Saída:
  `var/nutella.cache.json` (+ `var/nutella.status.json` com o progresso). TUDO que vira
  média é guardado como SOMA+N p/ o merge dos rollups ser exato.
- **Relatório 2.0 (01/09) — o que o coletor deriva POR MÁQUINA, só dos pontos DENTRO da
  prova** (`[CONTEST_START, CONTEST_END]`): minutos por editor (pontos × cadência mediana),
  **editor usado** = aberto ≥ 60 min, **máquina usada** = algum editor ≥ 10 min, **perfil
  puro** = um grupo (VS Code · JetBrains=idea/clion/pycharm · Code::Blocks · leves=vim/gedit/
  geany/emacs) em ≥ 60 % dos pontos (leve exige pesado ≤ 10 %; senão `mixed`/`none`), faixa de
  RAM, memória/swap/load (média, 1ª meia hora, última hora, janelas de 30 min).
  **Elo máquina↔time**: `binding` do serviço vem vazio; o coletor casa
  `status.hwinfo.machine_id/boot_id` com o par `machine_id/boot_id` do UA gravado em
  `var/access.log` pelo login (1 jq com `@base64d`; TODO login até o fim da janela — sessão
  não expira, quem logou às 10h é dono da máquina na prova; contas de papel fora; último
  login vence; time com 2 máquinas fica com a de mais pontos — `chosen`). ⚠ O `boot_id` é
  obrigatório na chave: na Maratona 2026, 62 `machine_id` eram CLONADOS (Salvador: 24
  máquinas com o mesmo `/etc/machine-id`; Goiânia: 25; Rio: 39 pares) — só o `machine_id`
  dava todas ao último time. Fallback por `machine_id` sozinho só quando ele é único na
  frota (`dupmids`). `link.present` = times que logaram até o fim da janela; a cobertura é
  `linked/present` (quem nunca logou é ausente, não "sem vínculo"). Posição no placar via `sc_place_map`
  (score-common.sh; prefere `placar-view-all-full` › `placar-full` › `placar`; convidado sem
  posição). `link.mode`: `ua` quando o elo cobre ≥ 50 % dos times das sedes mantidas (população
  "máquina de time" = a escolhida de cada time + usadas sem elo), senão `proxy` (= usadas).
  Chaves por sede (todas mergeáveis; rollup em `by_node`/`global`): `pop{seen,used,linked,
  chosen,ranked,tm,teams}`, `ram_bands` (`<8|8|12|16|24|32|>32`, máquinas de time) e
  `ram_bands_all` (vistas), `ram_sum_tm/ram_n_tm` (+ `ram_avg_sites` no rollup = média das
  médias por sede), `cpu_tm`, `ed_min{editor}`/`ed_min_total`, `ed_adopt{editor}`,
  `ed_groups{vscode,jetbrains,codeblocks,light}`, `ed_count{0,1,2,3+}`, `profiles{…}`,
  `mem/sw/ld _sum/_n`, `pressure{"<8|16|32|>32>|<perfil>": {n, mem_sum, mem_n, sw_sum, sw_n,
  sw_max, mem0_*, mem4_*, series[{t (s desde o início, bins de 30 min), …}]}}`,
  `rank_ed{n, all|top30|q1|p10: {n, ed{}, grp{}, prof{}}}` (editores × colocação DO RECORTE:
  re-rank pela posição global; a view só mostra com ≥ 30). `series[]` (10 min) ganhou
  `sw_sum/sw_n/fw_off`. Topo: `version:2`, `contest{start,end}`, `link{mode,linked,teams,present,
  coverage}`; `pop` ganha `present` por sede. Linhas por time (`_rows`) existem SÓ dentro do coletor e morrem antes de gravar.
  A **view** (`web/lib/mlinux-view.js`) infere fabricante/família/ano do modelo de CPU
  (`cpuInfo`, tabelas de ano dos scripts do artigo da Revista Maratona) e escreve as
  observações automáticas em STE pt/en. **Ranks** por sede: posição no país e no geral em RAM
  média (máquinas de time), núcleos e minutos de editor NA PROVA.
- **Rota**: `GET/POST /contest/nutella` (ver `API.md`). Papéis: admin/chefe tudo;
  `.cstaff`/`.staff` recebem `sedes[]` FILTRADO ao escopo (tokens `region:` do
  staff-filters) — agregados globais vão inteiros (não carregam MAC alheio). Comandos
  são **fail-closed** p/ staff: sem escopo explícito = 403 (diverge de propósito do
  "ausente = vê tudo" das rotas de leitura — comando é ação).
- **UI**: painel **Operação → mlinux** (admin: config/coleta/panorama/comandos) e a
  página avulsa `/contest/mlinux/?c=<id>` (cstaff/staff — linkada da fila do staff
  quando configurado). As seções moram em `web/lib/mlinux-view.js` — a MESMA view do
  painel, da página avulsa e do **relatório offline** (`mlinux.html`, gerado pelo
  report-gen QUANDO o cache existe; sem MAC, sem `teams`, sem `_rows` — só agregados/
  ranks/séries; o "editores × colocação" é contagem por recorte). A view recebe o cache
  inteiro + a árvore (`name/view/subregions`) + o recorte, e compara os FILHOS do nó
  (subregiões com dado, ou as sedes dele); nós `view:true` ficam fora da comparação.
- **Correlação**: o elo de verdade é o do coletor (UA do login × `machine_id`, acima). O
  campo `binding` da máquina (lado nutellaboot) continua vazio e é consumido se um dia
  existir; `POST {action:"push-roster"}` PUBLICA o roster do STORE nas imagens
  (user_id=login, nome do time, universidade, país) — sem `force` ele NUNCA atropela
  roster já povoado (o da Maratona veio do ICPC).
- **Quando coletar**: logo depois da prova (o serviço reamostra 400 pontos sobre a janela
  pedida, então a resolução não depende de quando; mas máquinas religadas muito depois podem
  perder histórico). Recoletar é barato; o bruto fica guardado p/ `--reaggregate`.

## Testes

`server/test/smoke-contest-nutella.sh` roda contra o **mock** `nutella-mock.py`
(stdlib; serve fixtures com os shapes reais, REGISTRA POST/PUT e o GET de samples com a
query) — cobre config, escopo, coleta ponta-a-ponta (since/until, elo por UA com conta de
papel tentando roubar o vínculo, adoção/perfis/pressão/rank_ed, privacidade do cache,
`--reaggregate` sem rede, modo proxy sem access.log), catálogo, gates de comando e
push-roster. O relatório é coberto no `smoke-contest-report.sh` (página condicional, sem
MAC/teams/_rows, view 2.0 embutida, invariantes). O jq do coletor vive em VARIÁVEIS
(`AGG_JQ`), que o `jq-portability.sh` não vê: rode o coletor com o jq 1.7 da imagem
(`--reaggregate` num bruto guardado) antes de deployar mudança nele.
