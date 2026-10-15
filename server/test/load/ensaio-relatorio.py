#!/usr/bin/env python3
"""ensaio-relatorio.py <dir> — o RELATÓRIO do ensaio de escrita: junta o lado cliente (ensaio-injetor.py: sub.csv,
req.csv, plano.csv) e o lado servidor (ensaio-sonda.sh: sonda.tsv) e diz, POR PLATÔ da escadaria:
  • taxa pedida × envios aceitos/min × veredictos/min;
  • envio→veredicto visto pelo cliente (p50/p95/máx; o poll é de 5 s, então ±5 s de resolução);
  • INCLINAÇÃO do backlog (spool + fila) — o critério da bancada: > 0 sustentado no platô ⇒ aquela taxa passa da
    capacidade; ≈ 0 ⇒ o servidor acompanha;
  • CPU do judged e da API, load, 5xx.
Depois: rotas (p50/p95/máx e BYTES — 200 com corpo vazio é falso-verde) e o mix de veredictos × intenção.
Escreve também <dir>/relatorio.md.
"""
import csv, os, statistics, sys
D = sys.argv[1]
def rd(n):
    p = os.path.join(D, n)
    return list(csv.DictReader(open(p))) if os.path.exists(p) else []
sub = rd('sub.csv'); req = rd('req.csv'); plano = rd('plano.csv')
sonda = list(csv.DictReader(open(os.path.join(D, 'sonda.tsv')), delimiter='\t')) if os.path.exists(os.path.join(D, 'sonda.tsv')) else []
def pct(v, q): v = sorted(v); return v[min(len(v) - 1, int(q * (len(v) - 1) + .5))] if v else float('nan')
def f(x, d=0.0):
    try: return float(x)
    except Exception: return d
def slope(pts):          # mínimos quadrados: unidades/minuto
    if len(pts) < 3: return float('nan')
    xs = [p[0] for p in pts]; ys = [p[1] for p in pts]; mx = statistics.mean(xs); my = statistics.mean(ys)
    den = sum((x - mx) ** 2 for x in xs)
    return float('nan') if den == 0 else 60 * sum((x - mx) * (y - my) for x, y in zip(xs, ys)) / den

L = []; P = lambda s='': L.append(s)
ok = [r for r in sub if r['http'] == '200']; seen = [r for r in ok if r['t_seen']]
lat_all = [f(r['t_seen']) - f(r['t_submit']) for r in seen]
P('# Ensaio de escrita — relatório'); P()
P(f'- envios: **{len(sub)}** · aceitos (200): {len(ok)} · 429: {sum(r["http"] == "429" for r in sub)} · '
  f'outros: {sum(r["http"] not in ("200", "429") for r in sub)}')
P(f'- veredictos vistos: **{len(seen)}/{len(ok)}** · envio→veredicto: p50 **{pct(lat_all, .5):.1f} s** · '
  f'p95 **{pct(lat_all, .95):.1f} s** · máx {max(lat_all) if lat_all else float("nan"):.1f} s')
if sonda:
    P(f'- servidor: CPU do judged máx {max(f(s["judged_cpu_pct"]) for s in sonda):.0f}% de um núcleo · API máx '
      f'{max(f(s["api_cpu_pct"]) for s in sonda):.0f}% · load máx {max(f(s["load1"]) for s in sonda):.2f} · '
      f'5xx {sum(int(f(s["nginx_5xx"])) for s in sonda)} · judged parado no máx '
      f'{max(f(s["judged_alive_age"]) for s in sonda):.0f} s'
      + (f' · tarefas de balão no fim: {int(f(sonda[-1].get("baloes", 0)))}' if 'baloes' in sonda[-1] else ''))
P()
# ---- por platô ----
marks = [(f(m['t_inicio']), f(m['taxa_min'])) for m in plano]
MIN = f(plano[0].get('minuto_s', 60), 60) if plano else 60.0   # ensaio a seco comprime: 1 "minuto" do plano = MIN s
if MIN != 60: L.append(f'_(plano comprimido: 1 min do plano = {MIN:g} s; taxas e inclinações em minutos DO PLANO)_\n')
P('## Por platô'); P()
P('| platô (subs/min) | envios aceitos/min | veredictos/min | p50 | p95 | máx | backlog (inclinação/min) | backlog máx | judged % | API % | load máx |')
P('|---|---|---|---|---|---|---|---|---|---|---|')
falta = []
for i in range(len(marks) - 1):
    a, rate = marks[i]; b = marks[i + 1][0]; dur_min = max((b - a) / MIN, 1e-9)
    s_in = [r for r in ok if a <= f(r['t_submit']) < b]
    v_out = [r for r in seen if a <= f(r['t_seen']) < b]
    lat = [f(r['t_seen']) - f(r['t_submit']) for r in s_in if r['t_seen']]
    sw = [s for s in sonda if a <= f(s['epoch']) < b]
    bl = [(f(s['epoch']), f(s['spool_s0']) + f(s['spool_s1']) + f(s['q_prova']) + f(s['q_lpriv']) + f(s['q_lpub']) + f(s['q_outras']))
          for s in sw]
    P(f'| {rate:g} | {len(s_in) / dur_min:.0f} | {len(v_out) / dur_min:.0f} | {pct(lat, .5):.1f} s | {pct(lat, .95):.1f} s | '
      f'{max(lat) if lat else float("nan"):.1f} s | {slope(bl) * MIN / 60:+.1f} | {max((y for _, y in bl), default=0):.0f} | '
      f'{statistics.mean([f(s["judged_cpu_pct"]) for s in sw]) if sw else float("nan"):.0f} | '
      f'{statistics.mean([f(s["api_cpu_pct"]) for s in sw]) if sw else float("nan"):.0f} | '
      f'{max((f(s["load1"]) for s in sw), default=float("nan")):.2f} |')
    if rate > 0 and len(s_in) / dur_min < 0.9 * rate:
        falta.append(f'{rate:g}/min (atingiu {len(s_in) / dur_min:.0f})')
P()
if falta:
    P('⚠ **taxa pedida não atingida** em: ' + '; '.join(falta) + ' — se o resumo do injetor mostra muitos "sem time '
      'livre", o limite foi o nº de times × pendentes por time (o CLIENTE), não o servidor: não conclua capacidade daí.')
    P()
# ---- rotas ----
P('## Rotas (lado cliente)'); P()
P('| rota | n | não-200 | p50 ms | p95 ms | máx ms | bytes (mediana) | 200 com 0 byte |'); P('|---|---|---|---|---|---|---|---|')
by = {}
for r in req: by.setdefault(r['rota'], []).append(r)
for rota, rs in sorted(by.items(), key=lambda kv: -len(kv[1])):
    ms = [f(r['ms']) for r in rs]; bt = [f(r['bytes']) for r in rs if r['http'] == '200']
    P(f'| {rota} | {len(rs)} | {sum(r["http"] != "200" for r in rs)} | {pct(ms, .5):.0f} | {pct(ms, .95):.0f} | {max(ms):.0f} | '
      f'{statistics.median(bt) if bt else 0:.0f} | {sum(1 for r in rs if r["http"] == "200" and f(r["bytes"]) == 0)} |')
P()
# ---- veredictos × intenção ----
P('## Veredictos × intenção'); P()
mix = {}
for r in seen: mix.setdefault(r['intent'], {}).setdefault(r['verdict'], 0); mix[r['intent']][r['verdict']] += 1
for k, v in sorted(mix.items()): P(f'- {k}: ' + ', '.join(f'{vv} {n}' for vv, n in sorted(v.items(), key=lambda x: -x[1])))
nao = [r for r in ok if not r['t_seen']]
if nao: P(f'- **sem veredicto no fim**: {len(nao)} (ex.: {", ".join(r["id"] for r in nao[:5])})')
out = '\n'.join(L) + '\n'; print(out); open(os.path.join(D, 'relatorio.md'), 'w').write(out)
