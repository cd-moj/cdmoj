# lib/problem-issues.sh — ISSUES POR PROBLEMA (2026-09-24, pedido da banca via Arthur Botelho: "um sistema
# de issues para os problemas, que devem ser resolvidas para o problema ficar ok").
#
# Loja: contests/treino/var/problem-issues/<org>/<prob>.json — um arquivo por problema:
#   {next, issues:[{n, title, body, state:open|closed, by, at, updated_at, closed_by, closed_at,
#                   comments:[{by, at, body}]}]}
# Dado DURÁVEL (junto de orgs.json/collections.json), FORA do pacote de propósito: dentro do repo git
# do problema a issue mudaria o `pkg_rev` (409 stale_rev à toa p/ quem está editando), sumiria no
# `upload` (rsync --delete) e iria ao juiz no tar do pacote.
# Sumário p/ o Painel: contests/treino/var/problem-issues-summary.json {id: nº de abertas} (upsert por
# evento, rebuild a frio). Acesso: quem EDITA o problema (require_problem_edit, no handler).
# O `by` é texto histórico (como o autor de um commit no 🕘 Histórico): não concede acesso, então não
# entra na cascata de rename de conta.
# Texto do usuário (título/corpo) só anda por ARQUIVO/stdin no jq, nunca por argv.
: "${CONTESTSDIR:=/home/ribas/moj/contests}"
PI_DIR="$CONTESTSDIR/treino/var/problem-issues"
PI_SUMMARY="$CONTESTSDIR/treino/var/problem-issues-summary.json"
PI_TITLE_MAX=200; PI_BODY_MAX=20000; PI_COMMENTS_MAX=200; PI_ISSUES_MAX=500

pi_file(){ local id="$1"; printf '%s/%s/%s.json' "$PI_DIR" "${id%%#*}" "${id#*#}"; }
# pi_get <id> -> o arquivo do problema (ou o vazio). Sempre JSON válido.
pi_get(){ local f; f="$(pi_file "$1")"
  if [[ -s "$f" ]] && jq -e 'type == "object"' "$f" >/dev/null 2>&1; then cat "$f"; else echo '{"next":1,"issues":[]}'; fi; }

# pi_apply <id> <login> <body-file> -> aplica a ação do corpo {action, n?, title?, body?} sob flock e
# escreve o resultado. stdout: {issue, open}. rc: 0 ok · 2 entrada inválida · 3 issue inexistente ·
# 4 estado (já aberta/fechada) · 5 teto · 1 falha de escrita. A mensagem de erro vai no stdout.
pi_apply(){
  local id="$1" login="$2" bf="$3" f d out t rc
  f="$(pi_file "$id")"; d="${f%/*}"; mkdir -p "$d" 2>/dev/null || return 1
  out="$(mktemp)"
  (
    flock 9
    cur="$(mktemp)"; pi_get "$id" > "$cur"
    # UM jq: valida, aplica e devolve {ok, err?, code?, doc?, issue?}. Texto do corpo vem do ARQUIVO.
    jq -c --slurpfile cur "$cur" --arg me "$login" --argjson now "$EPOCHSECONDS" \
       --argjson tmax "$PI_TITLE_MAX" --argjson bmax "$PI_BODY_MAX" \
       --argjson cmax "$PI_COMMENTS_MAX" --argjson imax "$PI_ISSUES_MAX" '
      def err($c; $m): {ok: false, code: $c, err: $m};
      def trim: sub("^\\s+"; "") | sub("\\s+$"; "");
      ($cur[0]) as $doc
      | (.action // "" | tostring) as $a
      | ((.title // "") | tostring | trim) as $title
      | ((.body // "") | tostring | sub("\\s+$"; "")) as $body
      | (.n | tonumber? // null) as $n
      | ([ $doc.issues[] | select(.n == $n) ] | .[0]) as $iss
      | if ($a | IN("open", "comment", "close", "reopen") | not) then err("bad_action"; "ação desconhecida (open, comment, close, reopen)")
        elif ($body | length) > $bmax then err("body_too_long"; "texto longo demais (máx. \($bmax) caracteres)")
        elif $a == "open" then
          (if ($title | length) == 0 then err("title_missing"; "falta o título")
           elif ($title | length) > $tmax then err("title_too_long"; "título longo demais (máx. \($tmax) caracteres)")
           elif ($doc.issues | length) >= $imax then err("too_many"; "o problema já tem \($imax) issues")
           else ({n: ($doc.next // 1), title: $title, body: $body, state: "open", by: $me, at: $now,
                  updated_at: $now, closed_by: null, closed_at: null, comments: []}) as $new
                | {ok: true, issue: $new,
                   doc: ($doc | .next = (($doc.next // 1) + 1) | .issues += [$new])} end)
        elif $iss == null then err("issue_notfound"; "issue #\($n // "?") não existe")
        elif $a == "comment" and ($body | length) == 0 then err("body_missing"; "falta o texto do comentário")
        elif ($body | length) > 0 and ($iss.comments | length) >= $cmax then err("too_many"; "a issue já tem \($cmax) comentários")
        elif $a == "close" and $iss.state == "closed" then err("issue_state"; "a issue #\($n) já está fechada")
        elif $a == "reopen" and $iss.state == "open" then err("issue_state"; "a issue #\($n) já está aberta")
        else
          ($iss
           | (if ($body | length) > 0 then .comments += [{by: $me, at: $now, body: $body}] else . end)
           | (if $a == "close" then .state = "closed" | .closed_by = $me | .closed_at = $now
              elif $a == "reopen" then .state = "open" | .closed_by = null | .closed_at = null else . end)
           | .updated_at = $now) as $upd
          | {ok: true, issue: $upd, doc: ($doc | .issues |= map(if .n == $n then $upd else . end))}
        end' "$bf" > "$out.r" 2>/dev/null
    rm -f "$cur"
    if ! jq -e '.ok == true' "$out.r" >/dev/null 2>&1; then
      jq -r '.err // "entrada inválida"' "$out.r" 2>/dev/null > "$out"
      case "$(jq -r '.code // ""' "$out.r" 2>/dev/null)" in
        issue_notfound) exit 3;; issue_state) exit 4;; too_many) exit 5;; *) exit 2;;
      esac
    fi
    t="$f.tmp.${BASHPID}"   # nome resolvido ANTES do redirect do jq (lição do ${BASHPID} no filho)
    jq -c '.doc' "$out.r" > "$t" 2>/dev/null && [[ -s "$t" ]] && mv -f "$t" "$f" || { rm -f "$t"; exit 1; }
    jq -c --slurpfile d "$f" '{issue, open: ([$d[0].issues[] | select(.state == "open")] | length)}' "$out.r" > "$out"
  ) 9>>"$f.lock"
  rc=$?
  cat "$out"; rm -f "$out" "$out.r"
  (( rc == 0 )) && pi_summary_upsert "$id"
  return $rc
}

# ---- sumário do Painel {id: abertas} ----------------------------------------------------------------
pi_open_count(){ local f; f="$(pi_file "$1")"; [[ -s "$f" ]] || { echo 0; return; }
  jq '[.issues[]? | select(.state == "open")] | length' "$f" 2>/dev/null || echo 0; }
_pi_summary_rebuild(){   # sob o flock do chamador; varre a loja inteira (só a frio)
  local t="$PI_SUMMARY.tmp.${BASHPID}"
  find "$PI_DIR" -mindepth 2 -maxdepth 2 -name '*.json' -type f 2>/dev/null \
    | while IFS= read -r f; do
        r="${f#"$PI_DIR"/}"; r="${r%.json}"
        printf '%s\t%s\n' "${r%%/*}#${r#*/}" "$(jq '[.issues[]? | select(.state == "open")] | length' "$f" 2>/dev/null || echo 0)"
      done \
    | jq -Rnc '[inputs | split("\t") | select(length == 2) | {key: .[0], value: (.[1] | tonumber? // 0)}]
               | map(select(.value > 0)) | from_entries' > "$t" 2>/dev/null
  [[ -s "$t" ]] || echo '{}' > "$t"
  mv -f "$t" "$PI_SUMMARY"
}
pi_summary_ensure(){
  [[ -s "$PI_SUMMARY" ]] && return 0
  mkdir -p "${PI_SUMMARY%/*}" 2>/dev/null
  ( flock 9; [[ -s "$PI_SUMMARY" ]] || _pi_summary_rebuild ) 9>>"$PI_SUMMARY.lock"
}
pi_summary_upsert(){
  local id="$1" n; n="$(pi_open_count "$id")"; n="${n//[^0-9]/}"; n="${n:-0}"
  mkdir -p "${PI_SUMMARY%/*}" 2>/dev/null
  ( flock 9
    if [[ ! -s "$PI_SUMMARY" ]]; then _pi_summary_rebuild; exit 0; fi
    t="$PI_SUMMARY.tmp.${BASHPID}"
    jq -c --arg id "$id" --argjson n "$n" 'if $n > 0 then .[$id] = $n else del(.[$id]) end' "$PI_SUMMARY" > "$t" 2>/dev/null \
      && [[ -s "$t" ]] && mv -f "$t" "$PI_SUMMARY" || rm -f "$t"
  ) 9>>"$PI_SUMMARY.lock"
}
# pi_drop <id> — o problema foi apagado: as issues vão junto
pi_drop(){ local f; f="$(pi_file "$1")"; [[ -e "$f" ]] || return 0
  rm -f "$f" "$f.lock"; pi_summary_upsert "$1"; }
# pi_move <old> <new> — /problems/move: as issues seguem o problema para o id novo
pi_move(){ local a b; a="$(pi_file "$1")"; b="$(pi_file "$2")"; [[ -s "$a" ]] || return 0
  mkdir -p "${b%/*}" 2>/dev/null && mv -f "$a" "$b" && rm -f "$a.lock"
  pi_summary_upsert "$1"; pi_summary_upsert "$2"; }
