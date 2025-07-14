// Estados globais (módulo)
window.sortField = window.sortField || "time";
window.sortAsc = window.sortAsc || false;
window.subFilter = window.subFilter || "ALL";
window.pollTimer = window.pollTimer || null;

window.renderSubmissionsTable = function(subs, filterProb, problems, allowLog) {
  if (!subs) return '';
  let subsF = subs.filter(sub => filterProb === "ALL" ? true : sub.probid === filterProb);
  subsF.sort((a, b) => {
    if(window.sortField==="time")
      return window.sortAsc ? a.sinceStart-b.sinceStart : b.sinceStart-a.sinceStart;
    if(window.sortField==="problem") {
      let sa = problems.find(p=>p.problem_id===a.probid)?.short_name || a.probid;
      let sb = problems.find(p=>p.problem_id===b.probid)?.short_name || b.probid;
      return window.sortAsc ? sa.localeCompare(sb) : sb.localeCompare(sa);
    }
    if(window.sortField==="verdict") {
      let va = window.normalizeVerdict(a.verdict||"");
      let vb = window.normalizeVerdict(b.verdict||"");
      return window.sortAsc ? va.localeCompare(vb) : vb.localeCompare(va);
    }
    return 0;
  });

  function getSortIcon(field) {
    if (window.sortField !== field) return "⇅";
    return window.sortAsc ? "🔼" : "🔽";
  }

  if (subsF.length === 0)
    return `<div style="color:#888;font-size:.98em;">(Nenhuma submissão ainda)</div>`;
  const lang = (window.contestLocale === "pt") ? "pt" : "en";
  let html = `<table class="res-table"><thead>
      <tr>
      <th class="sortable${window.sortField==="time"?' sorted':''}" data-sort="time">
        ${lang==="pt"?"Tempo":"Time"} <span class="sort-icon">${getSortIcon('time')}</span>
      </th>
      <th class="sortable${window.sortField==="problem"?' sorted':''}" data-sort="problem">
        ${lang==="pt"?"Problema":"Problem"} <span class="sort-icon">${getSortIcon('problem')}</span>
      </th>
      <th>${lang==="pt"?"Arquivo":"File"}</th>
      <th class="sortable${window.sortField==="verdict"?' sorted':''}" data-sort="verdict">
        ${lang==="pt"?"Resultado":"Result"} <span class="sort-icon">${getSortIcon('verdict')}</span>
      </th>
      <th>${lang==="pt"?"Data":"Date"}</th>
      ${allowLog?`<th>${lang==="pt"?"Log":"Log"}</th>`:""}
      </tr></thead><tbody>`;
  for (let s of subsF) {
    let statusClass = "";
    let vNorm = window.normalizeVerdict(s.verdict || "");
    if (vNorm === "Accepted") statusClass = "status-ok";
    else if (vNorm === "Wrong Answer" || vNorm === "RunTime Error") statusClass = "status-wrong";
    else if (vNorm === "Time Limit Exceeded") statusClass = "status-wait";
    let cellContent = s.verdict;
    if (/^(not\s*answered\s*yet|on\s*queue|running)$/i.test((s.verdict || "").trim())) {
      cellContent = `<span class="loader-animation" title="Aguardando..."></span><span>${s.verdict}</span>`;
    }
    const prob = problems.find(p=>p.problem_id===s.probid) || {};
    const fileLink = `<a class="link-btn" title="Baixar código fonte"
      href="#" onclick="downloadAuthenticated('${window.API_SOURCE}?id=${encodeURIComponent(s.subid)}&time=${encodeURIComponent(s.epoch)}','${s.subid}.txt');return false;">${s.filename}</a>`;
    let logHtml = allowLog
      ? `<button type="button" class="link-btn" title="Ver log"
        onclick="openLogAuthenticated('${window.API_LOG}?id=${encodeURIComponent(s.subid)}&time=${encodeURIComponent(s.epoch)}')">ℹ️</button>`
      : "";
    html += `<tr>
      <td>${s.sinceStart||0}</td>
      <td>${prob.short_name||s.probid}&nbsp;<span style="font-size:.93em;color:#849">${prob.full_name||s.probid}</span></td>
      <td class="nowrap">${fileLink}</td>
      <td class="trunc-status ${statusClass}" title="${(s.verdict||"").replace(/"/g,'&quot;')}">${cellContent}</td>
      <td>${typeof window.fmtDate !== "undefined" ? window.fmtDate(s.epoch, lang==="pt") : s.epoch}</td>
      ${allowLog?`<td>${logHtml}</td>`:""}
    </tr>`;
  }
  html+="</tbody></table>";
  return html;
}

window.fetchAndRenderSubmissions = async function() {
  const user = window.contestUserInfo && window.contestUserInfo.login;
  if (!user) return;
  const headers = localStorage.getItem("contest_token")
    ? {'Authorization': 'Bearer ' + localStorage.getItem("contest_token")} : {};
//  const resp = await fetch(window.API_SUBMISSIONS+encodeURIComponent(user), {headers});
  const resp = await fetch(window.API_SUBMISSIONS, {headers});
  const lines = (await resp.text()).trim().split('\n').filter(Boolean);
  window.contestSubmissionsRaw = lines.map(line=>{
    let [sinceStart, usern, probid, filename, verdict, epoch, subid] = line.split(':');
    return { sinceStart: parseInt(sinceStart,10), user: usern, probid, filename, verdict, epoch:parseInt(epoch,10), subid };
  });
  window.renderSubmissionsGeneral();
  const hasPending = window.contestSubmissionsRaw.some(s=>s && s.verdict && /^(not\s*answered\s*yet|on\s*queue|running)$/i.test(s.verdict.trim()));
  if(hasPending && !window.pollTimer) {
    window.pollTimer = setTimeout(() => { window.pollTimer=null; window.fetchAndRenderSubmissions();}, 5000+Math.random()*5000);
  }
}

window.renderSubmissionsGeneral = function() {
  let bar = `<button class="subfilter-btn${window.subFilter==="ALL"?' active':''}" data-pb="ALL">Todos</button>`;
  for(const p of window.contestProblems) {
    if(p.show!==false)
      bar += `<button class="subfilter-btn${window.subFilter===p.problem_id?' active':''}" data-pb="${p.problem_id}">${p.short_name}</button>`;
  }
  document.getElementById('subm-filter-bar').innerHTML = bar;
  document.querySelectorAll('.subfilter-btn').forEach(btn=>{
    btn.onclick = function() {
      window.subFilter = this.dataset.pb;
      window.renderSubmissionsGeneral();
    };
  });
  const allowLog = window.canViewLog;
  document.getElementById('submissions-table-container').innerHTML =
    window.renderSubmissionsTable(
      window.contestSubmissionsRaw,
      window.subFilter,
      window.contestProblems,
      allowLog
    );
  setTimeout(function(){
    document.querySelectorAll('.res-table th.sortable').forEach(th=>{
      th.onclick = function(){
        let sf = th.getAttribute('data-sort');
        if(sf) {
          window.sortAsc = (window.sortField===sf) ? !window.sortAsc : false;
          window.sortField = sf;
          window.renderSubmissionsGeneral();
          document.querySelectorAll('.res-table th').forEach(x=>x.classList.remove('sorted'));
          th.classList.add('sorted');
        }
      }
    });
  },10);
}

window.downloadAuthenticated = function(url, filename) {
  fetch(url, { headers: { 'Authorization': 'Bearer ' + localStorage.getItem("contest_token") } })
    .then(r => { if(!r.ok) throw ''; return r.blob(); })
    .then(blob => {
      const link = document.createElement('a');
      link.href = window.URL.createObjectURL(blob); link.download = filename;
      document.body.appendChild(link); link.click(); document.body.removeChild(link);
    }).catch(() => { alert("Falha ao baixar arquivo/log."); });
};
window.openLogAuthenticated = function(url) {
  fetch(url, { headers: { 'Authorization': 'Bearer ' + localStorage.getItem("contest_token") } })
    .then(r => r.text())
    .then(text => {
      const w = window.open();
      w.document.write('<pre style="font-family:monospace;white-space:pre-wrap;">' + text + '</pre>');
      w.document.close();
    });
};
