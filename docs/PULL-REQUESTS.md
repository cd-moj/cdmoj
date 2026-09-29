# Pull requests — como revisar, decidir e aplicar

Este é o padrão para **todo PR nos repositórios do MOJ** (`cdmoj`, `mojtools`, `judge`, `moj-cli`), de
contribuidor de fora ou de dentro. Vale para quem mantém e para os agentes (Claude Code). Nasceu da
revisão dos PRs #33–#39 do cdmoj em 29/09/2026: ali a revisão adversária achou defeitos reais em PRs que
pareciam certos, e as decisões do mantenedor trouxeram premissas que nenhum revisor tinha.

Quem **envia** um PR: veja [Para quem contribui](#para-quem-contribui) no fim.

## Princípios

1. **Quem decide é o mantenedor, PR a PR.** Nada é aplicado, mesclado, fechado ou comentado por conta
   própria.
   - Para cada PR vai uma recomendação e o racional: aplicar como está, aplicar com mudanças, devolver ao
     contribuidor, pedir mudanças ou rejeitar.
   - Mudança grande sempre se pergunta antes.
2. **Adversário antes de opinião.** Cada PR passa por revisores cujo trabalho é tentar QUEBRÁ-LO, com
   evidência. Ler o diff e achar bonito não é revisão.
3. **Validação das recomendações.** O que o revisor concluiu passa por um validador que confere as
   afirmações que sustentam a recomendação na fonte primária (arquivo:linha, `git show`).
   - Para agentes: o advisor; se ele estiver indisponível, um agente independente, só leitura.
   - Discordância se resolve na fonte, não no voto.
4. **Nada vai ao GitHub antes de o mantenedor ver tudo pronto**: diffs, testes, rascunhos dos
   comentários.
5. **Mesclar não é deployar.** Deploy é decisão à parte, e nunca com prova no ar. Ver [DEPLOY.md](DEPLOY.md).

## 1. Levantamento

- `gh pr list`; para cada PR, `gh pr view N` (descrição, commits) e `gh pr diff N`.
- **Base do PR × master atual.** A base sai dos pais dos commits: `gh api repos/<org>/<repo>/pulls/N/commits`.
  - Um PR feito sobre master velho pode ignorar o que mudou desde então: a interface trilíngue, uma lib
    nova, uma regra de acesso.
  - Avalie a aplicabilidade SEMÂNTICA com `git diff <base> origin/master -- <arquivos do PR>`, não só
    com `gh pr diff N | git apply --check`.
- **`maintainerCanModify`**: se for `true`, os nossos ajustes vão no branch do próprio PR (ver Execução).
- **Política já decidida.** Se o PR muda uma decisão registrada, a mudança se discute com o mantenedor,
  não se resolve no código.
  - Procure com `git log -S'<termo>'` e nos commits com "decisões do Ribas" na mensagem.
  - Confira se a decisão não foi superada depois: no #35, a de 03/07 tinha sido superada em 16/07.

## 2. Revisão adversária

- **Revisores em paralelo**, só leitura, agrupados por tema: servidor, interface e o PR mais arriscado
  sozinho.
- **Cada revisor tenta quebrar** e entrega:
  - defeitos confirmados, com arquivo:linha e o caso concreto (entrada → saída de antes → saída de agora);
  - o que resistiu ao ataque;
  - o veredito: aplicar / aplicar com mudanças / rejeitar.
- **Eixos que sempre entram:**
  - **Acesso pela API, nunca só pela interface.**
    - O predicado canônico é reusado, nunca reescrito inline (`owners_visible`, `problems_denied_for`).
    - Negar com 404 quando revelar a existência já é vazamento.
    - Atenção a homonímia de login e a contest sem `owner`.
  - **Regras da casa** (`CLAUDE.md` da raiz e de cada repo):
    - interface trilíngue `T('pt','en','es')` e `data-en`/`data-es`;
    - doc no mesmo commit (API.md + `web/api/openapi.json`, OVERVIEW, FLOW, CLAUDE.md);
    - os clientes (web e `moj-cli`) acompanham a API;
    - jq 1.7 da imagem (parênteses em valor de objeto);
    - ARG_MAX (nada de agregado por `--argjson`);
    - "mexeu numa, mexa na outra" (laços duplicados, porteiro ⇄ handler bash, libs gêmeas bash ⇄ JS);
    - a fronteira do pacote de problemas;
    - sidecars em vez de slurp;
    - as regras do molde (`${BASHPID}`, `lib/sources.sh`).
  - **Premissas de produto.** Exemplo: no contest o competidor escreve o código DELE por completo; por
    isso o esqueleto de código no editor do contest foi rejeitado (#34).
  - **Testes.** O PR traz algum? Quebra um existente? Que teste falharia sem ele?

## 3. Decisão

- **Um PR por pergunta**, com o achado principal. A opção recomendada vem primeiro, e cada opção diz o
  porquê.
- **As respostas ficam registradas**, junto com a validação.
- **"Rejeitar" também tem o seu racional**, e esse racional vai para o comentário do PR.

## 4. Execução (depois da aprovação)

- **Isolamento.** O checkout de desenvolvimento do cdmoj É o servidor de dev, então nunca troque de branch
  nele. Use um worktree por PR:
  ```
  git worktree add --detach /tmp/.../wt-N origin/master
  cd /tmp/.../wt-N && gh pr checkout N
  git merge --no-edit origin/master     # o "update branch" — NUNCA rebase nem force-push no fork
  ```
- **Nossos ajustes** entram como commits NOSSOS no branch do PR.
  - Mensagem em PT, no presente, com o prefixo do componente. Ela diz o que o PR já fazia e o que foi
    completado.
  - Rodapé só com `Co-Authored-By` quando houver agente.
- **Testes que discriminam.** Rode os testes novos contra o código do PR SEM os nossos commits
  (`git stash push -- <código>`). Eles têm de falhar lá e passar com a correção.
- **Integração:** um worktree com `origin/master` mais `git merge --no-ff` de todos os PRs aprovados.
  Nele:
  - a suíte inteira com o jq do dev (1.8) E com o da imagem (1.7.1, via `PATH`): todo
    `server/test/smoke-*.sh`, mais `i18n-coverage.sh` e `sem-pacote.sh`, em paralelo;
    - ⚠ o worktree não tem o `../mojtools` irmão: exporte `MOJTOOLS_DIR=<workspace>/mojtools`;
  - `bash server/test/jq-portability.sh server` nos dois jq;
  - `node --check` numa cópia `.mjs` de cada `.js` mudado (sem a cópia, o erro de ESM passa em falso);
  - os `*.gjs.sh`.
- **Interface se confere no navegador.**
  - Uma ponte HTTP→CGI local roda o `router.sh`, com `CONTESTSDIR` de fixture: master (antes) ×
    integração (depois), Firefox headless com perfil novo.
  - Para o editor (CodeMirror), uma página de teste com o bundle real e eventos sintéticos, incluindo
    um CONTROLE que reproduz o defeito do PR.

## 5. Publicação (só com o OK do mantenedor)

1. Push dos nossos commits no branch do PR (`git push`; o `gh pr checkout` já apontou para o fork).
2. `gh pr merge N --merge`: merge commit, o padrão desde o #31/#32.
   - O contribuidor vê "Merged" e o crédito fica.
   - Não feche PR que foi incorporado.
3. Confira que `git diff <integração> origin/master` está VAZIO: o que foi ao ar é o que foi testado.
4. Comentários educados, em português, concretos (arquivo:linha e o porquê):
   - **mesclado com ajustes** → resumo do que mudou por cima e por quê;
   - **pedir mudanças** → `gh pr review N --request-changes`, com checklist ou desenho;
   - **rejeitado** → `gh pr close N --comment …`, com o motivo e o convite para uma issue se a ideia puder
     voltar de outra forma;
   - **como veio** → agradecimento curto dizendo o que foi conferido.
5. Depois:
   - `git pull --ff-only` no checkout;
   - remover os worktrees, os branches `pr/*` locais e as refs temporárias;
   - registrar o que entrou, o que aguarda o contribuidor e o deploy pendente.

## Para quem contribui

Um PR entra mais rápido quando:

- **É feito sobre o master ATUAL.** Faça rebase antes de abrir: PR sobre master velho costuma conflitar.
- **Tem string nova de interface nos três idiomas:** `T('pt','en','es')` no JS e `data-en` + `data-es`
  no HTML. O `server/test/i18n-coverage.sh` reprova o que faltar. O glossário do espanhol está em
  [I18N.md](I18N.md).
- **Atualiza a doc no mesmo commit** quando muda rota, campo, formato ou fluxo: [API.md](API.md) e
  `web/api/openapi.json`, [PACOTE.md](PACOTE.md), [OVERVIEW.md](OVERVIEW.md), [FLOW.md](FLOW.md).
- **Traz teste**: um `server/test/smoke-*.sh`, ou um `*.gjs.sh` para lógica de interface. O teste falha
  sem a mudança e passa com ela.
- **Não reescreve regra de acesso.** Reusa o predicado que já existe (`owners_visible`,
  `problems_denied_for`).
- **Não muda uma decisão registrada sem abrir a discussão antes**, numa issue. O mesmo vale para uma
  premissa de produto. Exemplos: o sorteio de contest só com problemas públicos; o editor do contest
  vazio.
- **Roda o que a revisão vai rodar:** `bash -n` nos `.sh`, `node --check` (via `.mjs`) nos `.js`,
  `jq-portability.sh`, e os smokes do que tocou.
