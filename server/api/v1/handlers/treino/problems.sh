# GET /treino/problems
# Lista todos os problemas do treino: [{id, title, tags, collections, solved_count, attempted_count}]
# Cache var/problems.json invalidado POR EVENTO (stamp .treino-list-dirty, tocado por todo ponto
# que cria/remove json servível — index_problem_bg, set-public, delete, move, rebaixamento de org),
# com TTL LONGO só como rede de segurança (escritor esquecido não congela a lista p/ sempre).
# A regeneração agrega os SIDECARS de metadados (var/jsons-meta/*.json, minúsculos) — nunca mais
# slurpa o statement_html_b64 dos 400+ var/jsons/*.json (era 9s no request que pegava o TTL) —
# e roda sob flock (um regenera, os concorrentes esperam e servem o fresco: sem stampede).
JD="$CONTESTSDIR/treino/var/jsons"
META="$CONTESTSDIR/treino/var/jsons-meta"
CACHE="$CONTESTSDIR/treino/var/problems.json"
COUNTS="$CONTESTSDIR/treino/var/json-count"
STAMP="$CONTESTSDIR/treino/var/.treino-list-dirty"

_fresh(){ [[ -f "$CACHE" && ! "$STAMP" -nt "$CACHE" ]] \
          && [[ -z "$(find "$CACHE" -mmin +60 2>/dev/null)" ]]; }

if _fresh; then emit_json 200 OK; cat "$CACHE"; exit 0; fi

exec 9>>"$CACHE.lock"; flock 9
if _fresh; then emit_json 200 OK; cat "$CACHE"; exit 0; fi   # outro request regenerou enquanto esperávamos

set +o noglob
mkdir -p "$META" 2>/dev/null
# auto-cura dos sidecars: json sem sidecar (ou mais novo que ele) => deriva agora. Cobre o
# backfill pós-deploy e qualquer escritor fora dos handlers. Custo: 1 stat por arquivo.
for j in "$JD"/*.json; do
  [[ -f "$j" ]] || continue
  m="$META/$(basename "$j")"
  [[ -f "$m" && ! "$j" -nt "$m" ]] && continue
  jq -c '{id, title, public, tags:(.tags // []), collections:(.collections // [])}' "$j" \
    > "$m.tmp" 2>/dev/null && mv -f "$m.tmp" "$m" || rm -f "$m.tmp"
done
# sidecar órfão (json saiu por fora): não pode ressuscitar problema na lista
for m in "$META"/*.json; do
  [[ -f "$m" && ! -f "$JD/$(basename "$m")" ]] && rm -f "$m"
done

# Contagens por problema vêm de var/json-count/<arquivo>.json (mesmo basename que
# var/jsons/, ou seja, o id na forma '#'). O id INTERNO do json-count é pontilhado,
# então casamos pelo NOME DO ARQUIVO (input_filename), não pelo campo .id.
counts="$(jq -n '
  reduce inputs as $x ({};
    . + { (input_filename | sub(".*/";"") | sub("\\.json$";"")):
          {solved_count: ($x.solved_count // 0), attempted_count: ($x.attempted_count // 0)} })
' "$COUNTS"/*.json 2>/dev/null)"
[[ -n "$counts" ]] || counts='{}'

# base: os SIDECARS + contagens casadas por id ('#').
# O `select(.public != false)` é a 3ª camada anti-vazamento: esta lista é ANÔNIMA, e um bug do
# gerador já pôs problema privado (prova em elaboração) aqui dentro. `!= false` deixa passar json
# legado sem o campo e barra só o explicitamente privado. Ver mojtools/gen-problem-json.sh.
body="$(jq -s --argjson c "$counts" '
  map(select(.public != false)
      | {id, title, tags: (.tags // []), collections: (.collections // [])} + ($c[.id] // {solved_count:0, attempted_count:0}))
' "$META"/*.json 2>/dev/null)"
# corpo vazio: com sidecars presentes é ERRO (nunca servir lista vazia calada — regra da casa);
# sem sidecar nenhum é uma base legitimamente vazia.
if [[ -z "$body" ]]; then
  compgen -G "$META/*.json" >/dev/null 2>&1 \
    && fail 500 "Falha ao montar a lista de problemas" "list_failed" || body='[]'
fi

printf '%s' "$body" > "$CACHE.tmp" && mv -f "$CACHE.tmp" "$CACHE"
emit_json 200 OK
printf '%s' "$body"
