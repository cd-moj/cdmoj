#!/bin/bash
# smoke-ingest-vigia.sh — o VIGIA do spool de results (server/daemons/ingest-vigia.sh), com podman/systemctl FALSOS:
#   · com o spool acima do limiar ele para o daemon, roda o drenador DA IMAGEM (/opt/moj/…/ingest-drain.py, nunca uma
#     cópia em run/) dentro do container da API e religa o daemon;
#   · sem o drenador no container, o ciclo aborta com ERRO no log e o daemon volta mesmo assim.
set -u
ROOT="$(cd "$(dirname "$(readlink -f "$0")")/../.." && pwd)"
W="$(mktemp -d)"; trap 'rm -rf "$W"' EXIT
pass=0; fail=0
ck(){ if eval "$2"; then echo "  ok: $1"; ((pass++)); else echo "  FAIL: $1"; ((fail++)); fi; }
mkdir -p "$W/bin" "$W/run/spool/submissions"
# podman falso: registra a chamada; `test -f` responde pelo arquivo de controle; o `exec -i … python3 X` registra o X
cat > "$W/bin/podman" <<'EOF'
#!/bin/bash
echo "podman $*" >> "$W/calls"
if [[ "$1 $3" == "exec test" ]]; then [[ -e "$W/drain-existe" ]]; exit; fi
exit 0
EOF
# systemctl falso: registra; ao religar o daemon, pede o fim do vigia (o stop-file é lido no topo do laço)
cat > "$W/bin/systemctl" <<'EOF'
#!/bin/bash
echo "systemctl $*" >> "$W/calls"
[[ "$*" == *start* ]] && : > "$RUNDIR/ingest-vigia.stop"
exit 0
EOF
sed -i "s#\$W#$W#g" "$W/bin/podman" "$W/bin/systemctl"; chmod +x "$W/bin/"*
for i in 1 2 3; do : > "$W/run/spool/submissions/c:x:result:$i.json"; done
roda(){ : > "$W/calls"; : > "$W/run/ingest-vigia.log"
  PATH="$W/bin:$PATH" RUNDIR="$W/run" VIGIA_LIMIAR=2 VIGIA_COOLDOWN_S=0 timeout 20 bash "$ROOT/server/daemons/ingest-vigia.sh"; }

echo "== drenador presente na imagem =="
: > "$W/drain-existe"; roda
ck "para o daemon, drena e religa (nessa ordem)" \
   '[[ "$(grep -oE "systemctl --user (stop|start)|exec -i [^ ]+ python3 [^ ]+" "$W/calls" | tr "\n" "|")" == "systemctl --user stop|exec -i systemd-moj-api python3 /opt/moj/cdmoj/server/daemons/ingest-drain.py|systemctl --user start|" ]]'
ck "nunca a cópia em run/"   '! grep -q "/data/run/ingest-drain" "$W/calls"'

echo "== drenador ausente =="
rm -f "$W/drain-existe"; roda
ck "não roda python nenhum"  '! grep -q "python3" "$W/calls"'
ck "ERRO no log"             'grep -q "ERRO: .*ingest-drain.py não existe" "$W/run/ingest-vigia.log"'
ck "o daemon volta"          'grep -q "systemctl --user start" "$W/calls"'

echo; echo "RESULT: $pass passed, $fail failed"; (( fail == 0 ))
