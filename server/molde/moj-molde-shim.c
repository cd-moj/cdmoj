/* moj-molde-shim — ponte FastCGI ↔ worker bash persistente ("molde").
 *
 * O nginx fala FastCGI conosco (mesmo contrato do fcgiwrap: saída CGI-style com "Status:").
 * Nós NÃO forkamos+execamos um bash por requisição: cada processo-shim mantém UM bash
 * (server/api/v1/molde.sh) que sourceou as libs UMA vez e atende em loop — o custo por
 * requisição cai de exec+source (~6 ms) para um fork de subshell (~0,3 ms).
 *
 * Protocolo com o molde.sh (documentado também lá):
 *   → stdin do bash:  N records "CHAVE=VALOR\0" + record vazio "\0" (despacha)
 *   ← stdout do bash: "done <rc>\0" ao fim da requisição
 *   corpo:    $WDIR/body      (arquivo — EOF garantido p/ o `cat -` do read_body)
 *   resposta: $WDIR/resp.out  (CGI completo; streamado ao nginx APÓS o done)
 *   stderr:   $WDIR/stderr.log (arquivo — pipe de stderr de vida longa já travou worker)
 *
 * Robustez: deadline por requisição (default 310 s > fastcgi_read_timeout de 300 — o nginx
 * desiste primeiro; estouro = killpg do bash + respawn); requisição sem resposta termina o
 * stream FCGI vazio ⇒ o nginx gera 502 ⇒ `error_page 502 = @moj_fcgiwrap` faz o fallback;
 * bash reciclado pelo molde.sh a cada K requisições (saída limpa entre requisições).
 *
 * Uso: moj-molde-shim -s /caminho/socket -c N -w /dir/base [-t segundos] [-m molde.sh]
 *      moj-molde-shim --selftest   (spawna 1 molde, injeta PATH_INFO=/ e exige Status: 200
 *                                   — asserção de CAPACIDADE no build da imagem)
 */
#include <errno.h>
#include <fcntl.h>
#include <poll.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <unistd.h>
#include <fcgiapp.h>

static const char *CGI_VARS[] = {
  "SCRIPT_FILENAME", "PATH_INFO", "REQUEST_METHOD", "QUERY_STRING", "CONTENT_TYPE",
  "CONTENT_LENGTH", "HTTP_AUTHORIZATION", "HTTP_USER_AGENT", "HTTP_X_FORWARDED_FOR",
  "HTTP_X_REAL_IP", "REMOTE_ADDR", "SERVER_PROTOCOL", "GATEWAY_INTERFACE", "CONTEST_HOST",
  "HTTP_ACCEPT_ENCODING", NULL
};

static char *g_wdir = NULL;          /* dir deste worker (…/w<idx>) */
static char *g_molde = NULL;         /* caminho do molde.sh */
static int   g_timeout_s = 310;
static pid_t g_bash = -1;
static int   g_ctl = -1;             /* → stdin do bash */
static int   g_st  = -1;             /* ← stdout do bash */

static void bash_kill(void) {
  if (g_bash > 0) { kill(-g_bash, SIGKILL); waitpid(g_bash, NULL, 0); }
  g_bash = -1;
  if (g_ctl >= 0) { close(g_ctl); g_ctl = -1; }
  if (g_st  >= 0) { close(g_st);  g_st  = -1; }
}

/* spawna o bash molde com stdin=controle, stdout=status, stderr=append em arquivo */
static int bash_spawn(void) {
  int ctl[2], st[2];
  if (pipe(ctl) < 0 || pipe(st) < 0) return -1;
  pid_t pid = fork();
  if (pid < 0) return -1;
  if (pid == 0) {
    setpgid(0, 0);                                   /* grupo próprio: killpg não leva o shim */
    char errlog[4096];
    snprintf(errlog, sizeof errlog, "%s/stderr.log", g_wdir);
    int e = open(errlog, O_WRONLY | O_CREAT | O_APPEND, 0640);
    dup2(ctl[0], 0); dup2(st[1], 1);
    if (e >= 0) dup2(e, 2);
    close(ctl[0]); close(ctl[1]); close(st[0]); close(st[1]);
    if (e >= 0 && e > 2) close(e);
    setenv("MOLDE_WDIR", g_wdir, 1);
    execlp("bash", "bash", g_molde, (char *)NULL);
    _exit(127);
  }
  setpgid(pid, pid);
  close(ctl[0]); close(st[1]);
  g_bash = pid; g_ctl = ctl[1]; g_st = st[0];
  return 0;
}

static int write_all(int fd, const char *buf, size_t n) {
  while (n) {
    ssize_t w = write(fd, buf, n);
    if (w < 0) { if (errno == EINTR) continue; return -1; }
    buf += w; n -= (size_t)w;
  }
  return 0;
}

/* espera "done <rc>\0" no canal de status, com deadline. rc de retorno:
 * 0 = done recebido; -1 = bash morreu (EOF); -2 = timeout. */
static int wait_done(void) {
  char c, acc[64]; size_t n = 0;
  long left_ms = (long)g_timeout_s * 1000;
  struct pollfd p = { .fd = g_st, .events = POLLIN };
  for (;;) {
    int pr = poll(&p, 1, left_ms > 1000 ? 1000 : (int)left_ms);
    if (pr < 0) { if (errno == EINTR) continue; return -1; }
    if (pr == 0) { left_ms -= 1000; if (left_ms <= 0) return -2; continue; }
    ssize_t r = read(g_st, &c, 1);
    if (r == 0) return -1;
    if (r < 0) { if (errno == EINTR) continue; return -1; }
    if (c == '\0') return 0;
    if (n + 1 < sizeof acc) acc[n++] = c;            /* conteúdo ("done N") só p/ depuração */
  }
}

/* uma requisição FastCGI de ponta a ponta; devolve 0 se uma resposta foi enviada */
static int handle(FCGX_Request *req) {
  char path[4096];

  /* corpo → arquivo (stream; 1 GB não passa pela RAM) */
  snprintf(path, sizeof path, "%s/body", g_wdir);
  int bf = open(path, O_WRONLY | O_CREAT | O_TRUNC, 0640);
  if (bf < 0) return -1;
  char buf[65536]; int r;
  while ((r = FCGX_GetStr(buf, sizeof buf, req->in)) > 0)
    if (write_all(bf, buf, (size_t)r) < 0) { close(bf); return -1; }
  close(bf);

  /* garante bash vivo (reciclagem/morte anterior) */
  if (g_bash > 0 && waitpid(g_bash, NULL, WNOHANG) > 0) { g_bash = -1; }
  if (g_bash < 0) { bash_kill(); if (bash_spawn() < 0) return -1; }

  /* records de env + despacho */
  for (int tries = 0; tries < 2; tries++) {
    int failed = 0;
    for (int i = 0; CGI_VARS[i]; i++) {
      const char *v = FCGX_GetParam(CGI_VARS[i], req->envp);
      char rec[16384];                               /* QUERY_STRING pode chegar a ~8 KB */
      int len = snprintf(rec, sizeof rec, "%s=%s", CGI_VARS[i], v ? v : "");
      if (len >= (int)sizeof rec) len = (int)sizeof rec - 1;
      if (write_all(g_ctl, rec, (size_t)len + 1) < 0) { failed = 1; break; }
    }
    if (!failed && write_all(g_ctl, "", 1) == 0) break;     /* record vazio = despacha */
    /* bash caiu entre requisições (reciclagem): respawn e UMA nova tentativa */
    bash_kill();
    if (tries == 1 || bash_spawn() < 0) return -1;
  }

  int dr = wait_done();
  if (dr == -2) {                                    /* deadline: mata e NÃO responde nada */
    const char *pi = FCGX_GetParam("PATH_INFO", req->envp);
    const char *qs = FCGX_GetParam("QUERY_STRING", req->envp);
    fprintf(stderr, "moj-molde-shim: deadline de %ds — matando bash (pid %d) req=%s?%s\n",
            g_timeout_s, (int)g_bash, pi ? pi : "?", qs ? qs : "");
    bash_kill();
    return -1;                                       /* stream vazio ⇒ nginx 502 ⇒ fallback */
  }
  if (dr < 0) { bash_kill(); return -1; }            /* bash morreu no meio */

  /* resposta CGI completa → nginx */
  snprintf(path, sizeof path, "%s/resp.out", g_wdir);
  int rf = open(path, O_RDONLY);
  if (rf < 0) return -1;
  ssize_t rr;
  while ((rr = read(rf, buf, sizeof buf)) > 0)
    FCGX_PutStr(buf, (int)rr, req->out);
  close(rf);
  return 0;
}

static void worker(int sock) {
  FCGX_Request req;
  FCGX_Init();
  FCGX_InitRequest(&req, sock, 0);
  if (bash_spawn() < 0) _exit(1);
  /* ⚠ Accept_r < 0 NÃO é fatal: conexão abortada/envenenada (cliente 499, nginx que
   * desistiu) devolve erro e o worker TEM de seguir p/ a próxima — sair aqui foi o
   * crash-loop de 28/08 em produção ("worker N morreu — respawn" em série, com o master
   * respawnando p/ o mesmo veneno). Só desistimos com MUITOS erros consecutivos
   * (socket de escuta realmente quebrado). */
  int consec = 0;
  for (;;) {
    if (FCGX_Accept_r(&req) < 0) {
      if (++consec >= 100) { fprintf(stderr, "moj-molde-shim: accept falhou 100x seguidas\n"); break; }
      usleep(10000);
      continue;
    }
    consec = 0;
    handle(&req);
    FCGX_Finish_r(&req);
  }
}

/* --selftest: sem FastCGI — spawna o molde, injeta uma requisição sintética e exige
 * "Status: 200" no resp.out. Roda no BUILD da imagem (asserção de capacidade real). */
static int selftest(void) {
  char tmpl[] = "/tmp/molde-selftest.XXXXXX";
  g_wdir = mkdtemp(tmpl);
  if (!g_wdir) { perror("mkdtemp"); return 1; }
  char path[4096];
  snprintf(path, sizeof path, "%s/body", g_wdir);
  close(open(path, O_WRONLY | O_CREAT | O_TRUNC, 0640));   /* corpo vazio */
  if (bash_spawn() < 0) { perror("spawn"); return 1; }
  const char *kv[] = { "PATH_INFO=/", "REQUEST_METHOD=GET", "QUERY_STRING=", NULL };
  for (int i = 0; kv[i]; i++)
    if (write_all(g_ctl, kv[i], strlen(kv[i]) + 1) < 0) { perror("ctl"); return 1; }
  if (write_all(g_ctl, "", 1) < 0) { perror("despacho"); return 1; }
  g_timeout_s = 30;
  if (wait_done() != 0) { fprintf(stderr, "selftest: sem done\n"); return 1; }
  snprintf(path, sizeof path, "%s/resp.out", g_wdir);
  FILE *f = fopen(path, "r");
  char line[256] = "";
  if (f) { if (!fgets(line, sizeof line, f)) line[0] = 0; fclose(f); }
  bash_kill();
  if (strncmp(line, "Status: 200", 11) != 0) {
    fprintf(stderr, "selftest: resposta inesperada: %s\n", line);
    snprintf(path, sizeof path, "%s/stderr.log", g_wdir);
    f = fopen(path, "r");
    if (f) { while (fgets(line, sizeof line, f)) fputs(line, stderr); fclose(f); }
    return 1;
  }
  printf("selftest ok\n");
  return 0;
}

int main(int argc, char **argv) {
  const char *sock_path = NULL, *wbase = NULL;
  int nworkers = 8, do_selftest = 0, backlog = 8;
  g_molde = getenv("MOLDE_SH");
  for (int i = 1; i < argc; i++) {
    if (!strcmp(argv[i], "-s") && i + 1 < argc) sock_path = argv[++i];
    else if (!strcmp(argv[i], "-c") && i + 1 < argc) nworkers = atoi(argv[++i]);
    else if (!strcmp(argv[i], "-w") && i + 1 < argc) wbase = argv[++i];
    else if (!strcmp(argv[i], "-t") && i + 1 < argc) g_timeout_s = atoi(argv[++i]);
    else if (!strcmp(argv[i], "-b") && i + 1 < argc) backlog = atoi(argv[++i]);
    else if (!strcmp(argv[i], "-m") && i + 1 < argc) g_molde = argv[++i];
    else if (!strcmp(argv[i], "--selftest")) do_selftest = 1;
    else { fprintf(stderr, "arg desconhecido: %s\n", argv[i]); return 2; }
  }
  if (!g_molde) g_molde = "/opt/moj/cdmoj/server/api/v1/molde.sh";
  signal(SIGPIPE, SIG_IGN);

  if (do_selftest) return selftest();
  if (!sock_path || !wbase) {
    fprintf(stderr, "uso: moj-molde-shim -s socket -c N -w dir [-t s] [-m molde.sh]\n");
    return 2;
  }

  mkdir(wbase, 0750);
  unlink(sock_path);
  FCGX_Init();
  /* ⚠ BACKLOG PEQUENO É O QUEBRA-CIRCUITO DO MOLDE (incidente 28/08): com 1024, um pool
   * travado virava FILA SILENCIOSA — conexões esperavam 190 s no backlog segurando a zona
   * do limit_conn e o nginx nunca via erro nenhum (fallback só dispara com 502). Com
   * backlog mínimo, pool ocupado = connect recusado NA HORA = 502 = @moj_fcgiwrap serve.
   * O fcgiwrap é o transbordo natural — o molde nunca deve enfileirar de verdade. */
  int sock = FCGX_OpenSocket(sock_path, backlog);    /* perms vêm do umask (entrypoint: 007) */
  if (sock < 0) { fprintf(stderr, "não abriu %s\n", sock_path); return 1; }

  /* prefork + supervisão: filho morto é respawnado */
  pid_t kids[256]; if (nworkers > 256) nworkers = 256;
  for (int i = 0; i < nworkers; i++) {
    pid_t p = fork();
    if (p == 0) {
      char wd[4096]; snprintf(wd, sizeof wd, "%s/w%d", wbase, i);
      mkdir(wd, 0750); g_wdir = strdup(wd);
      worker(sock); _exit(0);
    }
    kids[i] = p;
  }
  for (;;) {
    int stx; pid_t dead = wait(&stx);
    if (dead < 0) { if (errno == EINTR) continue; sleep(1); continue; }
    for (int i = 0; i < nworkers; i++) if (kids[i] == dead) {
      fprintf(stderr, "moj-molde-shim: worker %d morreu — respawn\n", i);
      pid_t p = fork();
      if (p == 0) {
        char wd[4096]; snprintf(wd, sizeof wd, "%s/w%d", wbase, i);
        mkdir(wd, 0750); g_wdir = strdup(wd);
        worker(sock); _exit(0);
      }
      kids[i] = p;
    }
  }
}
