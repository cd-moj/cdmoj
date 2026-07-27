# POST /treino/admin/achievements  (.admin) — salva o registro de CONQUISTAS do perfil.
# Body: {achievements:[{id,icon,pt,en,kind,params,enabled}]}  |  {restore_default:true}
# Valida (ids únicos [a-z0-9-], kind conhecido, params por kind) e grava ATÔMICO em
# contests/treino/var/achievements.json. restore_default remove o arquivo (volta ao default
# embarcado). Formato/kinds documentados em docs/PERFIL.md; leitura: GET /treino/achievements.
require_method POST
require_auth_contest treino
is_admin || fail 403 "Apenas administradores do treino" "admin_required"

F="$CONTESTSDIR/treino/var/achievements.json"
body="$(read_body)"
jq -e . <<<"$body" >/dev/null 2>&1 || fail 400 "JSON inválido" "bad_json"

if jq -e '.restore_default == true' <<<"$body" >/dev/null 2>&1; then
  rm -f "$F"
  audit_log achievements-restore ""
  ok_json '{restored:true}'
  exit 0
fi

# validação: devolve a PRIMEIRA mensagem de erro (vazio = ok)
err="$(jq -r '
  def perr:
    (.id // "?") as $id
    | if (.id|type) != "string" or ((.id | test("^[a-z0-9-]{1,40}$")) | not)
        then "id inválido (minúsculas/dígitos/hífen, até 40): \($id)"
      elif (.icon|type) != "string" or .icon == "" then "ícone vazio em \($id)"
      elif (.pt|type) != "string" or .pt == "" then "nome pt vazio em \($id)"
      elif (.en|type) != "string" or .en == "" then "nome en vazio em \($id)"
      elif .kind == "solved_gte" or .kind == "submissions_gte" or .kind == "langs_gte" or .kind == "oneshots_gte"
        then (if (.params.n|type) == "number" and .params.n > 0 then empty else "params.n deve ser número > 0 em \($id)" end)
      elif .kind == "streak_gte"
        then (if (.params.days|type) == "number" and .params.days > 0 then empty else "params.days deve ser número > 0 em \($id)" end)
      elif .kind == "collection_complete"
        then (if (.params.min_size|type) == "number" and .params.min_size > 0 then empty else "params.min_size deve ser número > 0 em \($id)" end)
      elif .kind == "collection_named"
        then (if (.params.collection|type) == "string" and .params.collection != "" then empty else "params.collection deve ser o nome da coleção em \($id)" end)
      elif .kind == "tag_solved_gte"
        then (if (.params.tag|type) == "string" and .params.tag != "" and (.params.n|type) == "number" and .params.n > 0
              then empty else "params.tag (sem #) e params.n > 0 em \($id)" end)
      elif .kind == "diff_solved_gte"
        then (if (.params.diff == "veasy" or .params.diff == "easy" or .params.diff == "med" or .params.diff == "hard")
                 and (.params.n|type) == "number" and .params.n > 0
              then empty else "params.diff (veasy|easy|med|hard) e params.n > 0 em \($id)" end)
      else "kind desconhecido em \($id): \(.kind // "?")" end;
  .achievements
  | if type != "array" then "achievements deve ser uma lista"
    elif length == 0 then "registro vazio — use restore_default para voltar ao padrão"
    elif length > 100 then "máximo de 100 conquistas"
    elif ([.[].id] | length) != ([.[].id] | unique | length) then "id duplicado no registro"
    else ([ .[] | perr ] | first // empty) end
' <<<"$body" 2>/dev/null)" || fail 400 "JSON inválido" "bad_json"
[[ -z "$err" ]] || fail 400 "$err" "achievements_invalid"

# normaliza (só os campos do contrato; enabled default true) e grava atômico
out="$(jq -c --argjson t "$EPOCHSECONDS" --arg by "$SESSION_LOGIN" '
  {version:1, updated_at:$t, updated_by:$by,
   achievements:(.achievements | map(
     {id, icon, pt, en, kind, params:(.params // {}),
      enabled:(if .enabled == false then false else true end)}))}' <<<"$body" 2>/dev/null)"
[[ -n "$out" ]] || fail 500 "Falha ao serializar o registro" "achievements_write"

mkdir -p "$(dirname "$F")" 2>/dev/null
printf '%s\n' "$out" > "$F.tmp.$$" && mv -f "$F.tmp.$$" "$F" || fail 500 "Falha ao gravar" "achievements_write"

n="$(jq -r '.achievements | length' <<<"$out")"
audit_log achievements-save "count=$n"
ok_json '{saved:true, count:$n}' --argjson n "${n:-0}"
