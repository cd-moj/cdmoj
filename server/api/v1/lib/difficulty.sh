# lib/difficulty.sh — DIFICULDADE e DIRT de um problema: fonte ÚNICA (issue #30, 2026-09-15).
#
# Antes havia cinco fórmulas em quatro caches e três vocabulários: a busca/sugestão do treino
# rotulava pela taxa POR USUÁRIO, a página de estatística do problema pela taxa POR SUBMISSÃO
# (mesmas faixas, base diferente — "fácil" numa tela e "difícil" na outra), o sorteio de
# contest por submissão com faixas .5/.2. Este arquivo é o contrato; quem calcula (treino-list-
# gen, problem-stats, sorteio, stats-gen do contest) chama estas defs e NUNCA reescreve a conta.
# O gêmeo do lado JS é web/shared/difficulty.js (rótulos, cores, mesmas faixas).
#
#   dificuldade = "quem tenta consegue?" — taxa POR USUÁRIO: resolveram ÷ tentaram (distintos)
#       ≥ .9 veasy · ≥ .7 easy · ≥ .5 med · < .5 hard · sem tentantes = new
#   dirt        = "quanto se erra até acertar" — a métrica do resolver do ICPC, a mesma das
#       estatísticas do contest: (submissões de quem resolveu até o 1º AC − ACs) ÷ (essas
#       submissões). Só quem resolveu conta; submissão depois do AC não conta.
#   bucket do sorteio: easy = veasy+easy · medium = med · hard · unknown = new
: "${DIFF_VEASY:=0.9}"; : "${DIFF_EASY:=0.7}"; : "${DIFF_MED:=0.5}"
DIFF_JQ='
  def diff_rate(s; a): if ((a // 0) | tonumber) == 0 then null else (((s // 0) | tonumber) / ((a // 0) | tonumber)) end;
  def diff_label(s; a): (diff_rate(s; a)) as $r
    | if $r == null then "new" elif $r >= '"$DIFF_VEASY"' then "veasy" elif $r >= '"$DIFF_EASY"' then "easy"
      elif $r >= '"$DIFF_MED"' then "med" else "hard" end;
  def dirt_of(tries; s): if ((tries // 0) | tonumber) > 0
    then (((((tries | tonumber) - ((s // 0) | tonumber)) / (tries | tonumber)) * 1000) | floor) / 1000 else null end;
  def diff_bucket(lbl): if lbl == "new" then "unknown" elif lbl == "veasy" or lbl == "easy" then "easy"
    elif lbl == "med" then "medium" else "hard" end;
'
