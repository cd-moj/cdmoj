// shared/dom.js — o construtor de elementos, SEM nenhuma dependência (nem i18n, nem rede).
//
// Mora aqui (e não no ui.js) porque o ui.js importa auth/api: quem só quer montar DOM não
// pode arrastar a camada de rede junto. É o que permite reaproveitar os renderizadores de
// gráfico/estatística no RELATÓRIO OFFLINE, que é inlinado num <script> sem fetch nenhum.
// O ui.js re-exporta `el`, então os ~79 importadores antigos seguem valendo.
export function el(tag, attrs = {}, ...kids) {
  const e = document.createElement(tag);
  for (const [k, v] of Object.entries(attrs)) {
    // booleano = atributo booleano HTML: false OMITE (setAttribute('disabled', false)
    // deixaria o atributo PRESENTE = desabilitado!), true põe o atributo vazio.
    if (v == null || v === false) continue;
    if (k === 'class') e.className = v;
    else if (k === 'html') e.innerHTML = v;
    else if (k.startsWith('on') && typeof v === 'function') e.addEventListener(k.slice(2), v);
    else e.setAttribute(k, v === true ? '' : v);
  }
  for (const kid of kids.flat()) {
    if (kid == null) continue;
    e.append(kid.nodeType ? kid : document.createTextNode(String(kid)));
  }
  return e;
}
