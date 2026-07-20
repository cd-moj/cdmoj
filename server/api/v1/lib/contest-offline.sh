# lib/contest-offline.sh — submissão OFFLINE de contest (moj-comp): chave por contest,
# beacon de tempo assinado e decriptação de pacote. Fluxo completo: docs/FLOW.md §offline;
# rotas: docs/API.md (/contest/beacon, /contest/offline-submit).
#
# Modelo: o aluno recebe a PÚBLICA no login; sem rede, a CLI cifra {código+hora UTC} e
# guarda; na volta, /contest/offline-submit valida e contabiliza NO horário reivindicado.
# O tempo é cercado por dois lados: beacon assinado (piso — o pacote nasceu DEPOIS dele) e
# chegada (teto). A privada NUNCA sai de contests/<cid>/secrets/ (não vai em export/
# duplicate/template — esses caminhos só leem conf/PROBS).

: "${OFFLINE_SKEW_MAX:=30}"     # tolerância p/ claimed no futuro (relógio adiantado), segundos

offline_keydir(){ printf '%s/%s/secrets' "$CONTESTSDIR" "$1"; }

# offline_ensure_keys <cid> — gera o par RSA-4096 na 1ª vez (flock anti-corrida); ecoa o
# caminho da pública (vazio+rc1 se openssl falhar — o login degrada sem campos offline).
offline_ensure_keys(){
  local d; d="$(offline_keydir "$1")"
  if [[ ! -s "$d/offline.pub" ]]; then
    mkdir -p "$d" 2>/dev/null; chmod 700 "$d" 2>/dev/null
    ( flock -x 9
      if [[ ! -s "$d/offline.pub" ]]; then
        ( umask 077; openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:4096 \
            -out "$d/offline.key.tmp" 2>/dev/null ) \
        && openssl pkey -in "$d/offline.key.tmp" -pubout -out "$d/offline.pub.tmp" 2>/dev/null \
        && mv -f "$d/offline.key.tmp" "$d/offline.key" \
        && mv -f "$d/offline.pub.tmp" "$d/offline.pub"
        rm -f "$d/offline.key.tmp" "$d/offline.pub.tmp" 2>/dev/null
      fi
    ) 9>"$d/.offline.lock" 2>/dev/null
  fi
  [[ -s "$d/offline.pub" ]] || return 1
  printf '%s' "$d/offline.pub"
}

# offline_beacon <cid> <login> — ecoa "payload_b64.sig_b64"; payload JSON {v,c,l,t,n},
# assinatura RSA-PSS/sha256 da chave do contest. É o PISO de tempo do pacote offline.
offline_beacon(){
  local d payload pb sig n
  d="$(offline_keydir "$1")"; offline_ensure_keys "$1" >/dev/null || return 1
  n="$(head -c8 /dev/urandom | od -An -tx1 | tr -d ' \n')"
  payload="$(jq -cn --arg c "$1" --arg l "$2" --argjson t "$EPOCHSECONDS" --arg n "$n" \
             '{v:1, c:$c, l:$l, t:$t, n:$n}')"
  pb="$(printf '%s' "$payload" | base64 -w0)"
  sig="$(printf '%s' "$payload" \
         | openssl dgst -sha256 -sign "$d/offline.key" \
             -sigopt rsa_padding_mode:pss -sigopt rsa_pss_saltlen:-1 2>/dev/null | base64 -w0)"
  [[ -n "$sig" ]] || return 1
  printf '%s.%s' "$pb" "$sig"
}

# offline_beacon_verify <cid> <beacon> — ecoa o payload JSON se a assinatura confere; rc 1 senão.
offline_beacon_verify(){
  local d pb sig payload sf
  d="$(offline_keydir "$1")"
  pb="${2%%.*}"; sig="${2#*.}"
  [[ -n "$pb" && -n "$sig" && "$pb" != "$2" ]] || return 1
  payload="$(printf '%s' "$pb" | base64 -d 2>/dev/null)" || return 1
  sf="$(mktemp)"; printf '%s' "$sig" | base64 -d 2>/dev/null > "$sf" || { rm -f "$sf"; return 1; }
  if printf '%s' "$payload" | openssl dgst -sha256 -verify "$d/offline.pub" \
       -sigopt rsa_padding_mode:pss -sigopt rsa_pss_saltlen:-1 \
       -signature "$sf" >/dev/null 2>&1; then
    rm -f "$sf"; printf '%s' "$payload"
  else rm -f "$sf"; return 1; fi
}

# offline_packet_decrypt <cid> <pkt-json> — pacote claro {v:1, wk, ct}: wk = RSA-OAEP de
# "key:iv:sha256(conteúdo)" (hex), ct = AES-256-CBC do JSON interno. O sha DENTRO do envelope
# RSA dá INTEGRIDADE (CBC puro deixa flipar bytes no meio sem quebrar o padding — provado no
# teste de unidade). Ecoa o JSON interno; rc 1 = inválido/adulterado.
offline_packet_decrypt(){
  local d wk ct kim key iv mac out
  d="$(offline_keydir "$1")"
  wk="$(jq -r '.wk // empty' <<<"$2")"; ct="$(jq -r '.ct // empty' <<<"$2")"
  [[ -n "$wk" && -n "$ct" && -s "$d/offline.key" ]] || return 1
  kim="$(printf '%s' "$wk" | base64 -d 2>/dev/null \
           | openssl pkeyutl -decrypt -inkey "$d/offline.key" \
               -pkeyopt rsa_padding_mode:oaep 2>/dev/null)" || return 1
  IFS=: read -r key iv mac <<<"$kim"
  [[ "$key" =~ ^[0-9a-f]{64}$ && "$iv" =~ ^[0-9a-f]{32}$ && "$mac" =~ ^[0-9a-f]{64}$ ]] || return 1
  out="$(printf '%s' "$ct" | base64 -d 2>/dev/null | openssl enc -d -aes-256-cbc -K "$key" -iv "$iv" 2>/dev/null)" || return 1
  [[ "$(printf '%s' "$out" | sha256sum | cut -d' ' -f1)" == "$mac" ]] || return 1
  printf '%s' "$out"
}
