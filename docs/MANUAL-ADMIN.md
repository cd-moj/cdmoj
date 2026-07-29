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
| **📄 Documentos** | Gera, em PDF e HTML e nos dois idiomas, os três documentos impressos da prova: **informações do ambiente** (info sheet), **caderno da prova** (capa + enunciados) e **folha de time limits**. Baixa, publica para a sede e, se você quiser, vira notícia com o PDF anexo. A seção 5 explica. |
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

## 5. Documentos da prova (aba 📄 Documentos)

A aba existe para o **`.admin` e para o juiz-chefe (`.cjudge`)**, e produz os três documentos
que a prova imprime — cada um em **PDF e HTML**, em **português e inglês**:

| Documento | O que sai | De onde vêm os dados |
|---|---|---|
| **Informações do ambiente** (*info sheet*) | Versões de compilador de cada linguagem, limite de memória, tamanho de pilha, tempo limite por teste de cada problema e a tabela de linguagens aceitas. | Texto editável (Markdown) + dados vivos: `run/registry` (o que os juízes reportam), o `conf` do contest e o TL calibrado. |
| **Caderno da prova** | Capa + um enunciado por problema, na ordem das letras. Onde o problema tem **PDF próprio** no contest, é esse PDF que entra (diagramação preservada); senão o enunciado é renderizado. | `PROBS` do contest, `enunciados/<chave>.{pdf,html}` e, se faltar, o enunciado do banco. |
| **Folha de time limits** | Tabela `letra · nome · tempo limite`, com quebra por linguagem quando o TL difere entre elas, mais a **errata** que você escrever. | O TL **calibrado e servido** aos juízes (`run/tl`). |

**Fluxo, do começo ao fim**

1. **Preencha os dados** (⚙️ *Dados dos documentos*): versão do caderno (`v1.0`), nota da capa
   e errata. Salve.
2. **Ajuste a capa**, se quiser (🎨 *Capa do caderno*). São três modos, nesta ordem de
   precedência: **PDF enviado** › **texto editado** › **capa padrão**. O texto editado é
   Markdown e aceita marcadores substituídos na geração: `{{CONTEST_NAME}}`, `{{DATE}}`,
   `{{N_PROBLEMS}}`, `{{N_PAGES}}`, `{{SITES}}`, `{{VERSION}}`. Envie um PDF quando a capa for
   arte pronta do evento — ela entra como está e o resto do caderno é anexado depois dela.
3. **Ajuste o texto do info sheet**, se quiser (📝): também Markdown, com os marcadores
   `{{TOOLCHAIN}}`, `{{TL_TABLE}}`, `{{LANGS_TABLE}}`, `{{MEMLIMIT}}`, `{{STACK}}`,
   `{{CONTEST_NAME}}` e `{{DATE}}`. Apagar o texto volta ao padrão embarcado.
4. **Gere** (botão de cada linha, ou *Gerar todos (pt+en)*). Converter os PDFs leva alguns
   segundos — o caderno é o mais demorado, porque junta um PDF por problema.
5. **Confira**: cada linha tem **PDF**, **HTML** e **abrir**. Reveja antes de publicar.
6. **Publique** o que a sede pode ver. Publicar faz duas coisas: o documento passa a aparecer na
   seção **Prova** da página do contest e o `.cstaff` consegue baixá-lo em **📄 Documentos**.
   Marcando **+ notícia**, o MOJ ainda cria uma notícia com o PDF anexado.
   **Despublicar** desfaz (o link some; a notícia, se criada, continua — apague-a na aba de
   notícias se for o caso).

**Regenerou? Publique de novo não é preciso** — o link publicado aponta para o documento atual,
então gerar de novo já entrega a versão nova a quem baixar. Mas **avise a sede**: quem já
imprimiu ficou com a versão velha (é para isso que serve o campo *versão do caderno* na capa).

> ⚠️ **Enunciado não é traduzido.** PT/EN vale para a capa, os títulos, as tabelas e o info
> sheet. O corpo do enunciado sai no idioma em que foi escrito — o MOJ guarda um enunciado por
> problema, não dois. Prova bilíngue continua exigindo dois problemas (ou um enunciado que já
> traga as duas versões).

> 🔒 **Antes de publicar, o caderno é conteúdo de prova**: só `.admin` e `.cjudge` conseguem
> baixá-lo. Para todo o resto (inclusive `.cstaff` e times) a API responde **404** — não é uma
> trava de interface.

## 6. Template de usuários (habilita todas as funções)

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

## 7. Referências

- [Manual do juiz humano](MANUAL-JUIZ.html) — a operação da aba ⚖️ Avaliar e do juiz-chefe.
- [Manual do staff](MANUAL-STAFF.html) — impressão, balões, etiquetas, revelação por sede.
- [Manual do competidor](MANUAL-CONTEST.html) — o que o aluno vê (distribua com as senhas).
- [Tutorial do organizador](/treino/criar/tutorial.html) — criar o contest (wizard e CLI).
- [CLI do competidor](/contest/cli.html) — envio pelo terminal, com modo sem-Internet.
