# cdmoj/Makefile — build/deploy da imagem podman do MOJ.
#
#   make image                # constrói localhost/moj-server:$(TAG) e re-tagueia :prod
#   make install-units        # quadlets -> ~/.config/containers/systemd/ (raiz = WORKROOT)
#   make deploy               # git pull + image (ou pull) + restart + smoke
#   make deploy FROM=registry # idem, mas puxa a imagem do registry em vez de buildar
#   make rollback PREV=<tag>  # volta :prod p/ uma tag anterior e reinicia
#
# A imagem é a API + o daemon; o nginx do host serve web/ e faz fastcgi_pass ao socket.
# WORKROOT = raiz do workspace (o dir que contém cdmoj/ mojtools/ contests/ run/); default `..`.
# Ver deploy/Containerfile, deploy/quadlet/, docs/DEPLOY.md.

SHELL      := /bin/bash
IMAGE      ?= localhost/moj-server
REGISTRY   ?= ghcr.io/cd-moj/moj-server
TAG        ?= $(shell date +%Y-%m-%d)
PROD       ?= prod
WORKROOT   ?= ..
WITH_OFFICE ?= 1
WITH_JPLAG  ?= 1
UNITDIR    ?= $(HOME)/.config/containers/systemd
HOST_HDR   ?= moj.charge.naquadah.com.br
BASE       ?= http://127.0.0.1:8080

.PHONY: help check check-jq cli-dist docs-html image pull push install-units deploy restart restart-judged \
        rollback status smoke logs shell dev

help:
	@sed -n '1,11p' Makefile

## check — bash -n em todo .sh do server + node --check nos ESM (via .mjs, senão passa falso)
check:
	@echo ">> bash -n server/**/*.sh"; \
	find server -name '*.sh' -print0 | xargs -0 -n1 bash -n && echo "   sintaxe ok"; \
	echo ">> node --check web/**/*.js (ESM)"; \
	if command -v node >/dev/null 2>&1; then \
	  t=$$(mktemp -d); rc=0; \
	  while IFS= read -r -d '' f; do cp "$$f" "$$t/x.mjs"; node --check "$$t/x.mjs" || { echo "FAIL: $$f"; rc=1; }; done \
	    < <(find web -name '*.js' -not -path 'web/shared/vendor/*' -print0); \
	  rm -rf "$$t"; [ $$rc -eq 0 ] && echo "   ESM ok"; exit $$rc; \
	else echo "   (node ausente — pulei ESM)"; fi

## check-jq — compila TODO programa jq com o jq da IMAGEM (1.7), que é mais ESTRITO que o do dev (1.8)
# O 1.8 aceita `{a: X + Y}`; o 1.7 exige `{a: (X + Y)}`. Escrever no dev e só quebrar em produção
# (200 com corpo vazio, silencioso) já derrubou toda a listagem de problemas — ver server/test/.
check-jq:
	@podman image exists $(IMAGE):$(PROD) || { echo "sem $(IMAGE):$(PROD) — rode 'make image'"; exit 1; }
	podman run --rm --entrypoint bash -v $(CURDIR):/src:ro,z -w /src $(IMAGE):$(PROD) \
	  server/test/jq-portability.sh server

## image — constrói a imagem (contexto = raiz do workspace) e re-tagueia :prod
# regenera os artefatos de distribuição das CLIs (1 arquivo, lib embutida) a partir do
# checkout irmão ../moj-cli e sincroniza web/moj{,-contest,-judges}. O elo era MANUAL e
# dessincronizava (o /moj-contest servido ficou velho); agora todo deploy embarca CLIs
# frescas. Sem ../moj-cli (checkout avulso do cdmoj): avisa e segue.
cli-dist:
	@if [ -d ../moj-cli ]; then \
	  ( cd ../moj-cli && bash mkdist.sh >/dev/null ) || { echo "cli-dist: mkdist FALHOU" >&2; exit 1; }; \
	  for f in moj moj-contest moj-judges; do \
	    if ! cmp -s ../moj-cli/dist/$$f web/$$f 2>/dev/null; then \
	      cp ../moj-cli/dist/$$f web/$$f && echo "cli-dist: web/$$f ATUALIZADO"; \
	    fi; \
	  done; \
	else echo "cli-dist: ../moj-cli ausente — web/moj* mantidos como estão" >&2; fi

# docs/html é artefato por-checkout (gitignorado) — o /docs serve DELE. Sem pandoc no host,
# avisa e segue (o autoindex do nginx é o fallback).
docs-html:
	@if command -v pandoc >/dev/null 2>&1; then \
	  bash docs/build-html.sh >/dev/null && echo "docs-html: docs/html regenerado"; \
	else echo "docs-html: pandoc ausente no host — /docs pode ficar sem HTML" >&2; fi

image: cli-dist docs-html
	podman build --ignorefile deploy/.containerignore -f deploy/Containerfile \
	  --build-arg WITH_OFFICE=$(WITH_OFFICE) --build-arg WITH_JPLAG=$(WITH_JPLAG) \
	  --label org.opencontainers.image.revision=$$(git rev-parse --short HEAD) \
	  -t $(IMAGE):$(TAG) $(WORKROOT)
	podman tag $(IMAGE):$(TAG) $(IMAGE):$(PROD)
	@echo ">> imagem $(IMAGE):$(TAG) pronta e tagueada :$(PROD)"

## pull — puxa a imagem do registry e a tagueia como :prod local
pull:
	podman pull $(REGISTRY):$(TAG)
	podman tag $(REGISTRY):$(TAG) $(IMAGE):$(PROD)

## push — publica a tag no registry (precisa `podman login $(REGISTRY)`)
push:
	podman tag $(IMAGE):$(TAG) $(REGISTRY):$(TAG)
	podman push $(REGISTRY):$(TAG)

## install-units — instala os quadlets (com a raiz do workspace substituída) e recarrega o systemd
# Os quadlets são TEMPLATES: `@WORKROOT@` -> caminho absoluto de $(WORKROOT). Instalar por cópia
# crua (install/cp) deixaria o `@WORKROOT@` literal e o container não subiria.
install-units:
	@mkdir -p $(UNITDIR)
	@root="$$(cd $(WORKROOT) && pwd)"; \
	for q in moj-api moj-judged; do \
	  sed "s|@WORKROOT@|$$root|g" deploy/quadlet/$$q.container > $(UNITDIR)/$$q.container; \
	  chmod 644 $(UNITDIR)/$$q.container; \
	done; \
	echo ">> quadlets instalados em $(UNITDIR) (workspace = $$root)"
	systemctl --user daemon-reload
	@echo ">> Suba: systemctl --user start moj-api moj-judged   (+ sudo loginctl enable-linger \$$USER)"
	@echo "   (quadlet gera as units: 'systemctl enable' não se aplica — o [Install] do .container"
	@echo "    já as põe no default.target, e o linger é quem as sobe no boot.)"

## deploy — atualiza tudo. FROM=registry puxa em vez de buildar.
deploy:
	git pull --ff-only
	git -C $(WORKROOT)/mojtools pull --ff-only || true
ifeq ($(FROM),registry)
	$(MAKE) pull
else
	$(MAKE) image
endif
	$(MAKE) restart
	$(MAKE) smoke

## restart / restart-judged — reinício independente
# systemctl --user precisa do bus da sessão; sob `sudo -u moj make deploy` ele não existe
# no ambiente e TODO deploy morria em "Failed to connect to bus" (restart virava passo
# manual). Exportar XDG_RUNTIME_DIR do próprio uid resolve nos dois mundos.
restart:
	XDG_RUNTIME_DIR=$${XDG_RUNTIME_DIR:-/run/user/$$(id -u)} systemctl --user restart moj-api moj-judged
	@echo ">> reiniciados moj-api + moj-judged"
restart-judged:
	XDG_RUNTIME_DIR=$${XDG_RUNTIME_DIR:-/run/user/$$(id -u)} systemctl --user restart moj-judged

## rollback — volta :prod p/ uma tag anterior e reinicia (PREV=<tag> obrigatório)
rollback:
	@test -n "$(PREV)" || { echo "uso: make rollback PREV=<tag>"; exit 2; }
	podman tag $(IMAGE):$(PREV) $(IMAGE):$(PROD)
	$(MAKE) restart
	@echo ">> rollback p/ $(IMAGE):$(PREV)"

## status — compara o revision da imagem :prod com o HEAD do checkout (avisa se divergiu)
status:
	@img=$$(podman image inspect $(IMAGE):$(PROD) --format '{{ index .Labels "org.opencontainers.image.revision" }}' 2>/dev/null); \
	head=$$(git rev-parse --short HEAD); \
	echo "imagem :prod revision = $${img:-<sem label>}"; echo "checkout HEAD       = $$head"; \
	[ "$$img" = "$$head" ] && echo "OK: em sincronia" || echo "AVISO: imagem != checkout (rode make image)"; \
	systemctl --user is-active moj-api moj-judged 2>/dev/null || true

## smoke — fluxo zzdemo ponta-a-ponta (login -> submit -> history) via o nginx do host
smoke:
	@H="Host: $(HOST_HDR)"; B="$(BASE)"; \
	echo ">> API viva:"; curl -s -H "$$H" $$B/api/v1/ | jq -c . ; \
	echo ">> /index/status:"; curl -s -H "$$H" $$B/api/v1/index/status | jq -c '{ok:.success,daemons,judge:{online:.judge.online}}'

## logs / shell — journal do container e um shell dentro dele
logs:
	journalctl --user -u moj-api -u moj-judged -f
shell:
	podman exec -it systemd-moj-api /opt/moj/bin/moj-entrypoint shell

## dev — sobe a imagem com o código bind-montado ao vivo (edições valem na próxima requisição)
dev:
	podman run --rm -it --name moj-dev \
	  -v $(CURDIR)/server:/opt/moj/cdmoj/server:ro,z \
	  -v $(WORKROOT)/mojtools:/opt/moj/mojtools:ro,z \
	  -v $(WORKROOT)/run:/data/run:z \
	  -v $(WORKROOT)/contests:/data/contests:z \
	  -v $(WORKROOT)/moj-problems:/data/moj-problems:z \
	  $(IMAGE):$(PROD) api
