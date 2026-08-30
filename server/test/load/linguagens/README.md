# Benchmark de linguagens — o MESMO ingest em awk/perl/lua/ruby/C (30/08/2026)

A pergunta do Ribas: *e se implementar em awk em vez de bash? e uma linguagem mais legal
que python? ou não vale a pena sair da casinha (bash+make+awk)?* Cada `ingest.*` replica a
semântica do `server/daemons/ingest-drain.py` (o drain da Maratona) na MESMA fixture dos
tetos (`teto-lang.sh`: 2.000 results, 300 users, history+mojlog+results+done); o harness
CONFERE o resultado (history substituído, N results, spool vazio) — não é benchmark de
laço vazio.

Rodar:

    bash teto-lang.sh awk-gawk bash drain-awk.sh gawk
    bash teto-lang.sh perl     perl ingest.pl
    bash teto-lang.sh lua      lua ingest.lua
    bash teto-lang.sh ruby     ruby ingest.rb
    gcc -O2 -o /tmp/ingest-c ingest.c && bash teto-lang.sh C /tmp/ingest-c
    bash teto-lang.sh python   python3 ../../../daemons/ingest-drain.py

Resultados e leitura: seção "awk, make e a casinha" de `../AVALIACAO-CPU.md`.

Concessões declaradas (importam na leitura): awk NÃO tem rename ⇒ ingest.awk grava
history/results DIRETO (sem atomicidade — desqualifica awk como escritor de verdade) e o
consumo do spool é `xargs mv` em lote; awk/lua/C extraem os campos do JSON por
regex/pattern/strstr de chaves conhecidas (aspas escapadas quebrariam) — parser REAL só em
python/ruby (C nativo) e perl (JSON::PP puro-perl, e é por isso que o perl perde).
