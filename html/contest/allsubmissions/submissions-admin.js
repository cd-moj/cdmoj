(function(){
let selected = new Set();
let lastGroupedBy = "all", lastFilterUser = "", lastFilterProblem = "", lastFilterVerdict = "";

function getShortNameMap(problems) {
  let map = {};
  (problems||[]).forEach(p=>{
    if(p.problem_id && p.short_name) map[p.problem_id] = p.short_name;
  });
  return map;
}
function getProblemMetaMap(problems) {
  let map = {};
  (problems||[]).forEach(p=>{
    if(p.problem_id) map[p.problem_id] = p;
  });
  return map;
}

window.renderAdminSubmissions = function(subList, problems, {groupBy="all",filterUser="",filterProblem="",filterVerdict=""}={}) {
  lastGroupedBy = groupBy; lastFilterUser = filterUser; lastFilterProblem = filterProblem; lastFilterVerdict = filterVerdict;
  let probShortMap = getShortNameMap(problems);
  let probMetaMap  = getProblemMetaMap(problems);

  let listFiltered = subList.filter(s => {
    if (filterUser && !String(s.username||"").toLowerCase().includes(filterUser.toLowerCase())) return false;
    let sn = probShortMap[s.problem_id] || s.problem_id;
    if (filterProblem && filterProblem !== "ALL" && s.problem_id !== filterProblem && sn !== filterProblem) return false;
    if (filterVerdict && (!s.verdict || !s.verdict.toLowerCase().includes(filterVerdict.toLowerCase()))) return false;
    return true;
  });

  // Agrupamento
  let groups = {};
  if(groupBy==="user"){
    listFiltered.forEach(s=>{
      if (!groups[s.username]) groups[s.username]=[];
      groups[s.username].push(s);
    });
  } else if(groupBy==="problem"){
    listFiltered.forEach(s=>{
      let meta = probMetaMap[s.problem_id]||{};
      let key = meta.short_name || s.problem_id;
      let label = meta.short_name
        ? `${meta.short_name} - ${meta.full_name||""} (${s.problem_id})`
        : `${s.problem_id}`;
      if (!groups[key]) groups[key] = { label, items: [] };
      groups[key].items.push(s);
    });
  } else {
    groups["all"] = listFiltered;
  }

  let html = '<div class="admin-sub-groupbar">';
  html += '<button type="button" onclick="window.groupSubsBy(\'all\')">Todas</button>';
  html += '<button type="button" onclick="window.groupSubsBy(\'user\')">Por usuário</button>';
  html += '<button type="button" onclick="window.groupSubsBy(\'problem\')">Por problema</button>';
  html += '<input type="text" id="admin-user-filter" placeholder="🔍 usuário..." style="margin:0 .8em .3em .9em" value="'+(filterUser||"")+'">';
  html += '<input type="text" id="admin-prob-filter" placeholder="🔍 problema..." style="margin:0 .5em .3em .5em" value="'+(filterProblem||"")+'">';
  html += '<input type="text" id="admin-verd-filter" placeholder="🔍 veredicto..." style="margin:0 .5em .3em .5em" value="'+(filterVerdict||"")+'">';
  html += '<button onclick="window.adminMarkAll()">Marcar todos</button> <button onclick="window.adminRejudge()">Rejulgamento</button>';
  html += '</div>';

  let groupKeys = Object.keys(groups);
  if (groupBy === "problem" || groupBy === "user") {
    groupKeys = groupKeys.slice().sort((a,b) => a.localeCompare(b, undefined, {numeric:true}));
  }

  for(let gk of groupKeys) {
    let items, label = '';
    if(groupBy === "problem") {
      items = groups[gk].items;
      label = groups[gk].label;
      html+= `<div style="font-weight:bold;font-size:1.12em;margin-top:1.3em;margin-bottom:.4em;">
        Problema: <span style="color:#174;">${label}</span></div>`;
    } else if(groupBy==="user") {
      items = groups[gk];
      html+= `<div style="font-weight:bold;font-size:1.12em;margin-top:1.3em;margin-bottom:.4em;">
        Usuário: <span style="color:#174;">${gk}</span></div>`;
    } else {
      items = groups[gk];
    }
    html += `<table class="admin-table"><thead>
      <tr>
        <th><input type="checkbox" id="admin-check-all-${gk}" onclick="window.adminMarkGroup('${gk}',this.checked)"></th>
        <th>Tempo</th>
        <th>Epoch<br><span style="font-size:.93em;">(horário)</span></th>
        <th>Usuário</th>
        <th>Equipe</th>
        <th>Problema</th>
        <th>Veredicto</th>
        <th>Arquivo</th>
        <th>Log</th>
      </tr></thead><tbody>
    `;
    for(let s of items) {
      let isChecked = selected.has(s.submission_id);
      let sn = probShortMap[s.problem_id] || s.problem_id;
      let meta = probMetaMap[s.problem_id]||{};
      // Formata o epoch para humano (usa fmtDate global se presente)
      let epochStr = s.epoch || "";
      let human = (window.fmtDate ? window.fmtDate(Number(s.epoch), true) : "");
      let epochCell = epochStr ? `${epochStr}<br><span style="font-size:.93em;color:#29a">${human}</span>` : "";
      // Cores veredicto
      let cls = "";
      let v = (s.verdict||"");
      let vNorm = v.trim().toLowerCase();
      if (/accepted/.test(vNorm)) cls = "status-ok";
      else if (/wrong|runtime/.test(vNorm)) cls = "status-wrong";
      else if (/time limit/.test(vNorm)) cls = "status-wait";
        let logLink = `<a href="#" class="log-link" style="font-size:.93em;color:#29a" onclick="window.openLogAuthenticated('${window.API_LOG}?id=${encodeURIComponent(s.submission_id)}&time=${encodeURIComponent(s.epoch)}');return false;" title="Ver log">${s.submission_id}</a>`;
      html += `<tr>
        <td><input type="checkbox" class="admin-check" value="${s.submission_id}"${isChecked?" checked":""} onclick="window.adminSelect('${s.submission_id}',this.checked)"/></td>
        <td>${s.time_from_start||""}</td>
        <td>${epochCell}</td>
        <td>${s.username||""}</td>
        <td>${s.univ_short? `[${s.univ_short}]`:""} ${s.team_name||""}</td>
        <td>${sn}</td>
        <td class="trunc-status ${cls}">${s.verdict||""}</td>
        <td>
          <a class="link-btn" href="#" onclick="window.downloadAuthenticated('${window.API_SOURCE}?id=${encodeURIComponent(s.submission_id)}&time=${encodeURIComponent(s.epoch)}','${s.filename}');return false;">
            ${s.filename}
          </a>
        </td>        <td>${logLink}</td>
      </tr>`;
    }
    html += "</tbody></table>";
  }
  document.getElementById("admin-submissions-container").innerHTML = html;

  // Mantém foco dos filtros!
  ["admin-user-filter","admin-prob-filter","admin-verd-filter"].forEach(id=>{
    let el = document.getElementById(id);
    el.oninput = (e) => {
      let vuser = document.getElementById("admin-user-filter").value,
          vprob = document.getElementById("admin-prob-filter").value,
          vverd = document.getElementById("admin-verd-filter").value;
      window.renderAdminSubmissions(window.allSubs, window.contestProblems, {
        groupBy: lastGroupedBy,
        filterUser: vuser,
        filterProblem: vprob,
        filterVerdict: vverd
      });
      setTimeout(() => {
        let x = document.getElementById(id);
        if(x) {
          let len = x.value.length;
          x.focus(); x.setSelectionRange(len, len);
        }
      }, 10);
    };
  });
};

window.adminSelect = function(subid, checked) {
  if(!window.adminSelected) window.adminSelected = new Set();
  if(checked) window.adminSelected.add(subid);
  else window.adminSelected.delete(subid);
};
window.adminMarkAll = function() {
  document.querySelectorAll('.admin-check').forEach(box => { box.checked = true; window.adminSelected.add(box.value); });
};
window.adminMarkGroup = function(grp,checked) {
  document.querySelectorAll('table.admin-table').forEach(table => {
    if (grp === "all" || (table.previousElementSibling && table.previousElementSibling.textContent && table.previousElementSibling.textContent.includes(grp)))
      table.querySelectorAll('input.admin-check').forEach(box => {
        box.checked = checked;
        if(checked) window.adminSelected.add(box.value); else window.adminSelected.delete(box.value);
      });
  });
};
window.adminRejudge = function() {
  let toRejudge = Array.from(window.adminSelected||[]);
  if (!toRejudge.length) { alert("Selecione submissões para rejuizar!"); return; }
  fetch(window.API_REJUDGE, {
    method: "POST",
    body: JSON.stringify({ submission_ids: toRejudge }),
    headers: { "Content-Type": "application/json", "Authorization": "Bearer "+localStorage.getItem(window.TOKEN_KEY) }
  }).then(r=>r.json())
    .then(resp => {
      alert(resp.success ? "Submissões enviadas para rejulgamento!" : "Falha ao rejuizar.");
    });
};
window.groupSubsBy = function(grp) {
  window.renderAdminSubmissions(window.allSubs, window.contestProblems, {
    groupBy: grp,
    filterUser: lastFilterUser,
    filterProblem: lastFilterProblem,
    filterVerdict: lastFilterVerdict
  });
};
})();
