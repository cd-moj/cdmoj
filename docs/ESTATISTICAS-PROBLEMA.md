# Estatísticas de problema: como cada métrica é computada

Este documento explica, seção por seção, como a página **Estatísticas do problema** do
Treino Livre (`/treino/problema/stats/?id=<problema>`) calcula o que mostra — incluindo as
decisões estatísticas e as limitações honestas de cada número. A fonte de verdade é o
endpoint `GET /treino/problem-stats` (contrato completo em [API.md](API.md)); esta página
descreve a **semântica**.

## De onde vêm os dados

Cada conta do treino guarda o próprio histórico de submissões (1 linha por submissão:
problema, **linguagem**, **veredicto** e **horário** em epoch). A estatística de um problema
é a agregação de todas as linhas de todos os usuários para aquele problema — **só do Treino
Livre**: submissões feitas em contests de turma não entram.

- **Só problemas públicos** têm estatística (problema privado responde 404 — prova em
  elaboração não vaza nem por existência).
- O resultado fica num **cache por evento**: ele é regenerado quando há submissão nova
  (qualquer julgamento toca um marcador global), com piso de 2 minutos sob rajada. Sem
  submissão nova, o número não muda — então o cache vale indefinidamente.
- **Veredictos** são agrupados nas famílias canônicas: `Accepted`, `Wrong Answer`,
  `Time Limit Exceeded`, `Runtime Error`, `Compilation Error` e `Outro` (o que não casa
  com nenhum prefixo conhecido). "Aceita" = veredicto que começa com `Accepted`
  (inclui `Accepted,100p` etc.).
- **Linguagens** são canonicalizadas antes de qualquer contagem: minúsculas, variantes de
  C++ (`CC`/`CXX`/`C++`/`HPP`) viram `cpp`, `H` vira `c`, e os legados `PY3`/`PY2` viram
  `py`. Por isso uma submissão `.py3` e uma `.py` contam na mesma linguagem.

## Resumo

| Métrica | Cálculo |
|---|---|
| **submissões** | total de linhas de history do problema |
| **tentaram** | usuários **distintos** com ≥1 submissão |
| **resolveram** | usuários distintos com ≥1 submissão aceita |
| **taxa de acerto** | submissões aceitas ÷ submissões totais (**por submissão**, não por usuário) |
| **subs / usuário** | submissões ÷ tentaram |
| **dificuldade** | rótulo pela taxa de acerto por submissão: ≥90% muito fácil · ≥70% fácil · ≥50% médio · <50% difícil |

Note que há **duas taxas diferentes** na página: a do Resumo é por *submissão* (mede
quanto se erra tentando); a do percentil abaixo é por *usuário* (mede quem tentou e
conseguiu). Elas contam coisas distintas de propósito.

## Percentil de dificuldade contra o acervo

O card "**X% do acervo é mais fácil que este**" compara a **taxa de sucesso por usuário**
(resolveram ÷ tentaram) deste problema com a de todos os problemas públicos do treino
(a mesma base da lista de problemas).

- **Elegibilidade**: só entram na régua problemas com **≥5 tentantes**; o percentil só é
  mostrado se a coorte elegível tem **≥10** problemas.
- **Ranking com suavização de Laplace**: a posição não usa a taxa crua, e sim
  `(resolveram + 1) ÷ (tentaram + 2)`. O motivo é empírico: uma fração grande do acervo
  tem 100% de sucesso em coortes minúsculas (5–10 tentantes), e empatadas no topo elas
  esmagavam a ponta fácil — sem a suavização, até um "olá mundo" com 33/34 saía "mais
  difícil que 45% do acervo", porque 8/8 contava como mais fácil que 33/34. Com a
  suavização, 8/8 vira 0,90 e fica **abaixo** de 33/34 = 0,944, como a intuição manda.
  Empates restantes usam *midrank* (metade conta acima, metade abaixo).
- O **tooltip** do card mostra a taxa **crua** do problema e o tamanho da coorte — a
  suavizada é só régua interna de ordenação.

## Fatos

- **primeira/última submissão** — menor/maior horário do history do problema.
- **primeiro a resolver** — o usuário cuja primeira submissão aceita tem o menor horário.
  **Privacidade**: o nome/login só aparece se o perfil da conta é público; senão o card
  mostra apenas a data.
- **dia de pico** — o dia (fuso de Brasília) com mais submissões.
- **mediana de tentativas até o aceite** — ver "Como resolvem" abaixo.
- **tempo mediano até resolver** — idem.

## Linha do tempo

- **Submissões por mês** — histograma de todas as submissões desde a primeira, em meses
  do calendário (fuso de Brasília).
- **Resolvedores acumulados** — para cada usuário que resolveu, toma-se o horário do seu
  **primeiro aceite**; a curva é a contagem acumulada desses horários (quando o problema
  "ficou popular").
- **Taxa de aceitação acumulada (%)** — soma corrente de aceitas ÷ soma corrente de
  submissões, mês a mês (a taxa "histórica até aqui" — mostra se o problema ficou mais
  fácil de acertar com o tempo, p.ex. depois de um enunciado esclarecido).

## Calendário de atividade

- Todos os dias/horas usam o fuso **America/Sao_Paulo** (o history guarda UTC; a
  conversão é feita na agregação).
- **Heatmap anual** (estilo GitHub): submissões por dia. O seletor alterna entre anos; a
  aba "**Σ todos**" soma todos os anos **por dia-do-ano** e projeta num ano bissexto (para
  o 29/02 aparecer) — é a visão de **sazonalidade**: os períodos quentes do calendário
  letivo saltam aos olhos.
- **Hora do dia × dia da semana** (punchcard): submissões por célula (dom–sáb × 0–23h),
  todos os anos somados.

## Como resolvem

- **Veredictos** — rosca com as famílias canônicas (contagem por submissão).
- **Resolvedores distintos por linguagem** — usuários distintos com aceite naquela
  linguagem (quem resolveu em C e depois em Python conta nas duas). Extensões não
  reconhecidas são fundidas em "Outros".
- **Taxa de aceitação por linguagem** — aceitas ÷ submissões daquela linguagem; só
  linguagens com **≥3 submissões** aparecem (menos que isso é ruído).
- **Submissões até o 1º aceite** — para cada usuário que resolveu, quantas submissões ele
  fez até (e incluindo) a primeira aceita; distribuição em faixas `1 · 2 · 3 · 4–5 ·
  6–10 · >10` e mediana no card de Fatos. Quem nunca resolveu não entra (é o
  `tentaram − resolveram`).
- **Tempo entre a 1ª tentativa e o aceite** — por resolvedor, o intervalo entre sua
  primeira submissão e seu primeiro aceite, em faixas `<1h · 1h–1d · 1d–1sem · >1sem`
  (mediana nos Fatos). Mede persistência: um problema pode ser "difícil de acertar de
  primeira" mas rápido de dominar, ou o contrário.
- **Editores de quem resolveu** — o editor **declarado no perfil** dos resolvedores
  (quem não declara não conta; é autorretrato, não telemetria).

## Tempo de execução (submissões aceitas)

- O "tempo" de uma submissão aceita é o do seu **teste mais lento** — a mesma definição
  do Kattis (é o número que o time-limit de fato confronta).
- Vem do registro estruturado que o juiz grava por submissão (tempos por teste, medidos
  na máquina de julgamento). **Cobertura**: só submissões julgadas na plataforma atual —
  submissões migradas do MOJ antigo não têm medição, então a distribuição começa pequena
  e **engrossa sozinha** a cada julgamento novo. A página diz quantas submissões cobre.
- **Distribuição** — histograma com faixas "redondas" (passo 1/2/5×10ᵏ, ~10 faixas).
- **Mais rápida por linguagem** — o mínimo por linguagem (barra curta = mais rápida).
- Atenção ao comparar linguagens: os tempos vêm de submissões diferentes, de máquinas de
  juiz possivelmente diferentes, e o TL do MOJ é **por linguagem** (calibrado pelas
  soluções do autor) — a comparação aqui é ilustrativa, não um benchmark controlado.

---

Contrato do endpoint (campos e formatos): [API.md](API.md), rota `/treino/problem-stats`.
A exibição de veredictos segue a política central da plataforma (fonte única
`lib/verdict.sh` — veredictos nunca são traduzidos).
