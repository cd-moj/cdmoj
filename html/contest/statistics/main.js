window.renderTeamSubsTable = function(subs, regionFilter) {
  if(regionFilter) subs = subs.filter(regionFilter);
  let teamMap = {};
  subs.forEach(s=>{ teamMap[s.username]=teamMap[s.username]||0; teamMap[s.username]++; });
  let rows = Object.entries(teamMap).sort((a,b)=>b[1]-a[1]).map(([uname,cnt])=>
    `<tr><td>${uname}</td><td class="center">${cnt}</td></tr>`).join('');
  document.getElementById("stats-teamsubs-table").innerHTML =
    `<table class="stats-table-teams"><thead><tr><th>Usuário</th><th>Submissões</th></tr></thead><tbody>${rows}</tbody></table>`;
};

window.renderSubTimeHistogram = function(subs, regionFilter) {
  if(regionFilter) subs = subs.filter(regionFilter);

  // descobre min/max
  let min = Math.min(...subs.map(s=>Number(s.time_from_start)||0)), max = Math.max(...subs.map(s=>Number(s.time_from_start)||0));
  min = Math.floor(min/10)*10; max=Math.ceil(max/10)*10;
  let bins = [];
  for(let b=min;b<=max;b+=10) bins.push(b);
  let countsAll = bins.map(b=>subs.filter(s=>s.time_from_start>=b && s.time_from_start<b+10).length);
  let countsAcc = bins.map(b=>subs.filter(s=>s.time_from_start>=b && s.time_from_start<b+10 && /^accepted/i.test(s.verdict)).length);

  // Barra - geral
  let bar1 = document.getElementById("hist-all-submit");
  let old1 = Chart.getChart(bar1); if(old1) old1.destroy();
  new Chart(bar1, { type:"bar", data:{ labels: bins.map(b=>`${b}-${b+10}`), datasets:[{label:"Submissões",data:countsAll,backgroundColor:"#5baef3"}]}, options: {responsive:true, plugins:{legend:{display:false},title:{display:true,text:"Submissões por 10min"}} } });

  // Barra - aceitos
  let bar2 = document.getElementById("hist-accepted-submit");
  let old2 = Chart.getChart(bar2); if(old2) old2.destroy();
  new Chart(bar2, { type:"bar", data:{ labels: bins.map(b=>`${b}-${b+10}`), datasets:[{label:"Accepted",data:countsAcc,backgroundColor:"#49d099"}]}, options: {responsive:true, plugins:{legend:{display:false},title:{display:true,text:"Accepteds por 10min"}} } });
};

window.renderLangStats = function(subs, problems, regionFilter) {
  if(regionFilter) subs = subs.filter(regionFilter);
  let langs = {}, shorts = {};
  subs.forEach(s=>{langs[s.language]=1; shorts[s.short_name]=1;});
  let langlist = Object.keys(langs), pbList = Object.keys(shorts);

  // Monta contagem [problema][linguagem] = {total,accepted}
  let stat = {};
  pbList.forEach(pb=>{ stat[pb]={}; langlist.forEach(l=>{ stat[pb][l]={total:0,acc:0}; });});
  subs.forEach(s=>{
    if(stat[s.short_name] && stat[s.short_name][s.language]) {
      stat[s.short_name][s.language].total++;
      if(/^accepted/i.test(s.verdict)) stat[s.short_name][s.language].acc++;
    }
  });
  let tbl = `<table class="stats-table-lang"><thead><tr><th>Problema</th>`
    + langlist.map(l=>`<th>${l}</th>`).join('')
    + `</tr></thead><tbody>`;
  for(let pb of pbList) {
    tbl+=`<tr><td>${pb}</td>`+langlist.map(l=>
      `<td class="center">${stat[pb][l].total}${stat[pb][l].acc>0?('<br><span style="font-size:.97em;color:#17922f;">'+stat[pb][l].acc+'✓</span>'):""}</td>`
    ).join('')+"</tr>";
  }
  tbl+="</tbody></table>";
  document.getElementById("stats-lang-table").innerHTML = tbl;
  // Pie chart todas envios
  let countsRun = langlist.map(l=>subs.filter(s=>s.language===l).length);
  let countsAcc = langlist.map(l=>subs.filter(s=>s.language===l && /^accepted/i.test(s.verdict)).length);

  window.renderPieChart('pie-lang-run', langlist, countsRun, "Total por linguagem");
  window.renderPieChart('pie-lang-acc', langlist, countsAcc, "Accepted por linguagem");
};

window.renderLangVerdictBar = function(subs, regionFilter) {
  if(regionFilter) subs = subs.filter(regionFilter);
  let langs = {};
  subs.forEach(s=>{ langs[s.language]=1; });
  let langlist = Object.keys(langs), verdicts={};
  subs.forEach(s=>{ verdicts[s.verdict]=1; });
  let vlist = Object.keys(verdicts);

  // Gera cnt [verdict][lang]
  let cnt = {};
  vlist.forEach(v=>cnt[v]={});
  langlist.forEach(l=>vlist.forEach(v=>cnt[v][l]=0));
  subs.forEach(s=>{ cnt[s.verdict][s.language]++; });

  // Monta gráfico em barras para veredictos por linguagem (usa Chart.js stacked bar)
  let bars = langlist.map(l=>({label:l,data:vlist.map(v=>cnt[v][l])}));
  let stacked = document.getElementById("bar-lang-verdict");
  let old = Chart.getChart(stacked); if(old) old.destroy();
  new Chart(stacked, {
    type: "bar",
    data: {
      labels: vlist,
      datasets: langlist.map((l,idx)=>({
        label: l,
        data: vlist.map(v=>cnt[v][l]),
        backgroundColor: `hsl(${(idx*57)%360},65%,70%)`
      }))
    },
    options: { responsive:true,
      plugins: {
        legend: {position:'right'},
        title: {display: true, text: "Veredictos por linguagem"}
      },
      scales: { x:{stacked:true},y:{stacked:true}}
    }
  });
};

window.renderVerdictStatsByProblem = function(subs, problems, regionFilter) {
  if(regionFilter) subs = subs.filter(regionFilter);
  // UI: lista de problemas para selecionar/excluir/filtrar
  let allShorts = [...new Set(problems.map(p=>p.short_name))];
  let picked = window.statsVerdictPicked || allShorts.slice();
  let options = allShorts.map(s =>
    `<label><input type="checkbox" value="${s}"${picked.includes(s)?' checked':''} onchange="window.pickVerdictProblem(this.value,this.checked)"> ${s}</label>`
  ).join(' ');
  document.getElementById("stats-verdict-picker").innerHTML = `Problemas:&nbsp;${options}`;

  let filtered = subs.filter(s => picked.includes(s.short_name));
  // Monta o dataset de veredictos
  let verdictSet = {};
  filtered.forEach(s=>{verdictSet[s.verdict]=1;});
  let verdicts = Object.keys(verdictSet), stats={};
  verdicts.forEach(v=>{ stats[v]={}; });
  picked.forEach(k=> verdicts.forEach(v=> stats[v][k]=0 ) );
  filtered.forEach(s=>{ stats[s.verdict][s.short_name]++; });

  // Tabela de veredictos:
  let ht = `<table class="stats-table-prob"><thead><tr><th>Veredicto</th>${picked.map(x=>`<th>${x}</th>`).join('')}</tr></thead><tbody>`;
  for(let v of verdicts)
    ht+=`<tr><td>${v}</td>${picked.map(k=>`<td class="center">${stats[v][k]||""}</td>`).join('')}</tr>`;
  ht+="</tbody></table>";
  document.getElementById("stats-verdict-prob-table").innerHTML = ht;

  // Pie
  let pieCounts = verdicts.map(v=>filtered.filter(s=>s.verdict===v).length);
  window.renderPieChart('pie-verdicts', verdicts, pieCounts, "Veredictos selecionados");
};

window.pickVerdictProblem = function(pb, checked) {
  if(!window.statsVerdictPicked) window.statsVerdictPicked = [];
  if(checked) window.statsVerdictPicked.push(pb);
  else window.statsVerdictPicked = window.statsVerdictPicked.filter(x=>x!=pb);
  window.renderVerdictStatsByProblem(window._subs, window._probs, window._region);
};

window.renderProblemStats = function(subs, problems, regionFilter) {
  if(regionFilter) subs = subs.filter(regionFilter);
  let stats = {};
  (problems||[]).forEach(p=>{ stats[p.short_name] = { total:0, accepted:0 }; });
  subs.forEach(s=>{
    if(stats[s.short_name]) {
      stats[s.short_name].total++;
      if (/^accepted/i.test(s.verdict||"")) stats[s.short_name].accepted++;
    }
  });
  // Tabela
  let sheet = `<table class="stats-table-prob"><thead><tr>
    <th>Problema</th><th>Submissões</th><th>Accepted</th><th>Taxa (%)</th>
  </tr></thead><tbody>`;
  for(let k of Object.keys(stats)) {
    let t = stats[k].total, a = stats[k].accepted, tx = t ? ((a/t)*100).toFixed(1) : "--";
    sheet += `<tr>
      <td class="center">${k}</td>
      <td class="center">${t}</td>
      <td class="center">${a}</td>
      <td class="center">${tx}</td>
    </tr>`;
  }
  sheet += "</tbody></table>";
  document.getElementById("stats-problem-table").innerHTML = sheet;
  // Pizzas
  window.renderPieChart('pie-sub-count', Object.keys(stats), Object.values(stats).map(o=>o.total), "Submissões por problema");
  window.renderPieChart('pie-sub-acc', Object.keys(stats), Object.values(stats).map(o=>o.accepted), "Accepted por problema");
};

document.addEventListener("DOMContentLoaded", async function(){

  // --- Check login ---
  let contestID = window.location.hostname.split(".")[0];
  let token = localStorage.getItem(window.TOKEN_KEY);
  let dest = encodeURIComponent(window.location.pathname + window.location.search + window.location.hash);
  let headers = token ? { "Authorization": "Bearer " + token } : {};
//  if (!token) { window.location.replace(`/~ribas/contest?next=${dest}`); return; }
  let resp = await fetch(`/~ribas/api/auth/status.sh?contest=${encodeURIComponent(contestID)}`, {headers});
  let stat = await resp.json();
//  if (!stat.logged_in) { window.location.replace(`/~ribas/contest?next=${dest}`); return; }

  // --- Contest info/nav/user ---
  let basic = await fetch(window.API_BASIC).then(r=>r.json());
  window.contestLocale = basic.locale || "pt";
  document.title = basic.contest_name;
  document.getElementById('contest-title').textContent = basic.contest_name;
  window.startContestCountdown(basic.end_time, window.contestLocale);
  let userInfo = await fetch(window.API_USERINFO, {headers}).then(r=>r.json());
  window.showUserDetails(userInfo, window.contestLocale);
  window.initLogout && window.initLogout();
  let quicknav = await fetch(window.API_QUICKNAV, {headers}).then(r=>r.json());
  window.buildContestNav(quicknav, window.contestLocale);

  // --- Load problems and regions ---
  let problems = await fetch(window.API_PROBLEMS, {headers}).then(r=>r.json());
  let regions = await window.loadScoreRegions ? await window.loadScoreRegions() : [];
  let allSubs = [];
  let regionFilterFn = null;
  let regionUI = "";
  let regionRegex = "";
  window._probs = problems;

  // --- Filtro de região UI ---
  function setRegionFilter(regex) {
    regionRegex = regex;
    regionFilterFn = regex ? (s => new RegExp(regex, "i").test(s.username)) : null;
    renderAll();
  }
  window.setRegionFilter = setRegionFilter;

  function renderRegionPick() {
    document.getElementById("stats-region-filter").innerHTML =
      window.renderRegionFilters(regions, regionRegex, "window.setRegionFilter");
  }

  // --- Fetch and parse all submissions ---
  let respSubs = await fetch(window.API_SUBMISSIONS_ADMIN, {headers});
  let subTxt = await respSubs.text();
  if (!subTxt.trim()) { window.location.replace(`/~ribas/contest?next=${dest}`); return; }
  allSubs = window.parseAdminSubs(subTxt, problems);
  window._subs = allSubs;

  // --- Filtro: dynamic, depende da região ---
  function getFilteredSubs() {
    return regionFilterFn ? allSubs.filter(regionFilterFn) : allSubs;
  }

  // --- Renderizações ----
  function renderAll() {
    renderRegionPick();
    let filtered = getFilteredSubs();
    window.renderProblemStats && window.renderProblemStats(filtered, problems, null);
    window.renderVerdictStatsByProblem && window.renderVerdictStatsByProblem(filtered, problems, null);
    window.renderLangStats && window.renderLangStats(filtered, problems, null);
    window.renderLangVerdictBar && window.renderLangVerdictBar(filtered, null);
    window.renderTeamSubsTable && window.renderTeamSubsTable(filtered, null);
    window.renderSubTimeHistogram && window.renderSubTimeHistogram(filtered, null);
    // Adicione mais renderizadores conforme forem implementando as outras seções
  }

  renderAll();
  // Atualização do scoreboard/statistics das submissões a cada N minutos (ex: 3min = 180000):
  setInterval(async ()=>{
    let resp = await fetch(window.API_SUBMISSIONS_ADMIN, {headers});
    let subTxt = await resp.text();
    if (subTxt.trim()) {
      allSubs = window.parseAdminSubs(subTxt, problems);
      window._subs = allSubs;
      renderAll();
    }
  }, 180000 + Math.random()*120000);

});
