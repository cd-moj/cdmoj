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
- `GET …/machines/{mac}/samples`: a série (`{t, mem, ld, sw, hd, ed[], fw}` ~400 pontos).
- `GET /site-images/{i}/roster`: `user_id` **é o login MOJ** — a ponte entre os mundos.
- Comandos: catálogo em `GET /site-images/{i}/commands` (`allowed`: cantouch,
  cleanhomenow, disablefirewall, donottouch, enablefirewall, mlpoweroff, mlreboot,
  precontest, resetcontaeditores); envio por POST `{op}` em `/commands` (frota),
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
- **Coletor**: `server/score/nutella-gen.sh <c>` (standalone, destacado pelo painel) —
  baixa imagens/roster/máquinas/samples (xargs -P; ~2.6k requests na Maratona), agrega
  POR SEDE (specs, rank de editores, estado, série em janelas de 10 min na janela
  [início−1h, fim+1h]) e faz os rollups pela árvore de `regions.json` (nó casa por
  regex contra os logins do roster — o idioma do stats-gen). Sede da imagem =
  `.team.region` do store (fallback: fullname). **Ranks** por sede: posição no país e
  no geral em RAM média, núcleos e minutos de editor. Saída:
  `var/nutella.cache.json` (+ `var/nutella.status.json` com o progresso). Séries
  guardam SOMAS (`mem_sum/mem_n`) p/ o merge dos rollups ser exato.
- **Rota**: `GET/POST /contest/nutella` (ver `API.md`). Papéis: admin/chefe tudo;
  `.cstaff`/`.staff` recebem `sedes[]` FILTRADO ao escopo (tokens `region:` do
  staff-filters) — agregados globais vão inteiros (não carregam MAC alheio). Comandos
  são **fail-closed** p/ staff: sem escopo explícito = 403 (diverge de propósito do
  "ausente = vê tudo" das rotas de leitura — comando é ação).
- **UI**: painel **Operação → mlinux** (admin: config/coleta/panorama/comandos) e a
  página avulsa `/contest/mlinux/?c=<id>` (cstaff/staff — linkada da fila do staff
  quando configurado). As seções moram em `web/lib/mlinux-view.js` — a MESMA view do
  painel, da página avulsa e do **relatório offline** (`mlinux.html`, gerado pelo
  report-gen QUANDO o cache existe; sem MAC — só agregados/ranks/séries).
- **Correlação (futuro próximo)**: o campo `binding` da máquina liga MAC→login e o
  coletor/view já o consomem quando existir; `POST {action:"push-roster"}` PUBLICA o
  roster do STORE nas imagens (user_id=login, nome do time, universidade, país) — sem
  `force` ele NUNCA atropela roster já povoado (o da Maratona veio do ICPC). O elo que
  falta é o mlinux gravar o binding no login do time (lado nutellaboot).

## Testes

`server/test/smoke-contest-nutella.sh` roda contra o **mock** `nutella-mock.py`
(stdlib; serve fixtures com os shapes reais e REGISTRA POST/PUT) — cobre config,
escopo, coleta ponta-a-ponta, catálogo, gates de comando e push-roster. O relatório é
coberto no `smoke-contest-report.sh` (página condicional, sem MAC, invariantes).
