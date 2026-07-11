# MOJ — plataforma (cdmoj)

Juiz online (`moj.naquadah.com.br`) escrito em **bash**. Este repo (`cd-moj/cdmoj`) é a
**plataforma web**: uma **API bash** sob nginx + fcgiwrap (`server/`) + um **frontend
vanilla ESM sem build** (`web/`) + documentação (`docs/`). Os juízes **não** precisam deste
repo — eles rodam o `judge/` + `mojtools/` e puxam job pela API (modelo pull).

> Comece por **[`docs/OVERVIEW.md`](docs/OVERVIEW.md)** (arquitetura) e
> **[`docs/FLOW.md`](docs/FLOW.md)** (o caminho de uma submissão). Rotas:
> [`docs/API.md`](docs/API.md) + `web/api/openapi.json`. Deploy: [`docs/DEPLOY.md`](docs/DEPLOY.md);
> instalação do zero: [`docs/ADMIN.md`](docs/ADMIN.md). Manuais de usuário (treino, competidor,
> linguagens, staff, juiz): [`docs/`](docs/) (arquivos `MANUAL-*.md`).

## Onde vive (workspace multi-repo)

`/home/ribas/moj` **não** é um repositório — é o checkout de dev que junta repos independentes:

| Caminho | Papel |
|---|---|
| `cdmoj/` (este) | Plataforma: `server/` (API bash) + `web/` (frontend estático) + `docs/`. |
| `mojtools/` | Sandbox de julgamento + renderer de enunciado (usado pelo servidor e pelos juízes). |
| `judge/` | Agente pull que roda nas máquinas de julgamento. |
| `moj-cli/` | CLI `moj` de autoria de problemas (espelha o editor web). |
| `contests/`, `moj-problems/`, `run/` | Dados + estado de runtime (fora do versionamento). |

## Rodar com podman (recomendado)

A imagem (`deploy/Containerfile`, base `debian:trixie-slim`) traz **todas** as dependências
(jq, pandoc, git, ImageMagick, ghostscript, poppler, paps, fcgiwrap, e — por build-arg —
LibreOffice + JRE/jplag). O **nginx do host** serve `web/`/`docs/` e faz `fastcgi_pass` ao
socket unix do container; os dados vêm por **volume** (nunca na imagem).

```bash
cd cdmoj
make check          # bash -n + node --check (ESM)
make image          # constrói localhost/moj-server:<data> e re-tagueia :prod
make install-units  # instala os quadlets em ~/.config/containers/systemd/
systemctl --user start moj-api moj-judged
loginctl enable-linger "$USER"   # (opcional) sobreviver a logout
make smoke          # login->submit->history no contest de teste
```

Dois containers da MESMA imagem, papéis diferentes: **moj-api** (fcgiwrap + `router.sh`) e
**moj-judged** (daemon que enfileira p/ o pull) — restart independente.

### Atualizar (super simples)

O quadlet aponta sempre p/ `localhost/moj-server:prod`; build local e `podman pull` do
registry acabam ambos em `podman tag … :prod`, e o restart é o mesmo comando:

```bash
make deploy                 # git pull + build + restart + smoke
make deploy FROM=registry   # idem, mas puxa a imagem de ghcr.io/cd-moj/moj-server
make rollback PREV=<tag>    # re-tag da versão anterior + restart
make status                 # avisa se a imagem :prod divergiu do checkout
```

### Loop de dev (editar vale na próxima requisição)

Os handlers são `source`ados por requisição e `web/` é estático — editar `server/**` ou
`web/**` vale sem rebuild. `make dev` sobe a imagem com o código bind-montado ao vivo.

## Testar sem subir nada

- `bash -n server/**/<arquivo>.sh` · `node --check web/**/<arquivo>.js` (ou `make check`).
- Fluxo assíncrono de ponta a ponta (contest `zzdemo`): ver `docs/DEPLOY.md`.

## Convenções

Commits em PT, presente, prefixados pelo componente (`problemas:`, `julgamento:`, `deploy:` …);
rodapé só `Co-Authored-By:`. **Doc junto com o código** (rota/campo → `docs/API.md` +
`web/api/openapi.json`; arquitetura → `docs/OVERVIEW.md`/`FLOW.md`). Ver `CLAUDE.md`.
