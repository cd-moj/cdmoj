# score/classify-common.sh — o comum aos MOTORES de classificação (classify-br.sh, classify-pda.sh,
# classify-mundial.sh). Sourced só por eles (standalone, molde do report-gen); a API nunca o carrega.
#
# Contrato de saída dos motores (docs/CLASSIFICACAO.md):
#   rc 0 ok · 1 uso/IO · 2 config inválida (stderr = JSON {errors:[…]}) · 3 RECUSA de dado (stderr = texto
#   que diz qual time/código) — o handler admin/classify transforma em 422 config_invalid/engine_refused.
#
# Os dados saem SEMPRE das fontes únicas:
#   • o placar pelo CABEÇALHO (sc_board_rows, score-common.sh) — nunca pela posição das colunas;
#   • sede e pertença pela regra única (lib/regions.sh rg_map/rg_nodes);
#   • femininas pela PERTENÇA aos recortes "Times femininos" › "3/2/1 competidoras" (cl_female).
_CL_HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$_CL_HERE/score-common.sh"
source "$_CL_HERE/../api/v1/lib/regions.sh"

# cl_init <contest> — valida o id; define CD (dir do contest), W (tmp, apagado na saída) e BOARD (o placar
# COMPLETO: placar-full.txt, que só existe com freeze; senão placar.txt). rc 1 sem placar.
cl_init(){
  C="$1"
  case "$C" in *[!A-Za-z0-9._-]*|""|*..*) echo "classify: contest inválido" >&2; return 1;; esac
  : "${CONTESTSDIR:=/home/ribas/moj/contests}"
  CD="$CONTESTSDIR/$C"
  BOARD="$CD/var/placar-full.txt"; [[ -s "$BOARD" ]] || BOARD="$CD/var/placar.txt"
  [[ -s "$BOARD" ]] || { echo "classify: sem placar em $CD/var" >&2; return 1; }
  W="$(mktemp -d)" || return 1
  trap 'rm -rf "$W"' EXIT
  : > "$W/warn.jsonl"
}

# cl_warn <code> [data-json] — um aviso p/ a saída do motor (o painel o traduz pelo código)
cl_warn(){ jq -cn --arg c "$1" --argjson d "${2:-null}" '{code:$c} + (if $d == null then {} else {data:$d} end)' >> "$W/warn.jsonl" 2>/dev/null; }

# cl_rows — $W/rows.tsv = as linhas do placar SEM convidados, na ordem do placar (colunas do sc_board_rows).
# Desclassificado nem chega ao TXT (sc_users o tira).
cl_rows(){ sc_board_rows "$BOARD" | awk -F'\t' '$12 == 0' > "$W/rows.tsv"; }

# cl_subset_places <rows.tsv> <logins-file> — as linhas cujo login está no arquivo (um por linha), com a
# posição RECONTADA dentro do recorte (competição: 1, 2, 2, 4). Mesmas colunas do sc_board_rows.
cl_subset_places(){
  awk -F'\t' -v OFS='\t' -v KF="$2" '
    BEGIN { while ((getline l < KF) > 0) K[l] = 1; close(KF) }
    ($3 in K) { n++
      if (n > 1 && $8 == pt && $9 == pp && $10 == pl) place = pv; else place = n
      pt = $8; pp = $9; pl = $10; pv = place; $2 = place; print }' "$1"
}

# cl_female <contest> [nome-do-nó] — $W/female.tsv = "login \t faixa" (3, 2 ou 1 = nº de competidoras;
# a MAIOR faixa em que o time está). A faixa vem da PERTENÇA (lib/regions.sh) aos filhos "3…/2…/1…" do
# recorte de topo "Times femininos" — não mais do corte das regexes em tokens `^team` (que perdia login de
# outro formato). Avisos:
#   female_node_missing  — sem o nó: nenhum time é feminino (aviso visível, nunca zero calado);
#   female_multi_bucket  — o time está em mais de uma faixa (vale a maior);
#   female_prefix_match  — a regex casa o login, mas ele não é um token literal dela (^(teamsp03) casa
#                          teamsp030): confira a lista.
cl_female(){
  local c="$1" nm="${2:-Times femininos}" map nodes
  : > "$W/female.tsv"
  if ! map="$(rg_map "$c" 2>/dev/null)" || ! nodes="$(rg_nodes "$c" 2>/dev/null)"; then
    cl_warn female_node_missing "$(jq -cn --arg n "$nm" '{node:$n}')"; return 0
  fi
  if ! jq -e --arg nm "$nm" 'any(.[]; .depth == 0 and .name == $nm)' "$nodes" >/dev/null 2>&1; then
    cl_warn female_node_missing "$(jq -cn --arg n "$nm" '{node:$n}')"; return 0
  fi
  jq -Rrn --slurpfile N "$nodes" --arg nm "$nm" '
    ($N[0]) as $nodes
    | ($nodes | map({key:(.i | tostring), value:.}) | from_entries) as $byi
    | (first($nodes[] | select(.depth == 0 and .name == $nm)) | .i) as $root
    | ([$nodes[] | select(.parent == $root and ((.name // "") | test("^[123]")))
        | {key:(.i | tostring), value:((.name // "")[0:1] | tonumber)}] | from_entries) as $B
    | def bucket_of($i): if ($B[$i | tostring]) != null then $i
                          elif (($byi[$i | tostring].parent // -1) < 0) then null
                          else bucket_of($byi[$i | tostring].parent) end;
      def toks($re): [($re // "") | splits("[^A-Za-z0-9_-]+") | select(length > 0)];
      inputs | split("\t") | .[0] as $l
      | [ (.[2] // "") | split(",")[] | select(length > 0) | tonumber
          | . as $i | bucket_of($i) as $b | select($b != null) | {i:$i, b:($B[$b | tostring])} ] as $hits
      | select(($hits | length) > 0)
      | ($hits | map(.b) | unique) as $bs
      | ($hits | map(toks($byi[.i | tostring].regex)) | (add // []) | any(.[]; . == $l)) as $literal
      | [$l, ($bs | max | tostring), (if ($bs | length) > 1 then "multi" else "" end), (if $literal then "" else "prefix" end)]
      | join("\t")' "$map" > "$W/female.raw" 2>/dev/null || { : > "$W/female.raw"; }
  cut -f1,2 "$W/female.raw" > "$W/female.tsv"
  local multi prefix
  multi="$(awk -F'\t' '$3 == "multi" { print $1 }' "$W/female.raw" | head -20 | jq -Rcs 'split("\n") | map(select(length > 0))')"
  prefix="$(awk -F'\t' '$4 == "prefix" { print $1 }' "$W/female.raw" | head -20 | jq -Rcs 'split("\n") | map(select(length > 0))')"
  [[ "$multi" != "[]" && -n "$multi" ]] && cl_warn female_multi_bucket "$(jq -cn --argjson l "$multi" '{logins:$l}')"
  [[ "$prefix" != "[]" && -n "$prefix" ]] && cl_warn female_prefix_match "$(jq -cn --argjson l "$prefix" '{logins:$l}')"
  return 0
}

# cl_locale — o LOCALE do contest (pt|en|es; outro/ausente = pt): rótulos que o motor escreve (nome de região)
cl_locale(){
  local l; l="$(grep -m1 '^LOCALE=' "$CD/conf" 2>/dev/null | cut -d= -f2 | tr -d "\"'")"
  case "$l" in en|es) printf '%s' "$l";; *) printf 'pt';; esac
}

# CL_NORM_AWK / CL_NORM_JQ — a chave de ESCOLA, a mesma regra nos dois lados: "<país>:<sigla>" com a sigla em
# minúsculas (ASCII) e sem espaço/ponto/vírgula/hífen/sublinhado/aspas ("U.F.P.E" = "ufpe"). O `school_alias`
# da config junta chaves diferentes numa só (os campi de uma instituição).
CL_NORM_AWK='function cl_norm(s){ s = tolower(s); gsub(/[ .,_\047"-]/, "", s); return s }'
CL_NORM_JQ='def cl_norm: ascii_downcase | gsub("[ .,_\\x27\"-]"; "");
def cl_skey: split(":") | if length >= 2 then (.[0] | ascii_downcase) + ":" + (.[1:] | join(":") | cl_norm) else (.[0] | cl_norm) end;'

# cl_attrs <login-regex> <regiões-válidas.txt> <alias.tsv> — $W/attrs.tsv = "login \t região \t país \t escola"
# p/ cada linha de $W/rows.tsv (já sem os excluídos). Região e país saem do LOGIN (as duas capturas da regex);
# escola = "<país>:<sigla normalizada>" › alias. RECUSA (rc 3, com os logins no stderr) se algum login não casa a
# regex ou traz região fora da tabela — o motor nunca adivinha. Avisos: school_missing (sem sigla nem nome: a
# escola vira o próprio login) e school_key_collision (a mesma chave com nomes completos diferentes — confira se
# são mesmo a mesma instituição).
cl_attrs(){
  local re="$1" rf="$2" af="$3"
  # a regex vai por ENVIRON: o -v do gawk interpreta as barras invertidas (\. viraria .)
  CL_RE="$re" LC_ALL=C gawk -F'\t' -v OFS='\t' -v RF="$rf" -v AF="$af" -v BAD="$W/attrs.bad" -v MISS="$W/attrs.miss" -v COL="$W/attrs.col" "$CL_NORM_AWK"'
    BEGIN { RE = ENVIRON["CL_RE"]
            while ((getline l < RF) > 0) if (l != "") R[l] = 1; close(RF)
            while ((getline l < AF) > 0) { split(l, a, "\t"); if (a[1] != "") AL[a[1]] = a[2] } close(AF)
            printf "" > BAD; printf "" > MISS; printf "" > COL }
    { lg = $3
      if (!match(lg, RE, m) || m[1] == "" || m[2] == "") { print lg "\tpadrão" > BAD; next }
      rg = tolower(m[1]); ct = tolower(m[2])
      if (!(rg in R)) { print lg "\tregião " rg > BAD; next }
      us = $5; uf = $7
      if (cl_norm(us) != "")      sk = ct ":" cl_norm(us)
      else if (cl_norm(uf) != "") sk = ct ":" cl_norm(uf)
      else { sk = "login:" lg; print lg > MISS }
      if (sk in AL) sk = AL[sk]
      if (uf != "") { if (!(sk in UF)) UF[sk] = uf; else if (UF[sk] != uf && !(sk in COLD)) { COLD[sk] = 1; print sk "\t" UF[sk] "\t" uf > COL } }
      print lg, rg, ct, sk }' "$W/rows.tsv" > "$W/attrs.tsv" || return 1
  if [[ -s "$W/attrs.bad" ]]; then
    { echo "classify: $(wc -l < "$W/attrs.bad") login(s) fora do padrão de região/país (a regex é $re) — exclua-os ou corrija a regra:"
      head -20 "$W/attrs.bad" | awk -F'\t' '{ print "  " $1 " (" $2 ")" }'; } >&2
    return 3
  fi
  local miss col
  miss="$(head -20 "$W/attrs.miss" | jq -Rcs 'split("\n") | map(select(length > 0))')"
  col="$(head -20 "$W/attrs.col" | jq -Rcs 'split("\n") | map(select(length > 0) | split("\t") | {school:.[0], a:.[1], b:.[2]})')"
  [[ "$miss" != "[]" && -n "$miss" ]] && cl_warn school_missing "$(jq -cn --argjson l "$miss" '{logins:$l}')"
  [[ "$col" != "[]" && -n "$col" ]] && cl_warn school_key_collision "$(jq -cn --argjson l "$col" '{schools:$l}')"
  return 0
}

# cl_warnings_json — os avisos acumulados como array JSON (p/ a saída do motor)
cl_warnings_json(){ jq -cs '.' "$W/warn.jsonl" 2>/dev/null || printf '[]'; }
