#!/bin/bash
# server/score/jplag-run.sh <contest>
# Roda o jplag nas submissões ACEITAS do contest (última de cada usuário, por problema e
# por linguagem-jplag) e grava resultados em contests/<id>/jplag/. Rodado em background pelo
# handler /contest/admin/jplag-run. Resultado por (problema,lang):
#   {pairs:[{a,b,similarity, a_login,a_name,a_univ, b_login,b_name,b_univ}]}
# a/b = nome SANITIZADO do arquivo dado ao jplag (tr abaixo pode alterar o login; colisão de
# sanitização é pré-existente — o cp sobrescreve e o último vence); a_login = login literal,
# a_name = nome do time (.team.name // .fullname), via users.json gravado por run.
set -u
contest="${1:?uso: jplag-run.sh <contest>}"
: "${CONTESTSDIR:=/home/ribas/moj/contests}"
: "${JPLAG_JAR:=/opt/moj/jplag/jplag-3.0.0-jar-with-dependencies.jar}"
: "${JPLAG_MIN_TOKENS:=6}"
cdir="$CONTESTSDIR/$contest"; jdir="$cdir/jplag"; mkdir -p "$jdir"

status(){ jq -cn --argjson r "$1" --arg m "$2" --argjson t "$EPOCHSECONDS" \
  '{running:$r, message:$m, updated_at:$t}' > "$jdir/status.json.tmp" 2>/dev/null && mv -f "$jdir/status.json.tmp" "$jdir/status.json"; }

jlang(){ case "${1^^}" in C|CPP|CC|CXX|"C++"|GCC|"G++") echo cpp;; JAVA) echo java;;
  PY|PY2|PY3|PYTHON|PYTHON3) echo python3;; CS|CSHARP) echo csharp;; *) echo text;; esac; }
jext(){ case "$1" in cpp) echo cpp;; java) echo java;; python3) echo py;; csharp) echo cs;; *) echo txt;; esac; }

status true "iniciando…"
_SDIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; source "$_SDIR/../api/v1/lib/users.sh"
hist="$(mktemp)"; NAMES="$(mktemp)"; trap 'rm -f "$hist" "$NAMES"' EXIT
emit_history_stream "$contest" > "$hist"
[[ -f "$JPLAG_JAR" ]] || { status false "jar do jplag não encontrado"; exit 0; }
[[ -f "$hist" ]] || { status false "sem histórico"; exit 0; }

# login -> (nome do time, sigla univ) p/ o relatório. Local vence USERS_FROM (mesma resolução
# do _users_source, inline — o runner não carrega auth.sh). Separador \x01: campo vazio com
# TAB colapsaria no read. Nunca --argjson de mapa (ARG_MAX).
usrc=""; line="$(grep -m1 '^USERS_FROM=' "$cdir/conf" 2>/dev/null)"
v="${line#USERS_FROM=}"; v="${v//[\"\']/}"
[[ -n "$v" && "$v" != "$contest" && -d "$CONTESTSDIR/$v/users" ]] && usrc="$v"
for d in "$cdir/users" ${usrc:+"$CONTESTSDIR/$usrc/users"}; do
  [[ -d "$d" ]] || continue
  find "$d" -mindepth 2 -maxdepth 2 -name account.json -print0 2>/dev/null \
    | xargs -0 -r jq -r '[(.login // ""), ((.team.name // .fullname) // ""), (.team.univ_short // "")] | join("\u0001")' 2>/dev/null
done > "$NAMES"
declare -A TNAME TUNIV
while IFS=$'\x01' read -r l n u; do
  if [[ -n "$l" && -z "${TNAME[$l]+x}" ]]; then TNAME[$l]="$n"; TUNIV[$l]="$u"; fi
done < "$NAMES"

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
    src=("$(user_dir "$contest" "$user")/submissions/$sid".*)
    [[ -f "${src[0]:-}" ]] || continue
    safe="$(printf '%s' "$user" | tr -c 'A-Za-z0-9._-' '_')"
    cp "${src[0]}" "$rundir/sub/$safe.$ext" 2>/dev/null || continue
    ((nsub++))
    printf '%s\x01%s\x01%s\x01%s\n' "$safe" "$user" "${TNAME[$user]:-}" "${TUNIV[$user]:-}" >> "$rundir/users.map"
  done
  (( nsub >= 2 )) || { rm -rf "$rundir"; continue; }
  # sanitizado -> {login,name,univ} do run (o csv do jplag só tem o nome de arquivo)
  jq -R -s 'split("\n") | map(select(length>0) | split("\u0001"))
      | map({key: .[0], value: {login: (.[1] // ""), name: (.[2] // ""), univ: (.[3] // "")}})
      | from_entries' "$rundir/users.map" > "$rundir/users.json" 2>/dev/null \
    || printf '{}' > "$rundir/users.json"
  status true "jplag: $prob ($jl, $nsub soluções)…"
  java -jar "$JPLAG_JAR" -l "$jl" -t "$JPLAG_MIN_TOKENS" -r "$rundir/out" "$rundir/sub" >/dev/null 2>&1
  csv="$rundir/out/matches_avg.csv"
  [[ -f "$csv" ]] || continue
  pairs="$(awk -F';' 'NF>=4{gsub(/\.[^.]*$/,"",$2); gsub(/\.[^.]*$/,"",$3); printf "%s\t%s\t%s\t%s\n",$1,$2,$3,$4}' "$csv" \
    | jq -R -s '[ split("\n")[]|select(length>0)|split("\t")
        |{index:(.[0]|tonumber? // 0), a:.[1], b:.[2], similarity:(.[3]|tonumber? // 0)} ] | sort_by(-.similarity)')"
  # join aditivo com o users.json (a/b intactos — compat com csv, match<i>.html e smoke);
  # se o join falhar, os pares seguem sem os campos novos (o front tem fallback)
  enr="$(jq -c --slurpfile U "$rundir/users.json" '($U[0] // {}) as $u
    | map(. + { a_login: (($u[.a].login) // .a), a_name: (($u[.a].name) // ""), a_univ: (($u[.a].univ) // ""),
                b_login: (($u[.b].login) // .b), b_name: (($u[.b].name) // ""), b_univ: (($u[.b].univ) // "") })' \
      <<<"${pairs:-[]}" 2>/dev/null)" && [[ -n "$enr" ]] && pairs="$enr"
  jq -cn --arg p "$prob" --arg l "$jl" --argjson n "$nsub" --argjson t "$EPOCHSECONDS" --arg rid "run-$tag" \
     --argjson pr "${pairs:-[]}" \
     '{problem:$p, lang:$l, submissions:$n, generated_at:$t, run:$rid, pairs:$pr}' > "$jdir/r-$tag.json"
done
status false "concluído"
