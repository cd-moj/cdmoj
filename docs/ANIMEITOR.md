# Animeitor — o MOJ alimenta o telão pela API (2.1.0)

O **Animeitor** (Emilio Wuerges) é o sistema do TELÃO: placar animado, revelação do congelamento,
foto e música do time que resolve. Até set/2026 ele PUXAVA do MOJ um ZIP no protocolo do BOCA
(`docs/WEBCAST.md`, hoje **legado**). A API 2.1.0 dele desvincula o telão do BOCA e inverte o
sentido: **o juiz empurra**. Este documento é a fonte única da integração.

- API pública (leitura, WebSocket): `https://animeitor.naquadah.com.br/api/docs`
- API interna (configuração e ingestão; **só HTTPS, HTTP Basic**): `…/internal/docs`
- A pública também tem a rota da **conferência**: `GET /api/events/{e}/contests/{c}/runs_secret` (Bearer = a
  chave da sede) — ver [Conferência](#conferência-o-animeitor-tem-todas-as-submissões)
- No MOJ: `lib/animeitor.sh` · `handlers/contest/animeitor/api.sh` · `daemons/animeitor-feed.sh` ·
  `score/telao-runs.sh` · `web/contest/animeitor/api-section.js`. Módulo `telao`. Quem opera é o
  **`.animeitor`** (o admin também); `.cstaff`/`.staff` não entram.

## O modelo deles e o nosso

| Animeitor | No MOJ |
|---|---|
| **evento** (`/internal/events/{e}`): problemas, roster `{login, escola, nome}`, `score_freeze_time_seconds`, `penalty_seconds`, `time_seconds`, `photo_url_format`/`sound_url_format` com `{team_login}` (os templates de mídia, compartilhados por todos os placares), runs | o **contest**. Nome = id do contest (editável); com **rodadas**, o padrão é `<contest>-<rodada ativa>` — a promoção zera os `history` e a API não limpa o histórico do stream, então rodada nova é EVENTO novo (publicar num evento novo zera o `sent`: as runs da rodada anterior não vão p/ ele como `X`). Problemas = letras do `PROBS`. Roster = times do placar da visão `all` (conta de papel nunca está lá); `escola` = sigla. Freeze = `FREEZE_TIME − início` (sem freeze = duração). Penalidade = `PENALTY_MINUTES × 60`. |
| **contest** (`/internal/contests/{e}/{c}`): um PLACAR. `codes` = regex de login (OR), `ouro/prata/bronze` (última colocação de cada medalha), `style` — só isso: o contest é ESTRITO (campo desconhecido = 400 `invalid_json`) | proposta: **Geral** + um por **visão de coorte** (`ch_views`) + um por **nó de `regions.json` com subregiões** (um "país"). Editável. |
| **site** (`/internal/sites/{e}/{c}/{s}`): uma SEDE, com regex e **link secreto de revelação** | as **folhas** de `regions.json` (no Geral, todas as que não são recorte `view`; no país, as dele). Os times de cada sede/placar são os que **estão** no nó pela regra única de sedes (`lib/regions.sh`: sede gravada ou regex mais funda; pai = soma dos filhos) — até 28/09/2026 era a regex do nó (diferenciando maiúsculas) OU a sede gravada, e a folha de recorte repetia a sede no Geral. **Sem `regions.json`** (prova de sede única): o Geral leva UMA sede "Geral" com os mesmos times — o link de revelação é POR SEDE e sem sede nenhuma não há link (XIV Maratona UnB, 25/09/2026: "0 links de revelação" depois de liberar). Configuração já salva sem sede não muda sozinha: a tela avisa e aponta o "+ sede" |
| **run** `{id:int, team_login, prob, time_seconds, answer}` — reenviar o `id` CORRIGE | `id` = inteiro ESTÁVEL por submissão (`var/animeitor-ids.tsv`); `time_seconds` = `sub_epoch − início`; `answer`: `Y` aceito · `N` penaliza · `X` não conta (CE e o que estiver fora do `PENALTY_VERDICTS`, Judge Error, `(Ignored)`) · `?` pendente |
| `time_seconds` do evento | `agora − início`: **negativo** antes (contagem regressiva), com **teto** na duração. **Prorrogação por sede** (`time-overrides.json`): o evento tem um relógio só, então p/ o telão a prova acaba quando acaba p/ a ÚLTIMA sede — o teto é o `contest_end_all` (o mesmo portão da cerimônia e do descongelar) e o relógio segue andando até lá. O freeze não muda de lugar. Vale SÓ p/ o Animeitor: placar, aceite de submissão e relógio das outras sedes não mudam; prorrogação criada no meio da prova vale em até 5 s |

Três coisas do serviço mandam no desenho (todas conferidas no servidor real, 21/09/2026):

1. **O servidor não avança o relógio**: "a controller or feeder must send updates". Sem alimentador
   o telão fica parado — daí o `daemons/animeitor-feed.sh`.
2. **`PUT` é substituição TOTAL** e o `salt` omitido vira `null` ⇒ **troca os links de revelação**
   de quem já os recebeu. O MOJ usa SEMPRE `POST` e, no `409`, `PATCH` só dos campos dele. Nunca `PUT`
   (o mock zera o que o `PUT` omite, p/ o teste pegar quem tentar).
3. **O MOJ manda a resposta REAL de toda run**, inclusive depois do freeze — como o webcast fazia.
   Quem congela é o Animeitor: a API pública mascara `?` a partir do `score_freeze_time_seconds`, e a
   resposta real só sai pelo `runs_secret` com a chave da sede (o `secret` do link de revelação).

### `codes`: regex quando reproduz, lista quando não

Coorte e sede no MOJ se definem por regex **ou por campo da conta** (`.team.region`, coorte default).
O placar do telão TEM de bater com o do MOJ, então `an_derive` testa: se o regex que já existe
seleciona, no roster do evento, **exatamente** os times daquele recorte → vai o regex; se o recorte
é o evento inteiro → `.*`; senão a **lista exata** `^(a|b|…)$` (logins escapados). Regex com
look-around ou backreference cai na lista (o serviço é Rust e recusa: `invalid_regex`). Medido: uma
alternância de 2.000 logins é aceita. `codes:null` no `animeitor.json` = **automático**: resolvido a
cada publicação, então time que entra na sede entra no placar sozinho.

## Arquivos do contest

| Arquivo | O que é |
|---|---|
| `secrets/animeitor.cred` | a chave **PRÓPRIA** do contest: `usuario:token` (HTTP Basic), **600, write-only**. Vence a chave do MOJ. Vai ao curl por `-K <(printf …)` — nunca argv, log, GET nem conf. Formato validado (o arquivo de config do curl é entre aspas). |
| `animeitor.json` | não-segredo: `{url, event, moj_base_url, enabled, feed:{clock_s:1, runs_s:2}, contests: null \| [{name, source:{kind:view\|region\|manual, id}, codes\|null, ouro, prata, bronze, style, sites:[{name, source, codes\|null}]}]}`. `contests:null` = ainda vale a proposta. |
| `var/animeitor-ids.tsv` | `subid → id inteiro`, **só apêndice**, sob flock (`telao-runs.sh --runs-ids`). O sequencial do pacote BOCA renumera tudo quando chega uma submissão offline atrasada — inútil numa API que corrige POR id. Sobrevive ao `reset` (o id é da submissão, não do evento). |
| `var/animeitor-sent.tsv` | o que o serviço JÁ tem de cada run ⇒ só o **delta** viaja |
| `var/animeitor-managed.json` | o que ESTE contest criou lá, com o hash do que mandou: é o que torna a publicação idempotente (nada mudou = zero request) e o que limita o que ele altera/apaga |
| `var/animeitor.status.json` · `var/animeitor.clock` | último sync/erro/contagens · último relógio enviado (`epoch segundos http`, gravado com `printf`: é 1×/s) |
| `var/animeitor-verify.json` | a última **conferência** (contagens por sede e até 20 ids de amostra; **nunca** chave de sede nem resposta de run) |
| `$RUNDIR/secrets/animeitor.cred` | a **chave do MOJ** (`$ANIMEITOR_CRED_FILE`), fora de todo contest — ver abaixo |
| `$RUNDIR/animeitor/events.json` | o **registro de posse**: `{url: {evento: contest}}` — de qual contest do MOJ é cada evento |
| `$RUNDIR/animeitor/active/<contest>` · `feed.alive` · `feed.log` | marcador do alimentador ligado · batimento do processo · log (teto de 1 MB) |

A URL tem de ser `https://` — o serviço devolve `426` em claro e Basic em claro é credencial na
rede; a única exceção é `http://127.0.0.1` (o mock dos testes).

## Chave do MOJ (25/09/2026)

O Emilio criou uma credencial do MOJ no Animeitor (do lado dele, uma entrada `[[tokens]]` com `name = "moj"`).
Ela mora em `$RUNDIR/secrets/animeitor.cred` (`moj:<token>`, 600; `ANIMEITOR_CRED_FILE` muda o caminho;
instalação em `docs/ADMIN.md` › Segredos) e:

- **vale p/ todo contest que não gravou a própria** — a mesa do telão diz "Chave do MOJ: não há nada a
  configurar"; o `GET` responde `cred_source:"moj"` e **nem o usuário** dela volta p/ a tela;
- **a chave PRÓPRIA do contest vence** (`config {user, token}` → `secrets/animeitor.cred` do contest); apagá-la
  (`user:"", token:""`, botão "apagar e usar a chave do MOJ") volta p/ a do MOJ;
- **só vai ao servidor padrão** (`$ANIMEITOR_URL`, `https://animeitor.naquadah.com.br`). URL digitada pelo operador
  exige chave própria — senão qualquer contest mandaria a credencial do MOJ a um servidor qualquer. A conferência
  é feita na URL que a requisição de fato usa (o alimentador passa a dele), não só na gravada.

**Com uma credencial compartilhada, o serviço não sabe mais de qual contest é cada evento.** Quem diz é o
registro `$RUNDIR/animeitor/events.json` (`{url: {evento: contest}}`, sob flock), que só o servidor escreve:

- o evento entra no registro quando o contest o **cria** (201) e em todo PATCH de evento que o `managed` do
  contest já dizia ser dele (é o que semeia os eventos publicados antes do registro existir);
- nome de evento que o registro dá a **OUTRO** contest = `409 event_taken` **antes de qualquer request**, com ou
  sem `adopt` (a mensagem não diz de qual contest: o id pode ser de prova secreta). Sem isso o relógio e as runs
  de dois contests iriam p/ o mesmo evento;
- com a chave do MOJ, `adopt` de evento que ninguém do MOJ criou = `409 adopt_forbidden` (seria mexer, com a
  credencial do MOJ, no evento de outra pessoa — o `regional-2026` de exemplo do Emilio). Com chave própria pode,
  como antes (a credencial é do operador);
- o `reset` libera o nome.

## Publicar (`an_publish`)

`POST /contest/animeitor/api {action:"publish"}`: evento → placares → sedes, e apaga lá os placares e
sedes que saíram da configuração — **só os que este contest criou**. O roster vai com
`?keep_runs=true` (time que saiu não derruba as runs dele). O relógio não entra no hash nem no PATCH
do evento: quem o conduz é o alimentador. Erro de UM placar (ex.: regex recusado) aparece naquele
placar e não interrompe os outros.

**Evento que já existe lá e não foi criado por este contest** (`409`) só é tocado com `adopt:true` —
o servidor é compartilhado (hoje tem o `regional-2026` de exemplo do Emilio). O `reset` (apaga o evento
lá) exige `confirm:"<evento>"` e recusa evento que não é nosso.

## Runs (`an_push_runs`)

Delta contra o `sent.tsv`, em lotes de 500. Casos: nova (`added`), rejulgada (`updated`, mesmo `id`),
**removida no MOJ** → corrigida p/ `X` (a API não tem DELETE por run), e **time que o serviço não
conhece** → o serviço ignora e devolve `warnings:[{code:"unknown_team", message:"run <id> do time …"}]`;
o MOJ lê o `id` do aviso e **não** põe essa run no `sent` — ela vai de novo depois que o roster for
republicado (o alimentador força isso na hora). `full` reenvia tudo; o serviço não duplica.

## O alimentador (`daemons/animeitor-feed.sh`)

UM processo p/ todos os contests (flock), **fora do caminho do julgamento**: o `judged` nunca espera a
rede do telão; se o Animeitor cair, a prova não sente — recuo 1, 2, 4… até 30 s, e retoma. Só olha
`$RUNDIR/animeitor/active/` (nada de varrer 1.500 contests por segundo). Por contest:

- a cada **1 s**: `PATCH …/time` (timeout 3 s); depois do fim o relógio pára e o envio cai p/ 1 a cada
  30 s. Dorme até a virada do segundo (sem deriva);
- a cada **2 s**: runs — **só se algum `history` mudou** (`find -newer` num carimbo tirado ANTES da
  leitura);
- a cada **60 s**: assinatura barata (roster da visão `all` + mtime de `regions/cohorts/animeitor.json`
  + conta mexida); mudou ⇒ republica. `unknown_team` força na hora;
- **24 h depois do fim** o contest sai sozinho (rejulgamento pós-prova ainda corrige runs).
- **evento apagado lá** (alguém no console do Animeitor, servidor que perdeu o estado): o relógio dá 404 ⇒ o
  alimentador zera o `managed`/`sent` locais e republica evento, placares, sedes e runs na mesma passada.

### Custo (medido em 21/09/2026, Ryzen 5950X, contest de 2.000 times / 12 mil submissões, 11 placares, 60 sedes)

| Operação | Custo |
|---|---|
| proposta (`an_derive`) | 1,2 s de CPU, sob demanda (abrir a tela) |
| publicar 1ª vez (evento + 11 placares + 60 sedes) | 4,6 s; republicar sem mudança 2,7 s (é o hash de cada placar/sede — só a cada 60 s **e só se a assinatura mudou**) |
| runs: 1ª carga (12 mil) | 1,7 s; sem novidade 0,18 s (nem roda: o detector `find -newer` custa 10 ms); 1 veredicto novo 0,29 s |
| relógio (1 `PATCH`) | 80 ms de parede no mock; ~200 ms no servidor real (RTT + TLS), ~15 ms de CPU |
| **regime ocioso** (relógio 1/s + detector) | **4 % de um núcleo por contest** (14 % com 3 contests) — mais ~1 %/contest de TLS no servidor real |
| **rajada de 10 veredictos/s** (largada da 1ª fase) | **22 % de um núcleo**, 1 contest; 34 % com 3 contests (2 ociosos) |
| latência das rotas de usuário (placar + status) | **19,9 ms sem × 19,6 ms com** o alimentador em rajada: zero efeito mensurável (processo à parte, sem lock compartilhado) |

Teto prático: o alimentador é **serial** entre contests e o `PATCH` do relógio leva ~0,2 s no servidor real ⇒ até
~4 contests simultâneos o relógio anda de 1 em 1 s; acima disso ele começa a pular segundos (nada quebra: só a
cadência). Se um dia houver mais que isso, o passo é paralelizar por contest (um laço por marcador).

Medido no servidor real: relógio público andando de 1 em 1 s, run nova no telão ~2 s depois do
veredicto. Sobe pelo `deploy/moj-entrypoint` (laço com respawn; `ANIMEITOR_FEED_DISABLE=1` desliga;
`$RUNDIR/animeitor-feed.err`) e, no dev, pela unit `server/etc/systemd/moj-animeitor-feed.service`.
A tela avisa quando o marcador está ligado e o processo não bate o ponto há 15 s.

## Conferência: o Animeitor tem todas as submissões?

A rota **pública** `GET /api/events/{e}/contests/{c}/runs_secret`, com `Authorization: Bearer <chave da sede>`
(o `secret` da URL de revelação — `/internal/events/{e}/revelation_urls`), devolve as runs que o regex DAQUELA sede
seleciona no evento, **com a resposta real** (sem máscara de freeze), ordenadas por `(time_seconds, id)`. Antes do
início: `403 not_started`; chave ausente/errada: `403 invalid_key`; evento inexistente: `404`. Girar o salt invalida a
chave na hora. (Lido do `/api/openapi.json` público em 25/09/2026; o mock implementa igual.)

`an_verify` (`lib/animeitor.sh`) confere **sede a sede**:

1. o que o MOJ tem: as runs vivas (`telao-runs.sh --runs-ids`, como o `an_push_runs`) **mais** as removidas no MOJ
   (que lá têm de estar como `X`);
2. as chaves das sedes vêm do `revelation_urls` **ao vivo** e nunca são gravadas; o filtro de cada sede é o regex
   publicado (o mesmo que o serviço aplica ao `team_login`; o MOJ o aplica com `grep -P`, que cobre o que ele gera).
   Sedes com o **mesmo regex** em placares diferentes dão a mesma resposta ⇒ **uma** consulta (a LATAM tem cada
   sede no Geral e no país);
3. compara `id`, time, problema, tempo e resposta: **faltando** (no MOJ, não lá), **diferente** (mesmo id, outro
   conteúdo) e **a mais** (só lá, com resposta ≠ `X`, e id que o MOJ não conhece — o telão mostraria uma run que
   não existe; id conhecido em outra sede é só outro recorte, ex. time renomeado);
4. **reparo**: faltando/diferente viva sai do `sent` (o próximo push a manda de novo); removida que voltou a contar
   lá tem a flag do `sent` trocada p/ `?` (o push manda o `X` de novo); a "a mais" entra no `sent` com a resposta de
   lá, e o push a corrige p/ `X`. Tudo sob o MESMO lock do `an_push_runs`;
5. grava `var/animeitor-verify.json`: `{at, state: ok|diverge|not_started|no_sites|error, runs, checked, uncovered,
   missing, wrong, extra, repair, pending, over, final, final_at, sites:[…], sample:{ids}}`. `uncovered` = runs de
   times fora de qualquer sede (não dá p/ conferir sem chave de sede; a tela diz quantas).

**`final` — o "validado"**: tudo bate, a prova acabou p/ **todas** as sedes (`contest_end_all`) e nada está
pendente (`?`). `final_at` guarda a hora da 1ª validação (conferir de novo não a move). Rejulgamento depois disso
dispara nova conferência.

Quem confere:

- **o alimentador**, sozinho, **destacado** (um GET por sede pode levar segundos e o relógio dos outros contests
  não espera; `flock -n` por contest): durante a prova a cada `feed.verify_s` (300 s); depois do fim p/ todas as
  sedes, a cada 60 s até a conferência final passar; depois dela, só quando algum `history` muda. O que a
  conferência marca p/ reenvio vai na passada de runs seguinte;
- **o operador**: `POST {action:"verify"}` ("🔎 conferir agora"): confere, reenvia NA HORA o que faltou (republica se
  um time não estava no evento) e confere de novo — a resposta traz o `before` (o que a 1ª achou);
- **antes de liberar o reveleitor**: a mesa confere e põe o resultado na pergunta de confirmação;
- **a sede**: o `GET /contest/animeitor/reveal` devolve a conferência SÓ das sedes do `.cstaff`/`.staff`, e o
  cartão "🎬 Reveleitor da sua sede" mostra "✓ Validado" (final e as sedes dele batendo), "Conferido" ou "⚠".

A Central do admin (preflight `telao`, com o módulo ligado) avisa: telão sem chave (inclusive URL fora do padrão
com só a chave do MOJ), última conferência com divergência, e "Telão validado" quando a final passou.

## Mídia

`photo_url_format`/`sound_url_format` — no **evento** — = `<URL pública do MOJ>/api/v1/contest/team-photo?contest=<c>&user={team_login}`
e `…/team-music…` (sem a URL pública configurada vai `null`, e o serviço usa o padrão dele,
`photos/{team_login}.webp` na própria origem). **Mudou na versão do serviço de 24/09/2026**: até
então os templates eram de cada contest; o serviço passou a recusar o contest com eles
(`unknown field photo_url_format`) e a publicação parou — conserto em `an_event_json`/`an_resolved`. O mock
`server/test/animeitor-mock.py` é a cópia do contrato: a cada versão do serviço, confira o
`/internal/openapi.json` (autenticado) contra ele — foi por o mock ter ficado velho que o smoke não pegou. As duas rotas já são públicas e nunca dão 404 (devolvem o padrão do contest —
`docs/WEBCAST.md`, seções de fotos e músicas). A URL pública vai na configuração porque a tela do
operador costuma estar no subdomínio do contest.

## Reveleitor nas sedes (liberação dos links de revelação)

O link de revelação de cada sede mostra as respostas reais depois do congelamento — é **credencial**. Ele
chega ao `.cstaff`/`.staff` assim (decisões do Ribas, 21/09/2026):

- **Um interruptor só**, do `.animeitor`/admin: `POST /contest/animeitor/api {action:"reveal-release"}` (e
  `reveal-recall`). Estado em `animeitor.json` (`reveal{released, at, by}`); o marcador
  `var/animeitor-reveal.released` é só o atalho sem fork p/ o `navbuttons`. `reset` recolhe.
- Liberado, `GET /contest/animeitor/reveal` devolve a cada conta **só os links da sede dela**, em **todos os
  placares em que a sede aparece** (Geral, país…). A sede da conta é o `staff-filters.json` de sempre —
  `staff_regions` (`lib/print.sh`, a MESMA regra dos comandos do mlinux): token `region:<sede>` ou, com escopo
  por regex, as sedes dos times que ela enxerga. O casamento é pela **região de origem** do site (o operador pode
  ter renomeado a sede no telão); site manual casa pelo nome; sem caixa.
- **Fail-closed**: conta sem sede definida recebe `scoped:false` e ZERO links (nas telas de leitura "sem filtro =
  vê tudo"; aqui seria a revelação do evento inteiro). Antes da liberação: `released:false`, sem nem consultar
  o servidor do telão. Cada leitura atendida vai ao audit (`animeitor-reveal-read`).
- Na tela: botão **Reveleitor** na barra do `.cstaff`/`.staff` (só depois da liberação) → mesa do telão, com o
  cartão **🎬 Reveleitor da sua sede** no topo (abrir / copiar).

## Segurança

- Credencial e links de revelação são segredo: a credencial só em `secrets/` (a do MOJ em `$RUNDIR/secrets/`, e ela
  nunca volta p/ a tela, nem o usuário); os links são buscados **ao vivo** (`?links=1`) e nunca gravados. Na tela o
  `secret` aparece mascarado; "copiar" leva o inteiro. A conferência usa as chaves de sede em memória e grava só
  contagens e ids — nunca chave nem resposta.
- A chave do MOJ só vai ao servidor padrão; o registro de posse impede um contest de usar o evento de outro.
- O **nome** do evento e dos placares é público na página inicial do Animeitor mesmo antes do início
  (o estado e as runs dão `403 not_started`). Contest `SECRET=1` ganha um aviso na tela.
- O `/config` público de cada placar expõe os `codes` — com lista exata, os logins dos times.
- Rotas: `is_animeitor || is_admin`. Tudo auditado (`animeitor-*`).

## Testes

- `server/test/animeitor-mock.py` — mock **estrito**, escrito do OpenAPI e conferido no serviço real
  (401 sem Basic, 409, 404 sem pai, `PUT` zera o omitido, `PATCH` vazio/campo desconhecido = 400,
  `invalid_regex`, `unknown_team` com o texto real, problema desconhecido = 400 no lote, `keep_runs`).
- `server/test/smoke-animeitor-api.sh` (96, com a prorrogação por sede): gates, token write-only, proposta (regex × lista),
  publicação idempotente SEM `PUT` e com os salts preservados, evento alheio intocado, delta de runs
  com id estável, relógio negativo/teto, alimentador (`--once`: relógio, só-o-que-mudou, time tardio,
  serviço fora do ar, instância única, desliga em 24 h), rodada nova = evento novo, links, reveleitor nas sedes (antes/depois da liberação, region:, escopo por regex, sem sede, sede renomeada, recolher, botão na barra), reset. `smoke-animeitor.sh` prende
  a paridade do pacote BOCA e o mapa de ids. `admin-inplace.gjs.sh`: o estado ao vivo atualiza EM
  LUGAR sem reconstruir a tabela em edição.
- `server/test/smoke-animeitor-verify.sh` (37): chave do MOJ (padrão invisível, própria vence, apagar volta, nunca
  vai a outra URL), registro de posse (`event_taken` sem request, `adopt_forbidden`, própria pode, reset libera),
  conferência (antes do início, ok, perdida/diferente/a mais/removida reparadas e 2ª conferência ok, mesmo regex =
  1 consulta, final × pendente, `final_at` estável, reveleitor da sede, alimentador destacado, nada secreto em disco).
  `smoke-animeitor-key-verify.gjs.sh`: a mesa (chave do MOJ × própria × URL fora do padrão, estado da conferência,
  "conferir agora", conferência antes de liberar) e o selo da sede. `smoke-preflight.sh`: o item `telao`.
- Servidor real: só num evento de teste próprio, apagado no fim. **Nunca** tocar evento alheio.

## O que o Emilio respondeu (21/09/2026) — e o que ainda está aberto

| # | Pergunta | Resposta | Consequência no MOJ |
|---|---|---|---|
| 1 | O front interpola o relógio entre mensagens do `/timer`? | **Não: mantém o valor enviado.** | O relógio a **1 s** é necessário (`feed.clock_s: 1`). Ele também recomenda atualizações de 1 em 1 s. |
| 2 | `DELETE` de UMA run | **Vai implementar.** | Hoje a submissão removida no MOJ é corrigida p/ `X`. Quando a rota existir, `an_push_runs` passa a apagar (as já marcadas `X` ficam como estão). |
| 3 | `X` conta tentativa/penalidade? | **Não aplica penalidade, como no webcast.zip.** | Bate com o MOJ (CE e o que está fora do `PENALTY_VERDICTS`). Nada a mudar. |
| 4 | Prorrogação POR SEDE | Ele **não sabia** que o MOJ tem relógio por sede. | **Resolvido do lado do MOJ** (decisão do Ribas, 21/09): o relógio por sede é MASCARADO — o MOJ manda um relógio único que só pára quando a prova acaba p/ a última sede (`contest_end_all`). Nada a pedir ao Emilio. |
| 5 | Links de revelação em `http://` | **Não é problema.** | Nada a mudar. |
| 6 | Credencial do MOJ | **Criada em 25/09/2026** (`[[tokens]]`, `name = "moj"`). | É a **chave do MOJ** (acima): vale p/ todo contest no servidor padrão. O token vive só em `run/secrets/` do servidor. A `bruno` é pessoal e não vai p/ produção. |
| 8 | Conferir se o Animeitor tem tudo | (25/09) **`GET …/runs_secret`** com a chave da sede. | É a **conferência** (acima): o alimentador confere e reenvia, e o reveleitor mostra "validado". |
| 7 | Rate limit / tamanho do lote | **Não há rate limit nos endpoints internos.** | Lotes de 500 e 1 `PATCH`/s por evento seguem como estão. |
