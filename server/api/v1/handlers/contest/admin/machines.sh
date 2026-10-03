# GET /contest/admin/machines?contest=<c>[&round=<slug>]   (admin OU juiz-chefe)
# MAPA DE MÁQUINAS da rodada: time × IP × User-Agent. É no aquecimento que os times ligam as
# máquinas de verdade, então é ali que se descobre de onde cada um vem — e, na prova oficial, quem
# mudou de máquina (`changed`, comparado com o machines.json da última rodada arquivada).
#
# Fonte: contests/<c>/var/access.log (TSV epoch/login/ip/ua_b64, escritor único no login),
# recortado pela JANELA da rodada. Nada novo é capturado.
#
# SÓ LEITURA — as ações reusam endpoints que já existem:
#   preencher a sede do time -> POST /contest/admin/teams {set:{"<login>":{region:"<sede>"}}}
#   armar o gate de UA       -> POST /contest/admin/settings {login_ua_substring:"…"}
# GET -> {round, prev_round, window, by_login:[…], by_ip:[…], uas:[{ua,n}], ua_suggestion, totals}
require_method GET
contest="$(param contest)"
[[ -n "$contest" ]] || fail 400 "Missing contest" "contest_missing"
require_contest "$contest"
require_auth_contest "$contest"
is_admin_or_chief || fail 403 "Apenas o admin ou o juiz-chefe" "admin_required"
source "$_DIR/lib/users.sh"; source "$_DIR/lib/contest-create.sh"
source "$_DIR/lib/ua-gate.sh"     # UA esperado por time (gate por sede) no mapa
source "$_DIR/lib/contest-rounds.sh"

round="$(param round)"
if [[ -n "$round" ]]; then
  rd_valid_slug "$round" || fail 400 "round inválido" "round_invalid"
  [[ -n "$(rd_round "$contest" "$round")" ]] || fail 404 "Rodada não encontrada" "round_notfound"
fi

m="$(rd_machines "$contest" "$round")"
[[ -n "$m" ]] || fail 500 "Falha ao montar o mapa de máquinas" "build_fail"

# UA vem em base64 do access.log (o login grava assim p/ não injetar no arquivo *sourced*).
# `ua_suggestion` = a candidata ao gate de UA. Era 8 s por abertura no TCP 2026 (03/10/2026): um `base64 -d` por UA e
# um `grep` por SUBSTRING candidata (4.753 processos com 43 UAs únicos — machine_id+MAC tornam cada UA único) — e a
# sugestão saía inútil (") Gecko/20100101 Firefox/140.13.0" casa qualquer Firefox). Agora: decodifica num jq e
# sugere num awk só —
#   · todos os UAs do mlinux ⇒ o prefixo COMUM das imagens, cortado num separador ("MLinux/cl.tcp.2026."; uma
#     imagem só ⇒ "MLinux/<imagem>/"): é o que identifica a prova, e não o navegador;
#   · senão, a MAIOR substring comum a todos (busca binária no tamanho: existe comum de tamanho L ⇒ existe de L−1);
#   · vazia = navegadores diferentes na sala; a UI mostra a lista e deixa o admin escolher.
uas_file="$(mktemp)"
jq -r '[ .by_login[]?.uas[]? ] | unique | .[] | (try @base64d catch "") | gsub("[\r\n]"; " ")' <<<"$m" 2>/dev/null \
  | grep -v '^[[:space:]]*$' | sort -u > "$uas_file"
sug=""
if [[ -s "$uas_file" ]]; then
  sug="$(awk '
    { ua[NR] = $0 }
    END {
      n = NR; allml = 1
      for (i = 1; i <= n; i++) if (index(ua[i], "MLinux/") == 0) { allml = 0; break }
      if (allml) {
        for (i = 1; i <= n; i++) { r = substr(ua[i], index(ua[i], "MLinux/") + 7); p = index(r, "/"); img[i] = (p ? substr(r, 1, p - 1) : r) }
        pre = img[1]
        for (i = 2; i <= n; i++) { k = 0; while (k < length(pre) && k < length(img[i]) && substr(pre, k + 1, 1) == substr(img[i], k + 1, 1)) k++; pre = substr(pre, 1, k) }
        same = 1; for (i = 2; i <= n; i++) if (img[i] != img[1]) { same = 0; break }
        if (same && pre != "") { print "MLinux/" pre "/"; exit }
        # corta no último separador: "cl.tcp.2026.u" (uach/utfsm/…) vira "cl.tcp.2026."
        while (length(pre) > 0 && substr(pre, length(pre), 1) !~ /[.\-_]/) pre = substr(pre, 1, length(pre) - 1)
        if (length(pre) >= 3) { print "MLinux/" pre; exit }
      }
      # maior substring comum (do MENOR UA), por busca binária no tamanho
      s = ua[1]; for (i = 2; i <= n; i++) if (length(ua[i]) < length(s)) s = ua[i]
      lo = 8; hi = length(s); best = ""
      while (lo <= hi) {
        mid = int((lo + hi) / 2); found = ""
        for (off = 1; off + mid - 1 <= length(s) && found == ""; off++) {
          c = substr(s, off, mid); ok = 1
          for (i = 1; i <= n; i++) if (index(ua[i], c) == 0) { ok = 0; break }
          if (ok) found = c
        }
        if (found != "") { best = found; lo = mid + 1 } else hi = mid - 1
      }
      print best
    }' "$uas_file")"
fi

out="$(jq -c --rawfile uas "$uas_file" --arg sug "$sug" '
  def dec: (try (. | @base64d) catch "");
  . + { uas: ($uas | split("\n") | map(select(length > 0))),
        ua_suggestion: $sug,
        by_login: [ .by_login[] | . + { uas: [ .uas[] | dec ],
                    pairs: [ .pairs[] | (. + {ua: (.ua64 | dec)}) | del(.ua64) ] } ] }' <<<"$m")"
rm -f "$uas_file"
[[ -n "$out" ]] || fail 500 "Falha ao montar a resposta" "build_fail"
audit_log_to "$contest" machines-view "round=${round:-ativa}"
# resposta por --slurpfile (ok_json_slurp): o mapa cresce com o EVENTO (logins×IP×UA) e
# estourou os 128 KiB POR ARGUMENTO no treino (31/08: "jq: Argument list too long" na jq
# final, DEPOIS do emit_json ⇒ 200 com corpo VAZIO — as duas armadilhas documentadas da
# casa, juntas). Agregado nunca por --argjson; corpo antes do cabeçalho.
ok_json_slurp '$m[0]' m "$out"
