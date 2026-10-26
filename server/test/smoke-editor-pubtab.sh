#!/bin/bash
# smoke-editor-pubtab.sh — a aba "Publicação & Pacote" do editor (26/10/2026, pedido do Ribas): a calibração
# direcionada (os juízes por processador + os 3 botões) mora NO cartão "Validação & calibração", acima do resultado de
# cada juiz (#valpanel). Antes ela ficava no fim da aba, em "Avançado", longe do resultado que produz; o "Avançado"
# virou "Pacote do problema". O renderVal mostra o cartão quando há id (o título agora é do HTML) e o 1º Salvar o mostra
# (o id entra na assinatura de re-render). Estático (HTML + trechos do JS); o comportamento na tela foi visto no Chrome.
set -u
ROOT="$(cd "$(dirname "$(readlink -f "$0")")/../.." && pwd)"
H="$ROOT/web/problemas/editar.html"; J="$ROOT/web/problemas/editar.js"
pass=0; fail=0
ok(){ echo "  ok: $1"; pass=$((pass+1)); }
no(){ echo "  FAIL: $1"; fail=$((fail+1)); }
pub="$(awk 'index($0,"data-pane=\"pub\"")>0{f=1} f{print} f&&index($0,"</section>")>0{exit}' "$H")"
ln(){ grep -nF -- "$1" <<<"$pub" | head -1 | cut -d: -f1; }
a=$(ln 'id="calibsec"'); jp=$(ln 'id="judgePick"'); cs=$(ln 'id="calibSel"'); cp=$(ln 'id="calibPerCpu"')
ca=$(ln 'id="calibAll"'); vp=$(ln 'id="valpanel"'); co=$(ln '>Coleções (agrupamento)<'); pk=$(ln 'id="pkgInfo"')
for v in a jp cs cp ca vp co pk; do [[ -n "${!v}" ]] || { no "elemento não achado na aba ($v)"; echo "RESULT: $pass passed, $fail failed"; exit 1; }; done
(( a < jp && jp < cs && cs < cp && cp < ca && ca < vp )) && ok "juízes e botões no cartão Validação & calibração, acima do resultado" \
  || no "a calibração direcionada não está no cartão, acima do #valpanel"
(( vp < co )) && ok "o cartão vem antes das Coleções" || no "o cartão não vem antes das Coleções"
grep -qE 'data-en="Advanced"|>Avançado<' <<<"$pub" && no "a seção Avançado voltou" || ok "sem a seção Avançado"
if grep -qF '<h3 data-en="Problem package" data-es="Paquete del problema">Pacote do problema</h3>' <<<"$pub" && (( pk > co )); then
  ok "Pacote do problema é a última seção (h3)"; else no "a seção Pacote do problema não está no fim"; fi
for id in calibsec judgePick valpanel calibSel calibPerCpu calibAll; do
  [[ "$(grep -c "id=\"$id\"" "$H")" -eq 1 ]] || no "id $id repetido ou ausente"; done; ok "ids únicos"
blk="$(sed -n "${a},${vp}p" <<<"$pub")"
[[ "$(grep -o 'data-en=' <<<"$blk" | wc -l)" -eq "$(grep -o 'data-es=' <<<"$blk" | wc -l)" ]] \
  && ok "textos do cartão em pt/en/es" || no "texto do cartão sem data-en/data-es"
rv="$(awk 'index($0,"function renderVal() {")==1{f=1} f{print} f&&index($0,"// ---- pacote:")==1{exit}' "$J")"
grep -qF "const sec = \$('calibsec'); if (sec) sec.style.display = ID ? '' : 'none';" <<<"$rv" \
  && ok "renderVal mostra o cartão quando há id" || no "renderVal não controla o cartão"
grep -qF "el('h3', {}, T('Validação & calibração'" <<<"$rv" && no "renderVal ainda monta o título" || ok "o título é do HTML"
grep -qF "Ainda não validado nem calibrado" <<<"$rv" && ok "sem nada ainda: o painel diz o que fazer" || no "sem a dica do estado vazio"
grep -qE '^    id: ID,' "$J" && ok "o id entra na assinatura de re-render" || no "valRenderSig sem o id"
echo "RESULT: $pass passed, $fail failed"
(( fail == 0 ))
