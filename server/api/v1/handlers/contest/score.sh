# GET /contest/score?contest=<id>  -> TXT
# Serve o placar pré-gerado (var/placar.txt, gerado por server/score/), cuja
# 1ª linha é o MODO (icpc/obi/treino/...). Se ausente, emite só a linha do modo.
contest="$(param contest)"
[[ -n "$contest" ]] || fail 400 "Missing contest" "contest_missing"
require_contest "$contest"
# contest SUPER SECRETO: o placar deixa de ser público — exige sessão DO contest
# (gate ANTES do regen preguiçoso: anônimo não gasta rebuild)
require_not_secret_or_auth "$contest"

# PRÉ-INÍCIO (regra de produto): o placar NUNCA revela a quantidade de problemas antes de a
# competição começar. Antes do CONTEST_START, quem não é juiz/admin (mesmo conjunto de
# can_see_problems) recebe a VITRINE — var/placar-prestart.txt: os times da visão pública,
# com bandeira/sigla/nome e ZERO colunas de problema. O corte é AQUI, na API; o front só
# acrescenta a contagem regressiva. `is_judge` segue no fluxo normal (placar completo).
# SESSÃO UMA VEZ. O handler a consultava em TRÊS pontos (pré-início, coorte, placar full) e esta
# é a rota mais polada do contest — 29% da mistura real medida.
sess=0; SLOGIN=""
load_session 2>/dev/null && [[ "$SESSION_CONTEST" == "$contest" ]] && { sess=1; SLOGIN="$SESSION_LOGIN"; }

source "$_LIBDIR/contest-gate.sh"
if [[ "$(contest_phase "$contest")" == before ]]; then
  pre_priv=0
  (( sess )) && { is_judge || is_animeitor; } && pre_priv=1
  if [[ "$pre_priv" == 0 ]]; then
    pf="$CONTESTSDIR/$contest/var/placar-prestart.txt"
    : "${SCORE_SERVE_FLOOR_S:=8}"
    if [[ ! -f "$pf" ]] || score_sources_newer "$contest" "$pf"; then
     if [[ ! -f "$pf" ]] || [[ -z "$(find "$pf" -newermt "-$SCORE_SERVE_FLOOR_S seconds" 2>/dev/null)" ]]; then
      regen_locked "$CONTESTSDIR/$contest/var/.placar-prestart.lock" \
        "$pf" "$CONTESTSDIR/$contest/var/.score-dirty" "$CONTESTSDIR/$contest/conf" \
        -- bash "$SCOREDIR/build.sh" "$contest" --prestart
     fi
    fi
    [[ -f "$pf" ]] || bash "$SCOREDIR/build.sh" "$contest" --prestart >/dev/null 2>&1
    # antes do início não há freeze possível — o cabeçalho vai em 0 p/ o front não ter de
    # adivinhar a ausência dele.
    if [[ -f "$pf" && -s "$pf.gz" && ! "$pf" -nt "$pf.gz" && "${HTTP_ACCEPT_ENCODING:-}" == *gzip* ]]; then
      printf 'Status: 200 OK\r\nContent-Type: text/plain; charset=utf-8\r\n'
      printf 'X-MOJ-Frozen: 0\r\nContent-Encoding: gzip\r\nVary: Accept-Encoding\r\n\r\n'
      cat "$pf.gz"; exit 0
    fi
    printf 'Status: 200 OK\r\nContent-Type: text/plain; charset=utf-8\r\nX-MOJ-Frozen: 0\r\n\r\n'
    if [[ -f "$pf" ]]; then cat "$pf"; else score_mode_of "$contest"; printf '\n'; fi
    exit 0
  fi
fi

# COORTES (times oficiais × convidados): quando o contest tem coorte não-pública, cada VISÃO
# tem o seu placar. O login determina a visão — convidado recebe a dele (com todos), time
# regular recebe a pública (sem convidado nenhum), privilegiado e pós-liberação recebem a
# completa. `?view=oficial` força a pública (o pódio oficial continua alcançável depois da
# liberação). Sem cohorts.json nada disso acontece: é o placar único de sempre.
# ATENÇÃO: o corte é do SERVIDOR. Os filtros do front (região/país/escola) são client-side
# sobre o TXT recebido — mandar a linha do convidado e esconder no browser não esconderia nada.
source "$_LIBDIR/cohorts.sh"
# `ch_ctx` responde LIGADO + a visão do login num ÚNICO jq. Antes eram `ch_enabled` +
# `ch_view_for_login`, que se chamam em cascata e refaziam a normalização do `ch_get` QUATRO
# vezes: 13 processos jq por requisição nesta rota, medidos. Curto-circuito por existência do
# arquivo (builtin, zero processos) p/ o contest sem coortes, que é a maioria.
CH_ON=0; CH_VIEW=public; _co=""; _cv=public
if [[ -s "$CONTESTSDIR/$contest/cohorts.json" ]]; then
  IFS=$'\x01' read -r CH_ON _co _cv <<<"$(ch_ctx "$contest" "$SLOGIN")"
fi
if [[ "$CH_ON" == 1 ]]; then
  vparam="$(param view)"
  if [[ "$vparam" == oficial ]]; then CH_VIEW=public
  # placar PARALELO de coorte pública (ex.: `?view=times` num contest com inscrição): é
  # público como o geral — não depende de sessão nem esconde ninguém, só recorta o ranking.
  elif [[ -n "$vparam" ]] && ch_is_ranking_view "$contest" "$vparam"; then CH_VIEW="$vparam"
  else
    (( sess )) && CH_VIEW="$_cv"
    # `view=geral` só vale p/ quem já pode ver tudo (privilegiado ou pós-liberação)
    [[ "$vparam" == geral && "$CH_VIEW" == all ]] && CH_VIEW=all
  fi
fi
f="$(ch_view_file "$contest" "$CH_VIEW")"
# Cache preguiçoso: (re)gera o placar se a fonte mudou (var/.score-dirty, tocado a cada
# escrita de history; + conf) ou se ele nunca foi montado. O daemon já reconstrói a cada
# veredicto (coalescido); isto cobre contests importados cujo placar nunca foi gerado.
# PISO DE STALENESS (H2): se o placar foi montado há menos de SCORE_SERVE_FLOOR_S, serve como
# está SEM tentar regen. Sem o piso, 1500 clientes polando /contest/score logo após um
# veredicto disparavam rebuilds concorrentes presos no `flock -w 20` — medido: 16 requests
# concorrentes travavam ~0,74s CADA, ocupando os 8 workers. O daemon já mantém o placar
# fresco (SCORE_COALESCE_S); um placar até ~poucos segundos atrasado é aceitável (já é
# atrasado/frozen por natureza). Placar inexistente NÃO cai no piso: gera na 1ª vez.
: "${SCORE_SERVE_FLOOR_S:=8}"
# ORDEM IMPORTA: primeiro pergunta se há o que regenerar (`-nt`, builtin, zero processos) e só
# então paga o `find` do piso. O piso existe p/ 2000 clientes não dispararem rebuild concorrente,
# NÃO p/ decidir se há rebuild — e no estado normal (nada mudou desde o último build) o `find`
# era um processo por requisição, à toa. As fontes são as MESMAS que o `regen_locked` passa ao
# `stale_cache`; divergir aqui congelaria o placar em silêncio (200 com dado velho para sempre).
if [[ ! -f "$f" ]] || score_sources_newer "$contest" "$f"; then
  if [[ ! -f "$f" ]] || [[ -z "$(find "$f" -newermt "-$SCORE_SERVE_FLOOR_S seconds" 2>/dev/null)" ]]; then
    regen_locked "$CONTESTSDIR/$contest/var/.placar.lock" \
      "$f" "$CONTESTSDIR/$contest/var/.score-dirty" "$CONTESTSDIR/$contest/conf" \
      -- bash "$SCOREDIR/build.sh" "$contest"
  fi
fi
# uma passada de build gera TODAS as visões, então o gatilho acima (no arquivo da visão pedida)
# basta — mas a visão pedida pode não existir ainda num contest que acabou de ganhar coortes.
[[ -f "$f" ]] || bash "$SCOREDIR/build.sh" "$contest" >/dev/null 2>&1

# Privilegiados veem o placar COMPLETO (sem freeze): .admin/.judge SEMPRE + os logins na
# allowlist do conf (SCORE_FULL_USERS, espaço-separados, configurável pelo .admin — vale
# também p/ liberar um .cstaff). Auth é OPCIONAL aqui (placar é público): só checamos se
# houver token válido deste contest.
# `view=public` força a visão PÚBLICA (congelada) mesmo p/ privilegiado — a cerimônia de
# reveal precisa das DUAS visões (frozen + full) p/ computar o delta.
# `scope=mine` (honrado SÓ p/ .cstaff): recorta o placar servido (frozen E full) aos
# usuários que o cstaff enxerga (staff-filters) — é a cerimônia POR SEDE. Fora da
# allowlist, o cstaff só recebe o full quando o contest terminou PARA TODOS
# (contest_over_for_all: fim base + a prorrogação mais tardia de time-overrides.json).
ff="$(ch_view_file "$contest" "$CH_VIEW" full)"
if [[ "$(param view)" != public && -f "$ff" && "$sess" == 1 ]]; then
  # .animeitor SEMPRE recebe o descongelado: é a conta do TELÃO, que conduz a revelação
  priv=0; { is_judge || is_animeitor; } && priv=1
  if [[ "$priv" == 0 ]]; then
    # `conf_value` em vez de `. conf` num subshell: roda em toda requisição de quem tem sessão.
    allow="$(conf_value "$contest" SCORE_FULL_USERS)"
    case " $allow " in *" $SESSION_LOGIN "*) priv=1;; esac
  fi
  if [[ "$priv" == 0 && "$(param scope)" == mine ]] && is_cstaff; then
    source "$_LIBDIR/contest-gate.sh"
    contest_over_for_all "$contest" && priv=1
  fi
  [[ "$priv" == 1 ]] && f="$ff"
fi

# CONGELADO? A resposta é do SERVIDOR, não da tela: só ele sabe qual dos dois arquivos acabou de
# escolher. O front usa isto p/ avisar o competidor que está vendo o placar congelado — quem
# recebe o descongelado (juiz, telão, SCORE_FULL_USERS) recebe 0 e não vê aviso nenhum.
# `FREEZE_TIME` é lido sem sourcear o conf (caminho quente).
FROZEN=0
_fz="$(conf_value "$contest" FREEZE_TIME)"
if [[ "$_fz" =~ ^[0-9]+$ ]] && (( _fz > 0 && EPOCHSECONDS >= _fz )) && [[ "$f" != "$ff" ]]; then
  FROZEN=1
fi

# Corpo PRÉ-COMPRIMIDO (o `build.sh` grava o .gz ao lado de cada placar): o placar de 2000 times
# tem ~175 KB e é o corpo mais servido do dia — sem isto o nginx recomprime o MESMO conteúdo a
# cada requisição. Só vale p/ o arquivo INTEIRO: o recorte por sede (`scope=mine`) filtra linhas
# e sai cru. E o .gz só é servido quando NÃO é mais velho que o .txt.
FILTRA=0
[[ "$sess" == 1 && "$(param scope)" == mine ]] && is_cstaff && FILTRA=1
if (( ! FILTRA )) && [[ -f "$f" && -s "$f.gz" && ! "$f" -nt "$f.gz" && "${HTTP_ACCEPT_ENCODING:-}" == *gzip* ]]; then
  printf 'Status: 200 OK\r\nContent-Type: text/plain; charset=utf-8\r\n'
  printf 'X-MOJ-Frozen: %s\r\nContent-Encoding: gzip\r\nVary: Accept-Encoding\r\n\r\n' "$FROZEN"
  cat "$f.gz"
  exit 0
fi

printf 'Status: 200 OK\r\nContent-Type: text/plain; charset=utf-8\r\nX-MOJ-Frozen: %s\r\n\r\n' "$FROZEN"
if [[ -f "$f" ]]; then
  if (( FILTRA )); then
    source "$_LIBDIR/print.sh"
    pr_filter_board "$contest" "$SESSION_LOGIN" < "$f"
  else
    cat "$f"
  fi
else
  # placar ainda não gerado (contest sem history): front renderiza vazio pelo modo.
  score_mode_of "$contest"; printf '\n'
fi
