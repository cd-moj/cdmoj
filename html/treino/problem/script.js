function getQueryParam(name) {
    const url = new URL(window.location.href);
    return url.searchParams.get(name) || "";
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
function renderProblemTags(tagList) {
    const box = document.getElementById('problem-tags');
    if (!tagList || !tagList.length) {
        box.innerHTML = '';
        return;
    }
    box.classList.remove('unblur');
    // Renderiza as tags borradas + botão
    box.innerHTML =
        tagList.map(tag => {
            const encoded = encodeURIComponent(tag);
            return `<a class="problem-tag" href="../treino/?searchtag=${encoded}">${tag}</a>`;
        }).join(' ') +
        `<button class="unblur-btn" id="show-tags-btn" type="button" title="Mostrar tags deste problema">Ver tags</button>`;
    document.getElementById('show-tags-btn').onclick = function() {
        box.classList.add('unblur');
        this.remove(); // Oculta o botão depois
    };
}
function renderTimeLimitsTable(time_limits) {
    let html = "<tr><th>Linguagem</th><th>Limite (segundos)</th></tr>";
    for (const lang in time_limits) {
        html += `<tr><td>${lang}</td><td>${parseFloat(time_limits[lang]).toFixed(2)}</td></tr>`;
    }
    return html;
}
function base64DecodeUTF8(str) {
    // Decodifica base64 seguro para UTF-8
    if (typeof atob === 'function') {
        try { return decodeURIComponent(escape(atob(str))); }
        catch (e) { return atob(str); }
    }
    return Buffer.from(str, 'base64').toString('utf8');
}
function renderStatementB64(b64, time_limits) {
    document.getElementById("statement-loading").style.display = 'none';
    const contentDiv = document.getElementById("statement-content");
    contentDiv.style.display = '';
    // Decodifica o HTML
    const htmlDecoded = base64DecodeUTF8(b64);
    // Parseia o HTML para DOM e extrai <body>, omitindo <h1 class="title">
    let innerHtml = htmlDecoded;
    try {
        let doc = (new DOMParser()).parseFromString(htmlDecoded, "text/html");
        let body = doc.body;
        if (body && body.innerHTML.trim()) {
            // Remove <h1 class="title">
            let h1s = body.querySelectorAll('h1.title');
            h1s.forEach(el => el.parentNode.removeChild(el));
            innerHtml = body.innerHTML;
        }
    } catch (e) {}
    contentDiv.innerHTML = innerHtml;

    if (time_limits && Object.keys(time_limits).length > 0) {
        document.getElementById("timelimit-table").innerHTML = renderTimeLimitsTable(time_limits);
        document.getElementById("timelimits-box").style.display = "";
    } else {
        document.getElementById("timelimits-box").style.display = "none";
    }
}


// ------------------- Login & Auth ----------------------
function getToken() {
    return localStorage.getItem('moj_token_treino');
}

function showUserBox(name, login) {
    // Exibe nome + login na barra, junto com botão de logout
    document.getElementById('topbar-userbox').insertAdjacentHTML('beforeend',
                                                                 `<span class="user-box">
      <span class="user-box-user"><a href="../stat?user=${login}"><span style="font-weight:400;color:#888;">~${login}</span></a></span>
      <button id="logout-btn" type="button">Logout</button>
    </span>`);
    document.getElementById('logout-btn').onclick = function() {
        localStorage.removeItem('moj_token_treino');
        location.reload();
    };
}

function fetchAndUpdateSubmissionHistory() {
    const token = getToken();
    const problemId = getQueryParam("id");
    fetch('../../api/julgador/treino/problem/history/' + encodeURIComponent(problemId) +'/', {
        headers: token ? { 'Bearer':  token } : {},
    })
        .then(r => r.text())
        .then(txt => { renderSubmissionHistoryFromTxt(txt); });
}

// No checkAuthAndShow, reveja:
async function checkAuthAndShow(problemId) {
    const token = getToken();
    let userstat = await fetch('../../api/julgador/treino/auth/status/', {
        headers: token ? { 'Bearer':  token } : {},
    }).then(r=>r.json()).catch(()=>({logged_in:false}));
    // ============ NOVO ===============
    // Remove antes de inserir para não duplicar caso refresque status
    const oldBox = document.querySelector('.user-box');
    if (oldBox) oldBox.remove();
    if (userstat.logged_in) {
        showUserBox(userstat.name, userstat.login);
    }
    // ============ FIM NOVO ===============
    if (!userstat.logged_in) {
        document.getElementById("login-section").style.display = "";
        document.getElementById("submissions-section").style.display = "none";
    } else {
        document.getElementById("login-section").style.display = "none";
        document.getElementById("submissions-section").style.display = "";
        document.getElementById("login-error").innerHTML = "";
        fetchAndUpdateSubmissionHistory();
        /*AQUI fetch('/~ribas/api/open-training/history.sh?id=' + encodeURIComponent(problemId), {
          headers: token ? { 'Bearer': token } : {},
          })
          .then(r=>r.text())
          .then(txt => { renderSubmissionHistoryFromTxt(txt); });*/
    }
}


function downloadAuthenticated(url, filename) {
    fetch(url, {
        headers: { 'Bearer': getToken() }
    })
        .then(r => {
            if (!r.ok) throw new Error("Erro no download");
            return r.blob();
        })
        .then(blob => {
            const link = document.createElement('a');
            link.href = window.URL.createObjectURL(blob);
            link.download = filename;
            document.body.appendChild(link);
            link.click();
            document.body.removeChild(link);
        })
        .catch(e => {
            alert("Falha ao baixar arquivo/log.\n" + e);
        });
}

function openLogAuthenticated(url) {
    // Para visualizar em aba nova: pode abrir um modal, aqui usarei window.open + fetch/token
    fetch(url, {
        headers: { 'Bearer': getToken() }
    })
        .then(r => r.text())
        .then(text => {
            const w = window.open();
            w.document.write('<pre style="font-family:monospace;white-space:pre-wrap;">' + 
                             escapeHtml(text) + '</pre>');
            w.document.close();
        });
}
function escapeHtml(str) {
    return String(str).replace(/[<>&"']/g, s =>
        ({'<':'&lt;','>':'&gt;','&':'&amp;','"':'&quot;',"'":'&#39;'})[s]);
}

let submissionsCache = []; // global para ordenação

function hasPending(submissions) {
    return submissions.some(sub => /^(not\s*answered\s*yet|on\s*queue|running)$/i.test(sub.veredict.trim()));
}

function renderSubmissionHistoryFromTxt(txt) {
    const tbody = document.getElementById("history-tbody");
    tbody.innerHTML = "";
    const lines = txt.trim().split('\n').filter(Boolean);
    if (!lines.length) {
        tbody.innerHTML = '<tr><td colspan="4" class="minor">Nenhuma submissão deste problema.</td></tr>';
        submissionsCache = [];
        return;
    }
    submissionsCache = lines.map(line => {
        const parts = line.split(':');
        if (parts.length < 7) return null;
        const [minutos, username, probId, lang, veredict, epoch, submit_id] = parts;
        let statusClass = "";
        if (/Accepted/i.test(veredict)) statusClass = "status-ok";
        else if (/Wrong|Compile|Runtime/i.test(veredict)) statusClass = "status-wrong";
        else if (/Time Limit/i.test(veredict)) statusClass = "status-wait";
        // Detecta pendentes:
        let isPending = /^(not\s*answered\s*yet|on\s*queue|running)$/i.test(veredict.trim());
        return { minutos, username, probId, lang, veredict, epoch, submit_id, statusClass, isPending };
    }).filter(Boolean);

    fillHistoryTable(submissionsCache);

    // --------- PÓS-RENDER ORDEM ---------
    if (hasPending(submissionsCache)) {
        // Entre 5 e 10 segundos (random)
        let next = 5000 + Math.random() * 5000;
        setTimeout(fetchAndUpdateSubmissionHistory, next);
    }
}


function fillHistoryTable(submissions) {
    const tbody = document.getElementById("history-tbody");
    tbody.innerHTML = "";
    for (const sub of submissions) {
        const logUrl = `../../api/julgador/treino/submission/log/${encodeURIComponent(sub.submit_id)}/${encodeURIComponent(sub.epoch)}/`;
        const srcUrl = `../../api/julgador/treino/submission/source/${encodeURIComponent(sub.submit_id)}/${encodeURIComponent(sub.epoch)}/`;
        // Loader visual para pendentes:
        let cellContent = sub.veredict;
        if (sub.isPending) {
            cellContent = `
        <span class="loader-animation" title="Aguardando..."></span>
        <span style="margin-left:.9em;">${sub.veredict}</span>
      `;
        }
        tbody.innerHTML += `
      <tr>
        <td>${formatDate(sub.epoch)}</td>
        <td>
          <button type="button" class="link-btn" title="Baixar código fonte do envio" onclick="downloadAuthenticated('${srcUrl}','${sub.lang}')">&#128196;</button>
          <button type="button" class="link-btn" title="Ver log completo da submissão" onclick="openLogAuthenticated('${logUrl}')">ℹ️</button>
        </td>
        <td>${sub.lang.substring(sub.lang.indexOf(".")+1)}</td>
        <td class="trunc-status ${sub.statusClass}" tabindex="0" title="${sub.veredict.replace(/"/g, '&quot;')}">${cellContent}</td>
      </tr>
    `;
    }
}

// --- Ordenação ---
let lastSort = { key: null, asc: true };


function updateSortIndicators() {
    document.querySelectorAll('#history-table th.sortable').forEach(th => {
        const ind = th.querySelector('.sort-ind');
        const key = th.getAttribute('data-sort');
        if (lastSort.key === key) {
            ind.textContent = lastSort.asc ? ' 🔼' : ' 🔽';
        } else {
            ind.textContent = ' ⇅';
        }
    });
}

document.querySelectorAll('#history-table th.sortable').forEach(th => {
    th.addEventListener('click', function () {
        const sortKey = this.getAttribute('data-sort');
        let asc = true;
        if (lastSort.key === sortKey) asc = !lastSort.asc;
        lastSort = { key: sortKey, asc };
        document.querySelectorAll('#history-table th').forEach(e => e.classList.remove('sorted'));
        this.classList.add('sorted');
        let sorted = [...submissionsCache];
        if (sortKey === 'date') {
            sorted.sort((a, b) => asc ? +a.epoch - +b.epoch : +b.epoch - +a.epoch);
        } else if (sortKey === 'lang') {
            sorted.sort((a, b) => asc ? a.lang.localeCompare(b.lang) : b.lang.localeCompare(a.lang));
        } else if (sortKey === 'status') {
            sorted.sort((a, b) => asc ? a.veredict.localeCompare(b.veredict) : b.veredict.localeCompare(a.veredict));
        }
        fillHistoryTable(sorted);
        updateSortIndicators();
    });
});

// Inicializa indicadores no carregamento
updateSortIndicators();


document.getElementById("login-form").onsubmit = function(e) {
    e.preventDefault();
    let btn = this.querySelector("button");
    btn.disabled = true;
    document.getElementById("login-error").innerHTML = "";
    fetch('../../api/julgador/treino/auth/login/', {
        method: "POST",
        body: JSON.stringify({
            username: this.username.value, password: this.password.value
        }),
        headers: { "Content-Type": "application/json" }
    }).then(r=>r.json()).then(resp => {
        btn.disabled = false;
        if (resp.success && resp.token) {
            localStorage.setItem('moj_token_treino', resp.token);
            checkAuthAndShow(getQueryParam("id"));
        } else {
            document.getElementById("login-error").innerHTML = "Login falhou: " +
                ((resp.error && resp.error.message) || "usuário ou senha inválidos");
        }
    });
    return false;
};

/*
  function renderProblemTags(tagList) {
  const box = document.getElementById('problem-tags');
  if (!tagList || !tagList.length) {
  box.innerHTML = '';
  return;
  }
  box.innerHTML = tagList.map(tag => {
  const encoded = encodeURIComponent(tag);
  return `<a class="problem-tag" href="/treino?searchtag=${encoded}">${tag}</a>`;
  }).join(' ');
  }*/
// ---------- Submissão -----------
document.getElementById("submit-form").onsubmit = function(e) {
    e.preventDefault();
    let fileInput = document.getElementById("file-upload");
    let file = fileInput.files[0];
    let submitMsg = document.getElementById("submit-msg");
    submitMsg.innerHTML = "Lendo arquivo...";
    if (!file) {
        submitMsg.innerHTML = "Selecione um arquivo.";
        return;
    }
    let reader = new FileReader();
    reader.onload = function(event) {
        submitMsg.innerHTML = "Preparando Arquivo de Submissão...";
        // event.target.result é um ArrayBuffer (usando readAsArrayBuffer)
        let raw = new Uint8Array(event.target.result);
        // Converte para binary string
        let binary = "";
        for(let i=0; i<raw.length; ++i) {
            binary += String.fromCharCode(raw[i]);
        }
        // Encode base64
        let code_b64 = btoa(binary);

        const token = getToken();
        let problemId = getQueryParam("id");
        submitMsg.innerHTML = "Criando Submissão (não feche a aba e aguarde)...";
        fetch('../../api/julgador/treino/submission/submit/', {
            method: "POST",
            body: JSON.stringify({
                problem_id: problemId,
                filename: file.name,
                code_b64: code_b64
            }),
            headers: {
                "Content-Type": "application/json",
                ...(token ? { "Bearer": token } : {})
            }
        })
            .then(r=>r.json())
            .then(resp => {
                if (resp.success) {
                    submitMsg.innerHTML = "Submissão enviada com sucesso!";
                    // Atualiza histórico
                    fetchAndUpdateSubmissionHistory();
                } else {
                    submitMsg.innerHTML = "Erro: " + (resp.error||"Falha desconhecida.");
                }
            }).catch(()=>{
                submitMsg.innerHTML = "Falha na comunicação com o servidor.";
            });
    };
    reader.onerror = function() {
        submitMsg.innerHTML = "Erro ao ler arquivo.";
    };
    reader.readAsArrayBuffer(file);
};


window.onload = function() {
    const problemId = getQueryParam("id");
    // Ajusta página ao problema sendo resolvido:
    if (!problemId) {
        document.getElementById("problem-title").innerText = "Problema não especificado na URL!";
        document.getElementById("statement-loading").innerText = "Nenhum problema selecionado.";
        document.getElementById("statement-content").style.display = "none";
        document.getElementById("timelimits-box").style.display = "none";
        return;
    }
    fetch('../public/jsons/' + encodeURIComponent(problemId)+'.json')
        .then(r=>r.json())
        .then(data => {
            document.title = data.title + " - MOJ";
            document.getElementById("problem-title").innerText = data.title;
            renderStatementB64(data.statement_html_b64, data.time_limits);
            renderProblemTags(data.tags);
        });

    // Autenticação e submissão:
    checkAuthAndShow(problemId);
};
