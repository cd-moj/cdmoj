// score-obi.js

window.parseOBIScore = function(txt) {
  let lines = txt.trim().split('\n');
  if (!lines.length || !/obi/i.test(lines[0])) return null;
    let rawCols = lines[1].split(":");
  // Descobre índices de campos
  function idx(name) { return rawCols.findIndex(x=>x.toLowerCase() === name.toLowerCase()); }
  let idxFlag     = idx("flag"),
      idxUsername = idx("username"),
      idxUnivS    = idx("univ short"),
      idxUnivF    = idx("univ full"),
      idxTeamName = idx("team name"),
      idxTotal    = idx("total");
  // Problemas começam após os campos fixos
  let sysFields = ["flag","username","univ short","univ full","team name","total"];
  let probStart = 0;
  for(let i=0;i<rawCols.length;i++) {
      let f = rawCols[i].toLowerCase();
          if(/^asc$/i.test(rawCols[i])) continue; // Completely ignore asc now!

    if(!sysFields.includes(f)) { probStart = i; break; }
  }
  let probEnd = idxTotal >= 0 ? idxTotal : rawCols.length;
  let probShorts = rawCols.slice(probStart, probEnd);

  let data = lines.slice(2).map(l => l.split(":",rawCols.length));
  let teams = data.map(vals=>{
    let obj = {};
    rawCols.forEach((f,ix)=> obj[f]=vals[ix]||"");
    obj.flag = idxFlag >= 0 ? vals[idxFlag] || "" : "";
    obj.username = idxUsername >= 0 ? vals[idxUsername] || "" : "";
    obj.teamName = idxTeamName >= 0 ? vals[idxTeamName] || obj.username : obj.username;
    obj.univShort = idxUnivS >= 0 ? vals[idxUnivS] || "" : "";
    obj.univFull = idxUnivF >= 0 ? vals[idxUnivF] || "" : "";
    obj.total = idxTotal >= 0 ? vals[idxTotal] || "" : "";
    obj.probShorts = probShorts;
    obj.probs = {};
    probShorts.forEach((pname,idx)=> obj.probs[pname] = vals[probStart+idx]||"");
    return obj;
  });
  teams.forEach((obj,i)=>obj.place = (i+1));
  return {fields: rawCols, probShorts, teams};
};

window.renderOBIScore = function(parsed, searchTerm, regionFilterFn, favoriteList, oldOrder, regionUI) {
  if(!parsed) return "<div>Placar indisponível ou formato inválido.</div>";
  let fields = parsed.fields || [];
  // Decide se mostra a coluna de flag e universidade
  let hasFlag      = fields.includes("flag");
  let hasUnivShort = fields.includes("univ short");
  let hasUnivFull  = fields.includes("univ full");
  let teams = window.fuzzyTeamFilter ? window.fuzzyTeamFilter(parsed.teams, searchTerm) : parsed.teams;
  if(regionFilterFn) teams = teams.filter(regionFilterFn);

  let regionFilterHtml = regionUI || "";

  // Cabeçalho, só inclui flag ou universidade se tiver
  let ths = `<th>#</th>
    ${hasFlag ? "<th>Bandeira</th>" : ""}
    <th>Equipe</th>
    ${parsed.probShorts.map(pb=>`<th>${pb}</th>`).join('')}
    <th>Total</th>`;

  let rows = teams.map((t,i)=>{
    let fav = favoriteList && favoriteList.includes && favoriteList.includes(t.username);
    let moveCls = ""; // para animação
    let flagcell = (hasFlag && t.flag)
      ? `<img src="https://flagcdn.com/${t.flag.toLowerCase()}.svg" style="height:22px;vertical-align:middle;border-radius:4px;">`
      : "";
    // Equipe: "[sigla] Team", alt com univFull se houver, senão sem
    let equipe = (hasUnivShort && t.univShort ? `[${t.univShort}] ` : "") + (t.teamName||t.username);
    let equipeCell = (hasUnivFull && t.univFull)
      ? `<span title="${t.univFull}">${equipe}</span>`
      : `<span>${equipe}</span>`;
    let probcells = parsed.probShorts.map(sn=>{
      let v = t.probs[sn];
      if(v && parseInt(v, 10) > 0)
        return `<td class="prob-score" style="background:#dde9ff;color:#1346aa;font-weight:bold;">${v}</td>`;
      else if(v === "0")
        return `<td class="prob-score" style="background:#fbe7e9;color:#c88;font-weight:bold;">${v}</td>`;
      else
        return `<td class="prob-score"></td>`;
    }).join('');
    return `<tr id="tr-team-${t.username.replace(/\W/g,'_')}"${moveCls?` class="${moveCls}"`:''}>
      <td class="cl-place">${t.place}</td>
      ${hasFlag?`<td>${flagcell}</td>`:""}
      <td>${equipeCell}</td>
      ${probcells}
      <td>${t.total}</td></tr>`;
  }).join('');

  return (regionFilterHtml || "") +
    `<table class="score-table"><thead><tr>${ths}</tr></thead><tbody>${rows}</tbody></table>`;
};
