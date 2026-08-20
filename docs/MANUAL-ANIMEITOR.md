# MOJ: Manual do telão (`.animeitor`)

Este é o manual de quem **opera o telão** de uma competição no MOJ: o placar no projetor, as
fotos e músicas que animam a virada, e a cerimônia de revelação.

> **Tutorial web com screenshots** (PT/EN): `/contest/ajuda/animeitor.html` — abre pelo botão
> **📖 Como funciona este papel** na própria tela do telão.
> **Documento técnico** (protocolo do pacote, formato BOCA, mapa de arquivos):
> [WEBCAST.md](WEBCAST.md).

## Como o papel funciona

O papel vem do **sufixo do login**: uma conta terminada em `.animeitor` é a mesa do telão. Ela é
criada pelo administrador (painel **Pessoas › Contas**); ninguém vira `.animeitor` por
auto-cadastro.

A conta existe para alimentar o telão com três coisas: o **placar** (por uma chave de streaming),
as **fotos** dos times e as **músicas** dos times. Ela fica **fora** do placar, da lista de times,
das estatísticas, dos balões e das etiquetas — não é um competidor.

O **administrador entra na mesma tela com os mesmos poderes**, pelo cartão *🎥 Telão* da Central
do painel ou pelo link em *Pessoas › Times*. Em contest com usuários compartilhados (`USERS_FROM`),
essa é a **única** porta para subir foto/música.

## Abas que você vê

| Aba | Para que serve |
|---|---|
| **Score** | O placar, **sempre descongelado** — inclusive antes de a prova começar. É o sentido do papel: quem anima a virada precisa ver a classificação real. |
| **🎥 Animeitor** | A sua mesa: chaves de streaming + fotos e músicas dos times. |
| **📊 Estatísticas** | Números da prova (submissões por problema, linguagens, linha do tempo) — bom material de intervalo. |
| **🏆 Revelação** | A cerimônia **experimental do MOJ** (ver o aviso abaixo). Disponível a **qualquer** momento para você, para ensaiar antes da plateia chegar. |
| **Sair** | Encerra a sessão. |

## ⚠ A cerimônia oficial é o Animeitor, não a página do MOJ

A página `/contest/score/reveal.html` (botão **🏆 Revelação**) é **EXPERIMENTAL**: serve para
ensaio, para uma sede pequena, ou como plano B se não der para montar o Animeitor. A cerimônia
oficial de um evento é conduzida pelo **Animeitor, de Emílio Wuerges** — o sistema que este papel
inteiro existe para alimentar.

O fluxo oficial é: **criar uma chave de streaming** (seção abaixo) → apontar o Animeitor para
aquela URL → conduzir prova e cerimônia por lá. O Animeitor busca o pacote em laço, anima a virada
e sabe segurar o congelamento até a hora da revelação.

## 🎥 Chaves de streaming

Cada chave vira uma **URL** que o sistema Animeitor (ou outro exibidor compatível) busca em laço e
recebe o pacote do placar. Cada chave declara **qual** placar serve: o geral, ou o de uma coorte
específica quando a prova tem times convidados.

1. Escolha o placar, dê um apelido à chave (`telão principal`, `transmissão YouTube`) e crie.
2. **copiar** põe a URL na área de transferência; **testar** abre para conferir que o pacote vem.
3. A tabela mostra **quantas buscas** a chave recebeu e o **último acesso com IP** — é assim que
   você sabe que o projetor está mesmo conectado.

> ⚠ **A chave abre o placar DESCONGELADO, sem login.** Quem tem a URL vê a classificação real
> durante a prova. Trate como senha: uma chave por tela e **revogue todas depois do evento**.
> Revogar é imediato (a chave passa a responder 404, e a tentativa fica registrada).

## 📷 Fotos e ♪ músicas dos times

Cada time pode ter uma **foto** (aparece quando ele resolve) e um **mp3** (toca nessa hora). A
galeria abre no filtro **⚠ Pendências** — exatamente quem ainda está sem foto ou sem música.

- **Enviar em lote** é o caminho rápido: arraste dezenas de arquivos; o **nome do arquivo é o
  login** do time (`time-alfa.jpg`, `time-alfa.mp3`). Fotos e músicas podem ir juntas.
- A **foto** é convertida e redimensionada pelo servidor (webp + miniatura). A **música** vai como
  veio e precisa ser **mp3 de verdade** (até 15 MB) — o servidor confere o arquivo, não a extensão.
- **Baixar pacote (.zip)**: tudo num arquivo (fotos, músicas e um CSV dos times) — é o que se passa
  para quem opera o exibidor.
- Os **chefes de sede** (`.cstaff`) sobem as fotos **da sede deles**. Numa prova com várias sedes,
  deixe-os recolher localmente e você só confere a lista de pendências.

### A foto/música PADRÃO

Time sem foto não quebra o espetáculo: o MOJ responde com o **padrão do contest** (e o mesmo para a
música). O cartão no topo da galeria troca esse padrão — uma imagem com a identidade do evento, uma
vinheta — ou volta ao padrão de fábrica do MOJ. **Só você e o administrador** trocam o padrão.

No pacote `.zip`, a foto padrão é copiada por time (é pequena) e a música padrão vai **uma vez** na
raiz (megabytes × mil times, não).

## Checklist da véspera

1. Crie **uma chave por tela** e teste cada URL na máquina que vai projetar.
2. Abra a galeria em **⚠ Pendências** e persiga as fotos que faltam (peça aos chefes de sede).
3. Defina a **foto e a música padrão** com a identidade do evento.
4. Baixe o **.zip** e guarde na máquina do espetáculo como plano B.
5. **Ensaie** a página de revelação e teste o som no áudio da sala.
6. Depois do evento: **revogue todas as chaves**.

## O que o `.animeitor` NÃO faz

| Tentativa | Resposta |
|---|---|
| Enviar solução / ver enunciado | Recusado (a conta não compete) |
| Fila de impressão, balões, arquivo do competidor | Recusado (é da `.staff`) |
| Etiquetas de credenciais (senhas) | Recusado (é da `.cstaff`) |
| Responder clarification / publicar notícia | Recusado |
| Foto ou música de conta de PAPEL (staff, juiz…) | Recusado — papéis não são times |
| Qualquer tela de administração | Recusado |

> ⚠ **Duas assimetrias que surpreendem**: diferente da equipe de sala, o `.animeitor` **não** vê
> documento da prova antes do início e **não** vê rodada arquivada que não foi publicada. Se
> precisar do caderno para preparar a tela, peça ao administrador para publicar.

## Tabela-resumo: telão × sede

| Ação | `.animeitor` | `.cstaff` (sede) | `.staff` (sala) |
|---|:---:|:---:|:---:|
| Ver a galeria de fotos/músicas | Todos os times | Só a sede | Só a sede |
| Enviar/trocar/remover foto e música | Sim | Sim (só a sede) | **Não** |
| Baixar o pacote `.zip` | Completo | Recortado na sede | **Não** |
| Trocar a foto/música **padrão** do contest | **Sim** | Não | Não |
| Ver/criar/revogar **chaves de webcast** | **Sim** | Não | Não |
| Placar | Sempre descongelado | Congelado | Congelado |
| Estatísticas | Sim | Não | Não |

## Ponteiros

- **[WEBCAST.md](WEBCAST.md)**: o protocolo do pacote (formato do BOCA), o que ficou diferente, o
  mapa de arquivos e as decisões técnicas.
- **[MANUAL-STAFF.md](MANUAL-STAFF.md)**: a equipe de sala e o chefe de sede — quem divide a tela
  do telão com você.
- **[MANUAL-ADMIN.md](MANUAL-ADMIN.md)**: o organizador — quem cria a sua conta e publica os
  documentos.
