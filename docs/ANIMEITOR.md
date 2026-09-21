# Animeitor — o MOJ alimenta o telão pela API (2.1.0)

O **Animeitor** (Emilio Wuerges) é o sistema do TELÃO: placar animado, revelação do congelamento,
foto e música do time que resolve. Até set/2026 ele PUXAVA do MOJ um ZIP no protocolo do BOCA
(`docs/WEBCAST.md`, hoje **legado**). A API 2.1.0 dele desvincula o telão do BOCA e inverte o
sentido: **o juiz empurra**. Este documento é a fonte única da integração.

- API pública (leitura, WebSocket): `https://animeitor.naquadah.com.br/api/docs`
- API interna (configuração e ingestão; **só HTTPS, HTTP Basic**): `…/internal/docs`
- No MOJ: `lib/animeitor.sh` · `handlers/contest/animeitor/api.sh` · `daemons/animeitor-feed.sh` ·
  `score/telao-runs.sh` · `web/contest/animeitor/api-section.js`. Módulo `telao`. Quem opera é o
  **`.animeitor`** (o admin também); `.cstaff`/`.staff` não entram.

## O modelo deles e o nosso

| Animeitor | No MOJ |
|---|---|
| **evento** (`/internal/events/{e}`): problemas, roster `{login, escola, nome}`, `score_freeze_time_seconds`, `penalty_seconds`, `time_seconds`, runs | o **contest**. Nome = id do contest (editável); com **rodadas**, o padrão é `<contest>-<rodada ativa>` — a promoção zera os `history` e a API não limpa o histórico do stream, então rodada nova é EVENTO novo (publicar num evento novo zera o `sent`: as runs da rodada anterior não vão p/ ele como `X`). Problemas = letras do `PROBS`. Roster = times do placar da visão `all` (conta de papel nunca está lá); `escola` = sigla. Freeze = `FREEZE_TIME − início` (sem freeze = duração). Penalidade = `PENALTY_MINUTES × 60`. |
| **contest** (`/internal/contests/{e}/{c}`): um PLACAR. `codes` = regex de login (OR), `ouro/prata/bronze` (última colocação de cada medalha), `style`, `photo_url_format`/`sound_url_format` com `{team_login}` | proposta: **Geral** + um por **visão de coorte** (`ch_views`) + um por **nó de `regions.json` com subregiões** (um "país"). Editável. |
| **site** (`/internal/sites/{e}/{c}/{s}`): uma SEDE, com regex e **link secreto de revelação** | as **folhas** de `regions.json` (no Geral, todas; no país, as dele) |
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
| `secrets/animeitor.cred` | `usuario:token` (HTTP Basic), **600, write-only**. Vai ao curl por `-K <(printf …)` — nunca argv, log, GET nem conf. Formato validado (o arquivo de config do curl é entre aspas). |
| `animeitor.json` | não-segredo: `{url, event, moj_base_url, enabled, feed:{clock_s:1, runs_s:2}, contests: null \| [{name, source:{kind:view\|region\|manual, id}, codes\|null, ouro, prata, bronze, style, sites:[{name, source, codes\|null}]}]}`. `contests:null` = ainda vale a proposta. |
| `var/animeitor-ids.tsv` | `subid → id inteiro`, **só apêndice**, sob flock (`telao-runs.sh --runs-ids`). O sequencial do pacote BOCA renumera tudo quando chega uma submissão offline atrasada — inútil numa API que corrige POR id. Sobrevive ao `reset` (o id é da submissão, não do evento). |
| `var/animeitor-sent.tsv` | o que o serviço JÁ tem de cada run ⇒ só o **delta** viaja |
| `var/animeitor-managed.json` | o que ESTE contest criou lá, com o hash do que mandou: é o que torna a publicação idempotente (nada mudou = zero request) e o que limita o que ele altera/apaga |
| `var/animeitor.status.json` · `var/animeitor.clock` | último sync/erro/contagens · último relógio enviado (`epoch segundos http`, gravado com `printf`: é 1×/s) |
| `$RUNDIR/animeitor/active/<contest>` · `feed.alive` · `feed.log` | marcador do alimentador ligado · batimento do processo · log (teto de 1 MB) |

A URL tem de ser `https://` — o serviço devolve `426` em claro e Basic em claro é credencial na
rede; a única exceção é `http://127.0.0.1` (o mock dos testes).

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

Medido no servidor real: relógio público andando de 1 em 1 s, run nova no telão ~2 s depois do
veredicto. Sobe pelo `deploy/moj-entrypoint` (laço com respawn; `ANIMEITOR_FEED_DISABLE=1` desliga;
`$RUNDIR/animeitor-feed.err`) e, no dev, pela unit `server/etc/systemd/moj-animeitor-feed.service`.
A tela avisa quando o marcador está ligado e o processo não bate o ponto há 15 s.

## Mídia

`photo_url_format`/`sound_url_format` = `<URL pública do MOJ>/api/v1/contest/team-photo?contest=<c>&user={team_login}`
e `…/team-music…`. As duas rotas já são públicas e nunca dão 404 (devolvem o padrão do contest —
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

- Credencial e links de revelação são segredo: a credencial só em `secrets/`; os links são buscados
  **ao vivo** (`?links=1`) e nunca gravados. Na tela o `secret` aparece mascarado; "copiar" leva o inteiro.
- O **nome** do evento e dos placares é público na página inicial do Animeitor mesmo antes do início
  (o estado e as runs dão `403 not_started`). Contest `SECRET=1` ganha um aviso na tela.
- O `/config` público de cada placar expõe os `codes` — com lista exata, os logins dos times.
- Rotas: `is_animeitor || is_admin`. Tudo auditado (`animeitor-*`).

## Testes

- `server/test/animeitor-mock.py` — mock **estrito**, escrito do OpenAPI e conferido no serviço real
  (401 sem Basic, 409, 404 sem pai, `PUT` zera o omitido, `PATCH` vazio/campo desconhecido = 400,
  `invalid_regex`, `unknown_team` com o texto real, problema desconhecido = 400 no lote, `keep_runs`).
- `server/test/smoke-animeitor-api.sh` (90, com a prorrogação por sede): gates, token write-only, proposta (regex × lista),
  publicação idempotente SEM `PUT` e com os salts preservados, evento alheio intocado, delta de runs
  com id estável, relógio negativo/teto, alimentador (`--once`: relógio, só-o-que-mudou, time tardio,
  serviço fora do ar, instância única, desliga em 24 h), rodada nova = evento novo, links, reveleitor nas sedes (antes/depois da liberação, region:, escopo por regex, sem sede, sede renomeada, recolher, botão na barra), reset. `smoke-animeitor.sh` prende
  a paridade do pacote BOCA e o mapa de ids. `admin-inplace.gjs.sh`: o estado ao vivo atualiza EM
  LUGAR sem reconstruir a tabela em edição.
- Servidor real: só num evento de teste próprio, apagado no fim. **Nunca** tocar evento alheio.

## O que o Emilio respondeu (21/09/2026) — e o que ainda está aberto

| # | Pergunta | Resposta | Consequência no MOJ |
|---|---|---|---|
| 1 | O front interpola o relógio entre mensagens do `/timer`? | **Não: mantém o valor enviado.** | O relógio a **1 s** é necessário (`feed.clock_s: 1`). Ele também recomenda atualizações de 1 em 1 s. |
| 2 | `DELETE` de UMA run | **Vai implementar.** | Hoje a submissão removida no MOJ é corrigida p/ `X`. Quando a rota existir, `an_push_runs` passa a apagar (as já marcadas `X` ficam como estão). |
| 3 | `X` conta tentativa/penalidade? | **Não aplica penalidade, como no webcast.zip.** | Bate com o MOJ (CE e o que está fora do `PENALTY_VERDICTS`). Nada a mudar. |
| 4 | Prorrogação POR SEDE | Ele **não sabia** que o MOJ tem relógio por sede. | **Resolvido do lado do MOJ** (decisão do Ribas, 21/09): o relógio por sede é MASCARADO — o MOJ manda um relógio único que só pára quando a prova acaba p/ a última sede (`contest_end_all`). Nada a pedir ao Emilio. |
| 5 | Links de revelação em `http://` | **Não é problema.** | Nada a mudar. |
| 6 | Credencial do MOJ | **Pode criar uma credencial para o MOJ.** | Pendente do lado dele. A `bruno` é pessoal e não deve ir p/ produção. |
| 7 | Rate limit / tamanho do lote | **Não há rate limit nos endpoints internos.** | Lotes de 500 e 1 `PATCH`/s por evento seguem como estão. |
