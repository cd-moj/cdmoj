#!/usr/bin/env python3
"""ensaio-injetor.py — o lado CLIENTE do ENSAIO DE ESCRITA (ensaio-fixture.sh / ensaio-sonda.sh; véspera da Maratona de
8/11/2026, ~800 times em 20 sedes).

Cada time é um cliente com o ritmo REAL da tela do contest (contest.js): /contest/updates a cada 30 s, /contest/score a
cada 45 s em metade dos times (aba do placar aberta) e, enquanto tem envio pendente, /contest/history a cada 5 s (a
"espiral" de 29/08: veredicto atrasa → mais poll). O .staff de cada sede pola /contest/staff/queue a cada 15 s. As
SUBMISSÕES seguem uma ESCADARIA de taxas (subs/min × minutos — a régua é 2× o pico esperado, ~125/min p/ 800 times);
cada uma é um POST /submit REAL (A+B em C/C++/Python/Java; ~55% AC, ~35% WA, ~10% CE) que os JUÍZES REAIS julgam.

Saída em --out: sub.csv (uma linha por envio: time, linguagem, intenção, t_envio, http, id, epoch do servidor,
t_veredicto_visto, veredicto), req.csv (uma linha por requisição: t, rota, http, ms, bytes — 200 com corpo vazio é
falso-verde, o tamanho prova o conteúdo) e resumo.txt. Só biblioteca padrão; threads com conexão keep-alive.

  ensaio-injetor.py --base https://zz-ensaio-800.moj.naquadah.com.br --contest zz-ensaio-800 \\
      --times ensaio-tokens-times.txt --staff ensaio-tokens-staff.txt --sols sols/ --out run1/ \\
      --plan "30:5,60:5,90:5,125:10,180:5,250:3"
Ensaio a seco (pilha local): --base http://127.0.0.1:18850 --minute 10 (um "minuto" do plano dura 10 s).
"""
import argparse, base64, csv, heapq, http.client, json, os, queue, random, ssl, statistics, sys, threading, time
from urllib.parse import urlsplit

ap = argparse.ArgumentParser()
ap.add_argument('--base', required=True); ap.add_argument('--contest', required=True)
ap.add_argument('--times', required=True); ap.add_argument('--staff', default='')
ap.add_argument('--sols', required=True); ap.add_argument('--out', required=True)
ap.add_argument('--problem', default='ribas.admin#teste-juiz')
ap.add_argument('--plan', default='30:5,60:5,90:5,125:10,180:5,250:3')
ap.add_argument('--minute', type=float, default=60.0, help='segundos por "minuto" do plano (ensaio a seco: comprime)')
ap.add_argument('--workers', type=int, default=48); ap.add_argument('--submitters', type=int, default=16)
ap.add_argument('--max-pending', type=int, default=2, help='envios pendentes por time (o teto do servidor é 3)')
ap.add_argument('--drain', type=float, default=600, help='s esperando os veredictos depois do plano')
ap.add_argument('--no-poll', action='store_true', help='só envios + history (sem updates/score/staff)')
ap.add_argument('--seed', type=int, default=42); ap.add_argument('--insecure', action='store_true')
A = ap.parse_args()
random.seed(A.seed)
os.makedirs(A.out, exist_ok=True)

def load_tokens(p):
    out = []
    if not p: return out
    for ln in open(p):
        f = ln.strip().split('\t')
        if len(f) >= 2: out.append((f[0], f[1]))
    return out
TEAMS = load_tokens(A.times); STAFF = load_tokens(A.staff)
if not TEAMS: sys.exit('sem tokens de times')
PLAN = [(float(r), float(m)) for r, m in (x.split(':') for x in A.plan.split(','))]

# --- fontes: AC = a solução de referência; WA = soma + 1; CE = sintaxe quebrada ---------------------------------------
SRC = {}
for lang, fn in (('c', 'sol.c'), ('cpp', 'sol.cpp'), ('py', 'sol.py'), ('java', 'sol.java')):
    s = open(os.path.join(A.sols, fn)).read()
    wa = s.replace('a+b', 'a+b+1').replace('a + b', 'a + b + 1')
    assert wa != s, f'não achei a soma em {fn}'
    SRC[lang] = {'AC': s, 'WA': wa, 'CE': '@@@ ensaio: erro de compilação @@@\n' + s}
FNAME = {'c': 'solucao.c', 'cpp': 'solucao.cpp', 'py': 'solucao.py', 'java': 'Main.java'}
LANGS = [('cpp', .55), ('c', .15), ('py', .20), ('java', .10)]
INTENT = [('AC', .55), ('WA', .35), ('CE', .10)]
def pick(dist):
    x = random.random(); acc = 0
    for k, w in dist:
        acc += w
        if x <= acc: return k
    return dist[-1][0]

# --- HTTP: uma conexão keep-alive por thread ---------------------------------------------------------------------------
U = urlsplit(A.base); HOST = U.hostname; PORT = U.port; HTTPS = U.scheme == 'https'
CTX = ssl.create_default_context()
if A.insecure: CTX.check_hostname = False; CTX.verify_mode = ssl.CERT_NONE
TL = threading.local()
def conn():
    c = getattr(TL, 'c', None)
    if c is None:
        c = (http.client.HTTPSConnection(HOST, PORT or 443, timeout=60, context=CTX) if HTTPS
             else http.client.HTTPConnection(HOST, PORT or 80, timeout=60))
        TL.c = c
    return c
REQ = queue.Queue()            # linhas p/ req.csv (uma thread escreve)
def http_do(method, path, tok, body=None, route=None):
    t0 = time.time(); st = 0; data = b''
    hdr = {'Authorization': 'Bearer ' + tok, 'Accept-Encoding': 'identity'}
    if body is not None: hdr['Content-Type'] = 'application/json'
    for attempt in (1, 2):
        try:
            c = conn(); c.request(method, path, body=body, headers=hdr)
            r = c.getresponse(); data = r.read(); st = r.status; break
        except Exception as e:
            try: TL.c.close()
            except Exception: pass
            TL.c = None; st = 0; data = str(e).encode()
    REQ.put((round(t0, 3), route or path.split('?')[0], st, round((time.time() - t0) * 1000, 1), len(data)))
    return st, data

# --- estado ----------------------------------------------------------------------------------------------------------
LOCK = threading.Lock()
pending = {}                   # login -> {subid: rowdict}
inflight = {}                  # login -> envios EM VOO (reservados antes do POST: dois envios simultâneos do mesmo time
                               # passavam do teto de 3 pendentes do servidor e voltavam 429 — visto no ensaio a seco)
rows = []                      # todos os envios
next_hist = {}                 # login -> quando polar o history
tok_of = dict((l, t) for t, l in TEAMS)
stats = {'sem_time_livre': 0}
T0 = time.time()

def submit_one():
    with LOCK:
        livres = [l for t, l in TEAMS if len(pending.get(l, {})) + inflight.get(l, 0) < A.max_pending]
        if not livres: stats['sem_time_livre'] += 1; return
        login = random.choice(livres); inflight[login] = inflight.get(login, 0) + 1
    lang = pick(LANGS); intent = pick(INTENT)
    code = SRC[lang][intent] + f'\n// ensaio {login} {time.time():.3f}\n' if lang != 'py' else SRC[lang][intent] + f'\n# ensaio {login} {time.time():.3f}\n'
    body = json.dumps({'problem_id': A.problem, 'filename': FNAME[lang],
                       'code_b64': base64.b64encode(code.encode()).decode()})
    t = time.time()
    st, data = http_do('POST', f'/api/v1/submit?contest={A.contest}', tok_of[login], body, '/api/v1/submit')
    row = {'login': login, 'lang': lang, 'intent': intent, 't_submit': round(t, 3), 'http': st, 'id': '', 'epoch': '',
           't_seen': '', 'verdict': ''}
    if st == 200:
        try:
            j = json.loads(data); row['id'] = str(j.get('submission_id', '')); row['epoch'] = j.get('epoch', '')
        except Exception: pass
    with LOCK:
        rows.append(row); inflight[login] -= 1
        if row['id']:
            pending.setdefault(login, {})[row['id']] = row
            next_hist[login] = min(next_hist.get(login, 1e18), time.time() + 5)

def poll_history(login):
    st, data = http_do('GET', f'/api/v1/contest/history?contest={A.contest}', tok_of[login], route='/api/v1/contest/history')
    if st != 200: return
    now = time.time()
    seen = {}
    for ln in data.decode(errors='replace').splitlines():
        f = ln.split(':')
        if len(f) < 7: continue
        subid = f[-1]; verdict = ':'.join(f[4:-2])
        seen[subid] = verdict
    with LOCK:
        for subid, row in list(pending.get(login, {}).items()):
            v = seen.get(subid)
            if v and not v.lower().startswith(('not answered', 'on queue', 'running')):
                row['t_seen'] = round(now, 3); row['verdict'] = v
                del pending[login][subid]

# --- agenda: heap de (quando, tipo, login) consumido por um pool ---------------------------------------------------
JOBS = queue.Queue(maxsize=5000)
HEAP = []; HLOCK = threading.Lock()
def sched(when, kind, who):
    with HLOCK: heapq.heappush(HEAP, (when, kind, who))
if not A.no_poll:
    for i, (t, l) in enumerate(TEAMS):
        sched(T0 + random.uniform(0, 30), 'updates', l)
        if i % 2 == 0: sched(T0 + random.uniform(0, 45), 'score', l)
    for t, l in STAFF: sched(T0 + random.uniform(0, 15), 'staff', l)
STAFF_TOK = dict((l, t) for t, l in STAFF)
STOP = threading.Event(); POLL_STOP = threading.Event()

def dispatcher():
    while not POLL_STOP.is_set():
        now = time.time()
        # history dos times com pendência (cadência da tela: 5 s)
        with LOCK:
            due = [l for l, w in next_hist.items() if w <= now and pending.get(l)]
            for l in due: next_hist[l] = now + 5
        for l in due: JOBS.put(('history', l))
        with HLOCK:
            while HEAP and HEAP[0][0] <= now:
                w, kind, who = heapq.heappop(HEAP)
                JOBS.put((kind, who))
                nxt = {'updates': 30, 'score': 45, 'staff': 15}[kind]
                heapq.heappush(HEAP, (w + nxt, kind, who))
        time.sleep(0.2)

def worker():
    while True:
        kind, who = JOBS.get()
        if kind is None: return
        if kind == 'history': poll_history(who)
        elif kind == 'updates': http_do('GET', f'/api/v1/contest/updates?contest={A.contest}&news_since=0&clar_since=0', tok_of[who], route='/api/v1/contest/updates')
        elif kind == 'score': http_do('GET', f'/api/v1/contest/score?contest={A.contest}', tok_of[who], route='/api/v1/contest/score')
        elif kind == 'staff': http_do('GET', f'/api/v1/contest/staff/queue?contest={A.contest}', STAFF_TOK[who], route='/api/v1/contest/staff/queue')

SUBQ = queue.Queue()
def submitter():
    while True:
        x = SUBQ.get()
        if x is None: return
        submit_one()

def req_writer():
    with open(os.path.join(A.out, 'req.csv'), 'w', newline='') as fh:
        w = csv.writer(fh); w.writerow(['t', 'rota', 'http', 'ms', 'bytes'])
        while True:
            x = REQ.get()
            if x is None: return
            w.writerow(x)

ths = [threading.Thread(target=worker, daemon=True) for _ in range(A.workers)]
ths += [threading.Thread(target=submitter, daemon=True) for _ in range(A.submitters)]
for t in ths: t.start()
rw = threading.Thread(target=req_writer, daemon=True); rw.start()
threading.Thread(target=dispatcher, daemon=True).start()

# --- o plano: cada segundo acumula taxa/60 envios --------------------------------------------------------------------
print(f'{len(TEAMS)} times, {len(STAFF)} staff; plano {PLAN} (1 min = {A.minute:g} s)', flush=True)
marks = []
for rate, mins in PLAN:
    t_end = time.time() + mins * A.minute; acc = 0.0; tick = 0.25
    marks.append((round(time.time(), 3), rate))
    while time.time() < t_end:
        acc += rate / 60.0 * tick * (60.0 / A.minute)
        while acc >= 1: SUBQ.put(1); acc -= 1
        time.sleep(tick)
    with LOCK: pend = sum(len(v) for v in pending.values())
    print(f'  platô {rate:g}/min feito · envios {len(rows)} · pendentes {pend}', flush=True)
marks.append((round(time.time(), 3), 0))
deadline = time.time() + A.drain
while time.time() < deadline:
    with LOCK: pend = sum(len(v) for v in pending.values())
    if pend == 0 and SUBQ.empty(): break
    time.sleep(2)
POLL_STOP.set(); time.sleep(1)
for _ in range(A.submitters): SUBQ.put(None)
for _ in range(A.workers): JOBS.put((None, None))
time.sleep(1); REQ.put(None); rw.join(5)

with open(os.path.join(A.out, 'sub.csv'), 'w', newline='') as fh:
    w = csv.DictWriter(fh, fieldnames=['login', 'lang', 'intent', 't_submit', 'http', 'id', 'epoch', 't_seen', 'verdict'])
    w.writeheader(); w.writerows(rows)
with open(os.path.join(A.out, 'plano.csv'), 'w') as fh:
    fh.write('t_inicio,taxa_min,minuto_s\n'); fh.writelines(f'{t},{r},{A.minute:g}\n' for t, r in marks)

ok = [r for r in rows if r['http'] == 200]; seen = [r for r in ok if r['t_seen']]
lat = sorted(r['t_seen'] - r['t_submit'] for r in seen)
def p(v, q): return v[min(len(v) - 1, int(q * (len(v) - 1) + .5))] if v else float('nan')
res = [f'envios: {len(rows)} · 200: {len(ok)} · 429: {sum(r["http"] == 429 for r in rows)} · outros: '
       f'{sum(r["http"] not in (200, 429) for r in rows)} · sem time livre: {stats["sem_time_livre"]}',
       f'veredictos vistos: {len(seen)}/{len(ok)} · envio→veredicto (visto pelo cliente, poll de 5 s): '
       f'p50 {p(lat, .5):.1f} s · p95 {p(lat, .95):.1f} s · máx {(lat[-1] if lat else float("nan")):.1f} s',
       'veredictos: ' + ', '.join(f'{k} {v}' for k, v in sorted(
           {v: sum(1 for r in seen if r["verdict"] == v) for v in {r["verdict"] for r in seen}}.items(), key=lambda kv: -kv[1]))]
print('\n'.join(res)); open(os.path.join(A.out, 'resumo.txt'), 'w').write('\n'.join(res) + '\n')
