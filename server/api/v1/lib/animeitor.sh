# lib/animeitor.sh — o MOJ EMPURRA o contest p/ a API do Animeitor (telão), versão 2.1.0 do Emilio
# Wuerges. Doc fonte-única: docs/ANIMEITOR.md. Substitui a ideia do webcast (zip no protocolo do BOCA
# que o telão PUXAVA — lib/webcast.sh, legado): aqui quem fala é o juiz.
#
# MODELO DELES → O NOSSO
#   evento   = o contest do MOJ: problemas (letras), roster {login, escola, nome}, freeze, penalidade,
#              relógio (segundos DECORRIDOS; negativo = contagem regressiva) e as runs.
#   contest  = um PLACAR: `codes` (regex de login, OR) + medalhas + template de foto/música.
#   site     = uma SEDE dentro do placar: regex + link SECRETO de revelação (derivado de salts).
# ⚠ O servidor deles NÃO avança o relógio: alguém tem de mandar `PATCH …/time` (daemons/
#   animeitor-feed.sh). ⚠ `PUT` é substituição TOTAL e zera o `salt` omitido ⇒ troca os links de
#   revelação: aqui é SEMPRE `POST` e, no 409, `PATCH` só dos campos nossos.
# ⚠ O MOJ manda a resposta REAL de toda run (como o webcast fazia): quem congela e revela é o
#   Animeitor (a API pública dele mascara `?` depois do freeze; a real só sai com a chave da sede).
#
# CREDENCIAL (25/09/2026): o MOJ tem a SUA chave no servidor padrão ($ANIMEITOR_CRED_FILE, fora de todo
#   contest) e ela vale p/ todo contest que não gravou a própria — sem nunca aparecer na tela. O
#   `.animeitor`/admin pode gravar uma chave PRÓPRIA (vence a do MOJ; apagar volta p/ a do MOJ). A chave do
#   MOJ SÓ vai ao servidor padrão ($ANIMEITOR_URL): URL digitada pelo operador exige chave própria (senão
#   qualquer contest mandaria a credencial do MOJ a um servidor qualquer). Com uma chave COMPARTILHADA por
#   todos os contests, "de quem é o evento" deixa de ser garantido pela credencial: o registro
#   $RUNDIR/animeitor/events.json ({url:{evento:contest}}) é quem diz — nome de evento de OUTRO contest é
#   recusado antes de qualquer request, e a chave do MOJ só assume (`adopt`) evento que o registro diz ser
#   deste contest.
#
# CONFERÊNCIA (an_verify): a rota PÚBLICA `GET /api/events/{e}/contests/{c}/runs_secret`, com
#   `Authorization: Bearer <chave da sede>` (o `secret` do link de revelação), devolve as runs DAQUELA sede
#   com a resposta real. O MOJ compara com o que ele tem (id, time, problema, tempo, resposta), reenvia o
#   que falta ou diverge e grava o resultado — o alimentador confere durante a prova e, com a prova
#   encerrada p/ todas as sedes e nada pendente, faz a conferência FINAL (o "validado" que o reveleitor
#   mostra). Antes do início o serviço responde 403 not_started (nada a conferir).
#
# ARQUIVOS DO CONTEST
#   secrets/animeitor.cred      600, write-only: "usuario:token" (HTTP Basic) — a chave PRÓPRIA do contest.
#                               Vai ao curl por `-K <(printf …)` — nunca argv, log, GET nem conf.
#   animeitor.json              não-segredo: {url, event, moj_base_url, enabled, feed:{clock_s,runs_s,verify_s},
#                               contests: null | [{name, source:{kind:view|region|manual, id}, codes|null,
#                               ouro, prata, bronze, style, sites:[{name, source, codes|null}]}]}
#                               (`contests:null` = ainda não revisado ⇒ vale a PROPOSTA; `codes:null`
#                               = automático, resolvido a cada publicação)
#   var/animeitor-ids.tsv       subid → id inteiro estável (score/telao-runs.sh --runs-ids)
#   var/animeitor-sent.tsv      último estado ENVIADO de cada run ⇒ só o delta viaja
#   var/animeitor-managed.json  o que ESTE contest criou lá (só isso ele altera/apaga)
#   var/animeitor.status.json   último sync/erro/contagens · var/animeitor.clock  último relógio enviado
#   var/animeitor-verify.json   a última conferência (contagens e ids — nunca chave de sede nem resposta)
#
# Requer: lib/common.sh (conf_value, valid_id), lib/cohorts.sh. Sourceada POR HANDLER (rota fria).
AN_DEFAULT_URL="${ANIMEITOR_URL:-https://animeitor.naquadah.com.br}"; AN_DEFAULT_URL="${AN_DEFAULT_URL%/}"
_AN_LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AN_RUNS_SH="$_AN_LIB/../../../score/telao-runs.sh"

an_cfg_file(){ printf '%s/%s/animeitor.json' "$CONTESTSDIR" "$1"; }
an_credfile(){ printf '%s/%s/secrets/animeitor.cred' "$CONTESTSDIR" "$1"; }     # a PRÓPRIA do contest (escrita)
an_moj_credfile(){ printf '%s' "${ANIMEITOR_CRED_FILE:-${RUNDIR:-/home/ribas/moj/run}/secrets/animeitor.cred}"; }
# an_cred_source <c> [url] -> contest | moj | none. A do MOJ só vale no servidor padrão.
an_cred_source(){
  local u="${2:-}"
  if [[ -s "$(an_credfile "$1")" ]]; then printf contest; return 0; fi
  [[ -n "$u" ]] || u="$(jq -r .url <<<"$(an_cfg "$1")")"
  if [[ -s "$(an_moj_credfile)" && "${u%/}" == "$AN_DEFAULT_URL" ]]; then printf moj; return 0; fi
  printf none
}
an_has_cred(){ [[ "$(an_cred_source "$1" "${2:-}")" != none ]]; }
# a chave do MOJ existe (p/ a tela dizer "usar a chave do MOJ" mesmo com URL própria gravada)
an_moj_cred_available(){ [[ -s "$(an_moj_credfile)" ]]; }

# só HTTPS (o serviço responde 426 em claro — e Basic em claro é credencial na rede); a exceção é
# o loopback, p/ o mock dos testes
an_url_ok(){ [[ "$1" =~ ^https://[A-Za-z0-9.-]+(:[0-9]{1,5})?$ || "$1" =~ ^http://127\.0\.0\.1(:[0-9]{1,5})?$ ]]; }
an_name_ok(){ [[ -n "$1" && ${#1} -le 64 && "$1" != *"/"* && "$1" != *$'\n'* && "$1" != *$'\t'* && "$1" != "." && "$1" != ".." ]]; }

# an_cfg <c> -> animeitor.json NORMALIZADO (nunca vazio)
an_cfg(){
  local f rf dflt="$1" slug; f="$(an_cfg_file "$1")"
  # com RODADAS (aquecimento + prova no mesmo contest) o nome-padrão do evento leva a rodada ativa: a
  # promoção zera os history, e a API do Animeitor não limpa o histórico do stream — rodada nova tem de
  # ser EVENTO novo. (Nome gravado à mão pelo operador vence.)
  rf="$CONTESTSDIR/$1/rounds.json"
  if [[ -s "$rf" ]]; then slug="$(jq -r '.active // ""' "$rf" 2>/dev/null)"; [[ "$slug" =~ ^[a-z0-9][a-z0-9_-]{0,31}$ ]] && dflt="$1-$slug"; fi
  { [[ -s "$f" ]] && cat "$f" || printf '{}'; } | jq -c --arg c "$dflt" --arg du "$AN_DEFAULT_URL" '
    { version: 1, url: ((.url // "") | if . == "" then $du else . end), event: ((.event // "") | if . == "" then $c else . end),
      event_set: (.event // ""),
      moj_base_url: (.moj_base_url // ""), enabled: (.enabled == true),
      feed: { clock_s: ((.feed.clock_s // 1) | if . < 1 then 1 else . end), runs_s: ((.feed.runs_s // 2) | if . < 1 then 1 else . end),
              verify_s: ((.feed.verify_s // 300) | if . < 30 then 30 else . end) },
      reveal: { released: (.reveal.released == true), at: (.reveal.at // 0), by: (.reveal.by // "") },
      contests: (if (.contests | type) == "array" then .contests else null end) }' 2>/dev/null \
  || jq -cn --arg c "$1" --arg du "$AN_DEFAULT_URL" '{version:1, url:$du, event:$c, event_set:"", moj_base_url:"", enabled:false, feed:{clock_s:1, runs_s:2, verify_s:300}, reveal:{released:false, at:0, by:""}, contests:null}'
}
# (`event` no arquivo é o que o operador DIGITOU — vazio = nome-padrão, que o an_cfg resolve a cada leitura;
#  gravar o nome resolvido congelaria `<contest>-<rodada>` na rodada errada)
an_cfg_save(){ local f; f="$(an_cfg_file "$1")"; printf '%s\n' "$2" | jq '.event = (.event_set // .event // "") | del(.event_set)' > "$f.tmp" 2>/dev/null && mv -f "$f.tmp" "$f"; }
an_configured(){ local u; u="$(jq -r .url <<<"$(an_cfg "$1")")"; an_url_ok "$u" && an_has_cred "$1" "$u"; }

# an_curl <c> <METHOD> </internal/…> [arquivo-do-corpo] -> corpo + última linha "HTTP <code>"
an_curl(){
  local c="$1" method="$2" path="$3" bodyf="${4:-}" cred u t base tmo="${AN_TIMEOUT:-20}"
  base="${AN_URL:-}"; [[ -n "$base" ]] || base="$(jq -r .url <<<"$(an_cfg "$c")")"
  an_url_ok "$base" || { printf '\nHTTP 000'; return 1; }
  # a chave do contest; senão a do MOJ — e esta SÓ p/ o servidor padrão (a URL de fato usada, não a gravada)
  case "$(an_cred_source "$c" "$base")" in
    contest) IFS= read -r cred < "$(an_credfile "$c")" 2>/dev/null || { printf '\nHTTP 000'; return 1; } ;;
    moj)     IFS= read -r cred < "$(an_moj_credfile)" 2>/dev/null || { printf '\nHTTP 000'; return 1; } ;;
    *)       printf '\nHTTP 000'; return 1 ;;
  esac
  u="${cred%%:*}"; t="${cred#*:}"
  # o arquivo de config do curl é entre ASPAS: usuário/token com aspas ou barra invertida quebrariam
  [[ "$u" =~ ^[A-Za-z0-9._@-]{1,64}$ && "$t" =~ ^[A-Za-z0-9._~+/=-]{8,256}$ ]] || { printf '\nHTTP 000'; return 1; }
  [[ "$tmo" =~ ^[0-9]+$ ]] || tmo=20
  if [[ -n "$bodyf" ]]; then
    curl -s -m "$tmo" -w $'\nHTTP %{http_code}' -X "$method" -H 'Content-Type: application/json' -d @"$bodyf" \
      -K <(printf 'user = "%s:%s"\nurl = "%s%s"\n' "$u" "$t" "$base" "$path")
  else
    curl -s -m "$tmo" -w $'\nHTTP %{http_code}' -X "$method" \
      -K <(printf 'user = "%s:%s"\nurl = "%s%s"\n' "$u" "$t" "$base" "$path")
  fi
}
an_status(){ tail -n1 <<<"$1" | awk '{print $2}'; }
an_body(){ sed '$d' <<<"$1"; }
an_err(){ jq -r '(.errors // [])[0] | "\(.code // ""): \(.message // "")"' <<<"$(an_body "$1")" 2>/dev/null | cut -c1-240; }
an_enc(){ jq -rn --arg s "$1" '$s | @uri'; }

# an_status_set <c> <filtro jq sobre o status atual> [args] — merge atômico em var/animeitor.status.json
an_status_set(){
  local c="$1" f tmp; shift; f="$CONTESTSDIR/$c/var/animeitor.status.json"; mkdir -p "$CONTESTSDIR/$c/var"
  # o nome do temporário é resolvido ANTES: `$BASHPID` no alvo de um redirect dentro de pipeline expande
  # no FILHO, e o `mv` do pai procuraria outro nome (o status nunca seria gravado, em silêncio)
  tmp="$f.tmp.$BASHPID"
  { [[ -s "$f" ]] && cat "$f" || printf '{}'; } | jq -c --argjson now "$EPOCHSECONDS" "$@" > "$tmp" 2>/dev/null \
    && mv -f "$tmp" "$f" || rm -f "$tmp"
}
an_fail_note(){ # <c> <onde> <http> <mensagem>
  an_status_set "$1" '.last_error = {at:$now, where:$w, http:$h, message:$m}' --arg w "$2" --arg h "$3" --arg m "$4"
}

# --- tempos ---------------------------------------------------------------------------------
# PRORROGAÇÃO POR SEDE (decisão do Ribas, 21/09/2026): o evento do Animeitor tem UM relógio só, e o MOJ
# prorroga por sede (`time-overrides.json`). Para o telão a prova termina quando termina p/ a ÚLTIMA sede:
# o fim que vale AQUI é o `contest_end_all` (o mesmo portão da cerimônia e do descongelar) — o relógio
# enviado segue andando até lá e o "sem freeze = nunca congela" usa essa duração. Só p/ o Animeitor: nada
# muda no placar, no aceite de submissão nem no relógio das outras sedes. Prorrogação criada NO MEIO da
# prova vale na hora (o teto é relido; memo de 5 s p/ o alimentador não pagar um jq por segundo).
declare -gA _AN_EA_AT=() _AN_EA_V=()
_an_end_all(){ # <c> -> AN_EA = epoch do fim p/ TODAS as sedes (memo 5 s). Devolve por VARIÁVEL de propósito:
  local c="$1"   # por `$(…)` rodaria em subshell e o memo nunca sobreviveria (um jq por segundo, em silêncio)
  if (( EPOCHSECONDS - ${_AN_EA_AT[$c]:-0} >= 5 )); then
    declare -F contest_end_all >/dev/null 2>&1 || source "$_AN_LIB/contest-gate.sh" 2>/dev/null
    _AN_EA_V[$c]="$(contest_end_all "$c" 2>/dev/null)"; _AN_EA_AT[$c]="$EPOCHSECONDS"
  fi
  AN_EA="${_AN_EA_V[$c]:-0}"
}
_an_times(){ # <c> -> START END FREEZE PEN  (variáveis globais AN_*); AN_END = fim p/ TODAS as sedes
  local ea
  AN_START="$(conf_value "$1" CONTEST_START)"; [[ "$AN_START" =~ ^[0-9]+$ ]] || AN_START=0
  AN_END="$(conf_value "$1" CONTEST_END)";     [[ "$AN_END" =~ ^[0-9]+$ ]] || AN_END=0
  AN_END_CONF="$AN_END"
  if [[ -s "$CONTESTSDIR/$1/time-overrides.json" ]] && (( AN_END > 0 )); then
    _an_end_all "$1"; ea="$AN_EA"; [[ "$ea" =~ ^[0-9]+$ ]] && (( ea > AN_END )) && AN_END="$ea"
  fi
  AN_FREEZE="$(conf_value "$1" FREEZE_TIME)";  [[ "$AN_FREEZE" =~ ^[0-9]+$ ]] || AN_FREEZE=0
  AN_PEN="$(conf_value "$1" PENALTY_MINUTES)"; [[ "$AN_PEN" =~ ^[0-9]+$ ]] || AN_PEN=20
  AN_DUR=$(( AN_END > AN_START ? AN_END - AN_START : 0 ))
}
# an_time_now <c> -> segundos decorridos: NEGATIVO antes do início, teto na duração
an_time_now(){ _an_times "$1"; local t=$(( EPOCHSECONDS - AN_START )); (( t > AN_DUR )) && t=$AN_DUR; printf '%s' "$t"; }

# --- o EVENTO (problemas + roster + tempos) -------------------------------------------------
# an_event_json <c> <saída> [com-relógio 0|1]
an_event_json(){
  local c="$1" out="$2" withtime="${3:-1}" ev fz cfg
  cfg="$(an_cfg "$c")"; _an_times "$c"; ev="$(jq -r .event <<<"$cfg")"
  fz=$AN_DUR; (( AN_FREEZE > AN_START )) && fz=$(( AN_FREEZE - AN_START )); (( fz > AN_DUR )) && fz=$AN_DUR
  bash "$AN_RUNS_SH" "$c" all --teams 2>/dev/null > "$out.teams" || { rm -f "$out.teams"; return 1; }
  [[ -s "$out.teams" ]] || { rm -f "$out.teams"; return 1; }
  bash "$AN_RUNS_SH" "$c" all --probs 2>/dev/null > "$out.probs"
  # MÍDIA (Animeitor 2.1.0, 24/09/2026): `photo_url_format`/`sound_url_format` são do EVENTO, "shared by
  # all contests" — o contest ficou estrito e um template nele é 400 invalid_json (foi o que parou a
  # publicação). Sem `moj_base_url`, null = o padrão do serviço (`photos/{team_login}.webp` na origem dele).
  jq -Rn --arg n "$ev" --argjson fz "$fz" --argjson pen "$(( AN_PEN * 60 ))" --argjson t "$(an_time_now "$c")" \
     --argjson wt "$withtime" --rawfile probs "$out.probs" --arg b "$(jq -r '.moj_base_url // ""' <<<"$cfg")" --arg c "$c" '
    (if $b == "" then null else ($b + "/api/v1/contest/team-photo?contest=" + ($c | @uri) + "&user={team_login}") end) as $ph
    | (if $b == "" then null else ($b + "/api/v1/contest/team-music?contest=" + ($c | @uri) + "&user={team_login}") end) as $so
    | { name: $n, problems: ($probs | split("\n") | map(select(length > 0))),
      teams: [ inputs | split("\t") | select(length >= 1 and .[0] != "") | {login: .[0], escola: (.[1] // ""), nome: (.[2] // .[0])} ],
      score_freeze_time_seconds: $fz, penalty_seconds: $pen, photo_url_format: $ph, sound_url_format: $so }
    + (if $wt == 1 then {time_seconds: $t} else {} end)' "$out.teams" > "$out"
  local rc=$?; rm -f "$out.teams" "$out.probs"; return $rc
}

# --- PROPOSTA de placares e sedes -----------------------------------------------------------
# an_derive <c> <saída> -> {teams_total, contests:[{name, source, n, codes, kind:regex|list, sites:[…]}]}
#   · uma por VISÃO de placar (public = "Geral"; all = "Geral com convidados", só se difere; coortes)
#   · uma por nó de `regions.json` que tem subregiões (um "país"); as sedes são as FOLHAS da árvore
#   · sem sede nenhuma (prova de sede única, sem regions.json): o Geral leva UMA sede "Geral" com os mesmos
#     times — sem sede o Animeitor não gera link de revelação
# `codes`: o regex que JÁ existe (coorte/região) quando ele seleciona, no roster do evento, exatamente
# os times daquele recorte no MOJ; senão a lista exata `^(a|b|…)$`. Coorte e sede também se definem por
# CAMPO da conta (não regex), e o placar do telão TEM de bater com o do MOJ. Regex com look-around ou
# backreference (o serviço é Rust: recusa) cai na lista. Custo: on-demand, ~1 s com 2000 times.
an_derive(){
  local c="$1" out="$2" W v d="$CONTESTSDIR/$1"
  W="$(mktemp -d)" || return 1
  bash "$AN_RUNS_SH" "$c" all --teams 2>/dev/null | cut -f1 > "$W/all.txt"
  [[ -s "$W/all.txt" ]] || { rm -rf "$W"; return 1; }
  : > "$W/views.jsonl"
  while IFS= read -r v; do
    [[ -n "$v" ]] || continue
    bash "$AN_RUNS_SH" "$c" "$v" --teams 2>/dev/null | cut -f1 | jq -Rcn --arg v "$v" '{id:$v, logins:[inputs | select(length > 0)]}' >> "$W/views.jsonl"
  done < <(ch_views "$c" 2>/dev/null)
  [[ -s "$W/views.jsonl" ]] || jq -Rcn '{id:"public", logins:[inputs | select(length > 0)]}' "$W/all.txt" > "$W/views.jsonl"
  # sede de cada conta (campo .team.region) — UMA varredura (find|xargs jq), login pelo nome do dir
  find "$d/users" -mindepth 2 -maxdepth 2 -name account.json -print0 2>/dev/null \
    | xargs -0 -r jq -c '{l: (input_filename | split("/") | .[-2]), r: (.team.region // "")} | select(.r != "")' 2>/dev/null \
    | jq -cs 'map({key: .l, value: .r}) | from_entries' > "$W/reg.json"
  [[ -s "$W/reg.json" ]] || printf '{}' > "$W/reg.json"
  { [[ -s "$d/regions.json" ]] && jq -c 'if type == "array" then . else [] end' "$d/regions.json" 2>/dev/null || printf '[]'; } > "$W/tree.json"
  [[ -s "$W/tree.json" ]] || printf '[]' > "$W/tree.json"
  ch_get "$c" > "$W/coh.json"
  jq -n --rawfile allraw "$W/all.txt" --slurpfile views "$W/views.jsonl" --slurpfile reg "$W/reg.json" \
        --slurpfile tree "$W/tree.json" --slurpfile coh "$W/coh.json" '
    def esc: gsub("(?<c>[.+*?()\\[\\]{}|^$\\\\#/-])"; "\\\(.c)");
    def rustok: (test("\\(\\?[=!<]|\\\\[1-9]") | not);
    def clean: gsub("[/\\n\\r\\t]"; " ") | gsub("^ +| +$"; "") | .[0:64];
    ($allraw | split("\n") | map(select(length > 0))) as $all
    | ($reg[0] // {}) as $R
    | def pick($rx; $set):
        ($set | unique) as $s
        | if ($s | length) == 0 then {codes: [], kind: "list"}
          elif ($rx != "" and ($rx | rustok) and (([ $all[] | select(try test($rx) catch false) ] | unique) == $s)) then {codes: [$rx], kind: "regex"}
          elif ($s == ($all | unique)) then {codes: [".*"], kind: "regex"}
          else {codes: ["^(" + ($s | map(esc) | join("|")) + ")$"], kind: "list"} end;
      def nodeset($n): ([ $all[] | select((($n.regex // "") != "" and (try test($n.regex) catch false)) or (($R[.] // "") == ($n.name // "\u0000"))) ]
                        + [ ($n.subregions // [])[] | nodeset(.)[] ]) | unique;
      def leaves($n): if (($n.subregions // []) | length) == 0 then [$n] else [ $n.subregions[] | leaves(.)[] ] end;
    ([ $views[] | {key: .id, value: .logins} ] | from_entries) as $V
    | ($V.public // $all) as $base
    | ([ $tree[0][] | leaves(.)[] ]) as $LV
    | def sites($nodes; $within):
        [ $nodes[] | . as $n | (nodeset($n) - ((nodeset($n)) - $within)) as $s | select(($s | length) > 0)
          | pick(($n.regex // ""); $s) as $p
          | {name: (($n.name // "") | clean), source: {kind: "region", id: ($n.name // "")}, n: ($s | length), codes: $p.codes, kind: $p.kind} | select(.name != "") ];
    ( [ $views[] | .id as $id | .logins as $s
        | select($id != "all" or (($s | unique) != ($base | unique)))
        | (first($coh[0].cohorts[]? | select(.id == $id)) // null) as $co
        | pick(($co.regex // ""); $s) as $p
        | { name: ((if $id == "public" then "Geral" elif $id == "all" then "Geral com convidados" else ($co.name // $id) end) | clean),
            source: {kind: "view", id: $id}, n: ($s | unique | length), codes: $p.codes, kind: $p.kind,
            # SEDE ÚNICA (sem regions.json/folhas): uma sede "Geral" com os times do placar — o link de revelação
            # do Animeitor é POR SEDE, e sem sede nenhuma não há link (XIV Maratona UnB, 25/09/2026: o .animeitor
            # liberou o reveleitor e a tela mostrou "0 links de revelação").
            sites: (if ($id == "public" or $id == "all") then
                      (if ($LV | length) > 0 then sites($LV; $s)
                       else [ {name: "Geral", source: {kind: "whole", id: $id}, n: ($s | unique | length), codes: $p.codes, kind: $p.kind} ] end)
                    else [] end) } ]
      + [ $tree[0][] | select(((.subregions // []) | length) > 0) | . as $n
          | (nodeset($n) - (nodeset($n) - $base)) as $s | select(($s | length) > 0)
          | pick(($n.regex // ""); $s) as $p
          | { name: (($n.name // "") | clean), source: {kind: "region", id: ($n.name // "")}, n: ($s | length),
              codes: $p.codes, kind: $p.kind, sites: sites([ leaves($n)[] ]; $s) } | select(.name != "") ] ) as $cs
    # nomes únicos (o nome É o identificador no serviço)
    | (reduce $cs[] as $x ({seen: {}, out: []};
         ($x.name) as $nm | ((.seen[$nm] // 0) + 1) as $k
         | .seen[$nm] = $k | .out += [ $x + (if $k > 1 then {name: ($nm + " (" + ($k | tostring) + ")")} else {} end) ])).out as $u
    | {teams_total: ($all | length), contests: $u}' > "$out" 2>"$W/err"
  local rc=$?; [[ $rc -eq 0 ]] || cat "$W/err" >&2
  rm -rf "$W"; return $rc
}

# an_resolved <c> <saída> -> o que VAI ao serviço: {contests:[{name, codes, ouro, prata, bronze, style,
# sites:[{name, codes}]}]} — o contest é ESTRITO desde o Animeitor 2.1.0 (`name, codes, salt, style,
# ouro, prata, bronze`); os templates de mídia moraram aqui até lá e hoje são do evento (an_event_json).
# `codes:null` (automático) é resolvido
# pela proposta de agora — entrou time novo na sede, o placar acompanha na próxima publicação.
an_resolved(){
  local c="$1" out="$2" cfg pf; cfg="$(an_cfg "$c")"; pf="$(mktemp)"
  an_derive "$c" "$pf" || { rm -f "$pf"; return 1; }
  jq -n --argjson cfg "$cfg" --slurpfile p "$pf" --arg c "$c" '
    ($p[0].contests) as $P
    | def auto($src): first($P[] | select(.source == $src)) // null;
      def autosite($csrc; $ssrc): first((auto($csrc) // {sites: []}).sites[] | select(.source == $ssrc)) // null;
    (if $cfg.contests == null then [ $P[] | . + {ouro: 1, prata: 2, bronze: 3, style: null} ]
       else [ $cfg.contests[] | . as $x
              | (if ($x.codes | type) == "array" then $x.codes else ((auto($x.source // {}) // {codes: []}).codes) end) as $codes
              | { name: $x.name, source: ($x.source // {kind: "manual", id: ""}), codes: $codes,
                  ouro: ($x.ouro // 1), prata: ($x.prata // 2), bronze: ($x.bronze // 3), style: ($x.style // null),
                  sites: [ ($x.sites // [])[] | . as $s
                           | { name: $s.name, source: ($s.source // {kind: "manual", id: ""}),
                               codes: (if ($s.codes | type) == "array" then $s.codes
                                       else ((autosite($x.source // {}; $s.source // {}) // {codes: []}).codes) end) } ] } ] end) as $cs
    | {contests: [ $cs[] | {name, codes, ouro, prata, bronze, style: (.style // null),
                            # `region` = a sede do MOJ de onde o site saiu (NÃO vai ao serviço — o an_publish manda
                            # só {name, codes}); é o que casa o link de revelação com o escopo do staff
                            sites: [ (.sites // [])[] | {name, codes, region: (if (.source.kind // "") == "region" then (.source.id // "") else "" end)} ]} ]}' > "$out"
  local rc=$?; rm -f "$pf"; return $rc
}

# --- PUBLICAR a configuração (evento + placares + sedes) ------------------------------------
_an_hash(){ jq -cS . "$1" 2>/dev/null | md5sum | cut -c1-32; }
an_managed(){ local f="$CONTESTSDIR/$1/var/animeitor-managed.json"; { [[ -s "$f" ]] && cat "$f" || printf '{}'; } | jq -c '{event:(.event // ""), event_hash:(.event_hash // ""), contests:(.contests // {})}' 2>/dev/null || printf '{"event":"","event_hash":"","contests":{}}'; }
_an_managed_save(){ local f="$CONTESTSDIR/$1/var/animeitor-managed.json"; mkdir -p "$CONTESTSDIR/$1/var"; printf '%s\n' "$2" > "$f.tmp" && mv -f "$f.tmp" "$f"; }

# --- DE QUEM É O EVENTO (registro do servidor inteiro) -------------------------------------------
# Com a chave do MOJ todos os contests falam com o Animeitor com a MESMA credencial: o serviço não sabe
# mais separar o evento de um contest do de outro. $RUNDIR/animeitor/events.json = {url: {evento: contest}},
# gravado no create (201) e em todo PATCH de evento que o `managed` do contest diz ser dele; apagado no
# reset. É server-side (nenhum cliente o escreve) e vale p/ qualquer chave: um nome de evento de OUTRO
# contest do MOJ é recusado antes de qualquer request (senão o relógio e as runs de dois contests iriam
# p/ o mesmo evento).
an_reg_file(){ printf '%s/animeitor/events.json' "${RUNDIR:-/home/ribas/moj/run}"; }
an_reg_owner(){ # <url> <evento> -> o contest dono ("" = ninguém do MOJ)
  local f; f="$(an_reg_file)"; [[ -s "$f" ]] || return 0
  jq -r --arg u "${1%/}" --arg e "$2" '.[$u][$e] // empty' "$f" 2>/dev/null
}
# an_reg_set <url> <evento> <contest> <claim|release> — sob flock; claim de evento de OUTRO contest = rc 1;
# release só apaga se o dono é este contest
an_reg_set(){
  local u="${1%/}" e="$2" c="$3" op="$4" f d fd tmp cur rc=0
  f="$(an_reg_file)"; d="${f%/*}"; mkdir -p "$d" 2>/dev/null
  exec {fd}>"$d/.events.lock" || return 1
  flock -w 10 "$fd" || { exec {fd}>&-; return 1; }
  cur=""; [[ -s "$f" ]] && cur="$(jq -r --arg u "$u" --arg e "$e" '.[$u][$e] // empty' "$f" 2>/dev/null)"
  tmp="$f.tmp.$BASHPID"          # resolvido ANTES do jq (BASHPID no alvo do redirect expandiria no filho)
  if [[ "$op" == claim ]]; then
    if [[ -n "$cur" && "$cur" != "$c" ]]; then rc=1
    elif [[ -z "$cur" ]]; then
      { [[ -s "$f" ]] && cat "$f" || printf '{}'; } | jq -c --arg u "$u" --arg e "$e" --arg c "$c" '.[$u][$e] = $c' > "$tmp" 2>/dev/null \
        && mv -f "$tmp" "$f" || { rm -f "$tmp"; rc=1; }
    fi
  elif [[ "$cur" == "$c" ]]; then
    jq -c --arg u "$u" --arg e "$e" 'del(.[$u][$e]) | with_entries(select(.value | length > 0))' "$f" > "$tmp" 2>/dev/null \
      && mv -f "$tmp" "$f" || { rm -f "$tmp"; rc=1; }
  fi
  exec {fd}>&-; return $rc
}

# _an_upsert <c> <caminho> <arquivo-completo> <arquivo-do-patch> -> "created|updated HTTP" ou "error HTTP msg"
_an_upsert(){
  local c="$1" path="$2" full="$3" patch="$4" r st
  r="$(an_curl "$c" POST "$path" "$full")"; st="$(an_status "$r")"
  if [[ "$st" == 201 ]]; then printf 'created\t%s\t' "$st"; return 0; fi
  if [[ "$st" == 409 ]]; then
    r="$(an_curl "$c" PATCH "$path" "$patch")"; st="$(an_status "$r")"
    [[ "$st" == 200 ]] && { printf 'updated\t%s\t' "$st"; return 0; }
  fi
  printf 'error\t%s\t%s' "$st" "$(an_err "$r")"; return 1
}

# an_publish <c> <saída> [adopt 0|1] -> {ok, event:{name, action, http, error?}, contests:[…], deleted:[…]}
# Idempotente: o que não mudou (hash) não gera request. Evento que JÁ existe lá e não foi criado por
# este contest só é tocado com adopt=1 (o servidor é compartilhado com outros eventos).
an_publish(){
  local c="$1" out="$2" adopt="${3:-0}" W ev eenc man mev res act st msg h rc=0 base owner csrc code=""
  W="$(mktemp -d)" || return 1
  ev="$(jq -r .event <<<"$(an_cfg "$c")")"; eenc="$(an_enc "$ev")"
  an_name_ok "$ev" || { rm -rf "$W"; jq -cn '{ok:false, error:"nome de evento inválido"}' > "$out"; return 1; }
  base="${AN_URL:-$(jq -r .url <<<"$(an_cfg "$c")")}"; csrc="$(an_cred_source "$c" "$base")"
  # evento de OUTRO contest do MOJ: recusado antes de qualquer request (o registro é o dono de verdade
  # quando a credencial é compartilhada). Não diz QUAL contest (o id pode ser de uma prova secreta).
  owner="$(an_reg_owner "$base" "$ev")"
  if [[ -n "$owner" && "$owner" != "$c" ]]; then
    rm -rf "$W"
    jq -cn --arg n "$ev" '{ok:false, event:{name:$n, action:"error", http:"409", code:"event_taken", error:"este nome de evento já é de outro contest do MOJ: escolha outro nome"}}' > "$out"
    an_fail_note "$c" publish 409 "nome de evento de outro contest"; return 1
  fi
  man="$(an_managed "$c")"; mev="$(jq -r .event <<<"$man")"
  if [[ "$mev" != "$ev" ]]; then
    # evento NOVO (renomeado, ou rodada nova): começa do zero lá — inclusive as runs. Sem zerar o `sent`,
    # as submissões da rodada anterior (que sumiram do history) iriam p/ o evento novo como "removidas" (X).
    man='{"event":"","event_hash":"","contests":{}}'
    rm -f "$CONTESTSDIR/$c/var/animeitor-sent.tsv" "$CONTESTSDIR/$c/var/.animeitor-runs.stamp"
  fi
  an_event_json "$c" "$W/ev.json" 1 || { rm -rf "$W"; jq -cn '{ok:false, error:"sem placar gerado ainda (nenhum time)"}' > "$out"; return 1; }
  an_resolved "$c" "$W/res.json" || { rm -rf "$W"; jq -cn '{ok:false, error:"falha ao derivar placares"}' > "$out"; return 1; }
  res='{"contests":[],"deleted":[]}'

  # 1. evento (o relógio NÃO entra no hash nem no PATCH: quem o conduz é o alimentador)
  jq -c 'del(.time_seconds)' "$W/ev.json" > "$W/ev.patch.json"
  h="$(_an_hash "$W/ev.patch.json")"
  if [[ "$(jq -r .event <<<"$man")" == "$ev" && "$(jq -r .event_hash <<<"$man")" == "$h" ]]; then act=unchanged; st=0; msg=""
  else
    local r; r="$(an_curl "$c" POST "/internal/events/$eenc" "$W/ev.json")"; st="$(an_status "$r")"; msg=""
    if [[ "$st" == 201 ]]; then act=created
    elif [[ "$st" == 409 ]]; then
      if [[ "$(jq -r .event <<<"$man")" != "$ev" && "$adopt" != 1 ]]; then act=error; code=event_exists; msg="o evento já existe no Animeitor e não foi criado por este contest (adote-o para assumir)"; st=409
      elif [[ "$(jq -r .event <<<"$man")" != "$ev" && "$csrc" == moj && "$owner" != "$c" ]]; then
        # a chave do MOJ é de todos os contests: assumir um evento que ninguém do MOJ criou seria mexer, com
        # a credencial do MOJ, no evento de outra pessoa (o regional de exemplo do Emilio, outro sistema…)
        act=error; code=adopt_forbidden; st=409
        msg="com a chave do MOJ só dá para assumir evento criado por este contest; para um evento de fora, grave uma chave própria"
      else
        jq -c 'del(.name)' "$W/ev.patch.json" > "$W/ev.p2.json"
        r="$(an_curl "$c" PATCH "/internal/events/$eenc?keep_runs=true" "$W/ev.p2.json")"; st="$(an_status "$r")"
        if [[ "$st" == 200 ]]; then act=updated; else act=error; msg="$(an_err "$r")"; fi
      fi
    else act=error; msg="$(an_err "$r")"; fi
  fi
  # o evento agora é deste contest: grava no registro (seed dos que nasceram antes dele, via PATCH)
  if [[ "$act" != error ]] && ! an_reg_set "$base" "$ev" "$c" claim; then
    act=error; code=event_taken; st=409; msg="este nome de evento já é de outro contest do MOJ: escolha outro nome"
  fi
  res="$(jq -c --arg n "$ev" --arg a "$act" --arg h "$st" --arg m "$msg" --arg k "$code" '.event = {name:$n, action:$a, http:$h} + (if $m == "" then {} else {error:$m} end) + (if $k == "" then {} else {code:$k} end)' <<<"$res")"
  if [[ "$act" == error ]]; then
    jq -c '. + {ok:false}' <<<"$res" > "$out"; an_fail_note "$c" publish "$st" "$msg"; rm -rf "$W"; return 1
  fi
  man="$(jq -c --arg e "$ev" --arg h "$h" '.event = $e | .event_hash = $h' <<<"$man")"

  # 2. placares e sedes
  local n i cn cenc sn j ns
  n="$(jq '.contests | length' "$W/res.json")"
  for (( i = 0; i < n; i++ )); do
    cn="$(jq -r ".contests[$i].name" "$W/res.json")"; an_name_ok "$cn" || continue; cenc="$(an_enc "$cn")"
    jq -c ".contests[$i] | del(.sites)" "$W/res.json" > "$W/c.json"; jq -c 'del(.name)' "$W/c.json" > "$W/c.patch.json"
    h="$(_an_hash "$W/c.json")"; msg=""
    if [[ "$(jq -r --arg k "$cn" '.contests[$k].hash // ""' <<<"$man")" == "$h" ]]; then act=unchanged; st=0
    else
      IFS=$'\t' read -r act st msg < <(_an_upsert "$c" "/internal/contests/$eenc/$cenc" "$W/c.json" "$W/c.patch.json"; echo)
    fi
    local sres='[]'
    if [[ "$act" != error ]]; then
      man="$(jq -c --arg k "$cn" --arg h "$h" '.contests[$k] = ((.contests[$k] // {sites:{}}) + {hash:$h})' <<<"$man")"
      ns="$(jq ".contests[$i].sites | length" "$W/res.json")"
      for (( j = 0; j < ns; j++ )); do
        sn="$(jq -r ".contests[$i].sites[$j].name" "$W/res.json")"; an_name_ok "$sn" || continue
        jq -c ".contests[$i].sites[$j] | {name, codes}" "$W/res.json" > "$W/s.json"; jq -c 'del(.name)' "$W/s.json" > "$W/s.patch.json"
        local sh sa ss sm; sh="$(_an_hash "$W/s.json")"; sm=""
        if [[ "$(jq -r --arg k "$cn" --arg s "$sn" '.contests[$k].sites[$s] // ""' <<<"$man")" == "$sh" ]]; then sa=unchanged; ss=0
        else IFS=$'\t' read -r sa ss sm < <(_an_upsert "$c" "/internal/sites/$eenc/$cenc/$(an_enc "$sn")" "$W/s.json" "$W/s.patch.json"; echo); fi
        [[ "$sa" == error ]] && rc=1 || man="$(jq -c --arg k "$cn" --arg s "$sn" --arg h "$sh" '.contests[$k].sites[$s] = $h' <<<"$man")"
        sres="$(jq -c --arg n "$sn" --arg a "$sa" --arg m "$sm" '. + [{name:$n, action:$a} + (if $m == "" then {} else {error:$m} end)]' <<<"$sres")"
      done
      # sedes que saíram da configuração: só as que ESTE contest criou
      while IFS= read -r sn; do
        [[ -n "$sn" ]] || continue
        local r2; r2="$(an_curl "$c" DELETE "/internal/sites/$eenc/$cenc/$(an_enc "$sn")")"
        if [[ "$(an_status "$r2")" == 204 || "$(an_status "$r2")" == 404 ]]; then
          man="$(jq -c --arg k "$cn" --arg s "$sn" 'del(.contests[$k].sites[$s])' <<<"$man")"
          res="$(jq -c --arg n "$cn/$sn" '.deleted += [$n]' <<<"$res")"
        else rc=1; fi
      done < <(jq -r --arg k "$cn" --slurpfile r "$W/res.json" '((.contests[$k].sites // {}) | keys) - [ $r[0].contests[] | select(.name == $k) | .sites[].name ] | .[]' <<<"$man")
    else rc=1; fi
    res="$(jq -c --arg n "$cn" --arg a "$act" --arg m "$msg" --argjson s "$sres" '.contests += [{name:$n, action:$a, sites:$s} + (if $m == "" then {} else {error:$m} end)]' <<<"$res")"
  done
  # placares que saíram da configuração
  while IFS= read -r cn; do
    [[ -n "$cn" ]] || continue
    local r3; r3="$(an_curl "$c" DELETE "/internal/contests/$eenc/$(an_enc "$cn")")"
    if [[ "$(an_status "$r3")" == 204 || "$(an_status "$r3")" == 404 ]]; then
      man="$(jq -c --arg k "$cn" 'del(.contests[$k])' <<<"$man")"; res="$(jq -c --arg n "$cn" '.deleted += [$n]' <<<"$res")"
    else rc=1; fi
  done < <(jq -r --slurpfile r "$W/res.json" '(.contests | keys) - [ $r[0].contests[].name ] | .[]' <<<"$man")

  _an_managed_save "$c" "$man"
  jq -c --argjson ok "$([[ $rc -eq 0 ]] && echo true || echo false)" '. + {ok:$ok}' <<<"$res" > "$out"
  if [[ $rc -eq 0 ]]; then an_status_set "$c" '.published_at = $now | del(.last_error)'
  else an_fail_note "$c" publish "" "algum placar ou sede foi recusado (veja o resultado da publicação)"; fi
  rm -rf "$W"; return $rc
}

# --- RUNS: só o delta ------------------------------------------------------------------------
# an_push_runs <c> [full] -> imprime {total, sent, added, updated, ignored, removed, http?, error?}
# `sent.tsv` guarda o que o serviço JÁ tem (id \t login \t letra \t segundos \t flag). Submissão que
# sumiu do MOJ (removida pelo admin) não tem DELETE por run na API: é corrigida p/ `X` (não conta).
# Run de time que o serviço não conhece volta num warning `unknown_team` com o id — essa NÃO entra no
# sent (vai de novo depois que o roster for publicado).
an_push_runs(){
  local c="$1" full="${2:-}" d="$CONTESTSDIR/$1/var" W ev fd r st
  local added=0 updated=0 ignored=0 nsent=0 removed=0 total=0 err="" http=""
  W="$(mktemp -d)" || return 1
  mkdir -p "$d"; exec {fd}>"$d/.animeitor-push.lock" || { rm -rf "$W"; return 1; }
  flock -w 30 "$fd" || { exec {fd}>&-; rm -rf "$W"; return 1; }
  _an_times "$c"; ev="$(an_enc "$(jq -r .event <<<"$(an_cfg "$c")")")"
  bash "$AN_RUNS_SH" "$c" all --runs-ids 2>/dev/null \
    | awk -F'\t' -v S="$AN_START" 'BEGIN{OFS="\t"} { t=$2-S; if (t<0) t=0; print $1, $3, $4, t, $5 }' | sort > "$W/cur.tsv"
  total="$(wc -l < "$W/cur.tsv" | tr -d '[:space:]')"
  [[ "$full" == full ]] && : > "$d/animeitor-sent.tsv"
  { [[ -s "$d/animeitor-sent.tsv" ]] && sort "$d/animeitor-sent.tsv" || :; } > "$W/sent.tsv"
  comm -13 "$W/sent.tsv" "$W/cur.tsv" > "$W/delta.tsv"
  # removidas: id no sent, fora do cur, e ainda não marcadas X
  # (o 1º arquivo entra por getline, não pelo idioma NR==FNR: com ele VAZIO o NR==FNR casa com o 2º
  # arquivo inteiro e o filtro vira "nada passa" em silêncio)
  awk -F'\t' -v F="$W/cur.tsv" 'BEGIN{OFS="\t"; while ((getline l < F) > 0) { split(l, a, "\t"); C[a[1]]=1 } }
      !($1 in C) && $5 != "X" { print $1, $2, $3, $4, "X" }' "$W/sent.tsv" > "$W/gone.tsv"
  removed="$(wc -l < "$W/gone.tsv" | tr -d '[:space:]')"
  cat "$W/gone.tsv" >> "$W/delta.tsv"
  : > "$W/ok.tsv"
  if [[ -s "$W/delta.tsv" ]]; then
    split -l 500 -d -a 4 "$W/delta.tsv" "$W/b."
    local b
    # (find, não glob: os handlers rodam com `set -o noglob` e "$W"/b.* chegaria aqui literal)
    while IFS= read -r b; do
      jq -Rcn '{runs: [ inputs | split("\t") | select(length == 5)
                        | {id: (.[0] | tonumber), team_login: .[1], prob: .[2], time_seconds: (.[3] | tonumber), answer: .[4]} ]}' "$b" > "$W/body.json"
      r="$(AN_TIMEOUT="${AN_TIMEOUT:-25}" an_curl "$c" POST "/internal/events/$ev/runs" "$W/body.json")"; st="$(an_status "$r")"; http="$st"
      if [[ "$st" != 200 ]]; then err="$(an_err "$r")"; break; fi
      an_body "$r" > "$W/resp.json"
      added=$(( added + $(jq -r '.data.added // 0' "$W/resp.json") )); updated=$(( updated + $(jq -r '.data.updated // 0' "$W/resp.json") ))
      jq -r '(.warnings // [])[] | select(.code == "unknown_team") | (.message | capture("run (?<i>[0-9]+) ")? | .i) // empty' "$W/resp.json" | sort -u > "$W/ign.txt"
      ignored=$(( ignored + $(wc -l < "$W/ign.txt") ))
      awk -F'\t' -v F="$W/ign.txt" 'BEGIN{ while ((getline l < F) > 0) I[l]=1 } !($1 in I)' "$b" >> "$W/ok.tsv"
    done < <(find "$W" -maxdepth 1 -name 'b.*' | sort)
    nsent="$(wc -l < "$W/ok.tsv" | tr -d '[:space:]')"
    # sent novo = (sent antigo sem os ids entregues) + entregues
    awk -F'\t' -v F="$W/ok.tsv" 'BEGIN{ while ((getline l < F) > 0) { split(l, a, "\t"); K[a[1]]=1 } } !($1 in K)' "$W/sent.tsv" > "$W/new.tsv"; cat "$W/ok.tsv" >> "$W/new.tsv"
    sort "$W/new.tsv" > "$d/animeitor-sent.tsv.tmp" && mv -f "$d/animeitor-sent.tsv.tmp" "$d/animeitor-sent.tsv"
  fi
  exec {fd}>&-
  if [[ -n "$err" || ( -n "$http" && "$http" != 200 ) ]]; then an_fail_note "$c" runs "$http" "${err:-sem resposta}"; fi
  (( nsent > 0 || removed > 0 || ignored > 0 )) && an_status_set "$c" \
    '.runs = {at:$now, total:$t, last_sent:$s, added:((.runs.added // 0) + $a), updated:((.runs.updated // 0) + $u), ignored:$i}' \
    --argjson t "${total:-0}" --argjson s "$nsent" --argjson a "$added" --argjson u "$updated" --argjson i "$ignored"
  jq -cn --argjson t "${total:-0}" --argjson s "$nsent" --argjson a "$added" --argjson u "$updated" --argjson i "$ignored" \
     --argjson rm "${removed:-0}" --arg h "$http" --arg e "$err" \
     '{total:$t, sent:$s, added:$a, updated:$u, ignored:$i, removed:$rm} + (if $h == "" then {} else {http:$h} end) + (if $e == "" then {} else {error:$e} end)'
  rm -rf "$W"
  [[ -z "$err" && ( -z "$http" || "$http" == 200 ) ]]
}

# --- RELÓGIO ---------------------------------------------------------------------------------
# an_push_time <c> -> HTTP status. Grava var/animeitor.clock ("epoch segundos http") com printf — é
# chamado 1×/s e não pode custar um jq; o GET do painel junta isto ao status.
an_push_time(){
  local c="$1" t r st bf; t="$(an_time_now "$c")"; bf="$(mktemp)"
  printf '{"time_seconds":%d}' "$t" > "$bf"
  r="$(AN_TIMEOUT="${AN_CLOCK_TIMEOUT:-3}" an_curl "$c" PATCH "/internal/events/$(an_enc "$(jq -r .event <<<"$(an_cfg "$c")")")/time" "$bf")"; st="$(an_status "$r")"
  rm -f "$bf"
  printf '%s %s %s\n' "$EPOCHSECONDS" "$t" "${st:-000}" > "$CONTESTSDIR/$c/var/animeitor.clock" 2>/dev/null
  printf '%s' "${st:-000}"; [[ "$st" == 200 ]]
}

# --- LINKS (os de revelação são CREDENCIAL: buscados ao vivo, nunca gravados) ------------------
# an_links <c> -> {public:[{contest, url}], revelation:[{contest, site, url}]}
an_links(){
  local c="$1" cfg ev r st; cfg="$(an_cfg "$c")"; ev="$(jq -r .event <<<"$cfg")"
  r="$(an_curl "$c" GET "/internal/events/$(an_enc "$ev")/revelation_urls")"; st="$(an_status "$r")"
  [[ "$st" == 200 ]] || { jq -cn --arg h "$st" '{public:[], revelation:[], http:$h}'; return 1; }
  an_body "$r" | jq -c --arg ev "$ev" --arg api "$(jq -r .url <<<"$cfg")" --argjson man "$(an_managed "$c")" '
    (.data // []) as $rv
    | (first($rv[].url | capture("^(?<o>https?://[^/]+)").o) // $api) as $origin
    | { revelation: $rv,
        public: [ ($man.contests | keys[]) | {contest: ., url: ($origin + "/animeitor/" + ($ev | @uri) + "/" + (. | @uri) + "/")} ] }'
}

# --- CONFERÊNCIA: o Animeitor tem TODAS as runs? -------------------------------------------------
# an_curl_site <c> <caminho /api/…> <chave da sede> -> corpo + "HTTP <code>". GET na API PÚBLICA com
# `Authorization: Bearer <chave>`; a chave vai por `-K <(printf …)` como a credencial (nunca argv/log).
an_curl_site(){
  local c="$1" path="$2" key="$3" base tmo="${AN_TIMEOUT:-20}"
  base="${AN_URL:-}"; [[ -n "$base" ]] || base="$(jq -r .url <<<"$(an_cfg "$c")")"
  an_url_ok "$base" || { printf '\nHTTP 000'; return 1; }
  [[ "$key" =~ ^[A-Za-z0-9._~+/=-]{8,512}$ ]] || { printf '\nHTTP 000'; return 1; }
  [[ "$tmo" =~ ^[0-9]+$ ]] || tmo=20
  curl -s -m "$tmo" -w $'\nHTTP %{http_code}' -K <(printf 'header = "Authorization: Bearer %s"\nurl = "%s%s"\n' "$key" "$base" "$path")
}
an_verify_file(){ printf '%s/%s/var/animeitor-verify.json' "$CONTESTSDIR" "$1"; }
# an_verify_summary <c> -> o resumo SEM ids (o que .cstaff/.staff e a tela ao vivo leem); {} se nunca conferiu
an_verify_summary(){
  local f; f="$(an_verify_file "$1")"
  { [[ -s "$f" ]] && cat "$f" || printf '{}'; } | jq -c 'del(.sample)' 2>/dev/null || printf '{}'
}

# _an_sent_fix <c> <W> — sob o MESMO lock do an_push_runs. Arquivos em <W>:
#   fix.drop  ids VIVOS que faltam/divergem lá ⇒ saem do sent (o próximo push os manda de novo)
#   fix.rex   ids REMOVIDOS no MOJ (X no sent) que lá não estão como X ⇒ flag vira "?" (o push manda o X de novo)
#   fix.add   runs que SÓ o Animeitor tem (id que o MOJ não conhece, resposta ≠ X) ⇒ entram no sent com
#             a resposta de lá: sem estar no MOJ, o push as corrige p/ X (não contam)
_an_sent_fix(){
  local c="$1" W="$2" d="$CONTESTSDIR/$1/var" fd
  mkdir -p "$d"; exec {fd}>"$d/.animeitor-push.lock" || return 1
  flock -w 30 "$fd" || { exec {fd}>&-; return 1; }
  { [[ -s "$d/animeitor-sent.tsv" ]] && cat "$d/animeitor-sent.tsv" || :; } \
    | awk -F'\t' -v D="$W/fix.drop" -v R="$W/fix.rex" 'BEGIN{OFS="\t"; while ((getline l < D) > 0) K[l]=1; while ((getline l < R) > 0) X[l]=1 }
        ($1 in K) { next } ($1 in X) { $5 = "?" } { print }' > "$W/sent.new"
  [[ -s "$W/fix.add" ]] && cat "$W/fix.add" >> "$W/sent.new"
  sort -u "$W/sent.new" > "$d/animeitor-sent.tsv.tmp" && mv -f "$d/animeitor-sent.tsv.tmp" "$d/animeitor-sent.tsv"
  rm -f "$d/.animeitor-runs.stamp"          # o alimentador manda o delta na passada seguinte
  exec {fd}>&-
}

# an_verify <c> <saída> [repair 0|1] — pergunta ao Animeitor, SEDE a SEDE (runs_secret com a chave de cada
# uma, buscada ao vivo e nunca gravada), quais runs ele tem, e compara com o MOJ: id, time, problema, tempo e
# resposta REAL. As runs do MOJ são as vivas + as removidas (que lá devem estar como X). O filtro de cada sede
# é o regex dela (o mesmo que o serviço aplica ao `team_login`); sedes com o MESMO regex em placares
# diferentes dão a mesma resposta ⇒ uma consulta só. Grava var/animeitor-verify.json:
#   {at, event, state: ok|diverge|not_started|no_sites|error, ok, over, pending, final, final_at, runs,
#    checked, uncovered, missing, wrong, extra, repair, sites:[{contest, site, http, expected, got,
#    missing, wrong, extra}], sample:{missing:[ids], wrong:[ids], extra:[ids]}, error?}
# `final` = tudo bate, a prova acabou p/ TODAS as sedes e nada está pendente (`?`) — é o "validado".
# Com repair=1 o que falta/diverge é marcado p/ reenvio (_an_sent_fix); quem chama decide se já manda.
an_verify(){
  local c="$1" out="$2" repair="${3:-1}" d="$CONTESTSDIR/$1/var" W cfg ev eenc lk r st i=0 cn sn key
  W="$(mktemp -d)" || return 1
  cfg="$(an_cfg "$c")"; ev="$(jq -r .event <<<"$cfg")"; eenc="$(an_enc "$ev")"
  _an_times "$c"
  local over=false; (( AN_END > 0 && EPOCHSECONDS >= AN_END )) && over=true
  _an_vdone(){ # <state> [erro] — monta o JSON final a partir dos arquivos em $W
    local state="$1" err="${2:-}" prev pf
    touch "$W/sites.jsonl" "$W/miss.ids" "$W/wrong.ids" "$W/extra.ids" "$W/covered.ids"
    prev="$(an_verify_file "$c")"; pf='{}'; [[ -s "$prev" ]] && pf="$(jq -c '{final_at: (.final_at // 0), final}' "$prev" 2>/dev/null || printf '{}')"
    jq -n --arg st "$state" --arg err "$err" --arg ev "$ev" --argjson now "$EPOCHSECONDS" --argjson over "$over" \
       --argjson runs "$(wc -l < "$W/exp.tsv" | tr -d '[:space:]')" \
       --argjson pend "$(awk -F'\t' '$5 == "?"' "$W/cur.tsv" 2>/dev/null | wc -l | tr -d '[:space:]')" \
       --argjson checked "$(sort -u "$W/covered.ids" | wc -l | tr -d '[:space:]')" \
       --argjson repair "$(cat "$W/fix.n" 2>/dev/null || echo 0)" \
       --argjson prev "$pf" --slurpfile sites "$W/sites.jsonl" \
       --rawfile mi "$W/miss.ids" --rawfile wr "$W/wrong.ids" --rawfile ex "$W/extra.ids" '
      def ids($s): $s | split("\n") | map(select(length > 0)) | unique;
      (ids($mi)) as $M | (ids($wr)) as $Wr | (ids($ex)) as $E
      | ($st == "ok" and $over and $pend == 0) as $final
      | { at: $now, event: $ev, state: $st, ok: ($st == "ok"), over: $over, pending: $pend, final: $final,
          final_at: (if $final then (if ($prev.final == true and ($prev.final_at // 0) > 0) then $prev.final_at else $now end) else 0 end),
          runs: $runs, checked: $checked, uncovered: (if $st == "ok" or $st == "diverge" then ([$runs - $checked, 0] | max) else 0 end),
          missing: ($M | length), wrong: ($Wr | length), extra: ($E | length), repair: $repair,
          sites: $sites, sample: {missing: ($M | .[0:20] | map(tonumber? // .)), wrong: ($Wr | .[0:20] | map(tonumber? // .)), extra: ($E | .[0:20] | map(tonumber? // .))} }
        + (if $err == "" then {} else {error: $err} end)' > "$W/out.json" 2>"$W/jq.err" \
      || jq -cn --arg e "$(head -c 200 "$W/jq.err")" --argjson now "$EPOCHSECONDS" '{at:$now, state:"error", ok:false, final:false, error:("montagem: " + $e)}' > "$W/out.json"
    cp "$W/out.json" "$out"
    mkdir -p "$d"; local vf; vf="$(an_verify_file "$c")"
    cp "$W/out.json" "$vf.tmp.$BASHPID" 2>/dev/null && mv -f "$vf.tmp.$BASHPID" "$vf"
    rm -rf "$W"
    [[ "$state" == ok ]]
  }
  : > "$W/cur.tsv"; : > "$W/exp.tsv"
  [[ "$(jq -r .event <<<"$(an_managed "$c")")" == "$ev" ]] || { _an_vdone error "o evento ainda não foi publicado"; return 1; }
  # 1. o que o MOJ tem: vivas (id login letra segundos resposta) + removidas (X no sent, fora das vivas)
  bash "$AN_RUNS_SH" "$c" all --runs-ids 2>/dev/null \
    | awk -F'\t' -v S="$AN_START" 'BEGIN{OFS="\t"} { t=$2-S; if (t<0) t=0; print $1, $3, $4, t, $5 }' | sort > "$W/cur.tsv"
  { [[ -s "$d/animeitor-sent.tsv" ]] && sort "$d/animeitor-sent.tsv" || :; } > "$W/sent.tsv"
  awk -F'\t' -v F="$W/cur.tsv" 'BEGIN{OFS="\t"; while ((getline l < F) > 0) { split(l, a, "\t"); C[a[1]]=1 } }
      !($1 in C) && $5 == "X"' "$W/sent.tsv" > "$W/gone.tsv"
  sort "$W/cur.tsv" "$W/gone.tsv" > "$W/exp.tsv"
  cut -f2 "$W/exp.tsv" | sort -u > "$W/logins.txt"
  # 2. as sedes: o regex de cada uma (o que foi publicado) e a chave (do link de revelação, ao vivo)
  an_resolved "$c" "$W/res.json" || { _an_vdone error "falha ao derivar placares e sedes"; return 1; }
  lk="$(an_links "$c")" || { _an_vdone error "o Animeitor não entregou os links de revelação (HTTP $(jq -r '.http // "000"' <<<"$lk" 2>/dev/null))"; return 1; }
  jq -r --slurpfile r "$W/res.json" '
      ($r[0].contests) as $R
      | (.revelation // [])[]
      | . as $x
      | (first($R[] | select(.name == $x.contest) | .sites[] | select(.name == $x.site) | .codes) // null) as $codes
      | select($codes != null)
      # base64 em cada campo: o @tsv ESCAPA a barra invertida (`\-` do login escapado virava `\\-` e o regex
      # da sede não casava ninguém — "todas as 0 submissões" com sede por campo da conta)
      | [ ($x.contest | @base64), ($x.site | @base64), ((($x.url | capture("[?&]secret=(?<k>[^&#]+)") | .k) // "") | @base64), ($codes | tojson | @base64) ] | @tsv' <<<"$lk" > "$W/links.tsv" 2>/dev/null
  [[ -s "$W/links.tsv" ]] || { _an_vdone no_sites; return 1; }
  # 3. sede a sede
  declare -A seen=()
  : > "$W/fix.drop"; : > "$W/fix.rex"; : > "$W/fix.add"
  while IFS=$'\t' read -r cn sn key codes; do
    cn="$(base64 -d <<<"$cn")"; sn="$(base64 -d <<<"$sn")"; key="$(base64 -d <<<"$key")"; codes="$(base64 -d <<<"$codes")"
    [[ -n "$key" ]] || continue
    [[ "$key" == *%* ]] && { key="${key//%/\\x}"; printf -v key '%b' "$key"; }
    if [[ -n "${seen[$codes]:-}" ]]; then        # mesmo regex já conferido em outro placar: mesma resposta
      jq -c --arg c "$cn" --arg s "$sn" '. + {contest:$c, site:$s, same_as:.site}' <<<"${seen[$codes]}" >> "$W/sites.jsonl"; continue
    fi
    (( i++ ))
    # quem é da sede: o regex dela sobre os logins (PCRE ≈ o dialeto Rust do serviço p/ o que o MOJ gera)
    jq -r '"(?:" + join(")|(?:") + ")"' <<<"$codes" > "$W/rx"
    grep -P -f "$W/rx" "$W/logins.txt" > "$W/mem.$i" 2>/dev/null || { [[ $? -eq 1 ]] || grep -E -f "$W/rx" "$W/logins.txt" > "$W/mem.$i" 2>/dev/null; }
    awk -F'\t' -v F="$W/mem.$i" 'BEGIN{ while ((getline l < F) > 0) M[l]=1 } ($2 in M)' "$W/exp.tsv" > "$W/exp.$i"
    cut -f1 "$W/exp.$i" >> "$W/covered.ids"
    r="$(an_curl_site "$c" "/api/events/$eenc/contests/$(an_enc "$cn")/runs_secret" "$key")"; st="$(an_status "$r")"
    if [[ "$st" == 403 && "$(an_body "$r" | jq -r '(.errors // [])[0].code // ""' 2>/dev/null)" == not_started ]]; then
      _an_vdone not_started; return 1
    fi
    if [[ "$st" != 200 ]]; then
      local line; line="$(jq -cn --arg c "$cn" --arg s "$sn" --arg h "${st:-000}" --arg e "$(an_err "$r")" --argjson n "$(wc -l < "$W/exp.$i")" \
        '{contest:$c, site:$s, http:$h, expected:$n, got:null, missing:null, wrong:null, extra:null, error:$e}')"
      printf '%s\n' "$line" >> "$W/sites.jsonl"; seen[$codes]="$line"; printf 'x\n' >> "$W/fail.flag"; continue
    fi
    an_body "$r" | jq -r '(.data.runs // [])[] | [(.id | tostring), .team_login, .prob, (.time_seconds | tostring), .answer] | @tsv' 2>/dev/null | sort > "$W/got.$i"
    # faltando (no MOJ, não lá) · divergente (mesmo id, outro conteúdo) · sobrando (lá, não no MOJ desta sede)
    awk -F'\t' -v G="$W/got.$i" -v MI="$W/miss.$i" -v WR="$W/wrong.$i" -v EX="$W/extra.$i" '
      BEGIN{ while ((getline l < G) > 0) { split(l, a, "\t"); GL[a[1]] = l } }
      { if (!($1 in GL)) print $1 > MI; else { if (GL[$1] != $0) print $1 > WR; delete GL[$1] } }
      END{ for (k in GL) print GL[k] > EX; close(MI); close(WR); close(EX) }' "$W/exp.$i"
    touch "$W/miss.$i" "$W/wrong.$i" "$W/extra.$i"
    cat "$W/miss.$i" >> "$W/miss.ids"; cat "$W/wrong.$i" >> "$W/wrong.ids"
    # sobrando: id que o MOJ NÃO conhece (em lugar nenhum) com resposta ≠ X conta (o telão mostra uma run que
    # não existe); id conhecido é só outro recorte (ex.: time renomeado — a correção do "faltando" resolve)
    awk -F'\t' -v F="$W/exp.tsv" 'BEGIN{ while ((getline l < F) > 0) { split(l, a, "\t"); K[a[1]]=1 } } !($1 in K) && $5 != "X"' "$W/extra.$i" > "$W/xu.$i"
    cut -f1 "$W/xu.$i" >> "$W/extra.ids"; cat "$W/xu.$i" >> "$W/fix.add"
    local line; line="$(jq -cn --arg c "$cn" --arg s "$sn" --argjson n "$(wc -l < "$W/exp.$i")" --argjson g "$(wc -l < "$W/got.$i")" \
      --argjson m "$(wc -l < "$W/miss.$i")" --argjson w "$(wc -l < "$W/wrong.$i")" --argjson x "$(wc -l < "$W/xu.$i")" \
      '{contest:$c, site:$s, http:"200", expected:$n, got:$g, missing:$m, wrong:$w, extra:$x}')"
    printf '%s\n' "$line" >> "$W/sites.jsonl"; seen[$codes]="$line"
  done < "$W/links.tsv"
  # 4. reparo: marca p/ reenvio (vivas saem do sent; removidas voltam a "?" p/ o X ir de novo; as só-de-lá entram)
  sort -u "$W/miss.ids" "$W/wrong.ids" > "$W/bad.ids"
  awk -F'\t' -v F="$W/bad.ids" 'BEGIN{ while ((getline l < F) > 0) B[l]=1 } ($1 in B) { print $1 }' "$W/cur.tsv" > "$W/fix.drop"
  awk -F'\t' -v F="$W/bad.ids" 'BEGIN{ while ((getline l < F) > 0) B[l]=1 } ($1 in B) { print $1 }' "$W/gone.tsv" > "$W/fix.rex"
  sort -u -o "$W/fix.add" "$W/fix.add"
  local nfix; nfix=$(( $(wc -l < "$W/fix.drop") + $(wc -l < "$W/fix.rex") + $(wc -l < "$W/fix.add") ))
  if (( repair == 1 && nfix > 0 )); then _an_sent_fix "$c" "$W" && printf '%s' "$nfix" > "$W/fix.n"; fi
  if [[ -s "$W/fail.flag" ]]; then _an_vdone error "alguma sede não respondeu"; return 1; fi
  # nenhuma sede cobre time nenhum (sede sem time, regex que não casa): "ok" com 0 conferidas enganaria
  if [[ ! -s "$W/covered.ids" && -s "$W/exp.tsv" ]]; then _an_vdone no_sites "nenhuma sede publicada cobre os times"; return 1; fi
  if [[ -s "$W/bad.ids" || -s "$W/extra.ids" ]]; then _an_vdone diverge; return 1; fi
  _an_vdone ok
}

# --- REVELEITOR nas sedes: o .animeitor LIBERA e o .cstaff/.staff recebe os links DA SEDE DELE ---------
# O link de revelação mostra as respostas reais depois do freeze: é credencial. Fica trancado até o
# operador do telão liberar (um interruptor só, p/ todas as sedes) e pode ser recolhido. O estado mora
# no animeitor.json (`reveal{released, at, by}`); o marcador var/animeitor-reveal.released é só o atalho
# SEM fork p/ o navbuttons decidir se mostra o botão.
an_reveal_released(){ [[ -e "$CONTESTSDIR/$1/var/animeitor-reveal.released" ]]; }
an_reveal_set(){ # <c> <on|off> <quem>
  local c="$1" on="$2" by="${3:-}" cfg m="$CONTESTSDIR/$1/var/animeitor-reveal.released"
  cfg="$(an_cfg "$c")"; mkdir -p "$CONTESTSDIR/$c/var"
  if [[ "$on" == on ]]; then
    an_cfg_save "$c" "$(jq -c --argjson t "$EPOCHSECONDS" --arg by "$by" '.reveal = {released:true, at:$t, by:$by}' <<<"$cfg")" && : > "$m"
  else
    an_cfg_save "$c" "$(jq -c --argjson t "$EPOCHSECONDS" --arg by "$by" '.reveal = {released:false, at:$t, by:$by}' <<<"$cfg")"; rm -f "$m"
  fi
}
# an_reveal_links <c> <arquivo com as sedes do staff, 1/linha> -> [{contest, site, url}] — TODOS os placares
# em que a sede aparece (o Geral e o do país). O casamento é pela REGIÃO de origem do site (o operador
# pode ter renomeado a sede no telão); site manual casa pelo nome. Comparação sem caixa, como o staff-filters.
an_reveal_links(){
  local c="$1" regf="$2" rf lk; rf="$(mktemp)"
  an_resolved "$c" "$rf" || { rm -f "$rf"; printf '[]'; return 1; }
  lk="$(an_links "$c")" || { rm -f "$rf"; printf '[]'; return 1; }
  jq -c --slurpfile r "$rf" --rawfile regs "$regf" '
    ($regs | split("\n") | map(gsub("^ +| +$"; "") | ascii_downcase | select(length > 0))) as $mine
    | ([ $r[0].contests[] | .name as $cn | .sites[]
         | select(((if (.region // "") != "" then .region else .name end) | ascii_downcase) as $k | $mine | index($k))
         | {contest: $cn, site: .name} ]) as $ok
    | [ (.revelation // [])[] | . as $x | select($ok | index({contest: $x.contest, site: $x.site})) ]' <<<"$lk"
  local rc=$?; rm -f "$rf"; return $rc
}
