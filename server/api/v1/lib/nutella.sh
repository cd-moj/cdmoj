# lib/nutella.sh — integração com o NUTELLABOOT (gestão das máquinas maratona linux).
#
# O nutellaboot é o serviço EXTERNO que gerencia as máquinas mlinux das sedes (boot,
# telemetria, comandos). Cada sede é uma "site-image" (id `26<cc><sede>` casando com o
# prefixo de login dos times: 26brprcu ↔ teambrprcu001) e o roster de cada imagem já usa
# o LOGIN MOJ como user_id — a ponte entre os dois mundos. Ver docs/NUTELLABOOT.md.
#
# SEGREDO: a chave (`nb3a_…`) mora em contests/<c>/secrets/nutellaboot.key (600), NUNCA
# no conf (que é sourced e sai em export/template) e NUNCA em argv (o curl recebe o
# header por -K em process substitution — molde do mojinho-api.sh; /proc não vê nada).
# A URL, que não é segredo, fica no conf (NUTELLABOOT_URL; ausente = a de produção).
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

# nb_curl <contest> <METHOD> </api/v1/...> [arquivo-json-do-corpo]
#   -> corpo + última linha "HTTP <code>" (molde api() do mojinho-api.sh).
# Timeout 30s: chamada síncrona de handler não pode segurar um worker além disso — a
# COLETA pesada roda destacada (nutella-gen.sh) e usa a mesma função.
nb_curl(){
  local c="$1" method="$2" path="$3" bodyf="${4:-}" key
  key="$(grep -aoE 'nb3a_[A-Za-z0-9]+' "$(nb_keyfile "$c")" 2>/dev/null | head -n1)"
  [[ -n "$key" ]] || { printf 'HTTP 000'; return 1; }
  if [[ -n "$bodyf" ]]; then
    curl -s -m 30 -w $'\nHTTP %{http_code}' -X "$method" \
      -H 'Content-Type: application/json' -d @"$bodyf" \
      -K <(printf 'header = "Authorization: Bearer %s"\nurl = "%s/api/v1%s"\n' \
           "$key" "$(nb_url "$c")" "$path")
  else
    curl -s -m 30 -w $'\nHTTP %{http_code}' -X "$method" \
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
nb_staff_regions(){
  local c="$1" f="$CONTESTSDIR/$1/print-requests/staff-filters.json" out
  [[ -s "$f" ]] || return 1
  jq -e --arg s "$SESSION_LOGIN" 'has($s) and ((.[$s] // []) | length > 0)' "$f" >/dev/null 2>&1 || return 1
  out="$(jq -r --arg s "$SESSION_LOGIN" \
    '(.[$s] // [])[] | select(startswith("region:")) | .[7:] | gsub("^ +| +$"; "")' "$f" 2>/dev/null)"
  if [[ -n "$out" ]]; then printf '%s\n' "$out"; return 0; fi
  # escopo por regex: resolve os logins visíveis e colhe as sedes deles
  source "$_LIBDIR/print.sh" 2>/dev/null || true
  local logins
  if logins="$(staff_visible_logins "$c" "$SESSION_LOGIN" 2>/dev/null)"; then
    printf '%s\n' "$logins" | while IFS= read -r lg; do
      [[ -n "$lg" ]] || continue
      jq -r '.team.region // empty' "$(account_file "$c" "$lg")" 2>/dev/null
    done | sort -u
    return 0
  fi
  return 1
}
