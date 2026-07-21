# MOJ: Manual do organizador (o painel .admin do contest)

Este manual é para quem **opera** um contest: o dono da conta `.admin`. Ele explica cada aba do
painel de administração, cada opção de configuração, **como habilitar os papéis especiais**
(`.judge`, `.cjudge`, `.staff`, `.cstaff`, `.mon`), e como ligar a **correção validada por
juízes** — incluindo quantas pessoas você precisa.

> Criar o contest (wizard, problemas, contas) é o outro guia: o
> [tutorial do organizador](/treino/criar/tutorial.html). Aqui é a OPERAÇÃO, do dia da prova.

Você chega ao painel logando com a conta `.admin` do contest e clicando em **⚙ Administração**
na barra do topo.

## 1. As abas do painel

| Aba | O que faz |
|---|---|
| **📊 Situação** | O dashboard ao vivo (atualiza sozinho a cada ~12s): quem está logado, juízes de máquina online/ocupados, fila de julgamento, submissões pendentes, tarefas de impressão/balão abertas e o estado da avaliação manual. Os botões **🏆 Cerimônia de revelação** e **📦 Relatório estático** ficam aqui. |
| **✅ Pré-prova** | Checklist verde/amarelo/vermelho do que ainda bloqueia começar (problemas sem enunciado, TL não calibrado, login fechado…). Rode antes de toda prova. |
| **⚙️ Configurações** | Todas as opções do contest — a seção 2 explica uma a uma. Inclui a **⏱ Prorrogação por sede/grupo** (regras regex → novo fim; só estende, nunca encurta). |
| **📚 Problemas** | A prova em si: renomear/reordenar/remover problemas, restringir linguagens ou o pool de juízes POR problema, atualizar o enunciado a partir do banco, e **Adicionar do banco** (busca e sorteio). |
| **👥 Times** | Identidade de cada conta no placar: nome do time, país/bandeira, sede/região, universidade, brasão. Carga por CSV e "materializar matches" das regras por regex. |
| **🎨 Aparência** | Cores dos balões por problema, países/escolas por regex e filtros de região do placar. |
| **👥 Usuários & sessões** | Criar/resetar/desabilitar contas (individual e em lote), trocar a senha de todos, **sessões ativas** (alertas de multi-IP/UA, deslogar), log de acessos por dia (CSV) e download dos backups dos usuários. É AQUI que você cria as contas de papel (seção 3). |
| **🖨️ Tarefas do staff** | Panorama e ação sobre a fila de impressão + balões, desempenho por staff e o escopo de cada staff (regex por sede/sala). |
| **⚖️ Tarefas do judge** | A fila da correção manual: quem pegou cada submissão, votos, idade; decidir/resolver na hora; e a configuração do veredicto manual (opções de rótulo + matriz de auto-veredicto). |
| **🧾 Auditoria** | Feed unificado de tudo que aconteceu (ações de admin, logins, submissões, veredictos), com filtros e download CSV. |

## 2. Configurações — opção por opção

**Identidade e janela**

- **Nome** — o título exibido; o *id* (que vira o subdomínio) não muda.
- **Início / Fim** — a janela da prova. Antes do início: contagem regressiva; depois do fim: ninguém mais submete (exceto papéis de juiz). Prorrogação fina é na seção ⏱ (por regex de login — ex.: só uma sala que ficou sem luz).
- **Abertura do login** — a partir de quando o aluno consegue LOGAR (antes disso, contagem regressiva na tela de login). Útil p/ liberar o login minutos antes da largada.
- **Freeze** — congela o placar público a partir deste horário (estilo ICPC). Juízes e admin seguem vendo tudo; a revelação acontece na cerimônia.
- **Idioma** — o idioma default das telas do competidor.

**O que o aluno vê/pode**

- **Login habilitado** — desliga p/ trancar a porta (quem já está dentro continua).
- **Ver código das submissões** — o aluno rever o próprio código enviado.
- **Ver log de execução** — o relatório teste-a-teste. ⚠ Em prova valendo nota, deixar o log visível pode **vazar os testes** (o aluno vê entrada/saída) — o clássico "SHOWLOG" — desligue.
- **Editor no browser** — o editor lado a lado com o enunciado.
- **Mostrar time-limit** — exibe os TLs por linguagem no enunciado.
- **Aceitar atrasados** — permite login de conta criada depois da largada.
- **Backup** / **Impressão** — habilitam o upload de backup pelo aluno e os pedidos de impressão (que caem na fila do staff).
- **Placar anônimo** — esconde o desempenho individual (só a posição do próprio aluno).
- **Gate de login por UA** — só navegadores cuja identificação contém a substring conseguem logar (máquina de prova travada). Papéis privilegiados são isentos.
- **🕵️ SUPER SECRETO** — o contest some da home/arquivo/status e até o placar exige login. Para provas que não podem nem constar que existem.

**Julgamento**

- **Linguagens** — a lista permitida no contest (cada problema pode restringir mais, na aba Problemas).
- **Pool de juízes (máquinas)** — quais MÁQUINAS de julgamento atendem este contest (vazio = qualquer juiz online). Não confundir com juízes HUMANOS (seção 4).
- **Veredicto manual** — liga a **correção validada por juízes humanos** (seção 4).
- **Nº de juízes que validam cada veredicto** — o quórum da correção manual: **1 a 5, padrão 2**. Com 1, um único voto decide (revisão simples); com N≥2, o veredicto só sai com N votos **unânimes** — qualquer divergência vira conflito p/ o juiz-chefe.
- **Penalidade (ICPC)** — minutos somados por tentativa não aceita antes do Accepted (padrão 20) e QUAIS veredictos penalizam (padrão wa/tle/mle/rte/ce; vazio = nada penaliza).
- **Placar completo p/ logins** — allowlist de logins que veem o placar sem freeze (além de admin/juízes).

Pela CLI, tudo isso é `moj contest -c <cid> settings set chave=valor` (ex.:
`settings set manual_verdict=true review_judges=3`).

## 3. Papéis especiais — o que são e como habilitar

**Habilitar um papel é só criar a conta com o sufixo certo no login** — na aba *Usuários &
sessões* (ou `moj contest -c <cid> users add fulano.judge`). Não há caixinha de permissão: o
sufixo É o papel. O auto-cadastro público nunca cria conta com esses sufixos (reservados), e
operações em massa (reset de senha, desabilitar) **pulam** contas privilegiadas de propósito.

| Papel | Sufixo | Pode | Não pode |
|---|---|---|---|
| **Administrador** | `.admin` | Tudo: painel ⚙, submeter a qualquer hora, ver problemas antes da largada, placar sem freeze, votar como juiz, resolver conflitos, responder clarifications. | Aparecer no placar (nenhum papel aparece). |
| **Juiz (humano)** | `.judge` | Aba **⚖️ Avaliar** (correção manual), submeter/ver problemas a qualquer hora (testar a prova!), placar sem freeze, responder clarifications, Estatísticas. | Resolver conflitos; painel admin. |
| **Juiz-chefe** | `.cjudge` | Tudo do `.judge` **+** painel **👑 Juiz-chefe**: resolver conflitos de votos, editar respostas de clarification já dadas, opções e auto-veredicto. | Painel admin (Configurações etc.). |
| **Staff** | `.staff` | Fila de **🖨️ impressão e balões** (pegar/imprimir/entregar, modo automático de quiosque). | Ver problemas ou submeter (nunca); etiquetas; placar sem freeze. |
| **Chefe de sede** | `.cstaff` | Observar a fila do staff da sua sede (somente leitura), **🏷️ Etiquetas** de credenciais (com senha!) da sua sede, e a **🏆 revelação por sede** depois do fim. | Agir na fila de impressão; ver problemas/submeter; não herda `.staff`. |
| **Monitor** | `.mon` | Submeter DURANTE a prova (sem aparecer no placar), **responder clarifications**, Todas as Submissões e Estatísticas. | Ver problemas antes da largada; correção manual. |

Regra de ouro: **nenhuma conta com sufixo de papel entra no placar ou nas estatísticas** —
crie quantas precisar sem medo de sujar o resultado.

## 4. Correção validada por juízes (veredicto manual)

Com **Veredicto manual** ligado, o julgamento automático continua rodando, mas o veredicto
fica **retido**: o aluno vê a submissão pendente até juízes humanos validarem.

O fluxo, na aba **⚖️ Avaliar** (página do `.judge`):

1. O juiz **pega** uma submissão da fila (reserva com prazo; máx. N juízes na mesma).
2. Vê o veredicto computado, o log e o código, e **vota** (confirmar ou trocar o rótulo).
3. Quando **N votos unânimes** se acumulam (N = *Nº de juízes que validam*, padrão 2), o
   veredicto é liberado: entra no histórico do aluno e no placar na hora.
4. Votos **divergentes** viram **conflito**: o **juiz-chefe** (`.cjudge`) decide no painel dele
   (um alerta global avisa).

**Quantas pessoas você precisa?** No mínimo **N contas `.judge`** (o quórum) **+ 1 `.cjudge`**
para conflitos — e recomendo **N+1 juízes** para a fila não travar quando alguém pausa.
O `.admin` também vota (conta como juiz), mas em prova grande deixe o admin livre p/ operar.
Com **N=1** um único juiz revisa tudo (bom p/ prova pequena); N=2 é o padrão equilibrado;
N≥3 é para finais onde o veredicto precisa de banca.

## 5. Template de usuários (habilita todas as funções)

Cole na carga em lote da aba *Usuários & sessões* (uma linha por conta: `login nome`), ou crie
um a um com `moj contest -c <cid> users add <login> --name "<nome>"`:

```
juiz1.judge      Juiz Um
juiz2.judge      Juiz Dois
juiz3.judge      Juiz Três (reserva do quórum de 2)
chefe.cjudge     Juiz Chefe
apoio1.staff     Staff de impressão e balões
sede1.cstaff     Chefe da Sede 1 (etiquetas + revelação)
monitor1.mon     Monitor (responde clarifications)
```

Depois: ligue **Veredicto manual** (e ajuste o **Nº de juízes**) nas Configurações; distribua
as senhas geradas; cada pessoa loga na MESMA tela do contest e vê os botões do seu papel.

## 6. Referências

- [Manual do juiz humano](MANUAL-JUIZ.html) — a operação da aba ⚖️ Avaliar e do juiz-chefe.
- [Manual do staff](MANUAL-STAFF.html) — impressão, balões, etiquetas, revelação por sede.
- [Manual do competidor](MANUAL-CONTEST.html) — o que o aluno vê (distribua com as senhas).
- [Tutorial do organizador](/treino/criar/tutorial.html) — criar o contest (wizard e CLI).
- [CLI do competidor](/contest/cli.html) — envio pelo terminal, com modo sem-Internet.
