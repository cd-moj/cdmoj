# Webcast — o pacote de placar do Animeitor (e o papel `.animeitor`)

O **Animeitor** (de **Emílio Wuerges**) é o sistema autônomo que anima o placar no telão, e é a
**ferramenta oficial de cerimônia** — a página `/contest/score/reveal.html` do próprio MOJ é
**experimental** (ensaio, sede pequena, plano B). Ele foi feito para o BOCA:
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
| gerir **fotos e músicas dos times** (ver, ouvir, trocar, subir, baixar o pacote) | qualquer coisa de admin |
| criar/revogar as **chaves do webcast** | — |

Como todo papel, o sufixo está fora do placar, do `/contest/teams`, das etiquetas, dos balões,
das estatísticas e do gate de UA (a lista canônica é a de `lib/auth.sh`; ver a nota de papéis no
`CLAUDE.md`). A página dele é `/contest/animeitor/`.

**O admin do contest entra na MESMA página, com os mesmos poderes** — as rotas gatam
`{ is_animeitor || is_admin; }` e o `boot()` da página aceita os dois. Ele não tem botão na barra
de navegação (a doutrina do painel: página avulsa se linka, não vira aba); as portas são o cartão
**🎥 Telão (Animeitor)** na *Central › Gerar* e o link **🎥 Fotos e músicas no telão** ao lado do
título do painel *Pessoas › Times*. Em contest com `USERS_FROM` esse link não é atalho, é o
**único** caminho: o `/contest/admin/team-assets` recusa contest de usuários compartilhados e as
rotas do telão não (foto e música são asset LOCAL do contest).

### A sede (`.cstaff` e `.staff`) — a mesma tela, recortada

Os dois papéis de sede abrem `/contest/animeitor/` (botão **🎥 Animeitor** na barra deles) e veem
**só os times do escopo deles**. A diferença é o que podem fazer com eles:

| | `.cstaff` (chefe) | `.staff` (voluntário) |
|---|---|---|
| ver a galeria da sede, com filtros e busca | ✅ | ✅ |
| ver e **ouvir** o padrão que vai ao telão | ✅ | ✅ |
| subir/trocar/remover **foto e música** dos times da sede | ✅ | ❌ 403 |
| baixar o **pacote .zip** (recortado na sede) | ✅ | ❌ 403 (é exportação em massa) |
| tocar em time de **outra** sede | ❌ 403 `staff_scope` | ❌ |
| trocar a **foto/música PADRÃO** (é do contest inteiro) | ❌ 403 | ❌ 403 |
| ver ou criar **chaves do webcast** | ❌ 403 (a seção nem aparece) | ❌ 403 |

Na página, o `.staff` cai no modo `NOWRITE`: além de não ter a seção de streaming nem os botões do
padrão (como o chefe), ele fica **sem os botões de enviar/trocar/remover** dos cartões e **sem a
linha de lote/pacote** — sobra o ▶ da música e a foto em tamanho real.

O recorte é o **mesmo `staff-filters.json`** que já corta a fila de impressão, as etiquetas com
senha e a cerimônia de revelação — `{"<login .staff|.cstaff>": ["region:<sede>"|regex]}`, resolvido
pelos helpers `staff_can_see`/`staff_visible_logins` de `lib/print.sh`. Três regras que valem
lembrar:

- **Quem autoriza é a API, não a tela.** A listagem já vem recortada (`scoped:true` na resposta) e
  cada POST re-autoriza o login **resolvido** — o corpo pode mandar nome de arquivo
  (`fulano.mp3`), então resolve-se primeiro e autoriza-se depois.
- **Escopo vazio/ausente = vê tudo** (convenção da casa nos quatro consumidores; o `preflight`
  avisa com "Staff sem escopo de sede"). Mas **escopo que existe e não casa ninguém = vê nada** —
  quem manda é o `rc` do `staff_visible_logins`, não o tamanho da saída.
- Este é o **primeiro caminho de escrita escopada** do `.cstaff` (nas outras telas ele só lê);
  o `.staff` continua **100% leitura** em todo o MOJ.

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
  `WEBCAST_FLOOR_S` (10 s). **O arquivo `time` é recarimbado POR REQUISIÇÃO** (27/08/2026):
  o relógio da prova não pode andar em saltos de 10 s — o telão anima o cronômetro com ele.
  O handler serve uma CÓPIA do zip cacheado com só a entrada `time` refeita (custa ~ms); se o
  `zip` falhar, degrada para o valor do cache (salto de até 10 s), nunca para erro.

**Conteúdo do ZIP** — cinco arquivos, campos separados por **`0x1C`** (FS; **não** é TAB) e
linhas por `\n`:

| arquivo | conteúdo |
|---|---|
| `contest` | 1: `<nome da competição>` · 2: `<duração>␜<lastmileanswer>␜<lastmilescore>␜<penalidade>` (MINUTOS) · 3: `<nº de times>␜<nº de problemas>` · N linhas `<login>␜<sigla>␜<nome do time>` · `1␜1` · `<nº de problemas>␜Y` |
| `runs` | uma linha por submissão: `<id>␜<minuto>␜<login>␜<letra>␜<Y\|N\|?\|X>` |
| `time` | **segundos decorridos** da prova (inteiro, sem `\n`; **negativo antes do início** — é como o telão sabe quanto falta), limitado à duração no teto; **exato por requisição** (não sofre o cache de 10 s do pacote). ⚠ é o único campo em segundos: duração/freeze/penalidade do `contest` e o carimbo das linhas de `runs` seguem em MINUTOS (formato do BOCA). Era minutos com piso 0 até 27/08/2026 (pedido do Animeitor) |
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
  (`tp_thumb`, build-once com `flock`). O pacote continua levando a foto CHEIA.
- **Cache-buster é o `mtime`** (`&v=<mtime>`), não `Date.now()`: com o relógio, cada render
  rebaixava todas as imagens de novo.

A tela abre em **⚠ Pendências** — quem falta foto **ou** música, a fila de trabalho inteira — e
tem uma fileira de chips por família (`Foto:` sem/com/todos, `Música:` sem/com/todos), busca sem
acento (debounce de 150 ms), recortes por coorte/universidade/sede e **paginação de 48 cartões**
(o DOM fica pequeno e só as fotos da página corrente são baixadas).

Dois detalhes de comportamento que valem a pena conhecer:

- **A contagem do chip é o número de cartões que ele mostra.** Cada família conta com a OUTRA já
  aplicada: com "Sem foto" ligado, o chip de música vira "Sem música (64)" e não "(96)". Contar
  tudo sobre a base crua (como era antes) fazia o número mentir assim que dois recortes se
  cruzavam.
- **"Pendências" é exclusivo com as famílias** (é um OU entre elas, que chip por família não
  expressa): clicar em qualquer chip de foto/música sai do modo pendências, e voltar a ele devolve
  as duas famílias a "Todos". `limpar` mostra **todos** os times — não re-liga as pendências.

### A foto PADRÃO (time sem foto)

`GET /contest/team-photo` **não devolve mais 404**: quem não mandou foto recebe a **foto
padrão** do contest, com o cabeçalho `X-MOJ-Photo: placeholder`. É o que faz o Animeitor achar
imagem para todo time do placar, sem tratar ausência. Quem precisa saber quem MANDOU foto usa o
`has_photo` das listagens (é por isso que a galeria distingue quem mandou a sua, só para foto de
verdade, e a galeria continua mostrando a caixa "sem foto").

Quem escolhe a imagem é o **`.animeitor`**, na própria página (trocar / voltar ao padrão do
MOJ) — ela vive em `contests/<c>/placeholder.webp` (+ miniatura). Sem escolha, vale a de fábrica
que vem no repositório: `server/etc/team-placeholder.webp`, mesmo idioma do
`server/etc/info-sheet.pt.md` (arquivo do contest sobrescreve o embarcado; apagar volta ao
default). ⚠ Em produção `server/etc/` é read-only (vem da imagem), então a miniatura de fábrica
é **commitada** — nada é gerado ao lado dela, e a imagem nova só chega com `make deploy`.

No **pacote .zip** a padrão aparece de duas formas: uma vez na raiz (`placeholder.webp`) e como
`fotos/<login>.webp` de cada time sem foto — assim o Animeitor acha o arquivo de qualquer time.
A coluna **`padrao`** do `teams.csv` diz quem está com a imagem padrão (`true`) e quem mandou a
própria (`false`). Custo: ~20 KB por time sem foto (o zip não deduplica cópias idênticas).

---

## Músicas dos times (♪)

Cada time pode ter uma **música própria** em MP3 — a faixa que o telão toca quando ele resolve um
problema. É o mesmo desenho da foto: link por time na API, padrão para quem não mandou a sua,
gestão na página do `.animeitor` (botão **♪** que toca no próprio navegador e a fileira de chips
`Música: sem/com/todos`, irmã da de foto) e presença no pacote `.zip`.

```
GET  /contest/team-music?contest=<id>&user=<login>   ->  audio/mpeg (a do time, ou a PADRÃO)
POST /contest/animeitor/music?contest=<id>          ->  {login|filename, file_b64} | {action:"delete", login}
GET  /contest/placeholder?contest=<id>&kind=music   ->  a música padrão
```

Três decisões que valem a pena conhecer:

- **A música é guardada como veio** (`users/<login>/music.mp3`), sem conversão: a imagem de
  produção **não tem `ffmpeg`** (a foto tem o `convert`; áudio não tem equivalente). O que
  protege é a **validação por MIME** — `file --mime-type` tem de dizer `audio/mpeg`, senão 400
  `music_bad`. Extensão não é prova de nada, e um "mp3" que é outra coisa travaria o telão na
  hora errada. Teto de **15 MB** (~10 min a 192 kbps).
- **O corpo vem em ARQUIVO** (`read_body_file`): 15 MB de mp3 são ~20 MB de base64, e enfiar isso
  numa variável de shell é o caminho conhecido para o 504.
- **Sem `Range`** (a API não tem em rota nenhuma): o player toca progressivo, que é o uso aqui.
  Buscar uma posição no meio da faixa pode rebaixar o arquivo.

A **música padrão** vive em `contests/<c>/placeholder.mp3` e, sem escolha do `.animeitor`, é a de
fábrica `server/etc/team-placeholder.mp3` — mesma regra da foto padrão (arquivo do contest
sobrescreve o embarcado; `reset` apaga e volta ao default).

## O pacote `.zip` (fotos + músicas)

```
GET /contest/animeitor/photos-zip?contest=<id>
    fotos/<login>.webp     — TODOS os times (quem não mandou leva a padrão)
    musicas/<login>.mp3    — SÓ quem mandou a sua
    placeholder.webp       — a foto padrão, uma vez
    placeholder.mp3        — a música padrão, uma vez
    teams.csv              — o índice
```

`teams.csv` é o índice que casa os arquivos com o time do placar:

```
login,nome,universidade,coorte,bandeira,foto,padrao,musica,musica_padrao
```

`padrao=true` diz que a foto daquele time é a padrão; `musica_padrao=true` diz que ele **não** tem
faixa própria e deve tocar `placeholder.mp3`. A assimetria é proposital: foto são ~20 KB e sai
mais simples o Animeitor achar `<login>.webp` sempre; música são megabytes — copiar a padrão para
cada um de 1000 times daria um pacote de gigabytes.

A foto é armazenada em **WEBP** (`users/<login>/photo.webp`) — qualquer formato que chegue
(png/jpg/webp) é convertido, redimensionado (lado máx. 1000 px) e limpo de metadados por
`lib/team-photo.sh`. Fotos antigas em `photo.png` continuam sendo servidas e entram no pacote
como `fotos/<login>.png`; converta o acervo com `server/bin/photos-to-webp.sh --apply`.

O **envio em lote** aceita os dois de uma vez: o operador arrasta fotos e mp3 juntos e cada
arquivo vai para a rota certa pelo tipo — o **nome do arquivo é o login** (`fulano.jpg`,
`fulano.mp3`).

---

## Como testar um cliente de placar sem uma prova acontecendo

Quem desenvolve o Animeitor (ou qualquer consumidor do webcast) precisa de um placar de verdade:
muitos times, veredictos misturados e um freeze para mover de lugar. Dá para fabricar um em
segundos, com **contest de DEMONSTRAÇÃO** — e só nele: a rota que povoa recusa qualquer contest
que não tenha `DEMO=1` no conf, porque submissão sintética numa prova de verdade é dado
envenenado.

```bash
export MOJ_URL=https://moj.naquadah.com.br
moj login                                     # conta que pode criar contest

# 1. o contest: 12 problemas, 5h de janela, marcado como demo e fora das listagens
moj-contest create demo.json --id anim-demo   # spec com  "demo": true, "secret": true
moj-contest login anim-demo -u <seu>.admin

# 2. o placar: 80 times, 900 submissões, freeze no minuto 180
#    ⚠ o freeze tem de cair DENTRO da parte já decorrida da prova, senão não sobra submissão
#    depois dele e o placar congelado sai IGUAL ao completo — não há o que revelar. A resposta
#    traz `runs_after_freeze` e avisa quando dá zero.
moj-contest -c anim-demo seed --teams 80 --subs 900 --seed 42 --freeze-minute 180

# 3. a conta do telão e a chave do webcast
moj-contest -c anim-demo users add telao.animeitor
#    entre como ela em /contest/animeitor/ e crie a chave (ou use o admin)

# 4. aponte o cliente
curl -sO "https://anim-demo.moj.naquadah.com.br/api/v1/contest/webcast?key=mojwc_…"
```

O que exercitar a partir daí:

- **mover o freeze**: `moj-contest -c anim-demo settings set freeze=<epoch>` — o minuto novo
  aparece no `lastmilescore` (linha 2 do `contest`) na próxima busca. Lembre que **o pacote vai
  sempre completo**: aplicar o congelamento é trabalho do SEU cliente, e é isto que se está
  testando;
- **desligar o freeze**: `settings set freeze=0` (é o que o botão "Descongelar tudo" faz);
- **repetir o mesmo cenário**: o `--seed` é determinístico — mesmo número, mesmo placar. Um bug
  do cliente se reproduz com o mesmo comando;
- **ver o placar se mexer**: `moj-contest -c anim-demo seed --live 8` manda submissões **de
  verdade** (passam pelo juiz) como os times semeados, por cima do histórico injetado;
- **mudar a mistura de veredictos**: `verdicts:{accepted,wrong,tle,rte,ce,pending}` no corpo da
  rota — `pending` é o que gera o `?` no `runs`.

⚠ Um detalhe que só morde em contest de verdade, mas convém saber: **`FREEZE_TIME` no passado
suprime o balão de todo AC pós-freeze, e a lápide (`print-requests/.balloon-frozen`) é
PERMANENTE** — só `balloons_during_freeze` a solta. Num contest de demonstração isso é inócuo;
não repita a receita numa prova.

Detalhes da rota (parâmetros, limites, resposta): `docs/API.md`, `/contest/admin/seed`.

---

## Onde está o quê

| arquivo | papel |
|---|---|
| `server/score/webcast-gen.sh` | monta os cinco arquivos e o zip |
| `server/api/v1/lib/webcast.sh` | chaves (criar/revogar/validar/contabilizar) |
| `server/api/v1/handlers/contest/webcast.sh` | a rota **sem sessão** que o Animeitor busca |
| `server/api/v1/handlers/contest/animeitor/*.sh` | fotos, músicas e chaves (gate `.animeitor`/admin) |
| `server/api/v1/lib/team-photo.sh` | foto do time (webp), fonte única dos três escritores |
| `server/api/v1/lib/team-music.sh` | música do time (mp3 validado por MIME, sem conversão) |
| `server/etc/team-placeholder.{webp,mp3}` | a foto e a música de fábrica (o contest sobrescreve) |
| `web/contest/animeitor/` | a página do papel |
| `server/test/smoke-animeitor.sh` | o contrato inteiro, inclusive o formato do pacote |
| `server/api/v1/handlers/contest/admin/seed.sh` | povoa um contest **DEMO=1** p/ testar cliente de placar |
| `server/test/smoke-contest-seed.sh` | a trava do DEMO, o determinismo e o freeze partindo o placar |
