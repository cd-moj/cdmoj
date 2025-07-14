let loggedInUser = null, historyOwner = null, showLogCol = false;
let historyRows = [], historySort = {key:"date",asc:false};
// --- Topbar usuário/login/logout ---
async function getAuthUser() {
    let userstat;
    try {
        userstat = await fetch('../../api/julgador/treino/auth/status/', {
            headers: localStorage.getItem("moj_token_treino") ? {"Bearer": localStorage.getItem("moj_token_treino")} : {}
        }).then(r=>r.json());
        loggedInUser = (userstat && userstat.logged_in) ? userstat.login : null;
        updateTopbarUser();
    } catch { loggedInUser=null; updateTopbarUser(); }
    return loggedInUser;
}

async function updateTopbarUser() {
    const box = document.getElementById('topbar-userbox');
    while (box.querySelector('.user-box')) box.querySelector('.user-box').remove();
    if (box.querySelector('#login-section')) box.querySelector('#login-section').remove();
    let userstat;
    try {
        userstat = await fetch('../../api/julgador/treino/auth/status/', {
            headers: getToken() ? {"Bearer": getToken()} : {}
        }).then(r=>r.json());
    } catch(e) { userstat = {logged_in:false}; }
    if (userstat.logged_in) {
        let isLogged = userstat && userstat.logged_in;
        box.insertAdjacentHTML('beforeend',
                               `<span class="user-box">
         <span class="user-box-user" title="${userstat.login}"><a href="/~ribas/treino/stat?user=${encodeURIComponent(userstat.login)}"><span style="font-weight:400;color:#888;">~${userstat.login}</span></a></span>
         <button id="logout-btn" type="button">Logout</button>
       </span>`);
        document.getElementById('logout-btn').onclick = function() {
            localStorage.removeItem('moj_token_treino');
            location.reload();
        };
        return userstat.login;
    } else {
        let isLogged = userstat && userstat.logged_in;

        box.insertAdjacentHTML('beforeend',
                               `<form id="login-section" style="display:inline;">
        <input type="text" placeholder="Usuário" name="username" required/>
        <input type="password" placeholder="Senha" name="password" required/>
        <button type="submit">Entrar</button>
        <span id="login-error"></span>
      </form>`);
        document.getElementById("login-section").onsubmit=function(e){
            if (e) e.preventDefault();
            let form = document.getElementById("login-section");
            form.querySelector("button").disabled = true;
            let login = form.username.value, pwd = form.password.value;
            fetch('../../api/julgador/treino/auth/login/', {
                method: "POST",
                body: JSON.stringify({ username: login, password: pwd }),
                headers: {"Content-Type":"application/json"}
            })
                .then(r=>r.json())
                .then(data => {
                    form.querySelector("button").disabled = false;
                    if (data.success && data.token) {
                        localStorage.setItem('moj_token_treino', data.token);
                        location.reload();
                    } else {
                        form.querySelector("#login-error").textContent = "Login inválido!";
                    }
                });
            return false;
        };
        return null;
    }
}
// --- Normalizador de veredictos para estatísticas ---
function normalizeVerdict(str) {
    str = str.trim();
    if (/^(Accepted)/i.test(str)) return "Accepted";
    if (/^(Wrong|Wrong Answer)/i.test(str)) return "Wrong Answer";
    if (/^(Time Limit)/i.test(str)) return "Time Limit Exceeded";
    if (/^(Possible Runtime|Runtime)/i.test(str)) return "RunTime Error";
    if (/^(Compilation Error|Language)/i.test(str)) return "Compilation Error";
    return str.replace(/,.*/,"").trim();
}
function formatDate(epoch) {
    if (!epoch) return '';
    const ms = Number(epoch) * 1000;
    if (isNaN(ms) || ms < 0) return '';
    const date = new Date(ms);
    if (isNaN(date.getTime())) return '';
    return date.toLocaleString("pt-BR", {
        day: "2-digit", month: "2-digit", year: "numeric",
        hour: "2-digit", minute: "2-digit"
    });
}

function getlang(sourcefile) {
    return sourcefile.substring(sourcefile.indexOf(".")+1);
}
function parseHistoryLine(line) {
    const parts = line.split(':');
    if (parts.length < 7) return null;
    const [min, login, probid, lang, verdict, epoch, subid] = parts;
    return { min, login, probid, lang, verdict, epoch:parseInt(epoch,10), subid };
}
function getToken() { return localStorage.getItem('moj_token_treino'); }
function downloadAuthenticated(url, filename) {
    fetch(url, { headers: { 'Bearer':  getToken() } })
        .then(r => { if(!r.ok) throw ''; return r.blob(); })
        .then(blob => {
            const link = document.createElement('a');
            link.href = window.URL.createObjectURL(blob);
            link.download = filename;
            document.body.appendChild(link); link.click(); document.body.removeChild(link);
        }).catch(() => { alert("Falha ao baixar arquivo/log."); });
}
function openLogAuthenticated(url) {
    fetch(url, { headers: { 'Bearer': getToken() } })
        .then(r => r.text())
        .then(text => {
            const w = window.open();
            w.document.write('<pre style="font-family:monospace;white-space:pre-wrap;">' + escapeHtml(text) + '</pre>');
            w.document.close();
        });
}
function escapeHtml(str) {
    return String(str).replace(/[<>&"']/g, s =>
        ({'<':'&lt;','>':'&gt;','&':'&amp;','"':'&quot;',"'":'&#39;'})[s]);
}

// ----------- Tabela ordenável e segura ----------
function renderUserHistoryTable(history, problems, isOwnPage) {
    // Adapta colunas
    showLogCol = isOwnPage;
    let headTr = `<tr>
    <th class="sortable" data-sort="date">Data/Hora <span class="sortind"></span></th>
    <th class="sortable" data-sort="problem">Problema <span class="sortind"></span></th>
    <th class="sortable" data-sort="lang">Linguagem <span class="sortind"></span></th>
    ${showLogCol ? `<th id="logcol-th">Log/Cód</th>` : ''}
    <th class="sortable" data-sort="status">Status <span class="sortind"></span></th>
  </tr>`;
    document.getElementById("user-history-table").querySelector("thead").innerHTML = headTr;
    // Array global para ordenação
    historyRows = history.map(sub => ({
        ...sub,
        problemTitle: (problems.find(p=>p.id===sub.probid)?.title) || sub.probid
    }));
    fillHistoryTable(historyRows, showLogCol, problems);
    setUpHistorySort();
    updateHistorySortIndicators();
}
function fillHistoryTable(rows, showLogCol, problems) {
    const tbody = document.getElementById("history-tbody");
    tbody.innerHTML = '';
    for (const sub of rows) {
        let ptitle = (problems.find(p=>p.id===sub.probid)?.title) || sub.probid;
        let statusClass = "";
        const verdictNorm = normalizeVerdict(sub.verdict);
        if (verdictNorm === "Accepted") statusClass = "status-ok";
        else if (verdictNorm === "Wrong Answer" || verdictNorm==="RunTime Error") statusClass = "status-wrong";
        else if (verdictNorm === "Time Limit Exceeded") statusClass = "status-wait";
        let cellContent = sub.verdict;
        if (/^(not\s*answered\s*yet|on\s*queue|running)$/i.test(sub.verdict.trim())) {
            cellContent = `<span class="loader-animation" title="Aguardando..."></span>
      <span style="margin-left:.6em;">${sub.verdict}</span>`;
        }
        let tdLog = showLogCol
            ? `<td>
        <button type="button" class="link-btn" title="Baixar código fonte do envio"
          onclick="downloadAuthenticated('../../api/submission/source.sh?contest=treino&id=${encodeURIComponent(sub.subid)}&time=${encodeURIComponent(sub.epoch)}','${sub.lang.toLowerCase()}')">&#128196;</button>
        <button type="button" class="link-btn" title="Ver log"
          onclick="openLogAuthenticated('../../api/submission/log.sh?contest=treino&id=${encodeURIComponent(sub.subid)}&time=${encodeURIComponent(sub.epoch)}')">ℹ️</button>
      </td>` : '';
        tbody.innerHTML += `<tr>
      <td>${formatDate(sub.epoch)}</td>
      <td>
        <a class="prob-link" href="../problem?id=${encodeURIComponent(sub.probid)}" title="${ptitle}">${ptitle}</a>
      </td>
      <td>${getlang(sub.lang)}</td>
      ${tdLog}
      <td class="trunc-status ${statusClass}" tabindex="0" title="${sub.verdict.replace(/"/g, '&quot;')}">${cellContent}</td>
    </tr>`;
    }
}

function setUpHistorySort() {
    document.querySelectorAll('.history-table th.sortable').forEach(th => {
        th.onclick = function() {
            let k = this.getAttribute("data-sort");
            if (historySort.key === k) historySort.asc = !historySort.asc; else historySort = { key:k, asc:true };
            let sorted = [...historyRows];
            sorted.sort((a,b)=>{
                if (k==="date") return historySort.asc? a.epoch-b.epoch: b.epoch-a.epoch;
                if (k==="problem") return historySort.asc
                    ? (a.problemTitle||'').localeCompare(b.problemTitle||'')
                    : (b.problemTitle||'').localeCompare(a.problemTitle||'');
                if (k==="lang") return historySort.asc
                    ? (a.lang||'').localeCompare(b.lang||'')
                    : (b.lang||'').localeCompare(a.lang||'');
                if (k==="status") {
                    let va = normalizeVerdict(a.verdict)||"";
                    let vb = normalizeVerdict(b.verdict)||"";
                    return historySort.asc? va.localeCompare(vb): vb.localeCompare(va);
                }
                return 0;
            });
            fillHistoryTable(sorted, showLogCol || false, []);
            updateHistorySortIndicators();
        }
    });
}
function updateHistorySortIndicators() {
    document.querySelectorAll('.history-table th.sortable').forEach(th => {
        const ind = th.querySelector('.sortind');
        const key = th.getAttribute('data-sort');
        if (historySort.key === key) {
            ind.textContent = historySort.asc ? " 🔼" : " 🔽";
            th.classList.add("sorted");
        } else {
            ind.textContent = " ⇅";
            th.classList.remove("sorted");
        }
    });
}

// ------------- Estatísticas das submissões -------------
// args: array de history já parseado, e array de problemas (do open_training/problems)
function processUserStats(history, problems) {
    // Map problemId => [nTentativas, nAcertos]
    const probStats = {};
    const verdictStats = {};
    const dayStats = {}; // {YYYY-MM-DD: count}
    const langStats = {}; // código: {total, acerto}
    // Marcar problemas resolvidos/tentados p/ tags
    let resolvedProblems = {}, attemptedProblems = {};
    // Por submissão
    for (let sub of history) {
        if(!probStats[sub.probid]) probStats[sub.probid] = { tried:0, accepted:0 };
        probStats[sub.probid].tried++;
        const norm = normalizeVerdict(sub.verdict);
        if(norm === "Accepted") probStats[sub.probid].accepted++;
        // Resumo p/ tags
        attemptedProblems[sub.probid]=true;
        if(norm === "Accepted") resolvedProblems[sub.probid]=true;
        // contagem global veredictos
        verdictStats[norm] = (verdictStats[norm]||0)+1;
        // submissão por dia
        let d = new Date(sub.epoch*1000);
        let dayTag = d.getFullYear()+"-"+String(d.getMonth()+1).padStart(2,"0")+"-"+String(d.getDate()).padStart(2,"0");
        dayStats[dayTag] = (dayStats[dayTag]||0)+1;
        // linguagens usadas
        if (/^(Language|Compilation Error)/i.test(sub.verdict)) continue;
        let langKey = getlang(sub.lang);
        if (!langStats[langKey]) langStats[langKey] = {total:0, acerto:0};
        langStats[langKey].total++;
        if(norm === "Accepted") langStats[langKey].acerto++;
    }
    // Estatísticas de tags por problema
    let tagStats = {};
    for (let p of problems) {
        (p.tags||[]).forEach(tgRaw => {
            const tg = tgRaw.replace(/^#+/,'');
            if (!tagStats[tg]) tagStats[tg] = {resolvidos:0, tentativas:0};
            if (resolvedProblems[p.id]) tagStats[tg].resolvidos++;
            if (attemptedProblems[p.id]) tagStats[tg].tentativas++;
        });
    }
    let problemasDistintos = Object.keys(probStats).length;
    let acertosDistintos = Object.values(probStats).filter(p=>p.accepted>0).length;
    let mediaSubPorProb = (history.length / Math.max(1, acertosDistintos)).toFixed(2);
    return {
        probStats, verdictStats, dayStats, langStats, tagStats,
        problemasDistintos, acertosDistintos, mediaSubPorProb
    };
}
// ----------- Gráficos com Chart.js ----------
function makeDaysChart(dayStats) {
    const dias = [], cont = [], now = new Date();
    for(let i=29;i>=0;--i) {
        const d = new Date(now.getFullYear(),now.getMonth(),now.getDate()-i);
        const tag = d.getFullYear()+"-"+String(d.getMonth()+1).padStart(2,"0")+"-"+String(d.getDate()).padStart(2,"0");
        dias.push(tag); cont.push(dayStats[tag]||0);
    }
    new Chart(document.getElementById('days-chart'), {
        type: 'bar',
        data: { labels: dias, datasets: [{label: "Envios", data: cont, backgroundColor:'#65b2f7'}] },
        options: { responsive:true, plugins:{legend:{display:false}}, scales:{x:{ticks:{maxTicksLimit:12}}}}
    });
}
function makeVerdictChart(vstats) {
    let lb = Object.keys(vstats);
    let colors = lb.map(v=>
        v === "Accepted" ? "#19b153" : v === "Wrong Answer" ? "#ff5252" :
            v === "Time Limit Exceeded" ? "#f2be01" :
            v === "RunTime Error" ? "#dd7626" :
            v === "Compilation Error" ? "#7f6ae6" :
            "#82a2be"
    );
    new Chart(document.getElementById('verdict-chart'), {
        type: 'doughnut',
        data: { labels: lb, datasets: [{data:Object.values(vstats), backgroundColor:colors}] },
        options: { responsive:true, plugins:{legend:{position:'right'}} }
    });
}
function makeLangPieBarCharts(langStats) {
    let langs = Object.keys(langStats), tot = langs.map(l=>langStats[l].total),
        acs = langs.map(l=> Math.round(100*langStats[l].acerto/langStats[l].total) );
    new Chart(document.getElementById('lang-pie-chart'), {
        type: 'pie',
        data: { labels:langs, datasets:[{data:tot, backgroundColor:["#608eff","#23b0de","#12d88b","#f6cd36","#6060a1","#efac56"]}] }
    });
    new Chart(document.getElementById('lang-bar-chart'), {
        type: 'bar',
        data: { labels:langs, datasets:[{label:'Acerto (%)', data:acs, backgroundColor:'#2bb941'}] },
        options: { responsive:true, plugins:{legend:{display:false}}, scales:{y:{min:0,max:100}} }
    });
}
function makeTagsPieCharts(tagStats) {
    let alltags = Object.keys(tagStats);
    const topK = 15;
    let tags = alltags.sort((a, b) =>
        tagStats[b].resolvidos - tagStats[a].resolvidos ||
            tagStats[b].tentativas - tagStats[a].tentativas ||
            a.localeCompare(b)
    ).slice(0, topK);
    function pieColors(n) {
        const c = [], h = 315; for(let i=0;i<n;i++)
            c.push(`hsl(${Math.floor(360*i/n + h)%360},69%,68%)`);
        return c;
    }
    let dataRes = tags.map(t => tagStats[t].resolvidos);
    let dataTent = tags.map(t => tagStats[t].tentativas);
    new Chart(document.getElementById('tags-pie-resolvidos'), {
        type: 'pie',
        data: { labels: tags, datasets: [{data: dataRes, backgroundColor: pieColors(tags.length)}] },
        options: {responsive:true, plugins:{legend:{position:'bottom'}}}
    });
    new Chart(document.getElementById('tags-pie-tentativas'), {
        type: 'pie',
        data: { labels: tags, datasets: [{data: dataTent, backgroundColor: pieColors(tags.length)}] },
        options: {responsive:true, plugins:{legend:{position:'bottom'}}}
    });
}
// ----------- Estatísticas rápidas -----------
function renderQuickStats(stats) {
    let bar = document.getElementById('user-quickstats');
    bar.innerHTML =
        `<div class="stats-entry">Problemas distintos tentados:<br><strong>${stats.problemasDistintos}</strong></div>
     <div class="stats-entry">Problemas resolvidos:<br><strong>${stats.acertosDistintos}</strong></div>
     <div class="stats-entry">Média sub. / acerto:<br><strong>${stats.mediaSubPorProb}</strong></div>
     <div class="stats-entry">Submissões:<br><strong>${Object.values(stats.dayStats).reduce((a,b)=>a+b,0)}</strong></div>`;
}
function renderAnswerStats(stats) {
    let tot = Object.values(stats.verdictStats).reduce((a,b)=>a+b,0);
    let vlist = Object.entries(stats.verdictStats).sort((a,b)=>b[1]-a[1]).slice(0,3)
        .map(([v,k])=>`${v} <b style="color:#156090;">${k}</b>`);
    let txt =
        `<div class="stats-entry">Top respostas:<br>${vlist.join("<br>")}</div>
     <div class="stats-entry">Total envios:<br><strong>${tot}</strong></div>`;
    let acertosDistintos = stats.acertosDistintos||1;
    let media = (tot/acertosDistintos).toFixed(2);
    txt += `<div class="stats-entry">Envios por problema resolvido:<br><strong>${media}</strong></div>`;
    document.getElementById("answer-stats").innerHTML = txt;
}

// ------ Loader, API, Inicialização ------
async function init() {
    // Usuário da página a ser exibido
    const url = new URL(window.location.href); historyOwner = url.searchParams.get("user");
    // Info login da barra
    await getAuthUser();

    if (!historyOwner) { alert("Faltou informar ?user=login."); return; }
    // Info user a ser exibido
    let userinfo = await fetch(`../../api/julgador/treino/auth/status/`).then(r=>r.json());
    document.getElementById("user-fullname").textContent = userinfo.name;
    document.getElementById("user-login").textContent = "~" + userinfo.login;
    // Puxa lista de problemas
    let problems = await fetch("../json/lista.json").then(r=>r.json());
    // Puxa submission history text
    let reqopts = {};
    let isOwnPage = (loggedInUser && historyOwner && loggedInUser === historyOwner);
    if(isOwnPage) reqopts.headers = {'Bearer': getToken()};
    let historyTxt = await fetch(`../../api/julgador/treino/full/history/`, reqopts).then(r=>r.text());
    let history = historyTxt.trim().split("\n").map(parseHistoryLine).filter(Boolean);

    renderUserHistoryTable(history, problems, isOwnPage);
    let stats = processUserStats(history, problems);
    makeDaysChart(stats.dayStats);
    makeVerdictChart(stats.verdictStats);
    makeLangPieBarCharts(stats.langStats);
    makeTagsPieCharts(stats.tagStats);
    renderQuickStats(stats);
    renderAnswerStats(stats);
}
window.onload = init;
