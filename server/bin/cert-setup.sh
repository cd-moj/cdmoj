#!/bin/bash
# cert-setup.sh — emite o certificado TLS do MOJ (Let's Encrypt) e deixa a RENOVAÇÃO automática.
#
#   sudo bash server/bin/cert-setup.sh --email eu@dominio --credentials ~/digitalocean.ini \
#        --cert-name moj.naquadah.com.br \
#        -d moj.naquadah.com.br -d '*.moj.naquadah.com.br'
#
#   --cert-name N     nome do certificado (dir em /etc/letsencrypt/live/N). Default: o 1º -d.
#   -d DOMINIO        domínio (repetível). Wildcard (*.x) SÓ com DNS-01.
#   --email E         e-mail da conta ACME (obrigatório na 1ª emissão).
#   --credentials F   .ini com o token da API de DNS (vai p/ /etc/letsencrypt/, modo 600).
#   --dns-plugin P    plugin de DNS do certbot (default: digitalocean).
#   --webroot DIR     usa http-01 por webroot em vez de DNS-01 (NÃO emite wildcard).
#   --propagation S   segundos de espera da propagação do DNS (default: 60).
#   --staging         emite contra o ambiente de TESTE do Let's Encrypt (não gasta cota).
#   -n, --dry-run     só mostra o comando do certbot.
#
# Por que DNS-01 por padrão: é o ÚNICO desafio que emite **wildcard**, e wildcard é o que os
# subdomínios de contest (<id>.moj.<base>) exigem. Ele também NÃO precisa que o DNS do site já
# aponte p/ esta máquina (só cria um TXT _acme-challenge temporário) — dá p/ emitir o cert do
# domínio final ANTES do cutover.
#
# A RENOVAÇÃO não é feita aqui: quem renova é o próprio certbot (`certbot.timer` do systemd, 2x/dia,
# já habilitado pelo pacote). Este script garante o que falta p/ ela ser 100% automática:
#   - a credencial de DNS em /etc/letsencrypt/ (600, root);
#   - o HOOK de deploy que recarrega o nginx a cada renovação;
#   - e confere tudo com `certbot renew --dry-run`.
#
# Operação:  certbot certificates                       # o que existe / quando vence
#            certbot renew --dry-run                    # ensaia a renovação (não gasta cota)
#            certbot renew --force-renewal --cert-name <N>   # renova na marra
set -euo pipefail

SELF="$(readlink -f "$0")"
DOMAINS=(); CERTNAME=""; EMAIL=""; CREDS=""; PLUGIN="digitalocean"; WEBROOT=""
PROP=60; STAGING=0; DRYRUN=0
HOOK=/etc/letsencrypt/renewal-hooks/deploy/10-reload-nginx.sh

die(){ echo "cert-setup: $*" >&2; exit 2; }

while [ $# -gt 0 ]; do
  case "$1" in
    -d)             DOMAINS+=("${2:?}"); shift 2 ;;
    --cert-name)    CERTNAME="${2:?}"; shift 2 ;;
    --email)        EMAIL="${2:?}"; shift 2 ;;
    --credentials)  CREDS="${2:?}"; shift 2 ;;
    --dns-plugin)   PLUGIN="${2:?}"; shift 2 ;;
    --webroot)      WEBROOT="${2:?}"; shift 2 ;;
    --propagation)  PROP="${2:?}"; shift 2 ;;
    --staging)      STAGING=1; shift ;;
    -n|--dry-run)   DRYRUN=1; shift ;;
    -h|--help)      sed -n '2,30p' "$SELF"; exit 0 ;;
    *) die "opção desconhecida: $1 (--help)" ;;
  esac
done

[ "${#DOMAINS[@]}" -gt 0 ] || die "faltou -d <dominio>"
: "${CERTNAME:=${DOMAINS[0]}}"
[ "$DRYRUN" = 1 ] || [ "$(id -u)" = 0 ] || die "rode como root (ou -n p/ dry-run)"
command -v certbot >/dev/null || die "certbot ausente (apt install certbot python3-certbot-dns-$PLUGIN)"

args=(certonly --non-interactive --agree-tos --keep-until-expiring --expand --cert-name "$CERTNAME")
for d in "${DOMAINS[@]}"; do args+=(-d "$d"); done
[ -n "$EMAIL" ] && args+=(-m "$EMAIL") || args+=(--register-unsafely-without-email)
[ "$STAGING" = 1 ] && args+=(--staging)

warn_or_die(){ if [ "$DRYRUN" = 1 ]; then echo "cert-setup: AVISO: $*" >&2; else die "$*"; fi; }

if [ -n "$WEBROOT" ]; then
  printf '%s\n' "${DOMAINS[@]}" | grep -q '^\*' && die "wildcard exige DNS-01 (não use --webroot)"
  args+=(--webroot -w "$WEBROOT")
else
  certbot plugins 2>/dev/null | grep -q "dns-$PLUGIN" \
    || warn_or_die "plugin dns-$PLUGIN não instalado (apt install python3-certbot-dns-$PLUGIN)"
  [ -n "$CREDS" ] || CREDS="/etc/letsencrypt/$PLUGIN.ini"
  [ -f "$CREDS" ] || warn_or_die "credencial de DNS não encontrada: $CREDS (use --credentials)"
  dest="/etc/letsencrypt/$(basename "$CREDS")"
  if [ "$DRYRUN" != 1 ] && [ "$(readlink -f "$CREDS")" != "$(readlink -f "$dest" 2>/dev/null)" ]; then
    install -Dm600 -o root -g root "$CREDS" "$dest"; echo ">> credencial de DNS -> $dest (600)"
  fi
  chmod 600 "$dest" 2>/dev/null || true
  args+=("--dns-$PLUGIN" "--dns-$PLUGIN-credentials" "$dest"
         "--dns-$PLUGIN-propagation-seconds" "$PROP")
fi

if [ "$DRYRUN" = 1 ]; then printf 'certbot'; printf ' %q' "${args[@]}"; echo; exit 0; fi

# hook de deploy: o nginx só passa a servir o cert novo depois de um reload.
install -d -m755 "$(dirname "$HOOK")"
cat > "$HOOK" <<'EOF'
#!/bin/sh
# MOJ — recarrega o nginx quando o certbot renova um certificado (hook de deploy).
systemctl is-active --quiet nginx && systemctl reload nginx
exit 0
EOF
chmod 755 "$HOOK"; echo ">> hook de renovação: $HOOK (recarrega o nginx)"

echo ">> certbot ${args[*]}"
certbot "${args[@]}"

echo ">> conferindo a renovação automática…"
systemctl list-timers certbot.timer --no-pager 2>/dev/null | sed -n '2p' || true
systemctl is-enabled certbot.timer >/dev/null 2>&1 \
  || echo "   AVISO: certbot.timer não está enabled — rode: systemctl enable --now certbot.timer"
certbot renew --cert-name "$CERTNAME" --dry-run

echo ">> cert pronto: /etc/letsencrypt/live/$CERTNAME/{fullchain,privkey}.pem"
echo ">> aponte o nginx: bash server/bin/install-nginx.sh --workroot <raiz> --names \"…\" --cert $CERTNAME"
