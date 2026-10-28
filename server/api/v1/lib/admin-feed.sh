# lib/admin-feed.sh — PRIVACIDADE dos feeds do painel do treino: /treino/admin/activity-log (Atividade, + CSV) e
# /treino/admin/audit-log (o admin-audit). "Privado não lista nem p/ .admin": cada viewer vê só as linhas de autoria
# que ele mesmo poderia abrir. Uma regra só, nos dois handlers:
#   - linha que cita um problema (`org#prob`, em QUALQUER lugar: `id=`, `from=`/`to=`, o probid da submissão e do
#     veredicto, `id=org#p:`…) que o viewer não pode ver sai;
#   - ação org-*/repo-* de org de que ele não é membro sai (`name=`/`org=`/`repo=`);
#   - o `delete` de problema sai p/ quem não é super (o id já saiu do índice: não há como conferir);
#   - o SUPERADMIN (numa sessão do treino) vê tudo.
# "Pode ver" = `owners_vis` (lib/problems.sh, o predicado de sempre); "é privado" = `private_problem_ids`. Índice
# ilegível ⇒ `all`: some TODA linha que cita problema ou org — o resto do feed (logins, ações de conta) segue no ar.
# Uso: `feed_hidden_file <arquivo>` grava o conjunto; o jq do handler compõe `$FEED_VISIBLE_DEF` e filtra com
# `select(feed_visible($hid[0]))` (o conjunto entra por --slurpfile: cresce com o acervo).

FEED_VISIBLE_DEF='def feed_visible($H):
  if ($H.super // false) then true
  else
    ([(.details // ""), (.action // "")] | join(" ")) as $t
    | [$t | scan("[A-Za-z0-9._@+-]+#[A-Za-z0-9._@+-]+")] as $ids
    | ((.action // "") | test("^(org-|repo-)")) as $orgact
    | [(.details // "") | scan("(?:^|\\s)(?:name|org|repo)=([^\\s]+)") | .[0]] as $orgs
    | if ($H.all // false) then (($ids | length) == 0 and ($orgact | not))
      else (($ids | any(. as $i | $H.p[$i]) | not)
            and (($orgact | not) or ($orgs | any(. as $o | $H.o[$o]) | not))
            and ((.action // "") != "delete"))
      end
  end;'

feed_hidden_file(){ # <arquivo>
  local out="$1" m orgs priv vis
  if is_platform_superadmin; then printf '{"super":true}' > "$out"; return 0; fi
  declare -F owners_merged >/dev/null || source "$_LIBDIR/problems.sh"
  declare -F org_list_for >/dev/null || source "$_LIBDIR/orgs.sh"
  orgs="$(orgs_json_for "$SESSION_LOGIN")"
  if ! m="$(owners_merged)" || ! priv="$(private_problem_ids "$m")"; then
    printf '{"all":true}' > "$out"; return 0
  fi
  vis="$(jq -r --arg me "$SESSION_LOGIN" --argjson orgs "$orgs" \
           "$OWNERS_VIS_DEF"' .problems[] | select((.public | not) and owners_vis($me; $orgs)) | .id' <<<"$m" 2>/dev/null)" \
    || { printf '{"all":true}' > "$out"; return 0; }
  # p = privado − o que ele vê (comm sobre listas ordenadas); o = orgs do registro − as dele. Tudo por stdin/arquivo.
  local tp to; tp="$(mktemp)"; to="$(mktemp)"
  comm -23 <(printf '%s\n' "$priv" | sort -u) <(printf '%s\n' "$vis" | sort -u) \
    | jq -R 'select(length > 0)' | jq -s -c 'map({(.): true}) | add // {}' > "$tp" 2>/dev/null
  _orgs_read | jq -c --argjson mine "$orgs" '(keys - $mine) | map({(.): true}) | add // {}' > "$to" 2>/dev/null
  jq -n -c --slurpfile p "$tp" --slurpfile o "$to" '{p: $p[0], o: $o[0]}' > "$out" 2>/dev/null
  rm -f "$tp" "$to"
  jq -e '(.p | type == "object") and (.o | type == "object")' "$out" >/dev/null 2>&1 || printf '{"all":true}' > "$out"
  return 0
}
