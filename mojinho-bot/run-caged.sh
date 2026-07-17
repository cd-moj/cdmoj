#!/bin/bash
#
# run-caged.sh — lança o mojinho-bot ENJAULADO com bwrap (mount-namespace mínimo).
#
# A jaula enxerga SÓ: /usr (+ /bin /sbin /lib* RO), um /etc mínimo (DNS+TLS+nss),
# /proc, /dev, /tmp efêmero e um /bot em tmpfs com o CÓDIGO do bot (RO, arquivo a
# arquivo, direto do checkout) + token/bot.conf (RO, do dir "vivo") + mojinho-offset
# (o ÚNICO arquivo gravável, persistido fora da jaula). NADA de /home, do workspace,
# de contests/, run/ ou moj-problems/ — invisíveis por construção. A REDE é
# compartilhada (o bot precisa de api.telegram.org e da API do MOJ no loopback).
#
# Config (env):
#   MOJINHO_SRC   dir do código do bot           (default: o dir deste script)
#   MOJINHO_LIVE  dir vivo com segredos/estado   (default: $HOME/mojinho-live)
#                 conteúdo: token (do Telegram, 600) · bot.conf (600 — ponha
#                 BOT_TOKEN=mojb_… nele p/ a jaula não montar nada de run/) ·
#                 mojinho-offset (estado do getUpdates; criado se faltar)
#
# Segredos NUNCA entram neste repo: token e bot.conf vivem só no dir vivo.
# Host Ubuntu >= 24.04: exige bubblewrap + userns liberado p/ o bwrap via perfil
# AppArmor (ver README.md, seção "Rodando enjaulado").
set -euo pipefail

SRC="${MOJINHO_SRC:-$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)}"
LIVE="${MOJINHO_LIVE:-$HOME/mojinho-live}"

die(){ echo "FATAL: $*" >&2; exit 1; }

command -v bwrap >/dev/null 2>&1 || die "bwrap não instalado (apt install bubblewrap)"
bwrap --version 2>&1 | grep -qi fbwrap && \
  die "o bwrap daqui é o fbwrap (no-op do firejail) — sem jaula real nesta máquina"
# userns funcional? (Ubuntu >= 24.04 nega a não-root por default; ver README)
bwrap --ro-bind / / --dev /dev --proc /proc --unshare-all --die-with-parent true 2>/dev/null || \
  die "bwrap não cria namespace (userns negado? instale o perfil AppArmor — README)"

[[ -f "$SRC/mojinho-api.sh" ]] || die "código do bot não encontrado em $SRC"
[[ -d "$LIVE" ]] || die "dir vivo $LIVE não existe (crie com token + bot.conf; ver README)"
chmod 700 "$LIVE"
[[ -s "$LIVE/token" ]]    || die "$LIVE/token ausente (token do Telegram)"
[[ -f "$LIVE/bot.conf" ]] || die "$LIVE/bot.conf ausente (copie bot.conf.sample e ajuste)"
chmod 600 "$LIVE/token" "$LIVE/bot.conf"
[[ -f "$LIVE/mojinho-offset" ]] || echo 0 > "$LIVE/mojinho-offset"

ARGS=(
  --die-with-parent --new-session
  # unshare de tudo MENOS a rede (Telegram + API do MOJ via loopback do host)
  --unshare-user --unshare-pid --unshare-ipc --unshare-uts --unshare-cgroup
  --proc /proc --dev /dev --tmpfs /tmp
  --ro-bind /usr /usr
  --tmpfs /etc
  --tmpfs /bot --chdir /bot
  --clearenv
  --setenv HOME /bot --setenv PATH /usr/bin:/usr/sbin:/bin:/sbin
  --setenv TMPDIR /tmp --setenv LANG C.UTF-8
)
for d in /bin /sbin /lib /lib64; do [[ -e "$d" ]] && ARGS+=(--ro-bind "$d" "$d"); done
# /etc mínimo por ALLOWLIST: DNS + TLS + nss (o bind segue o symlink do resolv.conf
# até o arquivo real do systemd-resolved; o stub 127.0.0.53 responde — rede é a do host)
for f in resolv.conf hosts nsswitch.conf ld.so.cache gai.conf localtime passwd group; do
  [[ -e "/etc/$f" ]] && ARGS+=(--ro-bind "/etc/$f" "/etc/$f")
done
for d in /etc/ssl /etc/ca-certificates /etc/pki; do
  [[ -d "$d" ]] && ARGS+=(--ro-bind "$d" "$d")
done
[[ -d /etc/ssl/private ]] && ARGS+=(--tmpfs /etc/ssl/private)   # chaves NUNCA na jaula
# o código do bot, arquivo a arquivo (RO) — nada além dele entra do checkout
for f in mojinho-api.sh bot.conf.sample palavras-para-senha; do
  [[ -f "$SRC/$f" ]] && ARGS+=(--ro-bind "$SRC/$f" "/bot/$f")
done
for f in "$SRC"/musica.*; do
  [[ -f "$f" ]] && ARGS+=(--ro-bind "$f" "/bot/$(basename "$f")")
done
# segredos (RO) + o único gravável (offset — trunca o mesmo inode, persiste fora)
ARGS+=(
  --ro-bind "$LIVE/token"          /bot/token
  --ro-bind "$LIVE/bot.conf"       /bot/bot.conf
  --bind    "$LIVE/mojinho-offset" /bot/mojinho-offset
)

exec bwrap "${ARGS[@]}" /bin/bash /bot/mojinho-api.sh
