# bancada-plan.awk — plano DETERMINÍSTICO de submissões da bancada (ver BANCADA.md).
#
# Gera uma linha por submissão:  t_off \t team_idx \t prob_idx \t verdict
# seguindo uma ESCADARIA de platôs (taxa em subs/min, duração fixa) — não se comprime
# taxa, trunca-se duração: cada platô mede taxa e inclinação de backlog em regime.
# Mesmo seed ⇒ saída byte-idêntica (o report imprime o sha256; runs só comparam com
# sha igual). Mix de veredictos ≈ o da Maratona (32% AC / 45% WA / 15% TLE / 5% CE /
# 3% RTE).
#
# vars (-v): seed=42  teams=300  np=14  plateaus="40,60,80,100,120"  dur=180  scale=1
BEGIN {
  if (seed == "") seed = 42
  if (teams == "") teams = 300
  if (np == "") np = 14
  if (plateaus == "") plateaus = "40,60,80,100,120"
  if (dur == "") dur = 180
  if (scale == "") scale = 1
  srand(seed)
  nP = split(plateaus, P, ",")
  t0 = 0
  for (i = 1; i <= nP; i++) {
    rate = P[i] * scale                # subs/min no platô
    n = int(rate * dur / 60)
    for (s = 0; s < n; s++) {
      t = t0 + int(s * dur / n)        # espaçamento uniforme dentro do platô
      team = int(rand() * teams) + 1
      prob = int(rand() * np)
      r = rand()
      v = "Accepted,100p"
      if (r >= 0.32) v = "Wrong Answer"
      if (r >= 0.77) v = "Time Limit Exceeded"
      if (r >= 0.92) v = "Compilation Error"
      if (r >= 0.97) v = "Runtime Error"
      printf "%d\t%d\t%d\t%s\n", t, team, prob, v
    }
    t0 += dur
  }
}
