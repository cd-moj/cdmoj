# lib/verdict.sh — política de EXIBIÇÃO do veredicto ao competidor (fonte ÚNICA).
#
# O history em disco guarda a string de DISPLAY completa (com score embutido, ex.
# "Wrong,60p. Pontos | 30 | 0 |") e NÃO muda — a canonização é só na LEITURA. O que o
# competidor recebe nos endpoints de history é sempre o rótulo CANÔNICO
# (Accepted/Wrong Answer/Time Limit Exceeded/Memory Limit Exceeded/Runtime Error/
# Compilation Error/Judge Error); o DETALHE (score/grupos/testes) sai só pelo
# /submission/summary, redigido pelo nível do modo do contest:
#   none  (icpc / ausente / desconhecido) -> só o canônico (anti-leak: nem o dono vê score)
#   score (obi / heuristic / outro)       -> canônico + score/grupos/heur (sem correct/total)
#   full  (treino / lista-*)              -> tudo (resumo "passou em X/Y testes")
# Visões de juiz/admin NÃO passam por aqui (continuam com a string crua).

# contest_score_mode <contest> -> icpc|obi|heuristic|treino|outro
# MESMA tabela do score/build.sh (lê CONTEST_TYPE/SCORE_MODE sem sourcear o conf;
# vazio/ausente/desconhecido = icpc, contest clássico legado). Mudou lá? mude aqui.
contest_score_mode() {
  local raw
  raw="$(sed -n 's/^[[:space:]]*CONTEST_TYPE=//p; s/^[[:space:]]*SCORE_MODE=//p' "$CONTESTSDIR/$1/conf" 2>/dev/null | tail -1)"
  raw="${raw%\"}"; raw="${raw#\"}"; raw="${raw%\'}"; raw="${raw#\'}"
  raw="$(printf '%s' "$raw" | tr '[:upper:]' '[:lower:]' | tr -d '[:space:]')"
  case "$raw" in
    icpc)                              echo icpc ;;
    obi)                               echo obi ;;
    heuristic|flia)                    echo heuristic ;;
    treino|lista-publica|lista-privada|lista) echo treino ;;
    outro|custom)                      echo outro ;;
    *)                                 echo icpc ;;
  esac
}

# verdict_detail_level <mode> -> none|score|full  (o que o DONO vê além do canônico)
verdict_detail_level() {
  case "$1" in
    obi|heuristic|outro) echo score ;;
    treino)              echo full ;;
    *)                   echo none ;;
  esac
}

# Canonização da string de display -> rótulo canônico. DUAS implementações que DEVEM
# ficar EM SINCRONIA (awk p/ os streams TXT de history; jq p/ o /submission/summary):
#   - pendentes ("Not Answered Yet"/"On queue"/"Running") passam INTACTOS;
#   - o sufixo " (Ignored)" (fora da janela de contagem) é preservado;
#   - "Judge Error"/"No_Servers" -> "Judge Error";
#   - corta na 1ª vírgula/ponto e casa EXATO com o vocabulário ("Wrong" -> "Wrong Answer";
#     "Possible Runtime Error"/"Unknown ERROR" -> "Runtime Error");
#   - string desconhecida passa INTACTA — histories antigos têm "Wrong package format",
#     "Wrong Problem ID", "Language 'x' not availale", …: NUNCA canonizar por prefixo.
# Uso (awk): awk -F: "$VERDICT_CANON_AWK"'{ ... canon(v) ... }'
VERDICT_CANON_AWK='function canon(v,  orig, ign, head) {
  orig = v
  if (v ~ /^(Not Answered Yet|On queue|Running)/) return orig
  ign = ""
  if (sub(/ \(Ignored\)$/, "", v)) ign = " (Ignored)"
  if (v ~ /^(Judge Error|No_?Servers)/) return "Judge Error" ign
  head = v; sub(/[,.].*$/, "", head); sub(/[ \t]+$/, "", head)
  if (head == "Wrong") head = "Wrong Answer"
  else if (head == "Possible Runtime Error" || head == "Unknown ERROR") head = "Runtime Error"
  if (head == "Accepted" || head == "Wrong Answer" || head == "Time Limit Exceeded" ||
      head == "Memory Limit Exceeded" || head == "Runtime Error" || head == "Compilation Error")
    return head ign
  return orig
}'

# Uso (jq): jq "$VERDICT_CANON_JQ ..programa que chama vcanon.."
VERDICT_CANON_JQ='def vcanon:
  if . == null then null else
  . as $orig
  | if test("^(Not Answered Yet|On queue|Running)") then $orig
    else
      (if test(" \\(Ignored\\)$") then " (Ignored)" else "" end) as $ign
      | sub(" \\(Ignored\\)$"; "")
      | if test("^(Judge Error|No_?Servers)") then ("Judge Error" + $ign)
        else
          (split(",")[0] | split(".")[0] | sub("[ \\t]+$"; "")) as $h0
          | (if $h0 == "Wrong" then "Wrong Answer"
             elif ($h0 == "Possible Runtime Error" or $h0 == "Unknown ERROR") then "Runtime Error"
             else $h0 end) as $h
          | if (["Accepted","Wrong Answer","Time Limit Exceeded","Memory Limit Exceeded",
                 "Runtime Error","Compilation Error"] | index($h)) != null
            then ($h + $ign)
            else $orig end
        end
    end
  end;'
