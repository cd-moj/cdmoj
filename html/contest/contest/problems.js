function makeBalloonSVG(color) {
  // cor em formato "#rrggbb" ou "red", etc.
  // brilho: elemento ellipse, bola principal, bico, reflexo.
  return `<svg class="balloon-svg" viewBox="0 0 42 47">
    <ellipse cx="21" cy="21" rx="18" ry="18" fill="${color}" stroke="#b2b2b2" stroke-width="2"/>
    <ellipse cx="16" cy="14" rx="5" ry="5.1" fill="#fff" fill-opacity=".55"/>
    <polygon points="18,36 24,36 21,46" fill="${color}" stroke="#b2b2b2" stroke-width="1.4" stroke-linejoin="round"/>
    <ellipse cx="14" cy="15" rx="1.4" ry="2.8" fill="#fff" fill-opacity=".30" />
    <ellipse cx="12" cy="22" rx="1.1" ry="1.5" fill="#fff" fill-opacity=".20" />
    </svg>`;
}


// Exemplo: window.balloonColors = { ... };
let expandedStates = {};
window.renderProblemsList = function(probs) {
  const list = document.getElementById('problem-list');
  const subs = window.contestSubmissionsRaw || [];
  list.innerHTML = probs.filter(p=>p.show!==false).map(p => {
    const pid = p.problem_id, sn = p.short_name, full = p.full_name;
    // Testa se existe submissão accepted:
    let accepted = subs.some(s =>
      s && s.probid === pid && s.verdict && /Accepted/i.test(s.verdict));
    // Cor do balão
    let balloonColor = "";
    if (window.balloonColors && window.balloonColors[sn]) {
      balloonColor = typeof window.balloonColors[sn] === "string"
        ? window.balloonColors[sn]
        : window.balloonColors[sn].hex;
    }
    // Define style do destaque (fundo/bola)
    let balloonStyle = accepted && balloonColor
      ? `background: ${balloonColor}; border: 2px solid #b7b7b7;color:#222;`
      : (accepted ? "background: #e2ffe9; border: 2px solid #abf7c3;" : "");
    // Ball visually
    //let balloonDot = accepted && balloonColor
    //  ? `<span class="balloon-dot" style="background:${balloonColor};"></span>`
      //  : '';
//      let balloonDot = accepted && balloonColor
//  ? `<span class="balloon">
//      <span class="balloon-bubble" style="background:${balloonColor}; border-color: ${balloonColor==='white'||balloonColor==='#FFFFFF'?'#b2b2b2':balloonColor};"></span>
//      <span class="balloon-tail" style="border-top-color:${balloonColor};"></span>
//    </span>`
//          : '';
      let balloonSVG = accepted && balloonColor
  ? makeBalloonSVG(balloonColor)
          : '';
      if(balloonColor && window.balloonColors["enableSonic"])
          balloonSVG= accepted ? `<span>${getSubmissionIcon("correct",p.problem_id)}</span>`:'';

    // Time limits
    let tltxt = "";
    const tl = p.timelimits || {};
    if (Object.keys(tl).length > 0) {
      tltxt = `<div style="margin:.8em 0;"><b>Time Limits</b>
      <table class="tl-table"><thead><tr>${Object.keys(tl).map(lang=>`<th>${lang}</th>`).join('')}</tr></thead>
      <tbody><tr>${Object.values(tl).map(v=>`<td>${v} s</td>`).join('')}</tr></tbody>
      </table></div>`;
    }
    let statementLinks = '';
    if (p.statement_html_b64)
      statementLinks += `<a href="#" class="prob-openenun" onclick="window.openStatementHTML('${pid}');return false;">HTML</a>`;
    if (p.statement_pdf_b64)
      statementLinks += `<a href="data:application/pdf;base64,${p.statement_pdf_b64}" target="_blank" class="prob-openenun">PDF</a>`;
    if (p.url)
      statementLinks += `<a href="${p.url}" target="_blank" class="prob-openenun">LINK</a>`;
    let submitform = `
      <form class="problem-submit-form" id="problem-send-${pid}" autocomplete="off" data-prob="${pid}" enctype="multipart/form-data">
        <input type="file" id="file-upload-${pid}" accept=".c,.cpp,.py,.java" required style="width:155px;">
        <button type="submit" class="submit-btn" id="sbmbt-${pid}">Enviar</button>
        <span class="problem-submit-status" id="submit-msg-${pid}" style="min-width:3em; margin-left:.9em"></span>
      </form>
    `;
    // Balloon cor visual + linha
    return `<div class="problem-acc-item${accepted ? " problem-accepted" : ""}" id="acc-${pid}" style="${balloonStyle}">
      <div class="problem-acc-row" onclick="window.expandCollapseProblem('${pid}')">
        <span class="acc-header-left" >
          <span class="acc-toggle" id="acc-toggle-${pid}">&#9654;</span>
          ${balloonSVG}
          <span style="font-weight:bold">${sn}</span>&nbsp;<span style="font-size:1.1em">${full}</span>
        </span>
        <span class="acc-header-right">
          ${statementLinks}
          ${submitform}
        </span>
      </div>
      <div class="problem-acc-detail" id="acc-detail-${pid}" style="display:none;">
        ${tltxt}
        ${p.statement_html_b64 ? `
          <span class="statement-block-toggle" onclick="window.toggleStatement('${pid}')" id="smtoggle-${pid}">
            Mostrar enunciado
          </span>
          <div class="statement-block statement-content hidecontent" id="smdiv-${pid}"></div>
        ` : ""}
      </div>
    </div>`;
  }).join('');
};
// CSS do dot
if(!document.getElementById('balloon-dot-css')) {
  const style = document.createElement("style");
  style.id = "balloon-dot-css";
  style.innerHTML = `
  .balloon-dot {
    display:inline-block; width:1.4em;height:1.4em; border-radius:1em;margin-right:.55em;vertical-align:middle;
    box-shadow:0 2px 8px #1112b488; border:2.3px solid #a2b3c7;
  }`;
  document.head.appendChild(style);
}


// Accordion: abre/fecha detalhes do problema
window.expandCollapseProblem = function(pid) {
    const row = document.getElementById('acc-detail-' + pid);
    const tgl = document.getElementById('acc-toggle-' + pid);
    if (!row || !tgl) return;
    const opened = row.style.display !== "none";
    row.style.display = opened ? "none" : "block";
      tgl.innerHTML = opened ? "&#9654;" : "&#9660;";
//    tgl.innerHTML = opened ? "➕" : "➖";
    expandedStates[tgl]=opened;
};

// Toggle statement HTML inline (como antes)
function base64DecodeUTF8(str) {
  // Decodifica base64 seguro para UTF-8
  if (typeof atob === 'function') {
    try { return decodeURIComponent(escape(atob(str))); }
    catch (e) { return atob(str); }
  }
  return Buffer.from(str, 'base64').toString('utf8');
}
function parseStatementB64(b64) {
  // Decodifica o HTML
  const htmlDecoded = base64DecodeUTF8(b64);
  // Parseia o HTML para DOM e extrai <body>, omitindo <h1 class="title">
  let innerHtml = htmlDecoded;
  try {
    let doc = (new DOMParser()).parseFromString(htmlDecoded, "text/html");
    let body = doc.body;
    if (body && body.innerHTML.trim()) {
      // Remove <h1 class="title">
      //let h1s = body.querySelectorAll('h1.title');
      //h1s.forEach(el => el.parentNode.removeChild(el));
      innerHtml = body.innerHTML;
    }
  } catch (e) {}
    return innerHtml;
}
window.toggleStatement = function(pid) {
  const div = document.getElementById("smdiv-" + pid);
  const btn = document.getElementById("smtoggle-" + pid);
  if (!div || !btn) return;
  if (div.classList.contains("hidecontent")) {
    if (!div.hasAttribute("data-rendered")) {
      const pb = window.contestProblems.find(p => p.problem_id === pid);
      if (pb && pb.statement_html_b64) {
        const htmlString = parseStatementB64(pb.statement_html_b64);
        div.innerHTML = htmlString;
      } else div.innerHTML = "<i>Indisponível</i>";
      div.setAttribute("data-rendered","1");
    }
    div.classList.remove("hidecontent");
    div.classList.add("showcontent");
    btn.textContent = window.contestLocale === "pt" ? "Esconder enunciado" : "Hide statement";
  } else {
    div.classList.add("hidecontent");
    div.classList.remove("showcontent");
    btn.textContent = window.contestLocale === "pt" ? "Mostrar enunciado" : "Show statement";
  }
};
window.openStatementHTML = function(pid) {
  const p = window.contestProblems.find(p => p.problem_id === pid);
  if (!p || !p.statement_html_b64) return;

  // Decodifica b64:
  let htmlString = base64DecodeUTF8(p.statement_html_b64);
  // Pega só <body> se existir
  let onlyBody = htmlString;
  try {
    const m = htmlString.match(/<body[^>]*>([\s\S]*?)<\/body>/i);
    if(m && m[1]) onlyBody = m[1];
  } catch(e){}

  // Agora busca o CSS pela rede
  fetch("contest-statement.css")
    .then(resp => resp.text())
    .then(css => {
      // Monta o HTML novo
      const fullHtml = `<!DOCTYPE html>
<html lang="pt-BR"><head>
  <meta charset="UTF-8"><title>Enunciado</title>
  <style>
${css}
  </style>
</head>
<body>
  <div id="statement-content" class="statement-content">${onlyBody}</div>
</body></html>`;
      const blob = new Blob([fullHtml], {type:"text/html"});
      const url = URL.createObjectURL(blob);
      window.open(url,"_blank");
      setTimeout(()=>URL.revokeObjectURL(url),60000);
    });
};
