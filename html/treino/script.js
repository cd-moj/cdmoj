let allProblems = [], resolvedByUser = [], availableTags = [];
let selectedTags = [], curSorted = { key: "title", asc: true };
let page = 1, PER_PAGE = 20, shownTags = false;
let FILTER_MODE = 'all'; // 'all', 'solved', 'attempted'
//let resolvedByUser = { solved:[], attempted:[] };

function getToken() { return localStorage.getItem('moj_token_treino'); }
function updateUserFilterBar(isLogged) {
    // Renderiza os botões, só mostra os extras se logado
    const bar = document.getElementById("userfilt-btns");
    let html =
        `<button type="button" class="userfilt-btn${FILTER_MODE==='all'?' selected':''}" id="filter-all">Todos</button>`;
    if (isLogged) {
        html += `
      <button type="button" class="userfilt-btn${FILTER_MODE==='solved'?' selected':''}" id="filter-solved">Resolvidos</button>
      <button type="button" class="userfilt-btn${FILTER_MODE==='attempted'?' selected':''}" id="filter-attempted">Tentados não resolvidos</button>
    `;
    }
    bar.innerHTML = html;

    document.getElementById("filter-all").onclick = () => setUserFilter("all");
    if (isLogged) {
        document.getElementById("filter-solved").onclick = () => setUserFilter("solved");
        document.getElementById("filter-attempted").onclick = () => setUserFilter("attempted");
    }
}

function setUserFilter(mode) {
    FILTER_MODE = mode;
    updateUserFilterBar(!!(resolvedByUser && resolvedByUser.solved));
    page = 1;
    doSearchAndRender();
    renderPager();

}

async function showUserBar() {
    const box = document.getElementById('topbar-userbox');
    while (box.querySelector('.user-box')) box.querySelector('.user-box').remove();
    if (box.querySelector('#login-section')) box.querySelector('#login-section').remove();
    let userstat;
    try {
        userstat = await fetch('../api/julgador/treino/auth/status/', {
            headers: getToken() ? {"Bearer": getToken()} : {}
        }).then(r=>r.json());
    } catch(e) { userstat = {logged_in:false}; }
    if (userstat.logged_in) {
        let isLogged = userstat && userstat.logged_in;
        updateUserFilterBar(isLogged);
        box.insertAdjacentHTML('beforeend',
                               `<span class="user-box">
         <span class="user-box-user" title="${userstat.login}"><a href="stat?user=${encodeURIComponent(userstat.login)}"><span style="font-weight:400;color:#888;">~${userstat.login}</span></a></span>
         <button id="logout-btn" type="button">Logout</button>
       </span>`);
        document.getElementById('logout-btn').onclick = function() {
            localStorage.removeItem('moj_token_treino');
            location.reload();
        };
        return userstat.login;
    } else {
        let isLogged = userstat && userstat.logged_in;
        updateUserFilterBar(isLogged);

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
            fetch('../api/julgador/treino/auth/login/', {
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
async function fetchProblemsAndShow() {
    allProblems = await fetch('json/lista.json').then(r=>r.json());
    let tagSet = new Set();
    allProblems.forEach(prob => (prob.tags||[]).forEach(tag => tagSet.add(tag)));
    availableTags = Array.from(tagSet).sort((a,b)=>a.replace(/^#+/, '').localeCompare(b.replace(/^#+/, '')));
    let user = await showUserBar();
    resolvedByUser = user ?
        await fetch('../api/julgador/treino/solve/solvetry/', {
            headers: getToken() ? { "Bearer": getToken() } : {}
        }).then(r=>r.json()) : [];
    renderTagsArea();
    page = 1;
    doSearchAndRender();
}
// --------- BUSCA E FILTRO ---------



function doSearchAndRender() {
    let mode = document.querySelector('input[name=searchmode]:checked').value;
    let raw = document.getElementById('search-title').value.trim();
    let searchStr = raw.replace(/^#+/, '').toLowerCase();
    //let searchStr = document.getElementById('search-title').value.trim().toLowerCase();
    let filtered = allProblems;
    if (FILTER_MODE === 'solved') {
        filtered = filtered.filter(prob => resolvedByUser.solved.includes(prob.id));
    } else if (FILTER_MODE === 'attempted') {
        filtered = filtered.filter(
            prob => resolvedByUser.attempted.includes(prob.id) && !resolvedByUser.solved.includes(prob.id)
        );
    }
    if (mode==="title") {
        filtered = filtered.filter(prob =>
            !searchStr ||
                prob.title.toLowerCase().normalize("NFD").replace(/[\u0300-\u036f]/g,"").includes(
                    searchStr.normalize("NFD").replace(/[\u0300-\u036f]/g,""))
        );
        // NESTA VERSÃO: "OU" entre tags
        if (selectedTags.length) {
            filtered = filtered.filter(prob =>
                (prob.tags||[]).some(tag => selectedTags.includes(tag)) );
        }
    } else {
        filtered = filtered.filter(prob =>
            selectedTags.length
                ? (prob.tags||[]).some(tag => selectedTags.includes(tag))
                : searchStr
                ? (prob.tags||[]).some(tag =>
                    tag.replace(/^#+/, '').toLowerCase().includes(searchStr) )
                : true
        );
    }

    if (curSorted.key === 'title') {
        filtered.sort((a,b)=>curSorted.asc?a.title.localeCompare(b.title):b.title.localeCompare(a.title));
    } else if (curSorted.key === 'solved') {
        filtered.sort((a,b)=>curSorted.asc?a.solved_count-b.solved_count:b.solved_count-a.solved_count);
    } else if (curSorted.key === 'attempted') {
        filtered.sort((a,b)=>curSorted.asc?a.attempted_count-b.attempted_count:b.attempted_count-a.attempted_count);
    } else if (curSorted.key === 'percent') {
        filtered.sort((a, b) => {
            const as = a.solved_count || 0,  at = a.attempted_count || 0;
            const bs = b.solved_count || 0,  bt = b.attempted_count || 0;
            const ap = at > 0 ? as / at : -1;
            const bp = bt > 0 ? bs / bt : -1;
            // Se ambos não têm tentativas, mantém ordem inicial (ou qualquer ordem igual)
            if (ap === bp) return 0;
            return curSorted.asc ? ap - bp : bp - ap;
        });
    }
    document.getElementById('search-count').textContent =
        filtered.length + " problema(s) encontrado(s)";
    // 4. Paginação funcional
    const totalPages = Math.max(1, Math.ceil(filtered.length/PER_PAGE));
    page = Math.max(1, Math.min(page, totalPages));
    let view = filtered.slice((page-1)*PER_PAGE, page*PER_PAGE);
    renderProblemsTable(view, resolvedByUser ?? []);
    renderPager();
}
function getDifficultyBadge(acertos, total) {
    if (total === 0) return '';
    const percent = Math.round(100 * acertos / total);
    if (percent >= 90)   return `<span class="difficulty-badge difficulty-veryeasy">Muito fácil (${percent}%)</span>`;
    if (percent >= 70)   return `<span class="difficulty-badge difficulty-easy">Fácil (${percent}%)</span>`;
    if (percent >= 50)   return `<span class="difficulty-badge difficulty-medium">Médio (${percent}%)</span>`;
    return `<span class="difficulty-badge difficulty-hard">Difícil (${percent}%)</span>`;
}

function renderProblemsTable(probs) {
    let resolved = resolvedByUser.solved ?? [];
    let tbody = document.getElementById('problems-tbody');
    tbody.innerHTML = "";
    for (const prob of probs) {
        let isSolved = resolved.includes(prob.id);
        let attempted = resolvedByUser.attempted && resolvedByUser.attempted.includes(prob.id);
        let tags = (prob.tags||[]).map(tag=>
            `<a href="#" class="tag-btn smalltag" data-tag="${encodeURIComponent(tag)}">
        ${tag.replace(/^#+/,'')}
      </a>`).join(' ');
        let solved = prob.solved_count || 0, attemptedCount = prob.attempted_count || 0;
        let badge = '';
        if (solved === 0) {
            badge = `<span class="first-solver">Seja o primeiro a resolver!</span>`;
        } else {
            badge = getDifficultyBadge(solved, attemptedCount);
        }
        tbody.innerHTML += `
      <tr>
        <td>
          <a href="problem?id=${encodeURIComponent(prob.id)}" class="prob-title-link">${prob.title}</a>
          ${isSolved?`<span class="solved-indic">Resolvido</span>`:""}
          ${(!isSolved && attempted) ? `<span class="attempted-indic">Tentado</span>` : ""}
        </td>
        <td class="problem-tags-in-row tagcol">${tags}</td>
        <td>${badge}</td>
      </tr>
    `;
    }
    tbody.querySelectorAll('.smalltag').forEach(a => {
        a.onclick = function(e) {
            e.preventDefault();
            let tag = decodeURIComponent(this.dataset.tag);
            if (!selectedTags.includes(tag)) {
                selectedTags.push(tag);
                renderTagsArea();
                page = 1;
                doSearchAndRender();
            }
        };
    });
}
function renderTagsArea() {
    let tagsDiv = document.getElementById('tags-area');
    tagsDiv.innerHTML = '';
    // Limpar filtro
    tagsDiv.innerHTML += `<button id="clear-tags-btn" class="tag-btn${selectedTags.length?' selected':''}" style="font-weight:bold;margin-bottom:.3em;">Limpar filtro</button>`;
    let grouped = {};
    for(const tag of availableTags) {
        let norm = tag.replace(/^#+/,"");
        let first = norm[0] ? norm[0].toUpperCase() : '?';
        if (!grouped[first]) grouped[first] = [];
        grouped[first].push(tag);
    }
    for (const group of Object.keys(grouped).sort()) {
        tagsDiv.innerHTML += `<div style="margin: .5em 0 .1em 0;"><span style="color:#24509c;font-weight:bold;font-size:1.09em;">${group}</span> `;
        grouped[group].forEach(tag=>{
            tagsDiv.innerHTML += `<button class="tag-btn${selectedTags.includes(tag)?' selected':''}" data-tag="${encodeURIComponent(tag)}">${tag.replace(/^#+/,'')}</button>`;
        });
        tagsDiv.innerHTML += `</div>`;
    }
    tagsDiv.querySelectorAll('.tag-btn').forEach(btn=>{
        btn.onclick = function(e){
            let tg = this.id === "clear-tags-btn" ? null : decodeURIComponent(this.dataset.tag);
            if (tg === null) {
                selectedTags = [];
            } else {
                if (!selectedTags.includes(tg)) selectedTags.push(tg);
                else selectedTags = selectedTags.filter(t=>t!==tg);
            }
            renderTagsArea();
            page = 1;
            doSearchAndRender();
        }
    });
}


function renderPager() {
    let d = document.getElementById('pager');
    const searchStr = document.getElementById('search-title').value.trim().toLowerCase();
    const mode = document.querySelector('input[name=searchmode]:checked').value;
    // Repita TODO filtro usado na doSearchAndRender, mas sem slice!
    let filtered = allProblems;
    if (FILTER_MODE === 'solved') {
        filtered = filtered.filter(prob => resolvedByUser.solved.includes(prob.id));
    } else if (FILTER_MODE === 'attempted') {
        filtered = filtered.filter(
            prob => resolvedByUser.attempted.includes(prob.id) && !resolvedByUser.solved.includes(prob.id)
        );
    }
    if (mode === "title") {
        filtered = filtered.filter(prob =>
            !searchStr ||
                prob.title.toLowerCase().normalize("NFD").replace(/[\u0300-\u036f]/g, "").includes(
                    searchStr.normalize("NFD").replace(/[\u0300-\u036f]/g, ""))
        );
        if (selectedTags.length) {
            filtered = filtered.filter(prob =>
                (prob.tags || []).some(tag => selectedTags.includes(tag)));
        }
    } else {
        filtered = filtered.filter(prob =>
            selectedTags.length ?
                (prob.tags || []).some(tag => selectedTags.includes(tag))
                : (searchStr ?
                   (prob.tags || []).some(tag =>
                       tag.replace(/^#+/, '').toLowerCase().includes(searchStr)
                   )
                   : true)
        );
    }
    const totalPages = Math.max(1, Math.ceil(filtered.length / PER_PAGE));
    if (totalPages <= 1) { d.innerHTML = ""; return; }
    let h = '';
    for (let p = 1; p <= totalPages; ++p) {
        h += `<button class="pager-btn${p === page ? ' selected' : ''}" data-page="${p}">${p}</button>`;
    }
    d.innerHTML = h;
    Array.from(d.querySelectorAll('.pager-btn')).forEach(btn => {
        btn.onclick = function () {
            page = Number(this.dataset.page);
            doSearchAndRender();
        };
    });
}
function updateSortIndicators() {
    document.querySelectorAll('.problems-table th.sortable').forEach(th => {
        const ind = th.querySelector('.sort-ind');
        const key = th.getAttribute('data-sort');
        if (curSorted.key === key) {
            ind.textContent = curSorted.asc ? ' 🔼' : ' 🔽';
        } else {
            ind.textContent = ' ⇅';
        }
    });
}
document.querySelectorAll('.problems-table th.sortable').forEach(th => {
    th.addEventListener('click', function () {
        const sortKey = this.getAttribute('data-sort');
        let asc = true;
        if (curSorted.key === sortKey) asc = !curSorted.asc;
        curSorted = { key: sortKey, asc };
        document.querySelectorAll('.problems-table th').forEach(e => e.classList.remove('sorted'));
        this.classList.add('sorted');
        doSearchAndRender();
        updateSortIndicators();
    });
});
updateSortIndicators();
document.getElementById('search-title').oninput = function(){ page = 1; doSearchAndRender(); };
document.querySelectorAll('input[name=searchmode]').forEach(inp=>{
    inp.onchange = function(){ selectedTags = []; renderTagsArea(); page=1; doSearchAndRender(); }
});

document.getElementById('toggle-tags-btn').onclick = function(){
    shownTags = !shownTags;
    document.getElementById("tags-area").classList.toggle('visible', shownTags);
    this.textContent = shownTags ? "Esconder tags" : "Mostrar tags";
};
const TAGS_BLUR_STORAGE_KEY = 'moj_tags_blur'; // salva "1" (borrado) ou "0" ("unblur")
function isTagBlurred() {
    // Se não há valor, padrão é borrado ("1")
    return localStorage.getItem(TAGS_BLUR_STORAGE_KEY) !== "0";
}
function setTagBlurred(blur) {
    localStorage.setItem(TAGS_BLUR_STORAGE_KEY, blur ? "1" : "0");
}
function updateTagsBlurState(forceRedraw) {
    // Aplica a classe adequada à tabela
    let table = document.getElementById('problems-table');
    if (!table) return;
    let blur = isTagBlurred();
    //blur=1-blur;
    //setTagBlurred(blur);
    table.classList.toggle('blur-tags-table', blur);
    table.classList.toggle('unblur-tags-table', !blur);

    const btn = document.getElementById('toggle-blur-tags');

    if (btn) btn.textContent = blur ? "Desborrar Tags" : "Borrar Tags";

    // Se precisar redesenhar linhas tags, faça aqui para garantir class/click etc
    if (forceRedraw && typeof renderProblemsTable === "function") doSearchAndRender();
}
// Em algum lugar do seu JS de inicialização:
document.getElementById('toggle-blur-tags').onclick = function() {
    const novo = !(isTagBlurred());
    setTagBlurred(novo);
    updateTagsBlurState(true);
};
//window.onload = function() { fetchProblemsAndShow(); };
window.onload = function() {
    // Checa GET searchtag=
    const url = new URL(window.location.href);
    const searchtag = url.searchParams.get('searchtag');
    if (searchtag) {
        document.getElementById('searchmode-tag').checked = true;
        document.getElementById('search-title').value = searchtag.replace(/^#+/,'');
        // chama busca após carregar problemas
        fetchProblemsAndShow = (function(orig){ return function() {
            orig().then(()=>{
                doSearchAndRender();

            });
        };})(fetchProblemsAndShow);
    }
    fetchProblemsAndShow();
    updateTagsBlurState(true);

};
