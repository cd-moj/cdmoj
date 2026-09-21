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
- **Séries — em LOTE, uma chamada por sede**: `GET /site-images/{i}/samples?since&until&limit&active_since`
  devolve **NDJSON**, uma linha por máquina: `{mac, points[], native_points, resampled, interval_s, since,
  until, truncated}`. `limit` vai até **5000** (o default, 400, REAMOSTRA a janela); `active_since` poupa
  quem não apareceu. A rota por máquina (`…/machines/{mac}/samples`) devolve o mesmo objeto e segue
  existindo — é o fallback do coletor quando o lote dá 404 (serviço antigo). Sem `since/until` os pontos
  se espalham pela vida da máquina (5 dias ⇒ 45 pontos na prova).
- **O ponto** (`points[]`): `t, mem (% usada), ld (load1), sw (swap MB), hd (/home %), ed[] (editores
  abertos), fw, lk (tela travada)` — e, **só do agente novo** (set/2026): `psi_mem/psi_cpu/psi_io` (PSI
  `some avg60`, % do tempo com processo PARADO esperando o recurso — pressão de verdade, não "% de memória
  usada"), `oom` (OOM kills ACUMULADOS), `idle` (s sem teclado/mouse), `skew` (s de desvio do relógio),
  `edm/eds` (minutos de editor acumulados desde `eds`). Frota MISTA é o caso real (em 21/09/2026 a `26tete`
  tinha uma máquina de cada agente): todo campo novo é opcional, do coletor à tela.
- **A máquina** ganhou `boot_id`, `boots`, `last_boot`, `editors_reset_at`, `status.t_agent` (hora do agente;
  a presença dele = agente novo) e `status.hwinfo.{mac, hostname, dmi_uuid, product_vendor, product_name,
  uptime_s, last_boot}`. Alertas têm `kind`: `identity.duplicate` (com `other_mac` — home clonada por
  imagem de disco), `usb.storage|phone|network|other`; `kind` desconhecido é aceito.
- `status.hwinfo.machine_id` (+ `boot_id`, `image`) é o que o navegador do mlinux manda no
  User-Agent — o **elo máquina↔time** (abaixo). Agente antigo: `Mozilla/5.0 (MLinux/<imagem>/<machine_id>/
  <boot_id>) …`. **Agente novo (set/2026): `…/<boot_id>/<mac>)`** — o MAC entra no FIM (quem lê por posição
  continua lendo), no formato do `.mac` do serviço (`aa-bb-cc-dd-ee-ff`), e o `machine_id` passa a ser
  **`md5(MAC estável)`**, regravado a cada boot: acabou o `/etc/machine-id` clonado por imagem de disco. Sem
  MAC estável o campo vem vazio (e o MOJ trata como agente antigo). `editors_time` é ACUMULADO desde a
  instalação: não mede a prova.
- **Vínculo (`binding`)**: `PUT /site-images/{i}/machines/{mac}/binding {user_id, source?, at?, boot_id?,
  note?}` (escopo `bindings:write`; **404 se o `user_id` não está no roster da imagem**), `DELETE`, `GET
  …/binding/history`, `GET …/bindings`. Vinculada, a tela de bloqueio da máquina mostra o time. Vincular
  máquina que ainda não reportou funciona, mas ela só aparece em `/bindings` depois do 1º boot.
- `GET /site-images/{i}/roster`: `user_id` **é o login MOJ** — a ponte entre os mundos.
- Comandos: catálogo em `GET /site-images/{i}/commands` → `{allowed:[…], blocked:{comando: campo}}` (o que
  ESTA credencial pode mandar: cantouch, cleanhomenow, disablefirewall, donottouch, enablefirewall,
  mlpoweroff, mlreboot, precontest, resetcontaeditores). Envio: **sempre a rota DA SEDE**,
  `POST /site-images/{i}/commands` com **`{command, target, args?, delay?}`** — `target` é `"all"` ou uma
  LISTA de MACs — e a resposta é `{command_id, machines}`. A máquina busca no long-poll (segundos); ordem
  que ninguém buscou **caduca em 10 min**. ⚠ **Não existe** `POST …/machines/{mac}/commands` (aquele caminho
  só tem o GET do long-poll da própria máquina: **405**), e a rota de frota `POST /commands` exige
  `targets:{sede: "all"|[macs]}` **e credencial de console**. O MOJ usou as duas erradas até 21/09/2026 e o
  mock, que aceitava qualquer POST, escondeu — hoje o mock é estrito como o serviço.
- Auth: `Authorization: Bearer …`, em duas classes que o MOJ aceita:
  - **`nb3s_…` — chave de SERVIÇO, a recomendada.** Criada pela administração do nutellaboot em
    `POST /service-keys {name, scopes, images}`; o MOJ precisa de `machines:read`, `commands:write`,
    `bindings:write`, `roster:read`, `roster:write` nas imagens do evento (`images:["26*"]`). Ela **não entra
    nas rotas de console**: `/whoami` e a listagem `/site-images` dão **401**, `GET /site-images/{i}` dá 403,
    `POST /commands` (frota) dá 401 — por isso as sedes do evento vão no conf (`NUTELLABOOT_IMAGES`).
  - `nb3a_…` — chave de ADMINISTRAÇÃO: faz tudo, em TODAS as sedes do serviço (que hospeda outros eventos).
    Funciona, mas é mais poder do que a integração precisa; o painel a marca em amarelo.

## Como o MOJ guarda e usa

- **Chave**: `contests/<c>/secrets/nutellaboot.key` (600) — NUNCA no conf (sourced/vai
  em export) e NUNCA em argv (o curl recebe o header por `-K <(printf …)`, molde do
  mojinho-api.sh). Configurada pelo painel **Máquinas › mlinux** (write-only: o GET só
  diz `configured` e a CLASSE da chave, `key_kind: admin|service`). Não-segredos vão no conf:
  `NUTELLABOOT_URL` e **`NUTELLABOOT_IMAGES`** (ids das site-images do evento, separados por espaço —
  obrigatório com chave de serviço; com chave admin é opcional e só RESTRINGE a coleta).
- **"Todas as sedes" é do CONTEST, nunca do serviço**: o comando com `image:"all"` manda UMA ordem por
  sede do evento (cache da coleta ∪ `NUTELLABOOT_IMAGES`) e responde `{ok, failed, sedes:{<id>:{status,
  command_id, machines, detail?}}}` — a sede que recusou (cadeado do modelo = 403) aparece pelo nome, e as
  outras seguem. A rota de frota do serviço atingiria sedes de OUTROS eventos.
- **Lib**: `server/api/v1/lib/nutella.sh` (`nb_configured`, `nb_curl`, `nb_url`,
  `nb_staff_regions`) — sourceada POR HANDLER (rota fria, fora do prelúdio do MOLDE).
- **Coletor**: `server/score/nutella-gen.sh <c> [out] [--reaggregate]` (standalone,
  destacado pelo painel) — baixa imagens/roster/máquinas (xargs -P) e as séries **em lote, 1 request
  por sede** (`limit=5000`, `active_since` = início da janela; janela = [início−1h, fim+1h]). Era 1 request
  POR MÁQUINA: ~1.700 na Maratona, 1 min 16 s; o lote de uma sede de 29 máquinas volta em 0,15 s e a
  coleta inteira dela em 0,6 s (medido em 21/09/2026). Guarda o BRUTO em `var/nutella-raw/`
  (`samples/<sede>.ndjson`; `--reaggregate` refaz tudo dali, sem rede — mudança de view/agregado não
  depende do buffer do serviço). O leitor junta os DOIS leiautes de bruto — o novo e o por máquina
  (`samples/<sede>.<mac>.json`, o da LATAM 2026 e o do fallback) — e o smoke prende que dão o MESMO
  cache. Agrega POR SEDE e faz os rollups pela árvore de
  `regions.json` (nó casa por regex contra os logins do roster — o idioma do stats-gen).
  **Cadência** = `interval_s` do serviço quando `resampled:false` (20–600 s); senão a mediana dos `dt`.
  **Quais sedes entram**: TIMES da imagem = (roster ∩ logins do contest) ∪ (logins FORA de todo roster que
  entraram com o UA daquela imagem — `MLinux/<imagem>/…` no `var/access.log`; conta de papel fora). O
  roster MANDA (time do roster da sede B que logou de uma máquina da A continua da B). Entra a imagem que
  tem time **ou** que foi listada à mão em `NUTELLABOOT_IMAGES`. ⚠ Em 21/09/2026 o roster estava VAZIO em
  todas as imagens do serviço, inclusive na do evento da semana: a regra antiga (só roster ∩ logins)
  terminava em "nenhuma sede casa". Sede cujo `machines` não veio (rede, 403 do escopo) vai p/ `skipped`
  do cache e o painel avisa; se NENHUMA veio, a coleta FALHA dizendo isso e o cache anterior fica — nunca
  um `ok:true` todo zerado.
  Sede da imagem = `.team.region` do store (fallback: fullname); país = bandeira do 1º time (fallback:
  2 letras do id). Saída:
  `var/nutella.cache.json` (+ `var/nutella.status.json` com o progresso). TUDO que vira
  média é guardado como SOMA+N p/ o merge dos rollups ser exato.
- **Relatório 2.0 (01/09) — o que o coletor deriva POR MÁQUINA, só dos pontos DENTRO da
  prova** (`[CONTEST_START, CONTEST_END]`): minutos por editor (pontos × cadência mediana),
  **editor usado** = aberto ≥ 60 min, **máquina usada** = algum editor ≥ 10 min, **perfil
  puro** = um grupo (VS Code · JetBrains=idea/clion/pycharm · Code::Blocks · leves=vim/gedit/
  geany/emacs) em ≥ 60 % dos pontos (leve exige pesado ≤ 10 %; senão `mixed`/`none`), faixa de
  RAM, memória/swap/load (média, 1ª meia hora, última hora, janelas de 30 min).
  **Elo máquina↔time** — o coletor casa a máquina com o UA gravado em `var/access.log` pelo login
  (1 jq com `@base64d`; TODO login até o fim da janela — sessão não expira, quem logou às 10h é dono da
  máquina na prova; contas de papel fora; último login vence; time com 2 máquinas fica com a de mais
  pontos — `chosen`), em QUATRO degraus, do mais forte ao mais fraco:
  1. **MAC do UA ↔ `.mac`** (agente novo) — exato; sobrevive a reboot e a machine-id clonado;
  2. `machine_id/boot_id` (agente antigo). ⚠ O `boot_id` é obrigatório nesta chave: na Maratona 2026, 62
     `machine_id` eram CLONADOS (Salvador: 24 máquinas com o mesmo `/etc/machine-id`; Goiânia: 25; Rio: 39
     pares) — só o `machine_id` dava todas ao último time. Um reboot depois do login perde este elo;
  3. `machine_id` sozinho, só quando ele é único na frota (`dupmids`);
  4. o **`binding` do próprio serviço**, quando o UA não disse nada e o `user_id` é time DAQUELA sede (o
     staff vinculou à mão, ou o access.log se perdeu). Binding de login alheio à sede é ignorado. `link.present` = times que logaram até o fim da janela; a cobertura é
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
- **Telemetria do agente novo (NutellaBoot 3, 21/09)** — tudo SOMA+N/contagem (o rollup é um `madd`) e
  tudo opcional. Por sede/nó/global: **`health{agent_new, psi_mem_sum, psi_cpu_sum, psi_io_sum, psi_n,
  oom_machines, oom_kills, idle_pts, idle_hi, skew_n, skew_bad, reboots}`** — `agent_new` é o DENOMINADOR
  ("0 OOM em 12 máquinas que medem"; sem ele "0 OOM" seria indistinguível de "ninguém mede"); `oom_kills`
  = soma dos incrementos positivos do contador DENTRO da prova; `idle_hi` = pontos com `idle` > 300 s;
  `skew_bad` = |mediana do `skew`| > 120 s; `reboots` = `last_boot` dentro de (início, fim] da prova.
  `psi_mem_max`, **`model_tm{"<fabricante> <produto>": n}`** (máquinas de time; `hostname`, `dmi_uuid` e MAC
  NÃO entram em agregado), **`alert_kinds{kind: n}`** ao lado da contagem `alerts`. `pressure{…}` ganha
  `psi_sum/psi_n/psi_max` (e `psi_sum/psi_n` por bin de 30 min); `series[]` ganha `psi_sum/psi_n`;
  `sedes[].machines[]` ganha `model`, `oom`, `agent_new`. Na view: seção **🩺 Saúde das máquinas na prova**
  (só com `health.agent_new > 0`), "Modelo do equipamento" em Hardware, gráfico e colunas de PSI em Pressão,
  alertas POR TIPO em Atenção e as definições no "Como ler" — cache antigo rende exatamente a tela de antes
  (`smoke-mlinux-view.gjs.sh` renderiza os dois, pt e en).
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
- **O LOGIN publica o vínculo** (`lib/nutella-bind.sh`, 21/09): com o UA do agente novo, o login de um
  time DIZ em que máquina ele está, e o MOJ faz o `PUT …/binding {user_id, source:"moj-login", at, boot_id}`.
  **Custo zero no login**: o handler só acrescenta uma linha em `var/nutella-bind.queue` (`printf`, builtin;
  as guardas — `*MLinux/*` no UA e a chave configurada — também) e, no máximo a cada 10 s, larga um
  **drenador destacado** (molde `owner_rename_bg`: redirects no `setsid`; `MOJ_JOBS_SYNC=1` roda em linha nos
  testes) — quem fala com o serviço é ele (`-m 8`), nunca o worker do login; medido com o serviço
  respondendo em 2 s: login em 95 ms. Um drenador por contest (`flock`); ele carimba o INÍCIO de cada passada
  e só sai com a fila vazia DEPOIS de dormir 10 s, e quem chega espera o lock (`flock -w`) — nenhuma entrada
  fica órfã. Dedupa pelo último login de cada MAC e contra o que já publicou (`var/nutella-macs.tsv`: re-login
  igual não vira request; boot novo republica); 000/429/5xx voltam p/ a fila até 3 vezes; tudo em
  `var/nutella-bind.log` (`ok|noroster|image_unknown|retry|http <n>`). **Limites**: módulo `maquinas` + chave;
  conta de PAPEL nunca; `NUTELLA_BIND=0` desliga (`config {bind:false}`); a imagem do UA tem de ser sede DO
  CONTEST (`NUTELLABOOT_IMAGES` ∪ sedes da última coleta) — o UA é entrada do cliente e a chave admin alcança
  outros eventos. **404 = time fora do roster da imagem** (`noroster`): `push-roster` e depois
  **`push-bindings`**, que é o REPLAY do `access.log` pela mesma fila (serve também p/ quem logou antes do
  deploy). O UA pode ser forjado — quem barra isso é o gate de UA por sede; o binding é informação p/ o staff,
  não controle de acesso. `nutella-bind.log` e `nutella-macs.tsv` atravessam as rodadas (cópia no arquivo).
- **Roster**: `POST {action:"push-roster"}` PUBLICA o roster do STORE nas imagens (user_id=login, nome do
  time, universidade, país; os times de cada sede vêm da última coleta — que, com roster vazio, os tira do
  UA dos logins) — sem `force` ele NUNCA atropela roster já povoado (o da Maratona veio do ICPC).
- **Alertas em tempo real (webhooks, 21/09)**: o serviço avisa por `POST` assinado (`X-NB-Signature:
  sha256=<HMAC-SHA256 do corpo cru>`; até 3 tentativas, 5 s cada) — o MOJ recebe em **`POST /api/v1/hooks/
  nutella?contest=<c>`** (`handlers/hooks/nutella.sh`), sem Bearer. Segredo POR CONTEST em
  `secrets/nutella-webhook.secret` (600); a conferência é em **python3 stdlib** (`hmac.compare_digest`) lendo
  segredo e corpo de ARQUIVO — `openssl dgst -hmac <segredo>` poria o segredo no `ps`. **401 opaco** p/ tudo que
  não autentica (inclusive contest inexistente e evento velho: o `at` está no corpo assinado, janela −1 h…+5 min);
  só depois vêm 404 (imagem que não é sede do contest), 422, `ignored` (evento que não é alerta) e `duplicate`.
  `alert.raised`/`alert.dismissed` → `var/nutella-events.log` (JSONL, teto de 5 MB) com o TIME resolvido pelo elo
  do login (`nutella-macs.tsv`; senão a última coleta) e `mkey = "m:" + md5(MAC)` — o machine_id do agente novo
  É md5(MAC), então o alerta cai na MESMA chave de máquina do painel **Máquinas › Anomalias** (`events[]`,
  `kind:"machine_alert"`, cartão próprio quando há algum). Aviso por Telegram (DM ao DONO do contest, outbox da
  `lib/alerts.sh`) só `alert.raised`, só DURANTE a prova (início−1 h … fim: na montagem todo mundo espeta
  pendrive) e com teto — 1 por máquina+tipo e 10 por contest a cada 10 min; o log não tem teto de aviso.
  **Instalar**: `POST /contest/nutella {action:"webhooks-install", base_url?}` (cartão no painel) — exige chave
  de ADMINISTRAÇÃO (webhooks são rota de console), gera o segredo, pede só os dois eventos de alerta. ⚠ O `PUT
  …/webhooks` do serviço SUBSTITUI a lista e o `GET` mascara os segredos: havendo webhook de outro dono na sede o
  MOJ recusa antes de escrever em qualquer sede (`force` passa por cima, apagando o deles). A rota não atende
  pelo subdomínio do contest (isolamento), por isso a URL base vai no pedido. Depende de o nginx repassar o
  cabeçalho `X-NB-Signature` (repassa por omissão — `fastcgi_pass_request_headers on`, como já acontece com
  `If-None-Match`); conferir com um POST assinado depois do deploy.
- **Anomalias e a identidade da máquina**: a chave GRAVADA (`MKEY` da sessão, `submit-origin.log`,
  `sess_machine_key`) segue `m:<machine_id>/<boot_id>` — trocar o formato no meio de uma prova faria sessão
  antiga e requisição nova divergirem. A normalização é na APURAÇÃO (`lib/anomalies.sh`): `machine_id` visto
  com MAC no UA é único por placa, então p/ ele a máquina é `m:<mid>` — reboot deixa de ser "trocou de
  máquina"/"2 sessões em 2 máquinas", e dois times na MESMA máquina com um reboot no meio passam a aparecer
  em `machine_shared`. Sem MAC (agente antigo, ids clonados) nada muda.
- **Para a IMAGEM (mlinux)**: além do UA do navegador (`MLinux/<imagem>/<machine_id>/<boot_id>`),
  gravar o MESMO UA em **`/etc/moj/user-agent`** (uma linha, legível por todos). É de lá que a
  `moj-comp` (e as outras CLIs) o lê e o manda na frente do seu marcador `moj-comp/<build>` —
  passa no gate por sede, herda a chave de máquina do browser e o servidor separa web × CLI.
- **Quando coletar**: logo depois da prova (com `limit=5000` a janela vem SEM reamostragem — ~500 pontos
  nativos por máquina em 7 h; máquinas religadas muito depois podem perder histórico). Recoletar é
  barato (1 request por sede); o bruto fica guardado p/ `--reaggregate`.

## Testes

`server/test/smoke-contest-nutella.sh` roda contra o **mock** `nutella-mock.py`
(stdlib; serve fixtures com os shapes reais, REGISTRA POST/PUT e o GET de samples com a
query) — cobre config, escopo, coleta ponta-a-ponta (since/until, elo por UA com conta de
papel tentando roubar o vínculo, adoção/perfis/pressão/rank_ed, privacidade do cache,
`--reaggregate` sem rede, modo proxy sem access.log), a coleta em LOTE (2 requests p/ 2 sedes,
`limit=5000`), a telemetria nova com frota MISTA (agente novo × antigo), o bruto ANTIGO por máquina e o
fallback sem a rota de lote reagregando IGUAL, roster VAZIO (sedes pelo UA do login · imagem listada à
mão · erro claro sem nada), sede recusada ⇒ `skipped` e serviço mudo ⇒ falha, catálogo, gates de
comando e push-roster. A view tem o seu: `smoke-mlinux-view.gjs.sh` (DOM falso no gjs, do jeito que o
relatório a inlina; cache novo × antigo, pt × en). O elo pelo MAC (clone de machine_id + reboot) e o
binding de reserva estão no `smoke-contest-nutella.sh`; a publicação no login tem o `smoke-nutella-bind.sh`
(o que publica e o que NÃO, dedup, reboot, 404 do roster, 503 ⇒ retry, replay, e o caminho DESTACADO de
produção com o serviço lento); a identidade estável, no `smoke-contest-anomalies.sh`; os webhooks, no
`smoke-nutella-hook.sh` (opacidade do 401, corpo adulterado, outro segredo, frescor, 413, repetição, tetos de
aviso, fora da prova, instalação com webhook alheio/`force`/remoção, e a trilha de Anomalias). O relatório é coberto no `smoke-contest-report.sh` (página condicional, sem
MAC/teams/_rows, view 2.0 embutida, invariantes). O jq do coletor vive em VARIÁVEIS
(`AGG_JQ`), que o `jq-portability.sh` não vê: rode o coletor com o jq 1.7 da imagem
(`--reaggregate` num bruto guardado) antes de deployar mudança nele.
