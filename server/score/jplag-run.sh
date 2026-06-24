#!/bin/bash
# server/score/jplag-run.sh <contest>
# Roda o jplag nas submissões ACEITAS do contest (última de cada usuário, por problema e
# por linguagem-jplag) e grava resultados em contests/<id>/jplag/. Rodado em background pelo
# handler /contest/admin/jplag-run. Resultado por (problema,lang): {pairs:[{a,b,similarity}]}.
set -u
contest="${1:?uso: jplag-run.sh <contest>}"
: "${CONTESTSDIR:=/home/ribas/moj/contests}"
: "${JPLAG_JAR:=/home/ribas/moj/cdmoj/old/moj-prod/moj/jplag/jplag-3.0.0-jar-with-dependencies.jar}"
: "${JPLAG_MIN_TOKENS:=6}"
cdir="$CONTESTSDIR/$contest"; jdir="$cdir/jplag"; mkdir -p "$jdir"

status(){ jq -cn --argjson r "$1" --arg m "$2" --argjson t "$EPOCHSECONDS" \
  '{running:$r, message:$m, updated_at:$t}' > "$jdir/status.json.tmp" 2>/dev/null && mv -f "$jdir/status.json.tmp" "$jdir/status.json"; }

jlang(){ case "${1^^}" in C|CPP|CC|CXX|"C++"|GCC|"G++") echo cpp;; JAVA) echo java;;
  PY|PY2|PY3|PYTHON|PYTHON3) echo python3;; CS|CSHARP) echo csharp;; *) echo text;; esac; }
jext(){ case "$1" in cpp) echo cpp;; java) echo java;; python3) echo py;; csharp) echo cs;; *) echo txt;; esac; }

status true "iniciando…"
hist="$cdir/controle/history"
[[ -f "$JPLAG_JAR" ]] || { status false "jar do jplag não encontrado"; exit 0; }
[[ -f "$hist" ]] || { status false "sem histórico"; exit 0; }

rm -f "$jdir"/r-*.json 2>/dev/null; rm -rf "$jdir"/run-* 2>/dev/null

declare -A LATEST            # "prob|jlang|user" -> "epoch\tsubid"
while IFS=: read -r mn user prob lang verdict epoch subid; do
  [[ "$verdict" == Accepted* ]] || continue
  [[ -n "$prob" && -n "$user" && -n "$subid" ]] || continue
  jl="$(jlang "$lang")"; key="$prob|$jl|$user"
  prev="${LATEST[$key]:-}"; pe="${prev%%$'\t'*}"
  if [[ -z "$prev" || "${epoch:-0}" -ge "${pe:-0}" ]]; then LATEST[$key]="${epoch:-0}"$'\t'"$subid"; fi
done < "$hist"

set +o noglob; shopt -s nullglob
# grupos únicos (prob|jlang) das chaves de LATEST (GROUPS é reservada no bash!)
mapfile -t PJS < <(for key in "${!LATEST[@]}"; do printf '%s\n' "${key%|*}"; done | sort -u)
for pj in "${PJS[@]}"; do
  prob="${pj%|*}"; jl="${pj#*|}"
  tag="$(printf '%s' "$pj" | md5sum | cut -c1-12)"
  rundir="$jdir/run-$tag"; rm -rf "$rundir"; mkdir -p "$rundir/sub"
  ext="$(jext "$jl")"; nsub=0
  for key in "${!LATEST[@]}"; do
    [[ "${key%|*}" == "$pj" ]] || continue
    user="${key##*|}"; sid="${LATEST[$key]#*$'\t'}"
    src=("$cdir/submissions/"*"$sid"*); [[ -f "${src[0]}" ]] || continue
    safe="$(printf '%s' "$user" | tr -c 'A-Za-z0-9._-' '_')"
    cp "${src[0]}" "$rundir/sub/$safe.$ext" 2>/dev/null && ((nsub++))
  done
  (( nsub >= 2 )) || { rm -rf "$rundir"; continue; }
  status true "jplag: $prob ($jl, $nsub soluções)…"
  java -jar "$JPLAG_JAR" -l "$jl" -t "$JPLAG_MIN_TOKENS" -r "$rundir/out" "$rundir/sub" >/dev/null 2>&1
  csv="$rundir/out/matches_avg.csv"
  [[ -f "$csv" ]] || continue
  pairs="$(awk -F';' 'NF>=4{gsub(/\.[^.]*$/,"",$2); gsub(/\.[^.]*$/,"",$3); printf "%s\t%s\t%s\t%s\n",$1,$2,$3,$4}' "$csv" \
    | jq -R -s '[ split("\n")[]|select(length>0)|split("\t")
        |{index:(.[0]|tonumber? // 0), a:.[1], b:.[2], similarity:(.[3]|tonumber? // 0)} ] | sort_by(-.similarity)')"
  jq -cn --arg p "$prob" --arg l "$jl" --argjson n "$nsub" --argjson t "$EPOCHSECONDS" --arg rid "run-$tag" \
     --argjson pr "${pairs:-[]}" \
     '{problem:$p, lang:$l, submissions:$n, generated_at:$t, run:$rid, pairs:$pr}' > "$jdir/r-$tag.json"
done
status false "concluído"
