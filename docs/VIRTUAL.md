# Participação virtual (refazer um contest encerrado)

A participação virtual deixa uma conta do Treino Livre **refazer um contest que já terminou**. A
prova roda no tempo de quem participa. Os times oficiais aparecem como "fantasmas": cada um resolve
cada problema no mesmo minuto em que resolveu na prova real. No fim, a linha do participante fica
gravada no placar virtual do contest, marcada como **virtual**.

Página: `/treino/virtual/?c=<contest>` (site principal). Código: `server/api/v1/lib/virtual.sh`,
`handlers/treino/virtual/*`, `web/treino/virtual/`, `web/shared/virtual-board.js`.

## 1. De onde veio o desenho

| Plataforma | O que faz | O que o MOJ copiou | O que o MOJ mudou |
|---|---|---|---|
| Codeforces | Botão em toda prova encerrada. Regras de honra. Horário de início. Placar no tempo relativo. Uma participação por prova. Cancela só antes de qualquer ação. Linha marcada com `#`. | Regras de honra, horário de início, placar no tempo relativo, uma vez por conta, linha marcada. | Desistência explícita (ver §4): virtual abandonado não polui o placar. |
| AtCoder | A aba "Virtual Standings" anda no tempo virtual, mas a aba "Standings" mostra o resultado final. | — | Um placar só, sempre no tempo do participante. |

## 2. Quando um contest oferece participação virtual

O dono liga o módulo **`virtual`** (Central › Módulos). O portão `vr_load` confere **todas** as
condições **a cada requisição**:

1. módulo `virtual` ligado;
2. contest **não é secreto** (`SECRET`);
3. modo **ICPC** (versão 1);
4. início e fim definidos;
5. prova **encerrada para todas as sedes** (`contest_over_for_all`: fim + maior prorrogação);
6. placar final **descongelado** (`FREEZE_TIME` = 0 — o "Encerrar evento" faz isso);
7. **todos os problemas são públicos no treino** (`contests/treino/var/jsons/<id>.json` com
   `public != false`).

**Participação virtual de problema privado não existe.** Nada do virtual lê `jsons-private/` nem
`MOJ_PROBLEMS_DIR`. O enunciado vem da rota pública `/treino/problem?id=`.

### Blindagem

- Portão fechado ⇒ **404 `virtual_unavailable`** em todas as rotas, com corpo **idêntico** ao de
  contest inexistente. A resposta não confirma existência, fase, título nem número de problemas.
- conf ilegível ou índice indisponível ⇒ também 404 (fail-closed).
- O portão roda **antes** de ler qualquer cache. Contest que deixa de ser elegível (dono reabre,
  prorroga, recongela, marca secreto, problema volta a privado) ⇒ 404 **e** o cache do virtual é apagado.
- Ligar o módulo com problema não-público ⇒ **422 `virtual_not_eligible`**; a mensagem dá só a
  **contagem**, nunca o id.
- Módulo ligado com a prova ainda rodando fica **inerte** até o portão abrir sozinho.
- Testes: `server/test/smoke-virtual-leak.sh` (matriz rota × contest proibido, 365 asserções).

## 3. Como a run funciona

- **Uma participação por conta por contest.** Conta de papel (`.admin`, `.judge`…) não participa.
- Largada: **agora** ou **agendada** (até 7 dias). Agendamento se cancela sem custo.
- Duração = `CONTEST_END − CONTEST_START` do conf.
- **A submissão virtual é uma submissão normal do treino**, com o campo `virtual:"<cid>"` no
  `/submit`. Spool, juiz, report e perfil não mudam. O servidor exige: run rodando, problema da
  prova, linguagem permitida **no contest**.
- O resultado é **derivado**: history do treino ∩ subids etiquetados ∩ janela da run. Regra ICPC do
  contest (`PENALTY_MINUTES`, `PENALTY_VERDICTS`).
- Nada é escrito em `contests/<c>/users/`. Placar oficial, estatística, relatório, webcast e
  rodadas **não mudam**.

| Arquivo | Conteúdo |
|---|---|
| `contests/treino/users/<login>/virtual/<cid>.json` | estado da run (autoritativo; acompanha o rename) |
| `contests/treino/users/<login>/virtual/<cid>.subs` | subids etiquetados |
| `contests/<cid>/virtual/runs/<login>.json` | snapshot gravado ao finalizar (imune a rejulgamento) |
| `contests/<cid>/var/virtual-feed.json(.gz)` | feed dos fantasmas (cache) |
| `contests/<cid>/var/virtual-board.json` | agregado dos snapshots (cache) |

## 4. Desistir × gravar (decisão de 2026-09-18)

| Situação | Resultado |
|---|---|
| Rodando, **≤ 15 min** de prova **ou** **nenhum Accepted** | botão **Desistir**: nada é gravado e a tentativa volta |
| Rodando, > 15 min **e** ≥ 1 Accepted | não dá mais para desistir; o resultado será gravado |
| Tempo acabou com **0 Accepted** | descartada sozinha; conta como desistência |
| **Encerrar agora** com 0 Accepted | vira desistência |
| Já desistiu **2 vezes** | a próxima largada é **definitiva**: sem desistir, grava mesmo com 0 |

As submissões de uma run descartada continuam no histórico do treino. Constantes: `VR_GRACE_S`
(900), `VR_MAX_DISCARDS` (2), `VR_SCHEDULE_MAX_S` (7 d), `VR_PENDING_MAX_S` (1 h: pendente mais
velho que isso não segura a finalização).

## 5. O placar

- `GET /treino/virtual/feed` entrega os times do **placar público final** (`var/placar.txt`: coorte
  pública, desclassificados e papéis já filtrados) e todas as runs `[seg, time, problema, Y|N|X|?]`.
- `web/shared/virtual-board.js` reconstrói o placar em qualquer instante `t` e devolve o **mesmo
  objeto** que `parseICPC`; o renderizador do placar oficial o desenha.
- Linha virtual: intercalada pelo desempenho, **não consome posição oficial**, mostra em itálico a
  posição que **ocuparia**, nunca recebe ★.
- **Filtros: os mesmos do placar oficial.** A barra tem Placar (coorte), Bandeira, Universidade, Sede,
  busca, contador e "limpar". A lógica é a de `web/contest/score/score-filters.js`, fonte única com o
  placar ao vivo. Os dados vêm das rotas públicas `/contest/teams`, `/contest/teams-meta` e
  `/contest/regions`. A escolha fica lembrada no navegador, por contest.
  - **Coorte** recorta no **motor** (`boardAt … {teamOk}`): posição e ★ saem iguais às do placar
    próprio daquela visão no servidor. O feed traz `views[]` e a coorte de cada time — só coortes
    **públicas** com time no placar público.
  - **Bandeira, universidade, sede e busca** recortam **linhas**: o número grande é a posição no
    recorte, o pequeno é a geral, e a ★ é a do recorte. A linha virtual acompanha
    (`sliceVirtualPlaces`) e nunca recebe ★.
  - **Meus escolhidos (📌).** A pessoa escolhe virtuais que aparecem **sempre**, em qualquer filtro de
    linha — serve para se comparar com amigos e, por exemplo, filtrar uma sede. Escolhe-se pelo **📌** na
    linha virtual do placar ou pelo painel **📌 Escolhidos (N)** (busca por nome ou login, e "adicionar
    pelo login" para quem ainda não fez o virtual desta prova). A lista é **uma por conta**, para todos
    os contests: `GET/POST /treino/virtual/friends`, arquivo `treino/users/<login>/virtual/_friends.json`
    (o `_` impede colisão com o estado de um contest). Sem login a lista fica no navegador e é mesclada
    na conta no primeiro acesso logado. Teto de 100 logins. A rota não confere se a conta existe (seria
    oráculo de existência). O rename de conta reescreve as listas que citam o login antigo.
  - **Virtuais: todos | só os escolhidos | só o meu | nenhum.** A linha de quem está com a run em andamento aparece
    sempre. Os outros virtuais obedecem aos filtros de bandeira, universidade e busca. O filtro de
    **sede não os esconde**: o virtual não fez a prova em sede nenhuma, e quem escolhe uma sede quer
    se comparar com ela. Para tirar os virtuais da tela, use "Virtuais: nenhum".
- Sem run (ou depois dela) a página oferece o **Replay**: um controle de tempo sobre o mesmo motor.
- Duas implementações da regra ICPC (bash e JS) ⇒ teste **diferencial**
  `smoke-virtual-board.gjs.sh`: motor em `t=∞` == `placar.txt`; motor em `t=T` == placar de history truncado.

## 6. Painel do dono e moderação

**Evento › Virtual**: mostra o portão aberto em partes (o que falta), o link da página e as
participações gravadas. `remove`/`restore` tiram ou devolvem uma linha (auditado). Rota:
`/contest/admin/virtual`.

**Devolver a tentativa** (`reset`): para um testador, ou para quem teve problema. A ação apaga a linha
gravada e põe de lado o estado da conta **naquele contest** (as desistências também). A conta pode
largar de novo. A regra "uma vez por conta" continua para todos os outros. As submissões ficam no
histórico do treino. A ação é auditada (`virtual-reset`).

## 7. Fora da versão 1

Times virtuais; placar OBI/heurístico; rodadas arquivadas; `moj-comp --virtual`; ver ao vivo outras
participações virtuais em andamento.
