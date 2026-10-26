# POST /judge/tl-report   (Bearer mojw_<token>)
# O juiz reporta o TL que CALIBROU p/ um problema no seu cache:
#   body: {host, id, checksum, tl:{lang:seg, ...}, tl_kattis?:{lang:seg, ...}}
# `tl` = o método MOJ; `tl_kattis` = a metade Kattis da tabela (mojtools tl-methods.sh, 26/10/2026; juiz
# anterior não manda = o Kattis desse host fica "não calibrado"). Nos dois mapas só fica chave de linguagem
# (`^[A-Za-z0-9+]{1,16}$`) com valor NUMÉRICO — o resto é descartado (o servidor serve isto ao aluno).
# Guardamos por host; o TL servível = MÁX entre hosts p/ o checksum reportado. Se o
# problema já mudou no servidor (checksum != atual), o report é IGNORADO como obsoleto
# (o juiz vai recalibrar). Em sucesso, dispara em background a regeneração do var/jsons
# (time_limits do treino atualizado). É chamado tanto na calibração quanto ao RELANÇAR o
# juiz (re-reporta os TLs do cache, sem recalibrar).
require_method POST
require_worker
source "$_DIR/../../judge-gw/sched-lib.sh"   # valid_hostname
source "$_DIR/lib/tl-store.sh"

body="$(read_body)"
jq -e . >/dev/null 2>&1 <<<"$body" || fail 400 "Invalid JSON body" "bad_json"
host="$(jq -r '.host // empty' <<<"$body")"; valid_hostname "$host" || fail 400 "Invalid host" "host_invalid"
id="$(jq -r '.id // empty' <<<"$body")"; valid_id "$id" || fail 400 "Invalid id" "id_invalid"
cks="$(jq -r '.checksum // empty' <<<"$body")"
[[ "$cks" =~ ^[a-f0-9]{6,64}$ ]] || fail 400 "Invalid checksum" "cks_invalid"
# os dois mapas, saneados: chave de linguagem + número (".310", "1", "2.5"); lixo some, nunca vira "linguagem"
TLSANE='if type == "object" then with_entries(select((.key | test("^[A-Za-z0-9+]{1,16}$"))
          and ((.value | tostring) | test("^([0-9]+\\.?[0-9]*|\\.[0-9]+)$"))) | .value |= tostring) else {} end'
tl="$(jq -c "(.tl // {}) | $TLSANE" <<<"$body")"; [[ -n "$tl" ]] || tl='{}'
tlk="$(jq -c "(.tl_kattis // {}) | $TLSANE" <<<"$body")"; [[ -n "$tlk" ]] || tlk='{}'

# o juiz devolve a VERSÃO que baixou (package-meta.checksum = pkg_judge_version); o TL, porém, é
# guardado sob o tl_checksum ESTREITO calculado AQUI — é ele que o índice/contest comparam, e uma
# mexida em solução `wrong` não pode apagar o TL da prova (lib/tl-store.sh; commit 41ec3f6).
_pkg="$(pkg_path "$id")"
cur="$(pkg_judge_version "$_pkg" "$id")"
tlc="$(pkg_tl_checksum "$_pkg" "$id")"
if [[ -n "$cur" && "$cur" != "$cks" ]]; then
  # obsoleto: o pacote no servidor mudou desde a calibração -> o juiz recalibra
  ok_json '{recorded:false, stale:true, id:$id, current_checksum:$c}' --arg id "$id" --arg c "$cur"
else
  # CARIMBA o checksum fresco ANTES de gravar o TL: aqui o servidor acabou de conferir que o pacote
  # ATUAL tem este checksum ($cur == $cks), e o índice de donos só vai saber disso na próxima varredura
  # em background. O `mv` do tl_store_record é o que invalida o cache do /contest/problems — o carimbo
  # tem de já estar no lugar quando ele for refeito (lib/tl-store.sh `tl_fresh_*`).
  [[ -n "$cur" ]] && tl_fresh_set "$id" "$tlc"
  # o método do conf AGORA (rota de juiz: pode abrir o pacote) vai carimbado no store, p/ o sumário do Painel
  meth=moj; tl_conf_method_to meth "$_pkg"
  tl_store_record "$host" "$id" "$tlc" "$tl" "$cks" "$tlk" "$meth" || fail 500 "Could not store TL" "tl_store_fail"
  upd_cmd_clear "$host" "$id"   # calibração DIRIGIDA terminou: tira o marcador da tela
  index_problem_bg "$id" 0
  audit_log "tl-report" "id=$id host=$host pkg=${cks:0:8} tl=${tlc:0:8}"
  ok_json '{recorded:true, stale:false, id:$id, served:$srv, served_kattis:$srvk}' \
    --arg id "$id" --argjson srv "$(tl_store_served_for "$id" "$tlc")" --argjson srvk "$(tl_store_served_for "$id" "$tlc" tl_kattis)"
fi
