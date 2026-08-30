/* ingest.c — o ingest-drain em C (gcc -O2). rename() atômico como o python;
 * JSON por extração de campos conhecidos (strstr — a MESMA concessão do awk/lua:
 * um parser real em C seria cJSON/jansson, lib externa). b64 manual. */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <dirent.h>
#include <time.h>

static char SPOOL[4096], DONE[4096], RRES[4096];
static const char *RUN, *CTS;
static long NOW;

static int jget(const char *s, const char *k, char *out, size_t cap) {
    char pat[128];
    snprintf(pat, sizeof pat, "\"%s\":\"", k);
    const char *p = strstr(s, pat);
    if (p) {
        p += strlen(pat);
        const char *e = strchr(p, '"');
        if (!e || (size_t)(e - p) >= cap) return 0;
        memcpy(out, p, e - p); out[e - p] = 0; return 1;
    }
    snprintf(pat, sizeof pat, "\"%s\":", k);
    p = strstr(s, pat);
    if (p) {
        p += strlen(pat);
        size_t i = 0;
        while ((*p == '-' || (*p >= '0' && *p <= '9')) && i + 1 < cap) out[i++] = *p++;
        out[i] = 0; return i > 0;
    }
    return 0;
}

static int b64v(char c) {
    if (c >= 'A' && c <= 'Z') return c - 'A';
    if (c >= 'a' && c <= 'z') return c - 'a' + 26;
    if (c >= '0' && c <= '9') return c - '0' + 52;
    if (c == '+') return 62;
    if (c == '/') return 63;
    return -1;
}
static size_t b64dec(const char *s, unsigned char *out) {
    size_t n = 0; int val = 0, bits = 0;
    for (; *s && *s != '='; s++) {
        int v = b64v(*s);
        if (v < 0) continue;
        val = (val << 6) | v; bits += 6;
        if (bits >= 8) { bits -= 8; out[n++] = (val >> bits) & 0xff; }
    }
    return n;
}

static int wr_atomic(const char *path, const void *buf, size_t n) {
    char tmp[4200];
    snprintf(tmp, sizeof tmp, "%s.tmp.c", path);
    FILE *o = fopen(tmp, "w");
    if (!o) return 0;
    fwrite(buf, 1, n, o); fclose(o);
    return rename(tmp, path) == 0;
}

static void process(const char *base) {
    char path[4600], raw[65536], buf[512];
    snprintf(path, sizeof path, "%s/%s", SPOOL, base);
    FILE *f = fopen(path, "r");
    if (!f) return;
    size_t rn = fread(raw, 1, sizeof raw - 1, f); fclose(f);
    raw[rn] = 0;
    char *nl = strchr(raw, '\n'); if (nl) *nl = 0;
    char c[256], sid[256], login[256], verdict[256];
    if (!jget(raw, "contest", c, sizeof c) || !jget(raw, "id", sid, sizeof sid) ||
        !jget(raw, "login", login, sizeof login)) return;
    if (!jget(raw, "verdict", verdict, sizeof verdict)) strcpy(verdict, "Judge Error");
    if (!strcmp(c, "_testrun")) return;
    char udir[1024], hf[1100];
    snprintf(udir, sizeof udir, "%s/%s/users/%s", CTS, c, login);
    snprintf(hf, sizeof hf, "%s/history", udir);
    f = fopen(hf, "r");
    if (!f) return;
    static char hist[1 << 20];
    size_t hn = fread(hist, 1, sizeof hist - 1, f); fclose(f);
    hist[hn] = 0;
    /* acha a linha com sufixo :sid */
    char sfx[300]; snprintf(sfx, sizeof sfx, ":%s", sid);
    size_t sl = strlen(sfx);
    char *ls = hist, *hit = NULL, *hitend = NULL;
    while (ls && *ls) {
        char *le = strchr(ls, '\n');
        size_t len = le ? (size_t)(le - ls) : strlen(ls);
        if (len >= sl && !memcmp(ls + len - sl, sfx, sl)) { hit = ls; hitend = ls + len; break; }
        ls = le ? le + 1 : NULL;
    }
    if (!hit) return;
    /* campos 1-3 + verdict + 2 últimos */
    char tempo[64], prob[128], lang[64], sube[64];
    { char save = *hitend; *hitend = 0;
      char *p1 = strchr(hit, ':'), *p2 = p1 ? strchr(p1 + 1, ':') : NULL,
           *p3 = p2 ? strchr(p2 + 1, ':') : NULL;
      char *q2 = strrchr(hit, ':'), *q1 = NULL;
      if (q2) { *q2 = 0; q1 = strrchr(hit, ':'); *q2 = ':'; }
      if (!p3 || !q1) { *hitend = save; return; }
      snprintf(tempo, sizeof tempo, "%.*s", (int)(p1 - hit), hit);
      snprintf(prob, sizeof prob, "%.*s", (int)(p2 - p1 - 1), p1 + 1);
      snprintf(lang, sizeof lang, "%.*s", (int)(p3 - p2 - 1), p2 + 1);
      snprintf(sube, sizeof sube, "%.*s", (int)(q2 - q1 - 1), q1 + 1);
      *hitend = save; }
    static char nh[1 << 20];
    int pre = (int)(hit - hist);
    size_t nn = snprintf(nh, sizeof nh, "%.*s%s:%s:%s:%s:%s:%s%s",
                         pre, hist, tempo, prob, lang, verdict, sube, sid, hitend);
    if (!wr_atomic(hf, nh, nn)) return;
    if (jget(raw, "report_html_b64", buf, sizeof buf)) {
        unsigned char dec[512];
        size_t dn = b64dec(buf, dec);
        char mf[1400]; snprintf(mf, sizeof mf, "%s/mojlog/%s.html", udir, sid);
        wr_atomic(mf, dec, dn);
    }
    /* results: cirurgia de string no JSON cru (report_html_b64 é o último campo) */
    static char res[65536];
    char *rb = strstr(raw, ",\"report_html_b64\":\"");
    size_t keep = rb ? (size_t)(rb - raw) : strlen(raw) - 1;
    size_t rn2 = snprintf(res, sizeof res, "%.*s,\"report_html\":\"mojlog/%s.html\",\"finalized_at\":%ld}",
                          (int)keep, raw, sid, NOW);
    char rf[1400];
    snprintf(rf, sizeof rf, "%s/results/%s.json", udir, sid); wr_atomic(rf, res, rn2);
    snprintf(rf, sizeof rf, "%s/%s.json", RRES, sid); wr_atomic(rf, res, rn2);
    char dst[4600]; snprintf(dst, sizeof dst, "%s/%s", DONE, base);
    rename(path, dst);
}

static int cmpstr(const void *a, const void *b) { return strcmp(*(char **)a, *(char **)b); }

int main(void) {
    RUN = getenv("RUNDIR"); CTS = getenv("CONTESTSDIR");
    if (!RUN || !CTS) return 1;
    NOW = time(NULL);
    snprintf(SPOOL, sizeof SPOOL, "%s/spool/submissions", RUN);
    snprintf(DONE, sizeof DONE, "%s/spool/submissions-done", RUN);
    snprintf(RRES, sizeof RRES, "%s/results", RUN);
    DIR *d = opendir(SPOOL);
    if (!d) return 1;
    char **names = NULL; size_t n = 0, cap = 0;
    struct dirent *e;
    while ((e = readdir(d))) {
        if (e->d_name[0] == '.') continue;
        /* campo 5 == result */
        int colon = 0; const char *p = e->d_name; const char *f5 = NULL;
        for (; *p; p++) if (*p == ':' && ++colon == 4) { f5 = p + 1; break; }
        if (!f5 || strncmp(f5, "result", 6)) continue;
        if (n == cap) { cap = cap ? cap * 2 : 1024; names = realloc(names, cap * sizeof *names); }
        names[n++] = strdup(e->d_name);
    }
    closedir(d);
    qsort(names, n, sizeof *names, cmpstr);
    for (size_t i = 0; i < n; i++) process(names[i]);
    return 0;
}
