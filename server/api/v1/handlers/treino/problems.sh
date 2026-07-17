# GET /treino/problems
# Lista todos os problemas do treino: [{id, title, tags, collections, solved_count, attempted_count}]
# Cache var/problems.json com DUAS fontes de invalidação POR EVENTO:
#  1. composição da lista (problema entra/sai): stamp var/.treino-list-dirty, tocado por todo
#     ponto que cria/remove json servível — regenera EM FOREGROUND sob flock (rápido: agrega os
#     sidecars var/jsons-meta, nunca os enunciados);
#  2. contagens solved/attempted (var/.score-dirty, muda a cada submissão): refresh LAZY em
#     BACKGROUND com piso de 10 min — o request serve o stale na hora, ninguém espera placar.
# TTL de 60 min só como rede de segurança (escritor esquecido não congela a lista p/ sempre).
# A regeneração real vive em server/score/treino-list-gen.sh (compartilhada fg/bg).
T="$CONTESTSDIR/treino"
CACHE="$T/var/problems.json"
STAMP="$T/var/.treino-list-dirty"
DIRTY="$T/var/.score-dirty"
GEN="$_DIR/../../score/treino-list-gen.sh"

_fresh(){ [[ -f "$CACHE" && ! "$STAMP" -nt "$CACHE" ]] \
          && [[ -z "$(find "$CACHE" -mmin +60 2>/dev/null)" ]]; }
_counts_stale(){ [[ -f "$DIRTY" && "$DIRTY" -nt "$CACHE" ]] \
                 && [[ -n "$(find "$CACHE" -mmin +10 2>/dev/null)" ]]; }

if _fresh; then
  if _counts_stale; then   # contagens envelheceram: atualiza em background, serve o stale
    ( setsid bash -c 'exec 9>>"$1.lock"; flock -n 9 || exit 0; CONTESTSDIR="$2" bash "$3"' \
        _ "$CACHE" "$CONTESTSDIR" "$GEN" >/dev/null 2>&1 & ) 2>/dev/null
  fi
  emit_json 200 OK; cat "$CACHE"; exit 0
fi

exec 9>>"$CACHE.lock"; flock 9
if _fresh; then emit_json 200 OK; cat "$CACHE"; exit 0; fi   # outro request regenerou na espera
CONTESTSDIR="$CONTESTSDIR" bash "$GEN" 2>/dev/null \
  && [[ -s "$CACHE" ]] || fail 500 "Falha ao montar a lista de problemas" "list_failed"
emit_json 200 OK
cat "$CACHE"
