# lib/cli-version.sh — aviso de CLI desatualizada (moj, moj-comp, moj-contest, moj-judges).
#
# A CLI se apresenta no User-Agent como "moj[-tool]/<build>" (build = <git-short>-<AAAAMMDD>,
# carimbo do mkdist.sh; "dev" no repo). O servidor sabe a build que ELE serve — web/moj.build,
# o mesmo arquivo que `moj version` consulta — e em TODA resposta a uma CLI manda:
#   X-Moj-Cli-Status: current | outdated | dev | legacy
#   X-Moj-Cli-Latest: <build servida>
# A CLI atual lê o Status e avisa (uma vez por dia, stderr). A CLI ANTIGA (anterior a 02/09/2026)
# não manda marcador — chega como "curl/x.y" com Authorization: Bearer — e não lê cabeçalho: p/
# ela o `fail` ACRESCENTA a dica ("rode moj update") à error.message, que é o que aquela CLI
# imprime. Caso Edson (2026-09-02): create 400 mascarado como "Problema não existe (404)" por
# uma CLI de antes de agosto — só o aviso no servidor alcança quem nunca atualizou.
# Navegador (Mozilla/…) e curl cru sem Bearer: nada muda. Tudo em builtins (zero fork por request).
: "${MOJ_CLI_BUILD_FILE:=${_DIR:-}/../../../web/moj.build}"
CLI_STATUS=""; CLI_LATEST=""; CLI_BUILD=""; CLI_HINT=""
cli_status_compute(){
  [[ -n "${_CLI_STATUS_DONE:-}" ]] && return 0; _CLI_STATUS_DONE=1
  local ua="${HTTP_USER_AGENT:-}" b=""
  if [[ "$ua" =~ (^|[[:space:]])moj(-comp|-contest|-judges)?/([^[:space:]]+) ]]; then b="${BASH_REMATCH[3]}"
  elif [[ "$ua" == curl/* && "${HTTP_AUTHORIZATION:-}" == Bearer\ * ]]; then CLI_STATUS=legacy
  else return 0; fi
  if [[ -r "$MOJ_CLI_BUILD_FILE" ]]; then IFS= read -r CLI_LATEST < "$MOJ_CLI_BUILD_FILE" || true; fi
  CLI_LATEST="${CLI_LATEST//[[:space:]]/}"
  if [[ "$CLI_STATUS" == legacy ]]; then
    CLI_HINT=" — sua CLI moj é ANTIGA${CLI_LATEST:+ (o servidor está na build $CLI_LATEST)}: rode \"moj update\" (ou baixe de novo: https://${HTTP_HOST:-moj.naquadah.com.br}/moj)"
    return 0
  fi
  CLI_BUILD="$b"
  [[ "$b" == dev ]] && { CLI_STATUS=dev; return 0; }
  [[ -n "$CLI_LATEST" ]] || return 0            # sem referência (web/moj.build ausente): não julga
  [[ "$b" == "$CLI_LATEST" ]] && { CLI_STATUS=current; return 0; }
  local bd="${b##*-}" ld="${CLI_LATEST##*-}"
  if [[ "$bd" =~ ^[0-9]{8}$ && "$ld" =~ ^[0-9]{8}$ ]]; then
    # mais nova que o servidor (dev apontando p/ servidor velho) = current; mesma data com hash
    # diferente = outdated (o servidor é a referência dos SEUS clientes)
    if (( 10#$bd > 10#$ld )); then CLI_STATUS=current; else CLI_STATUS=outdated; fi
  fi
  return 0
}
cli_headers(){   # linhas extras do respond (vazio p/ navegador e curl cru)
  cli_status_compute
  [[ -n "$CLI_STATUS" ]] || return 0
  printf 'X-Moj-Cli-Status: %s\r\n' "$CLI_STATUS"
  [[ -n "$CLI_LATEST" ]] && printf 'X-Moj-Cli-Latest: %s\r\n' "$CLI_LATEST"
  return 0
}
