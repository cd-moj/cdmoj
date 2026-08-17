# Webcast — o pacote de placar do Animeitor (e o papel `.animeitor`)

O **Animeitor** é o sistema autônomo que anima o placar no telão. Ele foi feito para o BOCA:
busca uma URL em loop e recebe um **ZIP** com o estado da competição. O MOJ fala esse mesmo
protocolo — não é uma tradução aproximada, é o mesmo pacote, byte a byte na estrutura.

Quem opera isso é a conta de papel **`.animeitor`**.

---

## O papel `.animeitor`

Conta de contest com o sufixo `.animeitor` (criada pelo admin, como `.judge`/`.staff`). É a
**mesa de quem opera o telão**:

| pode | não pode |
|---|---|
| ver o placar **sempre DESCONGELADO** (é ele quem conduz a revelação) | submeter solução (403 `submit_forbidden`) |
| a **cerimônia de revelação** e as **estatísticas** do contest | ver enunciado (não compete) |
| gerir as **fotos dos times** (ver, trocar, subir, baixar o pacote) | qualquer coisa de admin |
| criar/revogar as **chaves do webcast** | — |

Como todo papel, o sufixo está fora do placar, do `/contest/teams`, das etiquetas, dos balões,
das estatísticas e do gate de UA (a lista canônica é a de `lib/auth.sh`; ver a nota de papéis no
`CLAUDE.md`). A página dele é `/contest/animeitor/`.

---

## O protocolo (compatível com o `webcast.php` do BOCA)

**URL** (é o que se configura no Animeitor):

```
https://<contest>.moj.naquadah.com.br/api/v1/contest/webcast?contest=<id>&key=<CHAVE>
```

- **Sem sessão**: quem autoriza é a `key` — o BOCA faz igual (o `header.php` dele pula o
  `ValidSession()` quando vem `webcastcode`).
- Chave inválida, revogada ou ausente → **404** (não confirma nem que o contest existe). A
  tentativa vai para `contests/<c>/var/webcast-denied.log`.
- Acerto → **200** `application/zip` com `Content-Length`. O acesso é contabilizado na própria
  chave (`fetches`, `last_at`, `last_ip`) — sem log crescendo sem fim, porque o Animeitor bate
  de segundos em segundos.
- Cache: o pacote é regerado quando o placar muda (`var/.score-dirty`) **ou** quando envelhece
  `WEBCAST_FLOOR_S` (10 s) — o arquivo `time` é o relógio da prova e precisa andar sozinho.

**Conteúdo do ZIP** — cinco arquivos, campos separados por **`0x1C`** (FS; **não** é TAB) e
linhas por `\n`:

| arquivo | conteúdo |
|---|---|
| `contest` | 1: `<nome da competição>` · 2: `<duração>␜<lastmileanswer>␜<lastmilescore>␜<penalidade>` (MINUTOS) · 3: `<nº de times>␜<nº de problemas>` · N linhas `<login>␜<sigla>␜<nome do time>` · `1␜1` · `<nº de problemas>␜Y` |
| `runs` | uma linha por submissão: `<id>␜<minuto>␜<login>␜<letra>␜<Y\|N\|?\|X>` |
| `time` | minuto corrente da prova (inteiro, sem `\n`), limitado à duração |
| `version` | `1.0` |
| `icpc` | vazio (no BOCA o bloco que o preenchia está sob `if(false)`) |

**O pacote vai SEMPRE COMPLETO, sem congelamento.** Não é descuido: no `webcast.php` o
`$freezeTime` é sobrescrito pela duração antes de filtrar. Quem anima a virada é o Animeitor —
e ele sabe a partir de quando animar porque o **`lastmilescore`** do `contest` é o minuto do
congelamento. No MOJ: `lastmilescore = (FREEZE_TIME − CONTEST_START)/60`, ou a duração quando
não há congelamento (= nunca congela). `lastmileanswer` (quando os juízes param de responder)
não existe como conceito no MOJ: vai igual à duração.

**O flag de cada run** sai do veredicto canônico (`lib/verdict.sh`) e da política de penalidade
do contest (`PENALTY_VERDICTS`), para a classificação que o Animeitor recalcula bater com a do
MOJ:

| veredicto | flag | por quê |
|---|---|---|
| `Accepted` | `Y` | resolveu |
| `Not Answered Yet` / `On queue` / `Running` | `?` | pendente |
| veredicto que **não conta** penalidade (por padrão `Compilation Error`), `Judge Error`, ` (Ignored)` | `X` | tentativa que não penaliza — é o que o `X` significa no BOCA |
| o resto (WA, TLE, MLE, RTE…) | `N` | tentativa que penaliza |

O `<id>` do run é sequencial pela ordem cronológica (o BOCA usa o `runnumber`, que também só
cresce). O `<login>` é a chave que liga tudo: é o mesmo nome no `contest`, no `runs` e no
arquivo de foto do pacote de fotos.

### O que ficou diferente do BOCA (e por quê)

| BOCA | MOJ |
|---|---|
| `?webcastcode=<alnum>`, chaves numa linha de `private/webcast.sep` | `?key=mojwc_…` em `contests/<c>/webcast.json` (600), criada/revogada pela página do `.animeitor` |
| a linha do `webcast.sep` restringe por **site/faixa de usuário** | a chave declara a **visão de coorte** (geral, Individual, Times…) — o placar de cada visão já existe pronto (ver `SCOREBOARD.md`) |
| `Content-type: application/force-download`, sem tamanho | `application/zip` + `Content-Length` |
| todo acesso vira linha em `webcast.log` | acerto vira contador na chave; **recusa** vira linha em `var/webcast-denied.log` |
| entradas do zip como `./contest` | entradas na raiz (`contest`) — todo unzip normaliza as duas |
| `contest` regerado no máximo 1×/hora | regerado junto com o resto (é barato) |

⚠ **A chave dá o placar descongelado durante a prova.** Chave vazada = resultado vazado. Ela é
longa e revogável, a página mostra último acesso e IP, e o `?key=` aparece no `access.log` do
nginx (o BOCA tem a mesma propriedade) — trate como senha e revogue depois do evento.

---

## Fotos dos times

O `.animeitor` tem uma galeria em `/contest/animeitor/`: ver quem já tem foto, trocar, subir em
lote (o **nome do arquivo é o login**) e baixar o pacote. Ela é feita para **prova de 1000+
times** — três decisões que valem a pena conhecer antes de mexer:

- **A listagem é UMA varredura, não um `jq` por time.** `GET /contest/animeitor/photos` faz um
  `find -printf` (tamanho+mtime de todas as fotos) e um `find | xargs jq` (todas as contas, login
  pelo `input_filename`, como o `sc_cells`), e junta por `--slurpfile`. Medido com 1000 times:
  **5,3 s → 0,10 s**. Voltar a forkar por usuário é o jeito garantido de derrubar a página.
- **A galeria pede MINIATURA** (`/contest/team-photo?…&thumb=1`, 320 px ≈ 7 KB no lugar de 37 KB).
  Ela nasce no upload (`tp_store`) e, para o acervo antigo, é gerada na 1ª leitura
  (`tp_thumb`, build-once com `flock`). O 📷 do placar e o pacote continuam com a foto CHEIA.
- **Cache-buster é o `mtime`** (`&v=<mtime>`), não `Date.now()`: com o relógio, cada render
  rebaixava todas as imagens de novo.

A tela abre filtrada em **"sem foto"** (a fila de trabalho), com chips de contagem viva, busca
sem acento (debounce de 150 ms), recortes por coorte/universidade/sede e **paginação de 48
cartões** — o DOM fica pequeno e só as fotos da página corrente são baixadas.

Rota do pacote:

```
GET /contest/animeitor/photos-zip?contest=<id>   ->  fotos/<login>.webp + teams.csv
```

`teams.csv` é o índice (`login,nome,universidade,coorte,bandeira,foto`) que casa cada foto com o
time do placar. A foto é armazenada em **WEBP** (`users/<login>/photo.webp`) — qualquer formato
que chegue (png/jpg/webp) é convertido, redimensionado (lado máx. 1000 px) e limpo de metadados
por `lib/team-photo.sh`. Fotos antigas em `photo.png` continuam sendo servidas; converta o
acervo com `server/bin/photos-to-webp.sh --apply`.

---

## Onde está o quê

| arquivo | papel |
|---|---|
| `server/score/webcast-gen.sh` | monta os cinco arquivos e o zip |
| `server/api/v1/lib/webcast.sh` | chaves (criar/revogar/validar/contabilizar) |
| `server/api/v1/handlers/contest/webcast.sh` | a rota **sem sessão** que o Animeitor busca |
| `server/api/v1/handlers/contest/animeitor/*.sh` | fotos e chaves (gate `.animeitor`/admin) |
| `server/api/v1/lib/team-photo.sh` | foto do time (webp), fonte única dos três escritores |
| `web/contest/animeitor/` | a página do papel |
| `server/test/smoke-animeitor.sh` | o contrato inteiro, inclusive o formato do pacote |
