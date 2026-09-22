# POST /hooks/nutella?contest=<c> — WEBHOOKS do NutellaBoot 3 (alertas das máquinas mlinux).
#
# SEM Bearer: quem autentica é o HMAC. O serviço manda `X-NB-Signature: sha256=<HMAC-SHA256 do corpo
# CRU com o segredo>`; o segredo é POR CONTEST, em contests/<c>/secrets/nutella-webhook.secret (600),
# gerado pela ação `webhooks-install` do /contest/nutella. A conferência é em python3 (stdlib,
# `hmac.compare_digest`): segredo lido do ARQUIVO e corpo do ARQUIVO — nada em argv (o `openssl dgst
# -hmac <segredo>` poria o segredo no `ps`).
#
# 401 OPACO p/ tudo que não autentica — contest inexistente, sem segredo, assinatura errada, evento
# velho: a rota é pública e não pode servir de oráculo de "este contest existe / tem integração".
# Só DEPOIS da assinatura: `image` fora das sedes do contest = 404; evento que não é alerta = 200
# `ignored`. Corpo > 64 KiB = 413. Repetição (o serviço tenta 3 vezes; alguém reenviando um corpo
# capturado) = 200 `duplicate`, sem efeito.
#
#   alert.raised / alert.dismissed  →  contests/<c>/var/nutella-events.log (JSONL):
#     {t, at, event, image, mac, mkey, id, kind, detail, vendor, other_mac, team, notified}
#   `mkey` = "m:" + md5(mac) — o machine_id do agente novo É md5(MAC), então o alerta cai na MESMA
#   chave de máquina do painel de anomalias. `team` = quem está na máquina (var/nutella-macs.tsv, o
#   elo publicado no login; senão o da última coleta).
#   Aviso por Telegram ao DONO do contest (DM; lib/alerts.sh) só DURANTE a prova (início−1h … fim),
#   com teto: 1 por máquina+tipo a cada 10 min e 10 por contest a cada 10 min. O log não tem teto de
#   aviso — o painel Máquinas › Anomalias mostra tudo.
[[ "${REQUEST_METHOD:-GET}" == POST ]] || fail 405 "POST only" "method_not_allowed"
_hk_deny(){ fail 401 "unauthorized" "unauthorized"; }
contest="$(param contest)"
{ [[ -n "$contest" ]] && valid_id "$contest" && [[ -d "$CONTESTSDIR/$contest" ]]; } || _hk_deny
cdir="$CONTESTSDIR/$contest"
secf="$cdir/secrets/nutella-webhook.secret"
[[ -s "$secf" ]] || _hk_deny
_cl="${CONTENT_LENGTH:-0}"; [[ "$_cl" =~ ^[0-9]+$ ]] || _cl=0
(( _cl <= 65536 )) || fail 413 "payload too large" "too_large"
bf="$(read_body_file)"
trap 'rm -f "$bf"' EXIT
[[ "$(stat -c %s "$bf" 2>/dev/null || echo 0)" -le 65536 ]] || fail 413 "payload too large" "too_large"

python3 -c '
import hashlib, hmac, sys
sec = open(sys.argv[1], "rb").read().strip()
body = open(sys.argv[2], "rb").read()
want = "sha256=" + hmac.new(sec, body, hashlib.sha256).hexdigest()
sys.exit(0 if (sec and hmac.compare_digest(want, sys.argv[3])) else 1)
' "$secf" "$bf" "${HTTP_X_NB_SIGNATURE:-}" 2>/dev/null || _hk_deny

# --- daqui p/ baixo o corpo é do serviço (assinado), mas segue sendo entrada externa: tudo via jq ---
IFS=$'\t' read -r ev img at mac aid kind dlv < <(jq -r '
  [ (.event // ""), (.image // ""), ((.at // 0) | floor), ((.data.mac // "") | ascii_downcase | gsub(":"; "-")),
    ((.data.id // "") | tostring), (.data.kind // ""), ((.delivery // "") | tostring) ] | map(tostring | gsub("[\t\n\r]"; " ")) | @tsv' "$bf" 2>/dev/null)
[[ "$at" =~ ^[0-9]+$ ]] || at=0
# frescor: `at` está DENTRO do corpo assinado — evento de mais de 1 h (ou do futuro) não entra
(( at >= EPOCHSECONDS - 3600 && at <= EPOCHSECONDS + 300 )) || _hk_deny
# `webhook.test` = o botão "testar" do serviço: assinado e aceito, sem registro (ele só quer um 2xx nosso)
[[ "$ev" == webhook.test ]] && { ok_json '{ok:true, ignored:true, test:true}'; exit 0; }
[[ "$img" =~ ^[A-Za-z0-9._-]{1,64}$ ]] || fail 404 "unknown image" "image_unknown"
source "$_LIBDIR/nutella.sh"
{ nb_images "$contest"; jq -r '.sedes[]?.id // empty' "$cdir/var/nutella.cache.json" 2>/dev/null; } | grep -qxF -- "$img" \
  || fail 404 "unknown image" "image_unknown"
# alertas E os eventos de máquina que valem uma linha na trilha de Anomalias durante a prova
case "$ev" in
  alert.raised|alert.dismissed|machine.rebooted|machine.offline|machine.online) ;;
  *) ok_json '{ok:true, ignored:true}'; exit 0 ;;
esac
[[ "$mac" =~ ^[0-9a-f]{2}(-[0-9a-f]{2}){5}$ ]] || fail 422 "mac inválido" "mac_invalid"
[[ "$aid" =~ ^[A-Za-z0-9._:-]{1,64}$ ]] || aid=""
[[ "$dlv" =~ ^[A-Za-z0-9_-]{1,64}$ ]] || dlv=""

LOGF="$cdir/var/nutella-events.log"; mkdir -p "$cdir/var"
exec {_hkfd}>"$cdir/var/.nutella-events.lock" 2>/dev/null && flock -w 5 "$_hkfd" 2>/dev/null
# repetição (o serviço tenta 3×): pelo `delivery` do corpo assinado quando existe (NutellaBoot ≥ 21/09/2026),
# senão pelo trio (evento, alerta, máquina) — evento de máquina sem `id` só dedupa por delivery
if [[ -s "$LOGF" ]]; then
  if [[ -n "$dlv" ]]; then tail -n 2000 "$LOGF" | jq -e --arg d "$dlv" -s 'any(.[]; .delivery == $d)' >/dev/null 2>&1 && { ok_json '{ok:true, duplicate:true}'; exit 0; }
  elif [[ -n "$aid" ]]; then tail -n 2000 "$LOGF" | jq -e --arg e "$ev" --arg i "$aid" --arg m "$mac" -s 'any(.[]; .event == $e and .id == $i and .mac == $m)' >/dev/null 2>&1 && { ok_json '{ok:true, duplicate:true}'; exit 0; }
  fi
fi
# teto de enchente: o log pára em 5 MB (o serviço já dedupa alerta aberto; isto é cinto de segurança)
if [[ -e "$LOGF" && "$(stat -c %s "$LOGF" 2>/dev/null || echo 0)" -gt 5242880 ]]; then ok_json '{ok:true, dropped:true}'; exit 0; fi

# o time: o próprio corpo já traz `data.binding.user_id` (≥ 21/09); senão o elo publicado no login; senão a coleta
team="$(jq -r '(.data.binding.user_id // "") | tostring' "$bf" 2>/dev/null)"; valid_id "${team:-x}" || team=""
[[ -n "$team" || ! -s "$cdir/var/nutella-macs.tsv" ]] || team="$(awk -F'\t' -v m="$mac" '$1 == m { print $2; exit }' "$cdir/var/nutella-macs.tsv")"
[[ -n "$team" ]] || team="$(jq -r --arg m "$mac" 'first(.sedes[]?.machines[]? | select(.mac == $m) | .team // empty) // ""' "$cdir/var/nutella.cache.json" 2>/dev/null)"
valid_id "${team:-x}" || team=""
mkey="m:$(printf '%s' "$mac" | md5sum | cut -c1-32)"

# avisar? só alerta NOVO, durante a prova, dentro dos tetos
notify=false
if [[ "$ev" == alert.raised ]]; then
  cs="$(conf_value "$contest" CONTEST_START)"; ce="$(conf_value "$contest" CONTEST_END)"
  [[ "$cs" =~ ^[0-9]+$ ]] || cs=0; [[ "$ce" =~ ^[0-9]+$ ]] || ce=0
  if (( cs > 0 && EPOCHSECONDS >= cs - 3600 && EPOCHSECONDS <= ce )); then
    notify=true
    if [[ -s "$LOGF" ]]; then
      tail -n 500 "$LOGF" | jq -e --arg m "$mac" --arg k "$kind" --argjson now "$EPOCHSECONDS" -s '
        ([ .[] | select(.notified == true and .t >= $now - 600) ]) as $r
        | (($r | length) >= 10) or any($r[]; .mac == $m and .kind == $k)' >/dev/null 2>&1 && notify=false
    fi
  fi
fi
if [[ "$notify" == true ]]; then
  source "$_LIBDIR/telegram.sh" 2>/dev/null; source "$_LIBDIR/alerts.sh" 2>/dev/null
  owner="$(head -1 "$cdir/owner" 2>/dev/null)"; chat=""
  valid_id "${owner:-}" 2>/dev/null && chat="$(tg_id_of_login treino "$owner" 2>/dev/null)"
  if [[ -n "$chat" ]] && declare -F alert_dm >/dev/null 2>&1; then
    txt="$(jq -r --arg c "$contest" --arg team "$team" '
      def esc: gsub("&"; "&amp;") | gsub("<"; "&lt;") | gsub(">"; "&gt;");
      "🖥 <b>" + ($c | esc) + "</b> — alerta de máquina: <b>" + ((.data.kind // "?") | tostring | .[0:40] | esc) + "</b>\n"
      + "sede " + ((.image // "") | esc) + " · máquina <code>" + ((.data.mac // "") | tostring | .[0:32] | esc) + "</code>"
      + (if $team != "" then " · time <b>" + ($team | esc) + "</b>" else "" end)
      + (if ((.data.detail // "") | tostring | length) > 0 then "\n" + ((.data.detail | tostring | .[0:200]) | esc) else "" end)
      + "\nPainel: Máquinas › Anomalias"' "$bf" 2>/dev/null)"
    alert_dm "$txt" "$chat" loud >/dev/null 2>&1 || notify=false
  else notify=false; fi
fi

jq -c --argjson t "$EPOCHSECONDS" --argjson at "$at" --arg mac "$mac" --arg mkey "$mkey" --arg id "$aid" \
   --arg team "$team" --argjson n "$notify" --arg dlv "$dlv" '
  def s($n): (. // "") | tostring | .[0:$n];
  {t: $t, at: $at, event: (.event | s(40)), image: (.image | s(64)), mac: $mac, mkey: $mkey, id: $id, delivery: $dlv,
   kind: (.data.kind | s(40)), detail: (.data.detail | s(300)), vendor: (.data.vendor | s(80)),
   other_mac: (.data.other_mac | s(32)), boot_id: (.data.boot_id | s(20)), team: $team, notified: $n,
   extra: (if (.event | startswith("machine.")) then ({offline_for: .data.offline_for, last_seen: .data.last_seen, previous_boot_id: .data.previous_boot_id, boots: .data.boots} | with_entries(select(.value != null))) else null end)}' "$bf" >> "$LOGF" 2>/dev/null \
  || fail 500 "log" "log_failed"
ok_json '{ok:true, logged:true, notified:$n}' --argjson n "$notify"
