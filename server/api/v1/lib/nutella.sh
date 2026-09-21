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
# (ids separados por espaço). É o que permite trabalhar com chave de SERVIÇO, que não lista
# `/site-images`; com chave admin a lista é opcional (o coletor descobre sozinho).
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
  if [[ -n "$bodyf" ]]; then
    curl -s -m "$tmo" -w $'\nHTTP %{http_code}' -X "$method" \
      -H 'Content-Type: application/json' -d @"$bodyf" \
      -K <(printf 'header = "Authorization: Bearer %s"\nurl = "%s/api/v1%s"\n' \
           "$key" "$(nb_url "$c")" "$path")
  else
    curl -s -m "$tmo" -w $'\nHTTP %{http_code}' -X "$method" \
      -K <(printf 'header = "Authorization: Bearer %s"\nurl = "%s/api/v1%s"\n' \
           "$key" "$(nb_url "$c")" "$path")
  fi
}
nb_status(){ tail -n1 <<<"$1" | awk '{print $2}'; }
nb_body(){ sed '$d' <<<"$1"; }

# nb_staff_regions <contest> — ecoa (1/linha) os NOMES de sede que o SESSION_LOGIN
# (.cstaff/.staff) enxerga, pelos tokens `region:` do staff-filters (idioma do badges.sh).
# Escopo só-regex (sem region:) cai em staff_visible_logins → .team.region dos visíveis.
# rc=1 = SEM escopo (arquivo/entrada ausente): convenção da casa é "vê tudo".
nb_staff_regions(){   # a regra mora na lib/print.sh (staff_regions) — é a mesma do link do reveleitor
  declare -F staff_regions >/dev/null 2>&1 || source "$_LIBDIR/print.sh" 2>/dev/null
  staff_regions "$1"
}
