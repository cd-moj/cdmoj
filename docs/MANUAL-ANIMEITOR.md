# MOJ: Manual do telão (`.animeitor`)

Este é o manual de quem **opera o telão** de uma competição no MOJ: o placar no projetor, as
fotos e músicas que animam a virada, e a cerimônia de revelação.

> **Tutorial web com screenshots** (PT/EN/ES): `/contest/ajuda/animeitor.html` — abre pelo botão
> **📖 Como funciona este papel** na própria tela do telão.
> **Documento técnico**: a integração pela API do Animeitor em [ANIMEITOR.md](ANIMEITOR.md); o pacote
> legado (formato BOCA) em [WEBCAST.md](WEBCAST.md).

## Como o papel funciona

O papel vem do **sufixo do login**: uma conta terminada em `.animeitor` é a mesa do telão. Ela é
criada pelo administrador (painel **Pessoas › Contas**); ninguém vira `.animeitor` por
auto-cadastro.

A conta existe para alimentar o telão com três coisas: o **placar** (o MOJ o envia ao Animeitor pela
API — seção 📡 abaixo), as **fotos** dos times e as **músicas** dos times. Ela fica **fora** do placar, da lista de times,
das estatísticas, dos balões e das etiquetas — não é um competidor.

O **administrador entra na mesma tela com os mesmos poderes**, pelo cartão *🎥 Telão* da Central
do painel ou pelo link em *Evento › Times*. Em contest com usuários compartilhados (`USERS_FROM`),
essa é a **única** porta para subir foto/música.

## Abas que você vê

| Aba | Para que serve |
|---|---|
| **Score** | O placar, **sempre descongelado** — inclusive antes de a prova começar. É o sentido do papel: quem anima a virada precisa ver a classificação real. |
| **Animeitor** | A sua mesa: 📡 o envio ao Animeitor (placares, sedes, alimentador, conferência, reveleitor), fotos e músicas dos times e, dobradas, as chaves de streaming legadas. |
| **Estatísticas** | Números da prova (submissões por problema, linguagens, linha do tempo) — bom material de intervalo. |
| **Revelação** | A cerimônia **experimental do MOJ** (ver o aviso abaixo). Disponível a **qualquer** momento para você, para ensaiar antes da plateia chegar. |
| **Logout** | Encerra a sessão. |

## ⚠ A cerimônia oficial é o Animeitor, não a página do MOJ

A página `/contest/score/reveal.html` (botão **Revelação**) é **EXPERIMENTAL**: serve para
ensaio, para uma sede pequena, ou como plano B se não der para montar o Animeitor. A cerimônia
oficial de um evento é conduzida pelo **Animeitor, de Emílio Wuerges** — o sistema que este papel
inteiro existe para alimentar.

O fluxo oficial é a seção **📡 Animeitor (telão)** da sua mesa: o MOJ **empurra** o evento, os placares, as
submissões e o relógio ao servidor do Animeitor, e a revelação de cada sede sai de lá. O Animeitor anima a
virada e segura o congelamento até a hora da revelação.

## 📡 Animeitor pela API (o jeito atual)

1. **Conexão.** O MOJ já tem uma **chave própria no Animeitor** (a *chave do MOJ*): a tela diz "Chave do MOJ —
   não há nada a configurar". Ela nunca aparece na tela. Se o seu evento usa outro servidor do Animeitor, ou se
   você recebeu uma chave sua, abra "usar uma chave própria" e grave usuário e token — a sua vence a do MOJ, e
   "apagar e usar a chave do MOJ" volta atrás. A chave do MOJ só vale no servidor padrão.
2. **URL pública do MOJ.** É de onde o telão busca a foto e a música de cada time; confira.
3. **Placares e sedes.** O MOJ propõe o geral, um por coorte e um por país, com as sedes; ajuste nomes e
   medalhas e salve. Prova de uma sede só ganha a sede "Geral" (sem sede não há link de revelação).
4. **📡 publicar no telão** e **▶ ligar o alimentador** (relógio a cada segundo e submissões a cada 2 s). O nome
   do evento é o id do contest; um nome que já é de outro contest do MOJ é recusado.
5. **Conferência.** O MOJ pergunta ao Animeitor, sede a sede, se ele tem **todas** as submissões, com a resposta
   certa — sozinho, a cada 5 minutos durante a prova e, depois do fim, até a **conferência final**. O que faltar
   ou divergir é reenviado sozinho. A linha "Conferência" do estado diz o último resultado; **🔎 conferir agora**
   confere na hora. "✓ VALIDADO" = a prova acabou para todas as sedes, nada está em julgamento e o Animeitor
   tem tudo. Runs de times fora de qualquer sede não entram na conferência (a tela diz quantas).
6. **🎬 Liberar os links de revelação para as sedes.** Antes de liberar, a mesa confere e mostra o resultado na
   pergunta. Cada chefe de sede (e cada staff) passa a ver o link da sede dele, **com o selo da conferência**
   ("✓ Validado", "Conferido" ou "⚠"). O link mostra as respostas depois do congelamento: trate como senha.

## 🎥 Chaves de streaming (legado)

O pacote no formato do BOCA, que o Animeitor antigo buscava por chave, continua na mesa, dobrado.

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

### Em contest 🕵️ SUPER SECRETO

A galeria funciona igual: fotos e músicas continuam visíveis para quem está logado no contest
(telão, sede, administrador) — o MOJ as busca com a **sua sessão**, e quem não está logado não vê
nem ouve nada, que é o ponto do modo secreto. A única diferença que se nota é no ♪: a faixa é
baixada inteira antes de tocar (o botão mostra **⏳**), então uma música grande demora alguns
segundos para começar. Se você opera o telão nesse modo, aperte ♪ uma vez em cada faixa antes da
prova — a segunda vez toca na hora.

> Se as fotos aparecerem em branco num contest secreto, o servidor está atualizado mas o
> navegador está com a versão antiga da página em cache: recarregue com Ctrl+Shift+R.

## Ensaio geral: a véspera e o aquecimento

Muita prova roda um **aquecimento** antes da prova oficial — mesma sala, mesmas contas, mesmo
endereço. É o ensaio geral da sala e, portanto, do telão: o placar se enche de submissões de
verdade, então é a hora de apontar o projetor, rodar a chave de webcast no Animeitor **para
valer** e ver as fotos e as músicas subirem na parede. Telão testado só com placar vazio é telão
não testado.

> Nada do que você montar se perde na promoção para a prova oficial: **chaves, fotos, músicas e
> os padrões** são configuração do contest, não dado da rodada. O que é arquivado é a rodada — o
> placar e as submissões dela, que continuam acessíveis como rodada encerrada.

A lista da véspera, em ordem:

1. Confira a **conexão** (chave do MOJ ou a sua), **publique** e ligue o **alimentador**; abra o link público de
   cada placar na máquina que vai projetar.
2. Abra a galeria em **⚠ Pendências** e persiga as fotos que faltam (peça aos chefes de sede).
3. Defina a **foto e a música padrão** com a identidade do evento.
4. Baixe o **.zip** e guarde na máquina do espetáculo como plano B.
5. **Ensaie** a página de revelação e teste o som no áudio da sala.
6. Durante o **aquecimento**: ponha a tela de verdade na parede e veja-a encher — fotos, música, placar e a linha
   **Conferência** batendo.
7. Na hora da cerimônia: espere o **✓ VALIDADO** e **libere os links de revelação** para as sedes.
8. Se usou chaves de streaming legadas: **revogue todas** depois do evento.

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
| Publicar no Animeitor, alimentador, **conferência** | **Sim** | Não | Não |
| Liberar os links de revelação | **Sim** | Recebe o da sede, com o selo da conferência | Idem |
| Ver/criar/revogar **chaves de webcast** (legado) | **Sim** | Não | Não |
| Placar | Sempre descongelado | Congelado | Congelado |
| Estatísticas | Sim | Não | Não |

## Ponteiros

- **[ANIMEITOR.md](ANIMEITOR.md)**: a integração pela API (chave do MOJ, placares/sedes, alimentador,
  conferência, reveleitor) e as decisões técnicas.
- **[WEBCAST.md](WEBCAST.md)**: o protocolo do pacote legado (formato do BOCA).
- **[MANUAL-STAFF.md](MANUAL-STAFF.md)**: a equipe de sala e o chefe de sede — quem divide a tela
  do telão com você.
- **[MANUAL-ADMIN.md](MANUAL-ADMIN.md)**: o organizador — quem cria a sua conta e publica os
  documentos.
