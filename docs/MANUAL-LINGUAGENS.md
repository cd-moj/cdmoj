# MOJ: Enviar soluções (linguagens e entrada/saída)

Este manual virou uma **página do próprio MOJ**:

> ### 📖 [`/treino/ajuda/`](/treino/ajuda/)
> No site: pelo link **"📖 Como enviar"**, ao lado do seletor de
> linguagem, na hora de enviar a solução. **Vale dentro de um contest também**: é a única página fora
> de `/contest/` que o `contest-guard` deixa abrir no subdomínio da prova (lá ela veste o topbar do
> contest e obedece o LOCALE dele), porque o competidor precisa dela na LAN isolada.

A página ensina o mesmo que este arquivo ensinava, e é onde o conteúdo passa a viver:

1. **Entrada e saída**: o programa lê do stdin, escreve no stdout e nunca abre arquivo.
2. **A extensão é a linguagem**: pelo editor, o menu decide (o código vira `solution.<ext>`); por
   arquivo, a extensão do arquivo decide e o menu é ignorado.
3. **Tabela de linguagens**, com o `id` (que é a extensão) e a observação de cada uma.
4. **Template de código de cada linguagem**: o esqueleto que o editor entrega e uma solução completa,
   com botão de copiar.
5. **Avisos**: a classe `public` do Java, `.pl` que é Prolog e não Perl, Python que é pypy3, e a pilha
   de 128 MB.
6. **O que é recusado na porta**: extensão que a plataforma não roda (`.exe`, `.pdf`, `.zip`…) volta
   com **400 `lang_not_allowed`** e a lista do que aquele problema aceita — lista de linguagens
   vazia significa **as da plataforma** (`PLATFORM_LANGS`, o espelho de `mojtools/lang/`), nunca
   "qualquer extensão". Fonte acima de **1 MB** volta com **413 `source_too_large`**. As duas
   travas nasceram do incidente de 2026-08-19, em que um binário compilado entrou na fila e ficou
   pendente para sempre.

## Por que virou página, e não um `.md`

- **A tabela de linguagens é gerada** da lista real que o site usa para montar o menu de submissão
  (`web/shared/languages.js`). Linguagem nova aparece na ajuda sozinha, então a página **não
  envelhece**. Uma tabela escrita à mão aqui envelheceria na primeira mudança.
- O esqueleto de código mostrado é o **mesmo** campo que o editor insere: o aluno lê exatamente o que
  vai ver na tela.
- A página é **bilíngue (pt/en)**, como toda tela do MOJ. Rodamos contests com competidores de fora, e
  um manual só em português deixaria essa gente sem instrução.
- O aluno **não lê o repositório**. Ele lê o site. Servir isto como `.md` em `/docs/` fazia o browser
  baixar um arquivo de texto.

O conteúdo é `web/treino/ajuda/` (a página) e `web/treino/ajuda/exemplos.js` (as soluções completas).
Para acrescentar uma linguagem à tabela, mexa em `web/shared/languages.js`. Para acrescentar uma
solução de exemplo, **rode o código antes** e acrescente em `exemplos.js`.

## Para onde ir agora

- Como usar o **treino** no dia a dia: [MANUAL-TREINO.md](MANUAL-TREINO.md).
- Como enviar durante uma **prova**: [MANUAL-CONTEST.md](MANUAL-CONTEST.md).
- Como as linguagens são implementadas no juiz (o contrato de `lang/<lang>/`): `mojtools/README.md`.
