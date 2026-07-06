# GET  /contest/badges?contest=<c>[&staff=<login>][&include_disabled=1]  (Bearer: admin/.staff)
# POST /contest/badges?contest=<c>  {staff_password:bool}                (Bearer: só admin)
# Credenciais p/ etiquetas imprimíveis (nome, login, SENHA EM CLARO, região, escola).
# Admin: lista completa, ou o "arquivo" de uma sede via staff=<login>; .staff: só o
# próprio recorte (staff-filters.json, semântica de staff_can_see: lista vazia/ausente
# = vê tudo, match case-insensitive no login). Contas de papel: .admin/.judge/.cjudge/
# .mon NUNCA entram; .staff entra escopada (a própria conta no arquivo de uma sede;
# todas na lista completa, com a região casada pelo filtro). O POST liga/desliga a
# variante COM SENHA p/ o .staff (print-requests/badges.json {staff_password}; default
# ligado): desligada, o GET do .staff vem SEM o campo password — o corte é na API, a
# UI só reflete. É o ÚNICO endpoint que devolve senha numa releitura — toda chamada é
# auditada (badges-view / badges-config).
contest="$(param contest)"
[[ -n "$contest" ]] || fail 400 "Missing contest" "contest_missing"
require_contest "$contest"
require_auth_contest "$contest"
{ is_admin || is_staff; } || fail 403 "Apenas admin/staff do contest" "staff_required"
source "$_LIBDIR/print.sh"

cfgfile="$(pr_dir "$contest")/badges.json"

if [[ "${REQUEST_METHOD:-GET}" == "POST" ]]; then
  is_admin || fail 403 "Apenas o admin do contest" "admin_required"
  body="$(read_body)"
  jq -e . >/dev/null 2>&1 <<<"$body" || fail 400 "JSON inválido" "bad_json"
  sp="$(jq -r 'if .staff_password == false then "false" else "true" end' <<<"$body")"
  mkdir -p "$(pr_dir "$contest")"
  printf '{"staff_password":%s}' "$sp" > "$cfgfile.tmp" && mv -f "$cfgfile.tmp" "$cfgfile"
  audit_log_to "$contest" badges-config "staff_password=$sp"
  ok_json '{saved:true, staff_password:($sp=="true")}' --arg sp "$sp"
  exit 0
fi

require_method GET

# variante com senha liberada p/ o .staff? (default ligado; só o admin muda)
staff_pass="true"
[[ -f "$cfgfile" ]] && jq -e '.staff_password == false' "$cfgfile" >/dev/null 2>&1 && staff_pass="false"
nopass=""
if is_staff && [[ "$staff_pass" == "false" ]]; then nopass="1"; fi

view=""     # login .staff cujo filtro define o recorte ("" = lista completa do admin)
if is_staff; then
  [[ -z "$(param staff)" ]] || fail 403 "Staff vê apenas o próprio arquivo" "staff_scope"
  view="$SESSION_LOGIN"
else
  view="$(param staff)"
  if [[ -n "$view" ]]; then
    valid_id "$view" && [[ "$view" == *.staff ]] || fail 400 "staff inválido" "staff_invalid"
  fi
fi
inc_dis="$(param include_disabled)"

tmp="$(mktemp -d)" || fail 500 "Falha interna" "internal"
trap 'rm -rf "$tmp"' EXIT
d="$CONTESTSDIR/$contest"

# junções pequenas por --slurpfile (regex vêm do admin — podem ser inválidas; try/catch no jq)
_slurp_json() {  # <src> <default> <out>
  if [[ -f "$1" ]] && jq -e . "$1" >/dev/null 2>&1; then jq -c . "$1" > "$3"
  else printf '%s' "$2" > "$3"; fi
}
_slurp_json "$d/regions.json"                        '[]' "$tmp/regions"
_slurp_json "$(pr_dir "$contest")/staff-filters.json" '{}' "$tmp/filters"
_slurp_json "$d/teams-meta.json"                     '[]' "$tmp/teams"

# contas: store próprio (prio 0) + fonte USERS_FROM (prio 1); dedup = local vence
# (mesma precedência de verify_password/_pr_acct). find|xargs jq — sem ARG_MAX.
_badges_accounts() {  # <usersdir> <prio>
  [[ -d "$1" ]] || return 0
  find "$1" -mindepth 2 -maxdepth 2 -name account.json -print0 2>/dev/null \
    | xargs -0 -r jq -c --argjson prio "$2" '
        {login:(.login//""), fullname:(.fullname//""),
         team:(.team.name//""),
         univ:((.team.univ_full // .team.univ_short) // ""),
         region:(.team.region//""),
         password:((.password//"")|ltrimstr("!")),
         disabled:((.password//"")|startswith("!")),
         prio:$prio}'
}
src="$(_users_source "$contest")"
{ _badges_accounts "$d/users" 0
  [[ "$src" != "$contest" ]] && _badges_accounts "$CONTESTSDIR/$src/users" 1
  true
} | jq -cs --slurpfile re "$tmp/regions" --slurpfile ff "$tmp/filters" --slurpfile tm "$tmp/teams" \
      --arg view "$view" --arg dis "$inc_dis" --arg nopass "$nopass" '
  ($re[0] // []) as $regions
  | ($ff[0] // {}) as $filters
  | ($tm[0] | (.rules // (if type=="array" then . else [] end))) as $teams
  | map(select(.login != "")) | group_by(.login) | map(min_by(.prio)) | map(del(.prio))
  | (if $dis == "1" then . else map(select(.disabled | not)) end)
  # alunos: sem contas de papel. Região EXPLÍCITA (.team.region do account) vence; senão
  # derivada de regions.json (regex no login). O recorte do staff (vazio/ausente = tudo)
  # entende "region:<nome>" (igualdade com a região do aluno) além de regex no login.
  | ( map(select(.login | test("\\.(admin|judge|cjudge|staff|mon)$") | not))
      | map(. + {region: (if (.region // "") != "" then .region
                          else ((.login as $l
                            | first($regions[] | (.regex//"") as $rr | select($rr != ""
                                and (try ($l|test($rr)) catch false)) | .name)) // null) end)})
      | ($filters[$view] // []) as $scope
      | (if ($view == "") or (($scope|length) == 0) then .
         else map(select(. as $u
                | any($scope[]; . as $r
                    | if ($r|startswith("region:"))
                      then ((($u.region // "")|ascii_downcase) == ($r[7:] | ascii_downcase | gsub("^ +| +$"; "")))
                      else (try ($u.login | ascii_downcase | test($r;"i")) catch false) end))) end)
    ) as $students
  # .staff: a própria conta no arquivo de uma sede; todas na lista completa. Região do
  # staff: 1º token region:<nome> do filtro dele; senão a derivação clássica (igualdade
  # do regex do filtro com o regex de uma região — semeadura antiga).
  | ( map(select(.login | endswith(".staff")))
      | (if $view != "" then map(select(.login == $view)) else . end)
      | map(. + {region: ((($filters[.login] // []) as $fl
            | (first($fl[] | select(startswith("region:")) | .[7:] | gsub("^ +| +$"; ""))
               // first($regions[] | (.regex//"") as $rr | select($rr != ""
                    and (($fl | index($rr)) != null)) | .name))) // null)})
    ) as $staffacc
  | ($students + $staffacc)
  | map(. + {name: (if .team != "" then .team else .fullname end),
             univ: (if .univ != "" then .univ
                    else ((.login as $l
                      | first($teams[] | (.regex//"") as $rr | select($rr != ""
                          and (try ($l|test($rr)) catch false))
                        | (.school_full // .school // ""))) // "") end)})
  | map(del(.team))
  # senha desligada p/ staff: o campo NEM SAI da API (a UI s\u00f3 reflete a aus\u00eancia)
  | (if $nopass == "1" then map(del(.password)) else . end)
  | sort_by([(.region // "\uffff"), (.login|endswith(".staff")), .name, .login])
' > "$tmp/users" || fail 500 "Falha ao montar a lista" "internal"

# lista de .staff (só p/ admin — alimenta o seletor "arquivo do staff" da página)
staff_list='[]'
if is_admin; then
  staff_list="$(pr_staff_logins "$contest" | jq -R -s '
    split("\n") | map(select(length>0) | split("\t")
      | {login:.[0], fullname:.[1], disabled:(.[2]=="true")})')"
  [[ -n "$staff_list" ]] || staff_list='[]'
fi
printf '%s' "$staff_list" > "$tmp/staff"

# nome/data do contest p/ o rodapé da etiqueta (conf roda em subshell, padrão navbuttons)
cname="$(. "$d/conf" 2>/dev/null; printf '%s' "${CONTEST_NAME:-$contest}")"
cstart="$(. "$d/conf" 2>/dev/null; printf '%s' "${CONTEST_START:-0}")"
cstart="${cstart//[^0-9]/}"; cstart="${cstart:-0}"

n="$(jq -r 'length' "$tmp/users" 2>/dev/null)"; n="${n//[^0-9]/}"; n="${n:-0}"
audit_log_to "$contest" badges-view "view=${view:-ALL} n=$n disabled=${inc_dis:-0} pass=$([[ -n "$nopass" ]] && echo 0 || echo 1)"

# envelope por --slurpfile (contests com milhares de contas — nunca --argjson gigante)
emit_json 200 OK
jq -cn --slurpfile u "$tmp/users" --slurpfile st "$tmp/staff" --slurpfile re "$tmp/regions" \
   --arg view "$view" --arg cn "$cname" --arg sp "$staff_pass" --argjson start "$cstart" '
  {success:true, users:$u[0], count:($u[0]|length),
   staff_view:(if $view=="" then null else $view end),
   regions:$re[0], staff:$st[0], staff_password:($sp=="true"),
   contest_name:$cn, start_epoch:$start, generated_at:(now|floor)}'
