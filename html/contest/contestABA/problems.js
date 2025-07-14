// problems.js

window.makeProblemTabs = function(probs, currProb) {
  return probs.filter(p=>p.show!==false)
    .map(p=>
      `<button type="button" class="prob-tab${p.problem_id === currProb ? " active" : ""}" data-pb="${p.problem_id}" id="tab-${p.problem_id}">
        ${p.short_name}
      </button>`
    ).join('');
};

window.makeProblemPanels = function(probs, currProb) {
  return probs.filter(p=>p.show!==false)
    .map(p => {
      const pid = p.problem_id, sn = p.short_name, full = p.full_name;
      const hasHtml = !!p.statement_html_b64, hasPdf = !!p.statement_pdf_b64;
      let tltxt = "";
      const tl = p.timelimits || {};
      if (Object.keys(tl).length > 0) {
        tltxt = `<div style="margin:1em 0; max-width:520px;"><b>Time Limits</b>
          <table class="tl-table"><thead><tr>
            ${Object.keys(tl).map(lang => `<th style="color:#196aad;">${lang}</th>`).join('')}
          </tr></thead><tbody><tr>
            ${Object.values(tl).map(v => `<td style="font-weight:bold;">${v} s</td>`).join('')}
          </tr></tbody></table></div>`;
      }
      let statementPart = "";
      if (hasHtml) {
        statementPart = `
        <span class="statement-block-toggle" onclick="window.toggleStatement('${pid}')" id="smtoggle-${pid}">
          Mostrar enunciado
        </span>
        <button type="button" onclick="window.openStatementHTML('${pid}')" class="problem-hide-btn statement-pdf-link">
          Abrir enunciado em nova aba
        </button>
        ${hasPdf ? `<a class="problem-hide-btn statement-pdf-link" href="data:application/pdf;base64,${p.statement_pdf_b64}" target="_blank">PDF</a>` : ''}
        <div class="statement-block statement-content hidecontent" id="smdiv-${pid}"></div>
        `;
      } else if (hasPdf) {
        statementPart = `<a class="problem-hide-btn statement-pdf-link"
          href="data:application/pdf;base64,${p.statement_pdf_b64}" target="_blank">PDF</a>`;
      }
      return `<div class="prob-panel${pid===currProb?' active':''}" id="panel-${pid}" data-prob="${pid}">
        <div class="problem-titlebar"><span class="problem-shortname">${sn}</span>${full}</div>
        ${statementPart}${tltxt}
      </div>`;
    }).join('');
};

// Toggle do enunciado robusto: "Mostrar"/"Esconder" sempre alterna, lazy render só uma vez.
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
  const div = document.getElementById('smdiv-' + pid);
  const btn = document.getElementById('smtoggle-' + pid);
  if (!div || !btn) return;
  if (div.classList.contains('hidecontent')) {
    if (!div.innerHTML) {
      const pb = window.contestProblems.find(p => p.problem_id === pid);
      if (pb && pb.statement_html_b64) {
        // Torna o HTML seguro e bonitão (com contest-statement.css aplicado)
        const htmlString = parseStatementB64(pb.statement_html_b64);
        div.innerHTML = htmlString;
      } else {
        div.innerHTML = "<i>Indisponível</i>";
      }
    }
    div.classList.remove('hidecontent');
    div.classList.add('showcontent');
    btn.textContent = (window.contestLocale === "pt" ? "Esconder enunciado" : "Hide statement");
  } else {
    div.classList.add('hidecontent');
    div.classList.remove('showcontent');
    btn.textContent = (window.contestLocale === "pt" ? "Mostrar enunciado" : "Show statement");
  }
};

// Abre statement HTML em nova aba incluindo o contest-statement.css externo
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
