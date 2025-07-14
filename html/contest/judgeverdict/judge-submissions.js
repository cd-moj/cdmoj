(function(){
    let verdictChoice = {}; // submission_id => veredicto escolhido

    function getVerdictClass(verdict) {
        let v = (verdict||"").trim().toLowerCase();
        if (/^accepted/.test(v))       return "status-ok";
        if (/^wrong|runtime/.test(v))  return "status-wrong";
        if (/time limit/.test(v))      return "status-wait";
        if (/compilation/.test(v))     return "status-wrong";
        return "";
    }
    window.renderJudgeSubmissions = function(subList, problems, finalVerdicts, contestID, judgeUsername) {
        let probShortMap = {};
        (problems||[]).forEach(p=>{if(p.problem_id && p.short_name) probShortMap[p.problem_id]=p.short_name;});

        let html = `<table class="admin-table"><thead>
  <tr>
    <th>Tempo</th><th>Epoch<br><span style="font-size:.93em;">(horário)</span></th>
    <th>Usuário</th>
    <th>Equipe</th>
<th>Problema</th>
    <th>Veredicto inicial</th>
    <th>Veredicto final</th>
    <th>Enviar</th>
    <th>Arquivo</th>
    <th>Log</th>
  </tr></thead><tbody>`;
        for(let s of subList) {
            let sn = probShortMap[s.problem_id] || s.problem_id;
            let human = window.fmtDate ? window.fmtDate(Number(s.epoch), true) : "";
            let epochCell = s.epoch ? `${s.epoch}<br><span style="font-size:.93em;color:#29a">${human}</span>` : "";
            let logLink = `<a href="#" class="log-link" style="font-size:.93em;color:#29a" onclick="window.openLogAuthenticated('${window.API_LOG}?id=${encodeURIComponent(s.submission_id)}&time=${encodeURIComponent(s.epoch)}');return false;" title="Ver log">${s.submission_id}</a>`;
            // Veredictos (select)
            let verList = Array.isArray(finalVerdicts) ? finalVerdicts : [];
            let sel = `<select id="verdict-sel-${s.submission_id}" onchange="window.judgeVerdictChanged('${s.submission_id}')">
      <option value="">-- Escolha --</option>
      ${verList.map(v=>`<option value="${v}">${v}</option>`).join('')}
    </select>`;
            let btn = `<button class="submit-btn" id="btn-send-jg-${s.submission_id}" type="button" disabled onclick="window.sendJudgeVerdict('${s.submission_id}','${contestID}','${s.problem_id}','${s.username}','${judgeUsername}')">
      Enviar
    </button>`;
            html += `<tr>
      <td>${s.time_from_start||""}</td>
      <td>${epochCell}</td>
      <td>${s.username||""}</td>

        <td>${s.univ_short? `[${s.univ_short}]`:""} ${s.team_name||""}</td>
      <td>${sn}</td>

      <td class="trunc-status ${getVerdictClass(s.verdict)}">${s.verdict||""}</td>
      <td>${sel}</td>
      <td>${btn}</td>
      <td>
        <a class="link-btn" href="#" onclick="window.downloadAuthenticated('${window.API_SOURCE}?id=${encodeURIComponent(s.submission_id)}&time=${encodeURIComponent(s.epoch)}','${s.filename}');return false;">
          ${s.filename}
        </a>
      </td>
      <td>${logLink}</td>
    </tr>`;
        }
        html += "</tbody></table>";
        document.getElementById("judge-submissions-container").innerHTML = html;
    };

    // Quando mudar o select, habilita o botão enviar daquele id:
    window.judgeVerdictChanged = function(subid) {
        let sel = document.getElementById("verdict-sel-"+subid);
        let btn = document.getElementById("btn-send-jg-"+subid);
        btn.disabled = !sel.value;
        verdictChoice[subid] = sel.value;
    };

    // Função para enviar veredicto via API (envia contest_id, problem_id, final_verdict, username do juiz, submission_id)
    window.sendJudgeVerdict = function(subid, contestID, problemID, usernameContestant, judgeUsername) {
        let verdict = verdictChoice[subid];
        let btn = document.getElementById("btn-send-jg-"+subid);
        btn.disabled = true;
        btn.innerHTML = `<span class="loader-animation"></span> Enviando...`;
        fetch(window.API_SEND_VERDICT, {
            method: "POST",
            body: JSON.stringify({
                contest_id: contestID,
                problem_id: problemID,
                final_verdict: verdict,
                username: judgeUsername,
                submission_id: subid
            }),
            headers: {
                "Content-Type": "application/json",
                "Authorization": "Bearer "+localStorage.getItem(window.TOKEN_KEY)
            }
        }).then(r=>r.json())
            .then(resp => {
                btn.innerHTML = resp.success ? "Enviado!" : "Erro!";
                setTimeout(()=>{btn.innerHTML = "Enviar"; btn.disabled = false; }, 1000);
            });
    };
})();
