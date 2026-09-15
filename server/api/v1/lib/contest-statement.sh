# lib/contest-statement.sh — IDIOMAS DO ENUNCIADO NO CONTEST (2026-09-15).
#
# O pacote pode trazer o enunciado em pt/en/es (mojtools/statement-langs.sh; o índice do treino
# serve `statement_langs` + `statements{<lang>:{title,html_b64}}`). No CONTEST quem decide o que o
# competidor vê é o admin/juiz-chefe: conf **`STATEMENT_LANGS`**. Dois modos (pedido do Ribas,
# 15/09/2026 — "o time não consegue escolher o idioma" num contest que ninguém configurou):
#   - **AUTOMÁTICO** (conf AUSENTE ou `auto`, o DEFAULT): a prova oferece TODO idioma que cada
#     problema tem (arquivo no contest ou tradução no banco). Zero configuração ⇒ a sanfona já
#     mostra os chips onde há tradução.
#   - **LISTA** (`STATEMENT_LANGS=pt\ en`): só os idiomas marcados; `pt` sozinho = prova só em PT.
# Os arquivos ficam em `enunciados/<skey>.html` (PT, como sempre) e `enunciados/<skey>.<lang>.html|pdf`.
# Idioma pedido sem arquivo cai no PT (nunca 404 por falta de tradução — só por falta de direito).
#
#   cs_mode <contest>             -> "auto" | "list"
#   cs_norm <raw>                 -> normaliza uma lista ("pt en", "en,es") p/ a allowlist; vazio ou
#                                    `auto` = TODOS (stmt_langs_all); lista sem idioma válido = pt
#   cs_langs <contest>            -> idiomas OFERECIDOS (conf STATEMENT_LANGS); automático = todos
#   cs_default <contest> <langs>  -> idioma da sanfona: LOCALE do contest se ∈ langs, senão o 1º
#   cs_file <c> <skey> <lang> <fmt> -> caminho do arquivo do idioma (→ PT); rc 1 se nenhum
#   cs_bank_json <skey>           -> json servível do banco (público › privado); rc 1 se nenhum
#   cs_bank_write <bankjson> <tdir> <skey> [all|langs] -> grava enunciados/<skey>[.<lang>].html
#   cs_bank_langs <bankjson>      -> idiomas com html no json ("pt en")
#   cs_bank_title <bankjson> <lang> -> title do idioma ("" se não há)
declare -F stmt_langs_all >/dev/null || source "${MOJTOOLS_DIR:-/home/ribas/moj/mojtools}/statement-langs.sh"

_cs_clean(){ local raw="${1:-}"; raw="${raw//\\/}"; raw="${raw//,/ }"; raw="${raw//\'/}"; raw="${raw//\"/}"; printf '%s' "${raw,,}"; }
cs_mode(){
  local raw; raw="$(_cs_clean "$(conf_value "$1" STATEMENT_LANGS)")"
  if [[ -z "${raw// /}" || " $raw " == *" auto "* ]]; then printf auto; else printf list; fi
}
cs_norm(){
  local raw l out=""; raw="$(_cs_clean "${1:-}")"
  if [[ -z "${raw// /}" || " $raw " == *" auto "* ]]; then stmt_langs_all; return 0; fi
  for l in $raw; do stmt_lang_ok "$l" || continue; [[ " $out " == *" $l "* ]] || out+="${out:+ }$l"; done
  [[ -n "$out" ]] || out=pt
  printf '%s' "$out"
}
cs_langs(){ cs_norm "$(conf_value "$1" STATEMENT_LANGS)"; }
cs_langs_json(){ jq -cn --arg s "$(cs_langs "$1")" '$s|split(" ")'; }
cs_default(){
  local langs="${2:-pt}" loc; loc="$(conf_value "$1" LOCALE)"; loc="${loc//[^a-z]/}"
  if [[ -n "$loc" && " $langs " == *" $loc "* ]]; then printf '%s' "$loc"; else printf '%s' "${langs%% *}"; fi
}
cs_file(){
  local d="$CONTESTSDIR/$1/enunciados" k="$2" l="${3:-pt}" f="${4:-html}"
  if [[ "$l" != pt && -f "$d/$k.$l.$f" ]]; then printf '%s' "$d/$k.$l.$f"; return 0; fi
  [[ -f "$d/$k.$f" ]] && { printf '%s' "$d/$k.$f"; return 0; }
  return 1
}
cs_bank_json(){
  local jf="$CONTESTSDIR/treino/var/jsons/$1.json"
  [[ -f "$jf" ]] || jf="$CONTESTSDIR/treino/var/jsons-private/$1.json"
  [[ -f "$jf" ]] && { printf '%s' "$jf"; return 0; }
  return 1
}
cs_bank_langs(){ jq -r '["pt"] + ((.statements // {}) | keys) | unique | join(" ")' "$1" 2>/dev/null; }
cs_bank_title(){ jq -r --arg l "$2" 'if $l == "pt" then (.title // "") else (.statements[$l].title // "") end' "$1" 2>/dev/null; }
# cs_bank_write: PT sai de statement_html_b64, cada tradução de statements[<lang>].html_b64. Com
# CC_KEEP_STATEMENTS=1 não sobrescreve arquivo existente (o admin pode ter subido o dele).
cs_bank_write(){
  local bf="$1" tdir="$2" skey="$3" what="${4:-all}" l tmp dst
  mkdir -p "$tdir/enunciados" 2>/dev/null
  tmp="$tdir/enunciados/.$skey.tmp.${BASHPID}"
  if [[ "$what" != langs ]]; then
    dst="$tdir/enunciados/$skey.html"
    if [[ "${CC_KEEP_STATEMENTS:-0}" != 1 || ! -s "$dst" ]]; then
      jq -r '.statement_html_b64 // ""' "$bf" 2>/dev/null | base64 -d > "$tmp" 2>/dev/null
      if [[ -s "$tmp" ]]; then mv -f "$tmp" "$dst"; else rm -f "$tmp"; fi
    fi
  fi
  for l in $(jq -r '(.statements // {}) | keys[]' "$bf" 2>/dev/null); do
    stmt_lang_ok "$l" || continue; [[ "$l" == pt ]] && continue
    dst="$tdir/enunciados/$skey.$l.html"
    [[ "${CC_KEEP_STATEMENTS:-0}" == 1 && -s "$dst" ]] && continue
    jq -r --arg l "$l" '.statements[$l].html_b64 // ""' "$bf" 2>/dev/null | base64 -d > "$tmp" 2>/dev/null
    if [[ -s "$tmp" ]]; then mv -f "$tmp" "$dst"; else rm -f "$tmp"; fi
  done
  return 0
}
