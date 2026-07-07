# GET /contest/badges?contest=<c>[&staff=<login>][&include_disabled=1]  (Bearer: admin/.cstaff)
# Credenciais p/ etiquetas imprimíveis (nome, login, SENHA EM CLARO, região, escola).
# Gate: admin OU .cstaff (chefe de sede) — o .staff NÃO vê etiquetas (403 cstaff_required).
# Admin: lista completa, ou o "arquivo" de uma sede via staff=<login .cstaff>; .cstaff: só
# o próprio recorte (staff-filters.json, semântica de staff_can_see: lista vazia/ausente =
# vê tudo, region:<nome> por igualdade, demais entradas como regex no login). Contas de
# papel: .admin/.judge/.cjudge/.mon NUNCA entram; .staff/.cstaff entram como seção própria
# — no arquivo de uma sede, a conta do PRÓPRIO view + as que casam o MESMO escopo dele (o
# chefe imprime a própria credencial e as do staff da sede). A senha sai SEMPRE (ver
# credencial é a razão de ser do papel; o antigo toggle {staff_password} do .staff foi
# extinto junto com o acesso do .staff — print-requests/badges.json é arquivo morto, sem
# leitor). É o ÚNICO endpoint que devolve senha numa releitura — toda chamada é auditada
# (badges-view).
contest="$(param contest)"
[[ -n "$contest" ]] || fail 400 "Missing contest" "contest_missing"
require_contest "$contest"
require_auth_contest "$contest"
{ is_admin || is_cstaff; } || fail 403 "Apenas admin/chefe de sede (.cstaff)" "cstaff_required"
require_method GET
source "$_LIBDIR/print.sh"

view=""     # login .cstaff cujo filtro define o recorte ("" = lista completa do admin)
if is_cstaff; then
  [[ -z "$(param staff)" ]] || fail 403 "Chefe de sede vê apenas o próprio arquivo" "staff_scope"
  view="$SESSION_LOGIN"
else
  view="$(param staff)"
  if [[ -n "$view" ]]; then
    valid_id "$view" && [[ "$view" == *.cstaff ]] || fail 400 "cstaff inválido" "staff_invalid"
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
      --arg view "$view" --arg dis "$inc_dis" '
  ($re[0] // []) as $regions
  | ($ff[0] // {}) as $filters
  # teams-meta: objeto {rules:[…]} ou array cru; SEM .rules em array (indexar array com
  # string é ERRO no jq — o // não o engole — e 500ava contest sem teams-meta.json)
  | ($tm[0] | (if type=="object" then (.rules // []) elif type=="array" then . else [] end)) as $teams
  | map(select(.login != "")) | group_by(.login) | map(min_by(.prio)) | map(del(.prio))
  | (if $dis == "1" then . else map(select(.disabled | not)) end)
  # alunos: sem contas de papel. Região EXPLÍCITA (.team.region do account) vence; senão
  # derivada de regions.json (regex no login). O recorte do view (vazio/ausente = tudo)
  # entende "region:<nome>" (igualdade com a região do aluno) além de regex no login.
  | ( map(select(.login | test("\\.(admin|judge|cjudge|staff|cstaff|mon)$") | not))
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
  # contas de papel (.staff/.cstaff): seção própria. Lista completa = todas; arquivo de uma
  # sede = a conta do PRÓPRIO view + (escopo vazio = todas; senão as que casam o MESMO
  # escopo do view). Região de cada conta: 1º token region:<nome> do filtro DELA; senão a
  # derivação clássica (igualdade do regex do filtro com o regex de uma região — semeadura
  # antiga).
  | ( map(select(.login | test("\\.(staff|cstaff)$")))
      | map(. + {region: ((($filters[.login] // []) as $fl
            | (first($fl[] | select(startswith("region:")) | .[7:] | gsub("^ +| +$"; ""))
               // first($regions[] | (.regex//"") as $rr | select($rr != ""
                    and (($fl | index($rr)) != null)) | .name))) // null)})
      | ($filters[$view] // []) as $scope
      | (if $view == "" then .
         elif ($scope|length) == 0 then .
         else map(select(.login == $view
               or (. as $u | any($scope[]; . as $r
                   | if ($r|startswith("region:"))
                     then ((($u.region // "")|ascii_downcase) == ($r[7:] | ascii_downcase | gsub("^ +| +$"; "")))
                     else (try ($u.login | ascii_downcase | test($r;"i")) catch false) end)))) end)
    ) as $staffacc
  | ($students + $staffacc)
  | map(. + {name: (if .team != "" then .team else .fullname end),
             univ: (if .univ != "" then .univ
                    else ((.login as $l
                      | first($teams[] | (.regex//"") as $rr | select($rr != ""
                          and (try ($l|test($rr)) catch false))
                        | (.school_full // .school // ""))) // "") end)})
  | map(del(.team))
  | sort_by([(.region // "\uffff"), (.login|test("\\.(staff|cstaff)$")), .name, .login])
' > "$tmp/users" || fail 500 "Falha ao montar a lista" "internal"

# lista de .cstaff (só p/ admin — alimenta o seletor "arquivo da sede" da página)
staff_list='[]'
if is_admin; then
  staff_list="$(pr_cstaff_logins "$contest" | jq -R -s '
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
audit_log_to "$contest" badges-view "view=${view:-ALL} n=$n disabled=${inc_dis:-0}"

# envelope por --slurpfile (contests com milhares de contas — nunca --argjson gigante)
emit_json 200 OK
jq -cn --slurpfile u "$tmp/users" --slurpfile st "$tmp/staff" --slurpfile re "$tmp/regions" \
   --arg view "$view" --arg cn "$cname" --argjson start "$cstart" '
  {success:true, users:$u[0], count:($u[0]|length),
   staff_view:(if $view=="" then null else $view end),
   regions:$re[0], staff:$st[0],
   contest_name:$cn, start_epoch:$start, generated_at:(now|floor)}'
