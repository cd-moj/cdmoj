#!/bin/bash
# smoke-mlinux-view.gjs.sh — RENDERIZA web/lib/mlinux-view.js (a view única do panorama mlinux:
# painel do admin, /contest/mlinux/ e o mlinux.html do relatório) num DOM falso, do jeito que o
# relatório offline a inlina (dom.js + charts.js + view, sem import/export).
# O que prende: a telemetria do agente NOVO do NutellaBoot 3 (PSI, OOM, reinícios, relógio,
# ociosidade, modelo do equipamento, alertas por tipo) aparece QUANDO o cache traz os campos — e
# um cache ANTIGO (o da LATAM 2026, sem nenhum deles) rende a tela de antes, sem exceção e sem
# seção fantasma. Nas duas línguas.
set -u
HERE="$(dirname "$(readlink -f "$0")")"; WEB="$(cd "$HERE/../../web" && pwd)"
command -v gjs >/dev/null 2>&1 || { echo "mlinux-view: gjs ausente — pulando"; exit 0; }
W="$(mktemp -d)"; trap 'rm -rf "$W"' EXIT

# agregado de UMA sede, com o que o coletor grava (score/nutella-gen.sh)
jq -n '
  def ser: [ range(0; 6) | {t: (. * 30), mem_sum: 300, mem_n: 5, sw_sum: 100, sw_n: 5} ];
  { id:"26tsca", name:"Sede A", machines_total: 6, seen: 6, alerts: 3,
    pop: {seen:6, used:5, linked:5, chosen:5, ranked:5, tm:5, teams:5, present:5},
    ram_bands: {"8":5}, ram_bands_all: {"8":6}, ram_avg_sum: 40960, ram_avg_n: 5,
    cpu: {"Intel(R) Core(TM) i5-10500 CPU @ 3.10GHz": 6}, cpu_tm: {"Intel(R) Core(TM) i5-10500 CPU @ 3.10GHz": 5},
    ed_adopt: {code: 4, vim: 1}, ld_sum: 5, ld_n: 10,
    pressure: {"8|vscode": {n:4, mem0_sum:160, mem0_n:4, mem4_sum:280, mem4_n:4, sw_sum:400, sw_n:4, sw_max:780, series: ser}},
    series: [ range(0; 4) | {t: (. * 10), act: 5, mem_sum: 200, mem_n: 5, sw_sum: 0, sw_n: 5, ld_sum: 2, ld_n: 5} ],
    machines: [ {mac:"aa-bb-01", processor:"i5-10500", cores:6, mem_mb:8192, team:"alice", used:true, pts:40} ] }' > "$W/old.json"
jq '. + { alert_kinds: {"identity.duplicate": 1, "usb.storage": 2},
          health: {agent_new: 4, psi_mem_sum: 40, psi_cpu_sum: 20, psi_io_sum: 10, psi_n: 20,
                   oom_machines: 1, oom_kills: 2, idle_pts: 40, idle_hi: 10, skew_n: 4, skew_bad: 1, reboots: 1},
          psi_mem_max: 3.9, model_tm: {"Dell Inc. OptiPlex 3090": 3, "Lenovo ThinkCentre M70q": 1} }
      | .pressure["8|vscode"] += {psi_sum: 8, psi_n: 4, psi_max: 3.9}
      | .pressure["8|vscode"].series |= map(. + {psi_sum: 4, psi_n: 4})
      | .series |= map(. + {psi_sum: 5, psi_n: 5})
      | .machines[0] += {model: "Dell Inc. OptiPlex 3090", oom: 2, agent_new: true}' "$W/old.json" > "$W/new.json"

mk(){ # <lang> → script gjs
  { printf 'const LANG=%s;\nfunction T(pt,en){return LANG==="en"?en:pt}\n' "\"$1\""
    cat <<'JS'
// DOM falso: só o que dom.js/charts.js/view usam
function N(tag) { this.tag = tag; this.kids = []; this.attrs = {}; this.style = {}; this.nodeType = 1; this.className = ''; this._t = null; }
N.prototype.append = function (...k) { k.forEach((x) => this.kids.push(x && x.nodeType ? x : { nodeType: 3, text: String(x) })); };
N.prototype.appendChild = function (k) { this.append(k); return k; };
N.prototype.setAttribute = function (k, v) { this.attrs[k] = String(v); };
N.prototype.addEventListener = function () {};
Object.defineProperty(N.prototype, 'textContent', {
  get() { return this._t != null ? this._t : this.kids.map((k) => (k.nodeType === 3 ? k.text : k.textContent)).join(''); },
  set(v) { this._t = String(v); this.kids = []; } });
Object.defineProperty(N.prototype, 'innerHTML', { get() { return this._t || ''; }, set(v) { this._t = String(v); } });
const document = { createElement: (t) => new N(t), createElementNS: (_, t) => new N(t), createTextNode: (s) => ({ nodeType: 3, text: String(s) }) };
const count = (n, tag) => (n.nodeType === 3 ? 0 : (n.tag === tag ? 1 : 0) + n.kids.reduce((s, k) => s + count(k, tag), 0));
JS
    for f in "$WEB/shared/dom.js" "$WEB/lib/charts.js" "$WEB/lib/mlinux-view.js"; do
      sed -E '/^import /d; s/^export (function|const|let|class) /\1 /; /^export \{/d' "$f"; done
    printf 'const OLD = %s;\nconst NEW = %s;\n' "$(cat "$W/old.json")" "$(cat "$W/new.json")"
    cat <<'JS'
const opts = { showMachines: true, contest: { start: 1000, end: 1000 + 5 * 3600 }, link: { mode: 'ua', coverage: 100 } };
const render = (a) => { const r = new N('root'); mlinuxSections(a, opts).forEach((s) => r.append(s)); return r; };
const o = render(OLD), n = render(NEW);
print('OLD_TEXT ' + o.textContent.replace(/\s+/g, ' '));
print('NEW_TEXT ' + n.textContent.replace(/\s+/g, ' '));
print('OLD_TH ' + count(o, 'th') + ' NEW_TH ' + count(n, 'th'));
JS
  } > "$W/$1.js"; gjs "$W/$1.js" > "$W/$1.out" 2> "$W/$1.err"; }
mk pt; mk en

pass=0; fail=0; ck(){ if eval "$2"; then echo "  ok: $1"; ((pass++)); else echo "  FAIL: $1"; ((fail++)); fi; }
o(){ grep "^OLD_TEXT" "$W/${2:-pt}.out" | grep -q -- "$1"; }; n(){ grep "^NEW_TEXT" "$W/${2:-pt}.out" | grep -q -- "$1"; }
echo "== renderiza sem exceção =="
ck "pt: sem erro no gjs"               '[[ ! -s "$W/pt.err" ]] && grep -q "^NEW_TEXT" "$W/pt.out"'
ck "en: sem erro no gjs"               '[[ ! -s "$W/en.err" ]] && grep -q "^NEW_TEXT" "$W/en.out"'
echo "== cache ANTIGO: a tela de antes, sem seção fantasma =="
ck "sem a seção de saúde"              '! o "Saúde das máquinas"'
ck "sem PSI em lugar nenhum da tela (fora o \"Como ler\")" '! o "PSI médio" && ! o "esperando memória"'
ck "sem modelo do equipamento"         '! o "Modelo do equipamento"'
ck "alertas: só a contagem"            'o "3 alertas" && ! o "3 alertas ("'
ck "o resto continua lá (pressão, hardware)" 'o "Pressão de memória" && o "Swap máx"'
echo "== cache NOVO: a telemetria do agente novo =="
ck "saúde com o DENOMINADOR (4 máquinas com o agente novo)" 'n "Medido em 4 máquina"'
ck "reinícios, OOM e relógio"          'n "1 máquina(s) reiniciaram" && n "2 processo(s) mortos por falta de memória, em 1 máquina" && n "1 de 4 máquinas com o relógio"'
ck "PSI médio por recurso + pico"      'n "memória 2% · CPU 1% · disco 0.5%" && n "pico de memória 3.9%"'
ck "ociosidade em % do tempo"          'n "25% do tempo"'
ck "alertas POR TIPO, com nome legível" 'n "3 alertas (pendrive ou HD externo 2 · identidade repetida 1)"'
ck "modelo do equipamento com o denominador" 'n "Modelo do equipamento (4 de 5 máquinas informam)" && n "OptiPlex 3090"'
ck "pressão: gráfico e colunas de PSI" 'n "esperando memória (PSI, %)" && n "PSI médio" && n "PSI máx"'
ck "…são 2 colunas a mais na tabela, e só no cache novo" '[[ "$(sed -n "s/^OLD_TH \([0-9]*\) NEW_TH \([0-9]*\)/\1 \2/p" "$W/pt.out" | awk "{print \$2-\$1}")" == 2 ]]'
ck "série de 10 min ganha PSI"         'n "Espera por memória (PSI, %)"'
ck "tabela de máquinas: modelo e OOM"  'n "i5-10500Dell Inc. OptiPlex 3090" && n "💥2"'
echo "== bilíngue =="
ck "en: saúde, PSI, modelo e alertas em inglês" 'n "Machine health in the contest" en && n "rebooted during the contest" en && n "Equipment model (4 of 5" en && n "USB storage 2 · duplicate identity 1" en'
ck "en: nada da seção nova ficou em português" '! n "reiniciaram" en && ! n "Medido em" en && ! n "informam" en'
echo ""; echo "RESULT: $pass passed, $fail failed"; exit $(( fail>0?1:0 ))
