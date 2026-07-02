#!/usr/bin/env bash
# store-migrate.sh <contest> [--apply]
#
# Converte um contest do modelo GLOBAL (passwd + controle/history + submissions/ mojlog/
# results/ flat, com o login embutido no nome) para o STORE POR-USUÁRIO:
#   contests/<c>/users/<login>/{account.json,history,metrics.json,submissions/,mojlog/,results/}
#
# DRY-RUN por padrão (só relata; não move nada). --apply move de fato.
# Idempotente-ish: rode sempre sobre uma CÓPIA primeiro (CONTESTSDIR apontando p/ scratch).
#
# Estratégia dirigida pelo history (a autoridade): cada linha
#   <tempo>:<login>:<probid>:<lang>:<verdict…>:<sub_epoch>:<subid>
# dá (login, sub_epoch, subid). O nome dos arquivos flat embute um "filename-id" que é
#   - <subid>            (era md5 nova / uuid) ; ou
#   - <sub_epoch>:<subid> (era legada)
# Construímos um mapa dos DOIS candidatos → (login, subid canônico) e varremos os dirs 1x.
set -uo pipefail

CONTEST="${1:?uso: store-migrate.sh <contest> [--apply]}"
APPLY=0; [[ "${2:-}" == "--apply" ]] && APPLY=1
: "${CONTESTSDIR:=/home/ribas/moj/contests}"
_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

CDIR="$CONTESTSDIR/$CONTEST"
[[ -d "$CDIR" && -f "$CDIR/conf" ]] || { echo "store-migrate: contest não encontrado: $CDIR" >&2; exit 1; }

# libs (para metrics_recompute / regen_passwd / paths). common.sh liga noglob → religamos abaixo.
export CONTESTSDIR
export MOJ_CONF="${MOJ_CONF:-/nonexistent-store-migrate}"
source "$_DIR/../api/v1/lib/common.sh"
source "$_DIR/../api/v1/lib/users.sh"
set +o noglob; shopt -s nullglob

UDIR="$CDIR/users"; HIST="$CDIR/controle/history"; PASSWD="$CDIR/passwd"
PROFDIR="$CDIR/var/profiles"
WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
mode="DRY-RUN"; (( APPLY )) && mode="APPLY"
say(){ printf '%s\n' "$*" >&2; }
say "== store-migrate ($mode) contest=$CONTEST CONTESTSDIR=$CONTESTSDIR =="

valid_login(){ [[ "$1" =~ ^[A-Za-z0-9._@#+-]+$ && "$1" != *..* && "$1" != "." && "$1" != -* ]]; }
mvf(){ (( APPLY )) && mv -f -- "$1" "$2"; }   # move só em --apply

(( APPLY )) && mkdir -p "$UDIR"

# ---------------------------------------------------------------- Fase 1: contas
# passwd: login:senha:nome[:email]  +  var/profiles/<login>.json → account.json
say "-- Fase 1: contas (passwd + profiles → account.json)"
n_acc=0; n_dup=0; n_bad=0
declare -A SEEN_LOGIN=()
: > "$WORK/logins"
while IFS= read -r line || [[ -n "$line" ]]; do
  [[ -z "$line" ]] && continue
  login="${line%%:*}"; rest="${line#*:}"
  pass="${rest%%:*}"; rest2="${rest#*:}"
  # nome e email: nome = até o próximo ':' ; email = resto (pode faltar)
  if [[ "$rest2" == *:* ]]; then name="${rest2%%:*}"; email="${rest2#*:}"; else name="$rest2"; email=""; fi
  if ! valid_login "$login"; then say "  ! login inválido, pulado: '$login'"; ((n_bad++)); continue; fi
  if [[ -n "${SEEN_LOGIN[$login]:-}" ]]; then say "  ! login duplicado no passwd: '$login' (mantido o 1º)"; ((n_dup++)); continue; fi
  SEEN_LOGIN[$login]=1
  printf '%s\n' "$login" >> "$WORK/logins"
  d="$UDIR/$login"
  if (( APPLY )); then
    mkdir -p "$d/submissions" "$d/mojlog" "$d/results"
    prof="$PROFDIR/$login.json"; [[ -f "$prof" ]] || prof=/dev/null
    jq -n --arg l "$login" --arg p "$pass" --arg n "$name" --arg e "$email" \
          --slurpfile pf <(cat "$prof" 2>/dev/null || echo '{}') \
      '($pf[0] // {}) as $P
       | {login:$l,password:$p,fullname:$n,email:$e,
          created_at:0,updated_at:0,status:"active",
          university:($P.university//null),favorite_editor:($P.favorite_editor//null),
          public:(if $P.public==false then false else true end),
          uname_changes:($P.uname_changes//[])}' > "$d/account.json"
    # foto do perfil → users/<login>/photo.png
    [[ -f "$PROFDIR/$login.png" ]] && mvf "$PROFDIR/$login.png" "$d/photo.png"
  fi
  ((n_acc++))
done < "$PASSWD"
say "  contas: $n_acc  (duplicadas no passwd: $n_dup, inválidas: $n_bad)"

# ---------------------------------------------------------------- Fase 2: history
# particiona por login (campo 2), removendo o login → <tempo>:<probid>:<lang>:<verdict…>:<sub_epoch>:<subid>
say "-- Fase 2: history → users/<login>/history"
tot_hist=0; part_hist=0; hist_orphan=0
if [[ -f "$HIST" ]]; then
  tot_hist="$(wc -l < "$HIST")"
  # sort -s por login (campo 2) para escrever cada arquivo de uma vez (bounded fds)
  LC_ALL=C sort -t: -k2,2 -s "$HIST" | awk -F: -v udir="$UDIR" -v apply="$APPLY" -v loginsf="$WORK/logins" '
    BEGIN{ part=0; orph=0; while((getline l < loginsf)>0) valid[l]=1 }
    { login=$2;
      if(!(login in valid)){ orph++; next }
      if(login!=cur){ if(cur!="" && apply=="1") close(curf); cur=login; curf=udir"/"login"/history" }
      # linha sem o login: $1 + $3..$NF (verdict pode conter ":")
      line=$1; for(i=3;i<=NF;i++) line=line":"$i;
      if(apply=="1") print line >> curf;
      part++;
    }
    END{ if(cur!="" && apply=="1") close(curf); print part" "orph > "/dev/stderr" }' 2> "$WORK/histcount"
  read -r part_hist hist_orphan < "$WORK/histcount"
fi
say "  history: total=$tot_hist particionadas=$part_hist órfãs(login ausente)=$hist_orphan"

# ---------------------------------------------------------------- Fase 3: roteamento de arquivos
# mapa: filename-id (subid  E  sub_epoch:subid) → login \t subid-canônico
say "-- Fase 3: roteia submissions/ mojlog/ results/ → dir do usuário"
if [[ -f "$HIST" ]]; then
  # só logins com conta (evita rotear arquivos de logins removidos do passwd p/ dir inexistente)
  awk -F: -v loginsf="$WORK/logins" '
    BEGIN{ while((getline l < loginsf)>0) valid[l]=1 }
    NF>=4 && ($2 in valid){ login=$2; se=$(NF-1); sid=$NF;
                            print sid"\t"login"\t"sid;
                            print se":"sid"\t"login"\t"sid; }' "$HIST" > "$WORK/route.map"
else
  : > "$WORK/route.map"
fi

route_dir(){ # <srcdir> ; emite MOVE/ORPHAN em $WORK/moves
  local src="$1"
  [[ -d "$src" ]] || return 0
  find "$src" -maxdepth 1 -type f -printf '%f\n' 2>/dev/null | \
  awk -v mapf="$WORK/route.map" -v src="$src" '
    BEGIN{ FS="\t"; while((getline l < mapf)>0){ split(l,a,"\t"); lg[a[1]]=a[2]; cn[a[1]]=a[3] } }
    { fn=$0; key="";
      # o id pode conter "-" (uuid) e ":" (epoch:...): testa prefixos cumulativos em cada "-"
      m=split(fn, parts, "-"); pref="";
      for(i=1;i<=m;i++){ pref=(i==1?parts[i]:pref"-"parts[i]); if(pref in lg){ key=pref; break } }
      if(key==""){ print "ORPHAN\t" src "\t" fn; next }
      # extensão = após o último ponto (se houver)
      ext=""; n=split(fn,dp,"."); if(n>1) ext=dp[n];
      base=cn[key]; dest=(ext!="" ? base"."ext : base);
      print "MOVE\t" src "\t" fn "\t" lg[key] "\t" dest;
    }'
}

: > "$WORK/moves"
route_dir "$CDIR/submissions" >> "$WORK/moves"
route_dir "$CDIR/mojlog"      >> "$WORK/moves"

# results/<id>.json: id == filename-id (subid ou sub_epoch:subid). login+canon vêm do map.
if [[ -d "$CDIR/results" ]]; then
  find "$CDIR/results" -maxdepth 1 -type f -name '*.json' -printf '%f\n' 2>/dev/null | \
  awk -v mapf="$WORK/route.map" -v src="$CDIR/results" '
    BEGIN{ FS="\t"; while((getline l < mapf)>0){ split(l,a,"\t"); lg[a[1]]=a[2]; cn[a[1]]=a[3] } }
    { fn=$0; id=fn; sub(/\.json$/,"",id);
      if(id in lg) print "RESULT\t" src "\t" fn "\t" lg[id] "\t" cn[id]".json";
      else print "ORPHAN\t" src "\t" fn; }' >> "$WORK/moves"
fi

# executa/《conta》os moves
n_sub=0; n_log=0; n_res=0; n_orph=0
while IFS=$'\t' read -r kind src fn login dest; do
  case "$kind" in
    MOVE)
      case "$src" in
        */submissions) ((n_sub++)); mvf "$src/$fn" "$UDIR/$login/submissions/$dest";;
        */mojlog)      ((n_log++)); mvf "$src/$fn" "$UDIR/$login/mojlog/$dest";;
      esac;;
    RESULT)
      ((n_res++))
      if (( APPLY )); then
        # report_html relativo ao dir do usuário: mojlog/<subid>.html
        tmpj="$UDIR/$login/results/$dest.tmp"
        jq -c --arg rh "mojlog/$(basename "$dest" .json).html" '.report_html=$rh' "$src/$fn" > "$tmpj" 2>/dev/null \
          && mv -f "$tmpj" "$UDIR/$login/results/$dest" && rm -f "$src/$fn"
      fi;;
    ORPHAN) ((n_orph++));;
  esac
done < "$WORK/moves"
say "  submissions=$n_sub mojlog=$n_log results=$n_res  órfãos(sem match no history)=$n_orph"

# ---------------------------------------------------------------- Fase 4: métricas
say "-- Fase 4: metrics.json por usuário"
n_met=0
if (( APPLY )); then
  while IFS= read -r login; do metrics_recompute "$CONTEST" "$login" && ((n_met++)); done < <(list_users "$CONTEST")
fi
say "  metrics recomputadas: $n_met"

# ---------------------------------------------------------------- Fase 5: índice Telegram (só treino)
if [[ "$CONTEST" == treino ]]; then
  say "-- Fase 5: índice Telegram (4º campo numérico do passwd)"
  TGDIR="$CDIR/var/telegram"; CONF="$TGDIR/conflicts.tsv"
  n_tg=0; n_conf=0
  (( APPLY )) && mkdir -p "$TGDIR/by-tgid" "$TGDIR/by-login"
  declare -A TG_OWNER=()
  while IFS= read -r line || [[ -n "$line" ]]; do
    login="${line%%:*}"; f4="${line##*:}"
    # só quando há 4 campos e o 4º é numérico
    [[ "$line" == *:*:*:* ]] || continue
    [[ "$f4" =~ ^[0-9]+$ ]] || continue
    valid_login "$login" || continue
    if [[ -n "${TG_OWNER[$f4]:-}" ]]; then
      say "  ! colisão telegram_id=$f4: '${TG_OWNER[$f4]}' e '$login' (mantido o 1º)"
      (( APPLY )) && printf '%s\t%s\t%s\n' "$f4" "${TG_OWNER[$f4]}" "$login" >> "$CONF"
      ((n_conf++)); continue
    fi
    TG_OWNER[$f4]="$login"
    if (( APPLY )); then
      jq -n --argjson id "$f4" --arg l "$login" \
        '{telegram_id:$id,login:$l,username:null,linked_at:0,source:"passwd-migration"}' \
        > "$TGDIR/by-tgid/$f4.json"
      printf '%s\n' "$f4" > "$TGDIR/by-login/$login"
    fi
    ((n_tg++))
  done < "$PASSWD"
  say "  vínculos Telegram: $n_tg  colisões(duplicatas): $n_conf"
fi

# ---------------------------------------------------------------- Fase 6: passwd derivado + verificação
say "-- Fase 6: regen_passwd + verificação vs original"
if (( APPLY )); then
  cp -f "$PASSWD" "$WORK/passwd.orig"
  regen_passwd "$CONTEST"
  # comparação insensível a ordem e a 4º campo vazio (login:senha:nome: == login:senha:nome)
  norm(){ sed -E 's/:$//' "$1" | LC_ALL=C sort; }
  if diff -q <(norm "$WORK/passwd.orig") <(norm "$PASSWD") >/dev/null; then
    say "  OK: passwd derivado == original (módulo ordem/4º-campo-vazio)"
    # ativa o store-v2 (chave explícita lida por store_v2): daemon/submit passam a usar users/
    if ! grep -q '^USER_STORE=' "$CDIR/conf" 2>/dev/null; then printf 'USER_STORE=v2\n' >> "$CDIR/conf"; fi
    say "  USER_STORE=v2 ativado no conf"
  else
    say "  ATENÇÃO: passwd derivado DIVERGE do original — USER_STORE NÃO ativado; investigar:"
    diff <(norm "$WORK/passwd.orig") <(norm "$PASSWD") | head -20 >&2 || true
  fi
else
  say "  (dry-run: passwd não regenerado, USER_STORE não ativado)"
fi

say "== fim ($mode) =="
