# GET /contest/esqueletos?contest=<id>   (Bearer, qualquer conta do contest) — módulo `esqueletos`
# Os esqueletos de código que o contest PERSONALIZOU: {on:true, langs:{<lang>:{mode:"custom",code}|{mode:"off"}}}.
# Linguagem ausente = o padrão (web/shared/languages.js). O editor busca isto só quando o /contest/userinfo
# diz `code_templates:true` — fora disso a resposta é 404 `module_off` (módulo desligado ou editor embutido
# desligado: lib/esqueletos.sh `esq_effective`, conferido a cada requisição). Esqueleto não tem nada da
# prova (é por LINGUAGEM, não por problema), então não espera o início do contest.
contest="$(param contest)"
[[ -n "$contest" ]] || fail 400 "Missing contest" "contest_missing"
require_contest "$contest"
require_auth_contest "$contest"
esq_effective "$contest" || fail 404 "Este contest não usa esqueletos de código" "module_off"
ok_json_slurp '{on:true, langs:$L[0]}' L "$(esq_langs_json "$contest")"
