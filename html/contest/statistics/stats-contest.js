window.parseAdminSubs = function(txt, problems) {
  let probShortMap = {};
  (problems||[]).forEach(p=>{if(p.problem_id && p.short_name) probShortMap[p.problem_id]=p.short_name;});
  return txt.trim().split('\n').filter(Boolean).map(line=>{
    let vals = line.split(":");
    return {
      time_from_start: vals[0],
      username: vals[1],
      problem_id: vals[2],
      filename: vals[3],
      verdict: vals[4],
      epoch: vals[5],
      submission_id: vals[6],
      team_name: vals[7] || "",
      univ_short: vals[8] || "",
      short_name: probShortMap[vals[2]]||vals[2]
    };
  });
};

// Estatísticas por problema com filtro de region
window.renderProblemStats = function(subs, problems, regionFilter) {
  if(regionFilter) subs = subs.filter(regionFilter);

  // Estatística por problema
  let stats = {};
  subs.forEach(s=>{
    if(!stats[s.short_name]) stats[s.short_name] = { total:0, accepted:0 };
    stats[s.short_name].total++;
    if (/^accepted/i.test(s.verdict||"")) stats[s.short_name].accepted++;
  });

  // Tabela resumida
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

  // Mini-gráficos
  window.renderPieChart('pie-sub-count', Object.keys(stats), Object.values(stats).map(o=>o.total), "Submissões por problema");
  window.renderPieChart('pie-sub-acc', Object.keys(stats), Object.values(stats).map(o=>o.accepted), "Accepted por problema");
};

window.renderPieChart = function(canvasId, labels, values, title) {
  let old = Chart.getChart(canvasId); if(old) old.destroy();
  new Chart(document.getElementById(canvasId), {
    type: "pie",
    data: { labels: labels, datasets: [{data: values}] },
    options: { 
      responsive:true, 
      plugins:{legend: {position:'bottom'}, title: {display:true, text:title} }, 
      layout: { padding: 10 }
    }
  });
};
