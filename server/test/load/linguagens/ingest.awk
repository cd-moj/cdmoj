# ingest.awk — o ingest-drain em awk POSIX (roda em gawk E busybox awk).
# Entrada: lista de arquivos do spool no stdin (find, 1 fork). Saída: os paths
# processados (o chamador move p/ done em LOTE com xargs mv — awk NÃO TEM rename).
# HONESTIDADE: (1) history/results gravados DIRETO (sem tmp+rename — awk não tem
# rename atômico); (2) JSON lido por REGEX de campos conhecidos (string com aspas
# escapadas quebraria — parser real em awk é o ponto fraco); (3) b64 manual.
BEGIN {
  B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
  for (i = 1; i <= 64; i++) V64[substr(B64, i, 1)] = i - 1
  RUN = ENVIRON["RUNDIR"]; CTS = ENVIRON["CONTESTSDIR"]
  NOWE = ENVIRON["NOW_EPOCH"]
}
function jget(s, k,   rest, p, m) {
  if (match(s, "\"" k "\":\"")) {
    rest = substr(s, RSTART + RLENGTH)
    p = index(rest, "\""); return substr(rest, 1, p - 1)
  }
  if (match(s, "\"" k "\":-?[0-9]+")) {
    m = substr(s, RSTART, RLENGTH); sub("\"" k "\":", "", m); return m
  }
  return ""
}
function b64dec(s,   out, i, c, val, bits) {
  out = ""; val = 0; bits = 0
  for (i = 1; i <= length(s); i++) {
    c = substr(s, i, 1)
    if (c == "=") break
    if (!(c in V64)) continue
    val = val * 64 + V64[c]; bits += 6
    if (bits >= 8) { bits -= 8; out = out sprintf("%c", int(val / 2 ^ bits) % 256) }
  }
  return out
}
{
  f = $0
  if ((getline line < f) <= 0) { close(f); next }
  close(f)
  c = jget(line, "contest"); sid = jget(line, "id"); login = jget(line, "login")
  verdict = jget(line, "verdict")
  if (c == "" || c == "_testrun" || sid == "" || login == "") next
  udir = CTS "/" c "/users/" login
  hf = udir "/history"
  n = 0; idx = 0; sfx = ":" sid
  while ((getline hl < hf) > 0) {
    H[++n] = hl
    if (substr(hl, length(hl) - length(sfx) + 1) == sfx) idx = n
  }
  close(hf)
  if (idx == 0) { for (i in H) delete H[i]; next }
  split(H[idx], F, ":")
  # prob pode conter '#' mas não ':' (id canônico); verdict antigo é campo 4..NF-2
  nf = 0; for (i in F) nf++
  H[idx] = F[1] ":" F[2] ":" F[3] ":" verdict ":" F[nf-1] ":" F[nf]
  for (i = 1; i <= n; i++) print H[i] > hf
  close(hf)
  for (i in H) delete H[i]; for (i in F) delete F[i]
  hb = jget(line, "report_html_b64")
  if (hb != "") {
    mf = udir "/mojlog/" sid ".html"
    printf "%s", b64dec(hb) > mf; close(mf)
  }
  res = line
  sub(/,"report_html_b64":"[^"]*"/, "", res)
  res = substr(res, 1, length(res) - 1) ",\"report_html\":\"mojlog/" sid ".html\",\"finalized_at\":" NOWE "}"
  rf = udir "/results/" sid ".json"
  print res > rf; close(rf)
  rf = RUN "/results/" sid ".json"
  print res > rf; close(rf)
  print f            # consumido: o chamador faz o mv em lote
}
