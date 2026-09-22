# lib/nutella.sh — integração com o NUTELLABOOT (gestão das máquinas maratona linux).
#
# O nutellaboot é o serviço EXTERNO que gerencia as máquinas mlinux das sedes (boot,
# telemetria, comandos). Cada sede é uma "site-image" (id `26<cc><sede>` casando com o
# prefixo de login dos times: 26brprcu ↔ teambrprcu001) e o roster de cada imagem já usa
# o LOGIN MOJ como user_id — a ponte entre os dois mundos. Ver docs/NUTELLABOOT.md.
#
# SEGREDO: a chave mora em contests/<c>/secrets/nutellaboot.key (600), NUNCA
# no conf (que é sourced e sai em export/template) e NUNCA em argv (o curl recebe o
# header por -K em process substitution — molde do mojinho-api.sh; /proc não vê nada).
# A URL, que não é segredo, fica no conf (NUTELLABOOT_URL; ausente = a de produção).
#
# DUAS CLASSES DE CHAVE (NutellaBoot 3, docs/api.md do serviço):
#   nb3a_…  ADMINISTRAÇÃO — faz tudo, inclusive as rotas de CONSOLE (`/whoami`, listar
#           `/site-images`, `POST /commands` da frota, `PUT …/webhooks`).
#   nb3s_…  SERVIÇO — a que a integração do MOJ DEVE usar: escopos (`machines:read`,
#           `commands:write`, `bindings:write`, `roster:read|write`) + lista de imagens. Ela NÃO
#           entra nas rotas de console: por isso as sedes podem vir de `NUTELLABOOT_IMAGES`
#           (conf) em vez da listagem, e o preflight não depende do `/whoami`.
# Até 21/09/2026 o MOJ só aceitava `nb3a_` — ou seja, só funcionava com a chave MAIS poderosa.
#
# Sourceada POR HANDLER (não entra no prelúdio/sources.sh — rota fria).

: "${NUTELLA_DEFAULT_URL:=https://nutellaboot.mdp.naquadah.com.br}"

nb_keyfile(){ printf '%s/%s/secrets/nutellaboot.key' "$CONTESTSDIR" "$1"; }

nb_configured(){ [[ -s "$(nb_keyfile "$1")" ]]; }

nb_url(){  # <contest> -> base SEM barra final (conf NUTELLABOOT_URL ou o default)
  local u; u="$(conf_value "$1" NUTELLABOOT_URL)"
  [[ "$u" =~ ^https?:// ]] || u="$NUTELLA_DEFAULT_URL"
  printf '%s' "${u%/}"
}

NB_KEY_RE='nb3[as]_[A-Za-z0-9]+'
nb_key(){ grep -aoE "$NB_KEY_RE" "$(nb_keyfile "$1")" 2>/dev/null | head -n1; }
# nb_key_kind <contest> -> admin | service | "" (sem chave). Decide o que dá p/ chamar.
nb_key_kind(){
  local k; k="$(nb_key "$1")"
  case "$k" in nb3a_*) printf admin;; nb3s_*) printf service;; *) printf '';; esac
}

# nb_images <contest> -> ids das site-images do evento, 1/linha. Fonte: conf NUTELLABOOT_IMAGES
# (ids separados por espaço). Com chave de SERVIÇO a lista é OPCIONAL desde 21/09/2026: o serviço passou a
# listar `/site-images` pelo glob da chave (e o `/whoami` traz `images`) — a lista à mão só RESTRINGE.
nb_images(){
  local v i; v="$(conf_value "$1" NUTELLABOOT_IMAGES)"; v="${v//\\/}"
  for i in $v; do [[ "$i" =~ ^[A-Za-z0-9._-]{1,64}$ ]] && printf '%s\n' "$i"; done
  return 0
}

# nb_curl <contest> <METHOD> </api/v1/...> [arquivo-json-do-corpo]
#   -> corpo + última linha "HTTP <code>" (molde api() do mojinho-api.sh).
# Timeout 30s: chamada síncrona de handler não pode segurar um worker além disso — a
# COLETA pesada roda destacada (nutella-gen.sh), usa a MESMA função e sobe o teto por
# NB_TIMEOUT (o lote de samples de uma sede grande não cabe em 30 s).
nb_curl(){
  local c="$1" method="$2" path="$3" bodyf="${4:-}" key tmo="${NB_TIMEOUT:-30}"
  key="$(nb_key "$c")"
  [[ -n "$key" ]] || { printf 'HTTP 000'; return 1; }
  [[ "$tmo" =~ ^[0-9]+$ ]] || tmo=30
  # --compressed: o lote de samples de uma sede grande são vários MB — o serviço comprime quando pedido
  local hdr=(); [[ "${NB_HEADERS:-0}" == 1 ]] && hdr=(-D -)
  if [[ -n "$bodyf" ]]; then
    curl -s --compressed -m "$tmo" -w $'\nHTTP %{http_code}' "${hdr[@]}" -X "$method" \
      -H 'Content-Type: application/json' -d @"$bodyf" \
      -K <(printf 'header = "Authorization: Bearer %s"\nurl = "%s/api/v1%s"\n' \
           "$key" "$(nb_url "$c")" "$path")
  else
    curl -s --compressed -m "$tmo" -w $'\nHTTP %{http_code}' "${hdr[@]}" -X "$method" \
      -K <(printf 'header = "Authorization: Bearer %s"\nurl = "%s/api/v1%s"\n' \
           "$key" "$(nb_url "$c")" "$path")
  fi
}
nb_status(){ tail -n1 <<<"$1" | awk '{print $2}'; }
# (com NB_HEADERS=1 a resposta vem com os cabeçalhos na frente: pula até a linha vazia)
nb_body(){ sed '$d' <<<"$1" | awk 'NR==1 && /^HTTP\// {h=1} h && /^\r?$/ {h=0; next} !h'; }
# nb_code <resposta> -> o `code` legível por máquina do erro (NutellaBoot ≥ 21/09/2026: todo erro traz
# {detail, code}; catálogo em GET /events/types). Vazio em sucesso ou em serviço antigo — quem decide
# pelo código tem de ter um fallback pelo HTTP.
nb_code(){ nb_body "$1" | jq -r '.code // empty' 2>/dev/null; }
# nb_retry_after <resposta> -> segundos do Retry-After (429) ou vazio. O -w do curl não traz cabeçalho: quem
# precisa dele chama com NB_HEADERS=1 e o cabeçalho vem antes do corpo (nb_body continua valendo: o corpo
# JSON é a última linha antes do "HTTP").
nb_retry_after(){ grep -im1 '^retry-after:' <<<"$1" | tr -dc '0-9'; }
# nb_whoami <contest> -> JSON de /whoami (chave admin E de serviço — desde 21/09/2026 a de serviço também
# responde: {kind:"service", name, scopes[], image_globs[], images[]}) ou vazio
nb_whoami(){ local r; r="$(nb_curl "$1" GET /whoami)"; [[ "$(nb_status "$r")" == 200 ]] && nb_body "$r" | jq -c . 2>/dev/null; }

# nb_staff_regions <contest> — ecoa (1/linha) os NOMES de sede que o SESSION_LOGIN
# (.cstaff/.staff) enxerga, pelos tokens `region:` do staff-filters (idioma do badges.sh).
# Escopo só-regex (sem region:) cai em staff_visible_logins → .team.region dos visíveis.
# rc=1 = SEM escopo (arquivo/entrada ausente): convenção da casa é "vê tudo".
nb_staff_regions(){   # a regra mora na lib/print.sh (staff_regions) — é a mesma do link do reveleitor
  declare -F staff_regions >/dev/null 2>&1 || source "$_LIBDIR/print.sh" 2>/dev/null
  staff_regions "$1"
}
