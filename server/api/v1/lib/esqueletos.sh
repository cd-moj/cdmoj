# lib/esqueletos.sh — módulo `esqueletos` do contest: o ESQUELETO de código por linguagem que o editor
# embutido mostra ao time (issue #40; decisões do Ribas de 30/09/2026). Só funções; no prelúdio
# (lib/sources.sh) porque o /contest/userinfo pergunta `esq_effective` a cada carga de página.
#
# Doutrina (CLAUDE.md, "Módulo esqueletos"):
#   • o PADRÃO de cada linguagem mora SÓ em web/shared/languages.js (fonte única); este arquivo guarda o
#     que o admin TROCOU: contests/<c>/esqueletos.json = {"langs":{"<lang>":{"mode":"custom","code":"…"}
#     | {"mode":"off"}}} — linguagem ausente = o padrão;
#   • o módulo EXIGE o editor embutido (SHOWEDITOR != 0): ligar sem editor = 422 `editor_required`,
#     desligar o editor com o módulo ligado = 409 `module_needs_editor` — em TODA porta que escreve
#     (admin/modules, admin/settings, criação/duplicar/template, admin/esqueletos). `esq_effective` repete
#     a conferência na LEITURA: conf editado à mão não liga nada;
#   • a trava do "esqueleto intacto" é de TELA (web/shared/editor-skeleton.js) — o /submit não a aplica:
#     o código é do time, inclusive pela CLI.
ESQ_MAX_BYTES=65536   # teto por linguagem (um esqueleto real tem centenas de bytes)

esq_file(){ printf '%s' "$CONTESTSDIR/$1/esqueletos.json"; }

# editor embutido ligado? (ausente = ligado; só SHOWEDITOR=0 desliga — o mesmo do userinfo/settings)
esq_editor_on(){ [[ "$(conf_value "$1" SHOWEDITOR)" != 0 ]]; }

# o módulo VALE neste contest? (ligado E com o editor embutido) — zero processos
esq_effective(){ mod_on "$1" esqueletos && esq_editor_on "$1"; }

# id de linguagem aceitável como chave (o resto do contrato — existir na plataforma — é do handler)
esq_lang_ok(){ [[ "$1" =~ ^[a-z0-9]{1,16}$ ]]; }

# esq_langs_json <c> — o objeto `langs` NORMALIZADO (só modos válidos, código string até o teto);
# arquivo ausente/corrompido = {} (nunca derruba a rota: o pior caso é o padrão).
esq_langs_json(){
  local f; f="$(esq_file "$1")"
  [[ -s "$f" ]] || { printf '{}'; return 0; }
  jq -c --argjson max "$ESQ_MAX_BYTES" '
    (.langs // {}) | if type == "object" then . else {} end
    | with_entries(select((.key | test("^[a-z0-9]{1,16}$"))
        and ((.value.mode == "off") or (.value.mode == "custom" and (.value.code | type) == "string"
             and ((.value.code | utf8bytelength) <= $max))))
      | .value |= (if .mode == "off" then {mode:"off"} else {mode:"custom", code:.code} end))' "$f" 2>/dev/null \
    || printf '{}'
}

# esq_write <c> <langs-json-FILE> — grava o objeto langs (já validado) atomicamente; {} apaga o arquivo.
# O tmp é resolvido em VARIÁVEL antes do jq (${BASHPID} no alvo de redirect de comando externo expande
# no FILHO — CLAUDE.md, molde).
esq_write(){
  local c="$1" lf="$2" f tmp; f="$(esq_file "$c")"
  if jq -e 'length == 0' "$lf" >/dev/null 2>&1; then rm -f "$f"; return 0; fi
  tmp="$f.tmp.${BASHPID}"
  jq -c '{langs: .}' "$lf" > "$tmp" 2>/dev/null && mv -f "$tmp" "$f" || { rm -f "$tmp"; return 1; }
}

# esq_lang_allowed <c> <lang> — a linguagem pode ganhar esqueleto neste contest? As da plataforma
# (PLATFORM_LANGS, lib/langs.sh) + as exóticas/opt-in que o contest DECLARA (whitelist LANGUAGES do conf
# ou o override por problema, problem-langs.json). Chave arbitrária nunca entra no arquivo.
esq_lang_allowed(){
  local c="$1" l="$2" w
  esq_lang_ok "$l" || return 1
  declare -F platform_langs_json >/dev/null || source "$(dirname "${BASH_SOURCE[0]}")/langs.sh"
  [[ " ${PLATFORM_LANGS:-} " == *" $l "* ]] && return 0
  w="$(conf_value "$c" LANGUAGES)"; w="${w//,/ }"; [[ " ${w//\\/} " == *" $l "* ]] && return 0
  [[ -s "$CONTESTSDIR/$c/problem-langs.json" ]] \
    && jq -e --arg l "$l" '[.. | strings] | index($l) != null' "$CONTESTSDIR/$c/problem-langs.json" >/dev/null 2>&1
}
