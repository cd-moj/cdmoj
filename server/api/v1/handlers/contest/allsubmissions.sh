# GET /contest/allsubmissions?contest=<id>   (Bearer, admin) -> TXT
# TODAS as submissões do contest, com 9 campos por linha:
#   tempo:username:problemid:lang:verdict:epoch:subid:fullname:univ
# Fonte: emit_history_stream (store-v2 fan-out em users/*/history; legado controle/history).
# (fullname/univ vêm do passwd; univ = vazio se não houver coluna específica.)
contest="$(param contest)"
[[ -n "$contest" ]] || fail 400 "Missing contest" "contest_missing"
require_contest "$contest"
require_auth_contest "$contest"
is_admin_or_chief || fail 403 "Admin/juiz-chefe only" "admin_required"

emit_text
passwd="$CONTESTSDIR/$contest/passwd"

# Mapa login -> fullname a partir do passwd (campo 3). univ não modelado -> "".
emit_history_stream "$contest" | awk -F: -v pw="$passwd" '
  BEGIN {
    while ((getline line < pw) > 0) {
      n = split(line, a, ":")
      if (n >= 1) name[a[1]] = (n >= 3 ? a[3] : "")
    }
  }
  {
    full = (($2 in name) ? name[$2] : "")
    print $0 ":" full ":"
  }
'
