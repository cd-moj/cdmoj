// ------------------ Funções Gerais  -----------------------
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
function fuzzyFilter(list, query) {
    if(!query) return list;
    const q = query.trim().toLowerCase();
    return list.filter(
        c => c.title && c.title.toLowerCase().normalize("NFD").replace(/[\u0300-\u036f]/g,"").includes(
            q.normalize("NFD").replace(/[\u0300-\u036f]/g,"")
        )
    );
}
function scrollToAnchor(id) {
    let el = document.getElementById(id);
    if (el) el.scrollIntoView({ behavior: 'smooth' });
}
document.querySelectorAll('.quick-menu-link').forEach(link => {
    link.addEventListener('click', function(e){
        if(this.hash){ e.preventDefault(); scrollToAnchor(this.hash.substring(1)); }
    });
});

// ----------------- Treino Livre --------------------------
let rawOpenTraining = {};
function renderTopUsers(list) {
    const tbody = document.getElementById("top-users-table");
    tbody.innerHTML = "";
    if (!list || !list.length) {
        tbody.innerHTML = `<tr><td colspan="3" class="minor">Nenhum usuário encontrado!</td></tr>`;
        return;
    }
    list.forEach((user, idx) => {
        const tr = document.createElement("tr");
        tr.innerHTML = `
      <td>${idx<3 ? ["🥇","🥈","🥉"][idx] : (idx+1)}</td>
      <td>${user.name} <span class="minor">(<a class="minor" href="$BASEURL/treino/stat?user=${user.username}">~${user.username}</a>)</span></td>
      <td>${user.solved_count}</td>
    `;
        tbody.appendChild(tr);
    });
}
function renderRecentSolved(list) {
    const ul = document.getElementById("recent-solved-list");
    ul.innerHTML = list.length ? "" : `<li class="minor">Nenhuma submissão recente.</li>`;
    list.forEach(solved => {
        const li = document.createElement("li");
        li.innerHTML = `
      <a href="${solved.url}">${solved.problem_title}</a>
      <span class="user-badge">${solved.user.name} (<a class="minor" href="$BASEURL/treino/stat?user=${solved.user.username}">~${solved.user.username}</a>)</span>
      <span class="minor">${formatDate(solved.solved_at)}</span>
    `;
        ul.appendChild(li);
    });
}
function renderMostSolvedWeek(list) {
    const tbody = document.getElementById("most-solved-week-table");
    tbody.innerHTML = list.length
        ? ""
        : `<tr><td colspan="2" class="minor">Nenhum problema mais resolvido ainda.</td></tr>`;
    list.forEach(prob => {
        const tr = document.createElement("tr");
        tr.innerHTML = `<td><a href="${prob.url}">${prob.problem_title}</a></td><td>${prob.solved_count}</td>`;
        tbody.appendChild(tr);
    });
}
function renderOpenTraining(data) {
    renderTopUsers((data && data.top_users) || []);
    renderRecentSolved((data && data.recent_solved) || []);
    renderMostSolvedWeek((data && data.most_solved_week) || []);
    document.getElementById("search-problems-link").href = data.search_problems_url || "#";
}

// ----------------- Notícias ------------------------------
function renderNews(news, all_url) {
    const ul = document.getElementById("news-list");
    document.getElementById("all-news-link").href = all_url || "/news";
    ul.innerHTML = news.length ? "" : `<li class="minor">Nenhuma notícia recente.</li>`;
    news.forEach(item => {
        const li = document.createElement("li");
        li.innerHTML = `
      <a href="${item.url}"><strong>${item.title}</strong></a>
      <span class="minor">(${formatDate(item.date)})</span><br>
      <span>${item.summary}</span>
    `;
        ul.appendChild(li);
    });
}

// ----------------- Contests ------------------------------
let closedPage = 1;
let closedFilter = '';
let openFilter = '';
let upcomingFilter = '';
let rawOpenContests = [];
let rawUpcomingContests = [];
let currentClosedJson = null;

function renderContestsList(list, ulId, showScoreboard = false) {
    const ul = document.getElementById(ulId);
    ul.innerHTML = list.length ? "" : `<li class="minor">Nenhum contest!</li>`;
    list.forEach(contest => {
        const li = document.createElement("li");
        let links = `<a href="${contest.url}">Detalhes</a>`;
        if (showScoreboard && contest.scoreboard_url)
            links += ` | <a href="${contest.scoreboard_url}">Placar</a>`;
        li.innerHTML = `
      <a href="${contest.url}" class="contest-title-badge">${contest.title}</a>
      <div class="contest-info">
        <div>Início: ${formatDate(contest.start_time)}</div>
        <div>Fim: ${formatDate(contest.end_time)}</div>
        <div>
          Problemas: ${contest.problems_count}${contest.participants_count ? ", Participantes: " + contest.participants_count : ""}
        </div>
        <div class="contest-links">${links}</div>
      </div>
    `;
        ul.appendChild(li);
    });
}

function renderContestsUpcoming(list) { renderContestsList(list, "upcoming-contests-list", false); }
function renderContestsOpen(list) { renderContestsList(list, "open-contests-list", true); }
function renderContestsClosed(pageObj) {
    const ul = document.getElementById("closed-contests-list");
    const filter = closedFilter.toLowerCase();
    ul.innerHTML = "";
    let filteredItems = pageObj.items;
    if(filter) filteredItems = filteredItems.filter(contest => contest.title.toLowerCase().includes(filter));
    if (!filteredItems || !filteredItems.length)
        ul.innerHTML = `<li class="minor">Nenhum contest encerrado nessa página/filtro.</li>`;
    else {
        filteredItems.forEach(contest => {
            const li = document.createElement("li");
            let links = `<a href="${contest.url}">Detalhes</a>`;
            if (contest.results_url)
                links += ` | <a href="${contest.results_url}">Resultados</a>`;
            if (contest.stats_url)
                links += ` | <a href="${contest.stats_url}">Estatística</a>`;
            li.innerHTML = `
        <a href="${contest.url}" class="contest-title-badge">${contest.title}</a>
        <div class="contest-info">
          <div>Início: ${formatDate(contest.start_time)}</div>
          <div>Fim: ${formatDate(contest.end_time)}</div>
          <div>
            Problemas: ${contest.problems_count}${contest.participants_count ? ", Participantes: " + contest.participants_count : ""}
          </div>
          <div class="contest-links">${links}</div>
        </div>
      `;
            ul.appendChild(li);
        });
    }
    // Paginação
    const pageInfo = document.getElementById("closed-page-info");
    const total = pageObj.total || 1, perPage = pageObj.per_page || 10, currentPage = pageObj.page || 1;
    pageInfo.textContent = `Página ${currentPage} de ${Math.max(1, Math.ceil(total / perPage))}`;
    document.getElementById("closed-prev").disabled = (currentPage <= 1);
    document.getElementById("closed-next").disabled = (currentPage >= Math.ceil(total / perPage));
}

// Filtro fuzzy local para abertos
document.getElementById("open-filter").oninput = function() {
    openFilter = this.value;
    renderContestsOpen(fuzzyFilter(rawOpenContests, openFilter));
};
// Filtro fuzzy local para por vir
document.getElementById("upcoming-filter").oninput = function() {
    upcomingFilter = this.value;
    renderContestsUpcoming(fuzzyFilter(rawUpcomingContests, upcomingFilter));
};

document.getElementById("closed-prev").onclick = function() {
    if(closedPage > 1){
        closedPage--;
        fetchContestsJson();
    }
};
document.getElementById("closed-next").onclick = function() {
    closedPage++;
    fetchContestsJson();
};
document.getElementById("closed-filter").oninput = function() {
    closedFilter = this.value;
    closedPage = 1;
    renderContestsClosed(currentClosedJson.closed);
};

// ----------------- Carregamento dos JSONs separadamente -------------
function fetchOpenTrainingJson() {
    fetch('../public/treino_stats.json')
        .then(res => res.json())
        .then(data => {
            rawOpenTraining = data;
            renderOpenTraining(data);
        });
}
function fetchNewsJson() {
    fetch('../public/news.sh')
        .then(res => res.json())
        .then(data => {
            renderNews(data.news || [], data.all_news_url);
        });
}
function fetchContestsJson() {
    //fetch('../public/contests.sh?page=' +closedPage)
    fetch('../public/contests.json')
        .then(res => res.json())
        .then(data => {
            // Atualiza lista bruta para filtro local
            rawOpenContests = (data.open || []);
            rawUpcomingContests = (data.upcoming || []);
            currentClosedJson = data;
            renderContestsOpen(fuzzyFilter(rawOpenContests, openFilter));
            renderContestsUpcoming(fuzzyFilter(rawUpcomingContests, upcomingFilter));
            renderContestsClosed(data.closed);
        });
}
window.onload = function() {
    fetchOpenTrainingJson();
    fetchNewsJson();
    fetchContestsJson();
};
