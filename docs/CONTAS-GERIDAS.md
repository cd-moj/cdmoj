# Contas geridas (menores de idade, sem Telegram)

O cadastro normal do Treino Livre é confirmado pelo **Telegram** — o que exclui quem não
pode ter a conta no mensageiro, tipicamente **menores de idade**. A **conta gerida** é a
resposta: criada por um `.admin` **responsável**, sem nenhum vínculo com Telegram, e com
travas de privacidade que **caem automaticamente aos 18 anos**.

## O modelo em 30 segundos

| | Conta normal | Conta GERIDA (menor) |
|---|---|---|
| Nasce | cadastro web + Telegram | aba **🧒 Contas geridas** do `/treino/admin/` |
| Senha | por DM do bot | **gerada e mostrada UMA vez** ao admin |
| Esqueci a senha | `/trocarsenha` no bot | **só o admin** (🔑 na aba) |
| Perfil público | opcional (padrão público) | **sempre privado** (o servidor recusa tornar público) |
| Telegram | opcional | **bloqueado** |
| Aos 18 | — | as travas **caem sozinhas**: pode vincular Telegram e abrir o perfil |

A marca fica no `account.json` do usuário:

```json
"managed": { "by": "prof.admin", "note": "turma A, Escola X",
             "birthdate": "2011-03-14", "expires_at": null, "created_at": 1785000000 }
```

**Menor** é calculado da data de nascimento a cada acesso — nada é "virado" aos 18; os
gates simplesmente deixam de valer. A marca `managed` permanece (histórico/listagem, com
o badge `18+`), e o perfil continua privado até o próprio usuário abri-lo.

## O que o menor pode e não pode

- **Pode**: tudo do treino — resolver, submeter, ver o próprio perfil/estatísticas,
  editar nome/universidade/editor/foto, trocar a própria senha (sabendo a atual).
- **Não pode (até os 18)**:
  - **tornar o perfil público** — `profile_is_public` corta no servidor; a conta não
    aparece no top-10 nem no "resolvido recentemente" da home, e o perfil dos outros
    pontos de vista é o cadeado 🔒 (mesma regra do perfil privado comum);
  - **vincular Telegram** — `POST /treino/telegram/link-start` responde 403
    `managed_minor`.
- **Expiração (opcional)**: com `expires_at` vencido o login responde 403
  `account_expired` ("fale com o responsável"). Renovar = editar/limpar a data na aba.

## Operação (aba 🧒 Contas geridas do `/treino/admin/`)

- **➕ Nova conta**: nome completo + **nascimento** (obrigatórios), login opcional
  (vazio = gerado do nome, `nome.sobrenome`, com dedup), nota livre e expiração opcional.
- **📥 Criar em lote**: uma linha por conta no formato `Nome Completo;AAAA-MM-DD`, com
  nota e expiração comuns — ideal para uma turma.
- **Credenciais**: a resposta mostra **login + senha de cada conta criada, UMA única
  vez**, com "📋 Copiar tudo". A senha **não é recuperável depois** — anote/imprima na hora (o treino não tem tela de etiquetas: `/contest/badges` recusa `contest=treino` de propósito, para não despejar a base inteira em claro).
- **Por conta**: 🔑 senha nova (mostrada uma vez; derruba sessões) · ✎ editar
  nota/nascimento/expiração · ⏻ desabilitar (senha-sentinela + derruba sessões) /
  ▶ reabilitar (senha nova) · ✕ remover (arquiva em `.removed-users/`, submissões
  preservadas).
- **Filtros**: por texto e **"só as minhas"** (contas cujo responsável sou eu).
- **Auditoria**: `managed-create/reset/update/remove` entram no audit-log com o admin
  autor (aba 📜 Atividade).

## Pela API (mesmo efeito; Bearer de `.admin`)

| Rota | Uso |
|---|---|
| `GET  /treino/admin/managed-users` | lista `{login,fullname,by,note,birthdate,minor,expires_at,disabled}` |
| `POST /treino/admin/managed-create` | `{users:[{fullname,birthdate,login?,note?,expires_at?}]}` (1..500) → `{created:[{login,password,…}], skipped}` |
| `POST /treino/admin/managed-reset` | `{login}` → senha nova (uma vez) |
| `POST /treino/admin/managed-update` | `{login, note?, birthdate?, expires_at?\|null, disabled?}` |
| `POST /treino/admin/managed-remove` | `{login}` |

## Privacidade e dados (nota LGPD)

- O único dado extra guardado é a **data de nascimento** — necessária para o
  desbloqueio automático aos 18 — mais a nota livre do responsável (evite dados
  sensíveis na nota; ela é visível a todos os admins).
- O perfil do menor é **invisível ao público por construção** (gate no servidor, não na
  UI): estatísticas, foto e histórico só para o próprio e para admins.
- A senha **não fica armazenada em claro em nenhum lugar novo** além do `account.json`
  (modelo padrão da plataforma) e só transita na resposta de criação/reset.

## Para quem mantém o código

- Helpers: `managed_json` / `is_managed_minor` em `server/api/v1/lib/profile.sh` —
  `is_managed_minor` é o gate usado por `profile_is_public`, pelo POST do
  `/treino/profile` e pelo `link-start`. Data ilegível = trata como menor (fail-safe).
- A UI do perfil (`web/treino/perfil/perfil.js`) esconde o vínculo Telegram e trava o
  checkbox de privacidade quando `GET /treino/profile` devolve `managed.minor:true`.
- Guarda colateral: `POST /contest/admin/users-set-password` **recusa `contest=treino`**
  (um POST resetaria todas as contas da plataforma).

## Ver também

- [`MANUAL-TREINO.md`](MANUAL-TREINO.md) — o manual do aluno (cadastro normal, login).
- [`PERFIL.md`](PERFIL.md) — o perfil público e as conquistas.
- [`API.md`](API.md) — contratos completos das rotas.
