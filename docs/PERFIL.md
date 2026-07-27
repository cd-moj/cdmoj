# Perfil público & Conquistas (`/treino/stat/`)

O **perfil público** de um usuário do Treino Livre vive em `/treino/stat/?user=<login>`.
É um dashboard calculado **inteiramente no cliente** a partir de poucos fetches — o servidor
não pré-agrega nada além do que já serve para o resto do site. Este documento descreve a
anatomia da página, as fontes de dados, as regras de privacidade e, em detalhe, o sistema de
**conquistas** (catálogo padrão, como configurar pela aba do admin e como criar tipos novos).

Chega-se ao perfil por: **📊 Minhas estatísticas** (menu do usuário na topbar), o **top-10**
da home e a **nuvem de avatares** nas estatísticas de um problema.

## 1. Anatomia da página

| Seção | Conteúdo | De onde vem |
|---|---|---|
| **Cabeçalho** | avatar (foto ou iniciais), nome, `~login`, 🎓 universidade, 🗓️ *membro desde* (`created_at`), 💻 editor favorito com ranking, ⚡ último envio, botão ✎ (só o dono) | `/treino/profile?user=` + `/treino/editors` + history |
| **Cartões** | resolvidos, submissões, taxa de acerto, AC na 1ª tentativa, tentativas até resolver, streak atual, maior streak, linguagem preferida | derivados do history |
| **📈 Resolvidos ao longo do tempo** | curva cumulativa de problemas distintos resolvidos | history (1º AC de cada problema) |
| **🔥 Atividade + 🕐 Ritmo** | heatmap de 26 semanas + punchcard dia×hora | history |
| **🎯 Veredictos / 💻 Linguagens** | barras horizontais + tabela por linguagem (subs/AC/taxa) | history (rótulo de linguagem via `shared/languages.js`, com alias p/ extensões `bash`/`python`/`py3`) |
| **🧗 Dificuldade dos resolvidos** | muito fácil/fácil/médio/difícil — derivada da **taxa global** de cada problema (`solved_count/attempted_count` da lista), mesmas faixas do /treino (≥0.9 / ≥0.7 / ≥0.5 / resto) | history × `/treino/problems` |
| **📚 Progresso por coleção** | top coleções por VOLUME resolvido, com barra e link p/ a busca do treino | history × `/treino/problems` |
| **🏷️ Forças por tag / ⏳ Em aberto** | resolvidos por tag; tentados sem AC com última tentativa | history × `/treino/problems` |
| **🏅 Conquistas** | badges do registro (ver §4) — travadas mostram o progresso | `/treino/achievements` + derivações |
| **📜 Histórico** | tabela **paginada (25/página)** com filtros por problema/veredicto/linguagem, ordenação por coluna, datas compactas; cód/log e resumo de testes só p/ o dono | `/treino/history-full?user=` |

**Streaks** contam dias consecutivos com ≥1 **submissão** (não AC), tolerando "ainda não
enviou hoje". **One-shot** = problema resolvido com AC já na primeira submissão.

## 2. Fontes de dados (todas já existentes)

| Rota | Auth | Uso na página |
|---|---|---|
| `GET /treino/profile?user=` | opcional | cabeçalho + privacidade + `created_at` |
| `GET /treino/history-full?user=` | opcional | TXT 7 campos `tempo:login:probid:lang:verdict:epoch:subid` — TODO o resto deriva daqui |
| `GET /treino/problems` | anônimo | títulos, tags, coleções e contagens (dificuldade) |
| `GET /treino/achievements` | anônimo | registro de conquistas (§4) |
| `GET /treino/editors` | anônimo | ranking do editor favorito |
| `GET /submission/summary` | Bearer | resumo de testes (só o dono; 300 recentes, após o 1º render) |

Os fetches do boot rodam em **paralelo** (`Promise.allSettled`). O Bearer é enviado **sempre
que há login** — o servidor decide o que devolver; é isso que dá ao `.admin` a visão de
perfil privado.

## 3. Privacidade

O dono controla em `/treino/perfil/` (🔒 Privacidade). `public != false` = público (default).

| Visitante | Perfil PÚBLICO | Perfil PRIVADO |
|---|---|---|
| Anônimo / logado ≠ dono | tudo, MENOS cód/log e resumo de testes | só `~login` + cadeado |
| Dono | tudo (+ ✎ editar, cód/log, resumo) | tudo (o próprio sempre se vê) |
| `.admin` | tudo (sem cód/log — são do dono) | tudo (privilégio da API) |

Perfil privado também **não aparece** nas listas públicas da home (`top_users` e
`recent_solved` do `/index/open_training` pulam para o próximo).

## 4. Conquistas

As conquistas são **dados, não código**: um registro JSON servido por
`GET /treino/achievements` e avaliado no cliente contra as estatísticas do perfil.

- **Registro vivo**: `contests/treino/var/achievements.json` — criado quando um admin salva
  pela aba 🏅 do painel. Ausente ou corrompido ⇒ vale o **default embarcado**
  (`server/api/v1/lib/achievements-default.json`, versionado no repo).
- Cada conquista: `{id, icon, pt, en, kind, params, enabled}`. O rótulo exibido é `pt`/`en`
  conforme o idioma do usuário. `enabled:false` esconde sem apagar.
- **Travada** aparece acinzentada com o progresso (ex.: `62/100`); conquistada aparece
  dourada. Nenhuma é persistida no servidor — são recalculadas a cada visita (mudou o
  registro, TODOS os perfis refletem na hora).

### 4.1 Catálogo padrão

| Ícone | Nome | Regra (kind + params) |
|---|---|---|
| 🌱 | Primeiro AC | `solved_gte {n:1}` |
| ✊ | Aquecendo (10 resolvidos) | `solved_gte {n:10}` |
| ⭐ | Meio-centurião (50 resolvidos) | `solved_gte {n:50}` |
| 🏅 | Centurião (100 resolvidos) | `solved_gte {n:100}` |
| 👑 | Imparável (250 resolvidos) | `solved_gte {n:250}` |
| 🔥 | Streak de 7 dias | `streak_gte {days:7}` |
| 🔥 | Streak de 30 dias | `streak_gte {days:30}` |
| 💻 | Poliglota (5 linguagens) | `langs_gte {n:5}` |
| 🎯 | 25 one-shots (AC de primeira) | `oneshots_gte {n:25}` |
| 🎯 | Sniper (100 one-shots) | `oneshots_gte {n:100}` |
| 🏆 | Coleção completa (≥10 problemas) | `collection_complete {min_size:10}` |
| 🧗 | Alpinista (10 difíceis) | `diff_solved_gte {diff:"hard", n:10}` |
| 🕸️ | Grafeiro (15 de #grafos) | `tag_solved_gte {tag:"grafos", n:15}` |
| 📚 | Maratonista (500 envios) | `submissions_gte {n:500}` |

### 4.2 Tipos de regra (kinds) disponíveis

| kind | params | Conquistada quando… | Progresso mostrado |
|---|---|---|---|
| `solved_gte` | `n` | problemas distintos resolvidos ≥ n | `x/n` |
| `submissions_gte` | `n` | total de submissões ≥ n | `x/n` |
| `streak_gte` | `days` | MAIOR streak (dias consecutivos com envio) ≥ days | `x/days` |
| `langs_gte` | `n` | linguagens distintas usadas ≥ n | `x/n` |
| `oneshots_gte` | `n` | ACs na primeira submissão ≥ n | `x/n` (conquistada mostra `×total`) |
| `collection_complete` | `min_size` | ALGUMA coleção 100% resolvida com ≥ min_size problemas | nome da coleção |
| `collection_named` | `collection` | a coleção NOMEADA (nome exato do /treino) 100% resolvida | `x/total` |
| `tag_solved_gte` | `tag`, `n` | resolvidos com a tag (sem `#`) ≥ n | `x/n` |
| `diff_solved_gte` | `diff` (`veasy`\|`easy`\|`med`\|`hard`), `n` | resolvidos daquela dificuldade ≥ n | `x/n` |

### 4.3 Criar/configurar conquistas (admin — sem commit)

Aba **🏅 Conquistas** do painel `/treino/admin/`:

1. **➕ Nova conquista**: escolha o `kind`, preencha ícone (emoji), `id`
   (`minúsculas/dígitos/hífen`), nomes **pt e en** (obrigatórios — a UI é bilíngue) e os
   parâmetros do tipo. Ex.: "🐍 Pythonista" não dá para fazer por linguagem hoje (não há
   kind por linguagem — ver §4.4), mas "🏁 OBI completa" é
   `collection_named {collection:"Olimpíada Brasileira de Informática"}`.
2. Edite (✎), remova (✕) ou desligue (checkbox) qualquer item — inclusive os do padrão.
3. **💾 Salvar registro** publica TUDO de uma vez (o servidor valida e grava
   `var/achievements.json`; auditado como `achievements-save`).
4. **↺ Restaurar padrão** apaga o registro personalizado e volta ao default embarcado.

Pela API (mesmo efeito): `POST /treino/admin/achievements` com
`{"achievements":[…]}` ou `{"restore_default":true}` (Bearer de `.admin`).

Exemplo de item novo, pronto para colar:

```json
{ "id": "obi-completa", "icon": "🏁",
  "pt": "OBI completa", "en": "Full OBI",
  "kind": "collection_named",
  "params": { "collection": "Olimpíada Brasileira de Informática" },
  "enabled": true }
```

### 4.4 Criar um TIPO de regra novo (é código)

Um kind novo (ex.: `lang_solved_gte` — resolvidos numa linguagem específica) exige mexer em
**quatro** lugares, no MESMO commit:

1. **Avaliação** — `web/treino/stat/stat.js`, função `evalAchievement`: um `case` novo
   devolvendo `{got, sub}` (o `ctx` de `achContext` já traz os agregados comuns; acrescente
   ali o que faltar). Kind desconhecido devolve `null` e a conquista simplesmente não
   renderiza em cliente antigo — seguro para publicar registro antes do deploy do cliente.
2. **Validação** — `server/api/v1/handlers/treino/admin/achievements.sh`, função `perr` do
   jq: o ramo do kind com a checagem dos params (o POST recusa kind desconhecido).
3. **Formulário do admin** — `web/treino/admin/admin.js`, tabela `ACH_KINDS`: rótulo pt/en
   + lista de campos (`number`/`text`/`select`).
4. **Esta doc** (§4.2) — e, se a conquista entrar no padrão,
   `server/api/v1/lib/achievements-default.json`.

### 4.5 Limites e comportamento

- Máx. **100** conquistas; `id` único; validação server-side devolve o PRIMEIRO erro (400
  `achievements_invalid`).
- O registro salvo é NORMALIZADO (só os campos do contrato + `updated_at`/`updated_by`).
- Não há medalha persistida/notificação — é derivação ao vivo (fora do escopo por ora).

## Ver também

- `docs/API.md` — contratos de `/treino/achievements`, `/treino/admin/achievements`,
  `/treino/profile`, `/treino/history-full`.
- `docs/ESTATISTICAS-PROBLEMA.md` — a página irmã de estatísticas POR PROBLEMA.
- `docs/MANUAL-ADMIN.md` — o painel administrativo do treino.
