document.addEventListener("DOMContentLoaded", async function () {
    // 1. Check login status (caso não autenticado: modo público + menos info)
    contestID = getContestID();
    let token = localStorage.getItem(TOKEN_KEY);
    let dest = encodeURIComponent(window.location.pathname + window.location.search + window.location.hash);
    let headersAuth = token ? { "Bearer": token } : {};
    let isAuthenticated = false;
    let userInfo = null;

    if (token) {
        try {
            let resp = await fetch(`${window.API_USERINFO}?contest=${contestID}`, {headers: headersAuth});
            let stat = await resp.json();
            isAuthenticated = !!stat.logged_in;
            userInfo=stat;
        } catch {}
    }

    let showPublicInfo = !isAuthenticated;
    if (showPublicInfo) {
        document.getElementById("info-score-public").style.display = "";
    } else {
        document.getElementById("info-score-public").style.display = "none";
    }

    // ----------- Contest info/topo/nav/user ----------
    let basic = await fetch(`${window.API_BASIC}?contest=${contestID}`).then(r=>r.json());
    window.contestLocale = basic.locale || "pt";
    document.title = basic.contest_name;
    document.getElementById('contest-title').textContent = basic.contest_name;
    window.startContestCountdown(basic.end_time, window.contestLocale);

    if (userInfo) window.showUserDetails(userInfo, window.contestLocale);
    window.initLogout && window.initLogout();
    let quicknav = await fetch(`${window.API_QUICKNAV}?contest=${contestID}`, {headers: headersAuth}).then(r=>r.json());
    window.buildContestNav(quicknav, window.contestLocale);

    // ----------- Balloon colors + regions ----------
    window.balloonColors = await window.loadBalloonColors ? await window.loadBalloonColors() : {};
    window.scoreRegions = await window.loadScoreRegions ? await window.loadScoreRegions() : [];

    // ----------- Region filter helpers/favs -----------
    window.activeRegionRegex = null; window.activeRegionFilterFun = null;
    window.scoreFavorites = [];
    window.setRegionFilter = function(regex) {
        window.activeRegionRegex = regex;
        window.activeRegionFilterFun = regex ? (t => new RegExp(regex,"i").test(t.username)) : null;
        reRenderScore();
    };
    window.toggleFavorite = function(username) {
        if (window.scoreFavorites.includes(username))
            window.scoreFavorites = window.scoreFavorites.filter(u=>u!==username);
        else
            window.scoreFavorites.push(username);
        reRenderScore();
    };
    window.renderFavoriteBar = function (teams) {
        let favdiv = document.getElementById("fav-team-bar");
        if(!favdiv) return;
        favdiv.innerHTML =
            "Favoritos: " +
            teams.filter(t => window.scoreFavorites.includes(t.username)).map(fav =>
                `<span style="background:#eee;padding:0.2em 1.3em;border-radius:1em;margin-right:.6em;display:inline-block;">
          <b>${fav["team name"]||fav.username}</b>
          <a href="#" style="color:#c55;" onclick="window.toggleFavorite('${fav.username}');return false;">x</a>
        </span>`
            ).join('');
    };
    function renderFilterBar() {
        //    return renderRegionFilters(window.scoreRegions, window.activeRegionRegex, "window.setRegionFilter") +
        return `<input type="text" id="score-fuzzy-input" placeholder="🔍 Buscar time/universidade..." style="padding:.6em 1.5em;margin-right:1.2em;font-size:1.05em;border-radius:1.2em;border:1.4px solid #bdd9f8;max-width:320px;">
      <label style="margin-right:.7em;"><input type="checkbox" id="score-no-anim"> Desabilitar animação</label>
      <span id="fav-team-bar"></span>`;
    }

    document.getElementById("score-filter-bar").innerHTML = renderFilterBar();

    let searchTerm = "", lastOrder = [], parsed = null;
    document.getElementById("score-fuzzy-input").oninput = (e) => {
        searchTerm = e.target.value;
        reRenderScore(window.parsedScore);
    };
    document.getElementById("score-no-anim").onchange = function() {
        window.scoreNoAnim = this.checked;
    };

    // ------------- Score/polling principal -------------
    async function pollScore() {
        let headers = isAuthenticated ? {"Authorization":"Bearer "+token} : {};
        let scoreTxt="";
        try {
            let resp = await fetch(window.API_SCORE, {headers});
            scoreTxt = await resp.text();
        } catch(e){
            window.location.replace(`/~ribas/contest?next=${encodeURIComponent(window.location.pathname + window.location.search + window.location.hash)}`);
            return;
        }
        if (!scoreTxt || !scoreTxt.trim()) {
            window.location.replace(`/~ribas/contest?next=${encodeURIComponent(window.location.pathname + window.location.search + window.location.hash)}`);
            return;
        }
        let scoreType = scoreTxt.trim().split(/\n/)[0].toLowerCase();
        let renderer = null;
        let parsed = null;
        if (/icpc/i.test(scoreType)) {
            renderer = window.renderICPCScore;
            parsed = window.parseICPCScore(scoreTxt, window.balloonColors);
        }
        else if (/obi/i.test(scoreType)) {
            renderer = window.renderOBIScore;
            parsed = window.parseOBIScore(scoreTxt);
        }
        else if (window.parseOutroScore && window.renderOutroScore) {
            renderer = window.renderOutroScore;
            parsed = window.parseOutroScore(scoreTxt);
        }
        if (!parsed || !renderer) {
            document.getElementById("score-table-container").innerHTML =
                "<div style='color:#a14;font-size:1.14em;margin:2em;'>Formato de placar não suportado!</div>";
            return;
        }
        window.parsedScore=parsed;
        let regionUI = renderRegionFilters(window.scoreRegions, window.activeRegionRegex, "window.setRegionFilter");
        document.getElementById("score-table-container").innerHTML = renderer(parsed, "", window.activeRegionFilterFun, window.scoreFavorites, lastOrder, regionUI);
        setTimeout(pollScore, 30000 + Math.random()*30000);
    }
    /**************  async function pollScore() {
    let headers = isAuthenticated ? {"Authorization":"Bearer "+token} : {};
    let scoreTxt;
    try {
      let resp = await fetch(window.API_SCORE, {headers});
      scoreTxt = await resp.text();
    } catch(e){
      window.location.replace(`/~ribas/contest?next=${encodeURIComponent(window.location.pathname + window.location.search + window.location.hash)}`);
      return;
    }
    if (!scoreTxt || !scoreTxt.trim()) {
      window.location.replace(`/~ribas/contest?next=${encodeURIComponent(window.location.pathname + window.location.search + window.location.hash)}`);
      return;
    }
    let scoreType = scoreTxt.trim().split(/\n/)[0].toLowerCase();
    if (/icpc/i.test(scoreType) && window.parseICPCScore)
      parsed = window.parseICPCScore(scoreTxt, window.balloonColors);
    else if (/obi/i.test(scoreType) && window.parseOBIScore)
      parsed = window.parseOBIScore(scoreTxt);
    else if (window.parseOutroScore)
      parsed = window.parseOutroScore(scoreTxt);
    if (!parsed) {
      document.getElementById("score-table-container").innerHTML =
      "<div style='color:#a14;font-size:1.14em;margin:2em;'>Formato de placar não suportado!</div>";
      return;
    }
    reRenderScore(parsed);
    setTimeout(pollScore, 30000 + Math.random()*30000);
  }
    *******************/
    function reRenderScore(parsed) {
        let filterFn = window.activeRegionFilterFun;
        let regionUI = renderRegionFilters(window.scoreRegions, window.activeRegionRegex, "window.setRegionFilter");
        let favs = window.scoreFavorites || [];
        let tableHtml = window.renderICPCScore
            ? window.renderICPCScore(parsed, searchTerm, filterFn, favs, lastOrder, regionUI)
            : "<div style='color:#a14;font-size:1.14em;margin:2em;'>Nenhum renderer disponível!</div>";

        // Patch table: anima apenas linhas que mudaram, mas reescreve corpo inteiro para manter a renderização simples — 
        document.getElementById("score-table-container").innerHTML = tableHtml;
        //window.renderFavoriteBar && window.renderFavoriteBar(parsed ? parsed.teams : []);
        // Animação leve:
        /*
          const oldOrderMap = lastOrder.reduce((acc, t, idx) => {acc[t.username]=idx; return acc;}, {});
          parsed.teams.forEach((t, idx) => {
          let row = document.getElementById("tr-team-"+t.username.replace(/\W/g,'_'));
          if (row && oldOrderMap[t.username]!=null) {
          let oldIdx = oldOrderMap[t.username];
          if (oldIdx > idx) { row.classList.add("placing-up"); setTimeout(()=>row.classList.remove("placing-up"),900);}
          else if (oldIdx < idx) { row.classList.add("placing-down"); setTimeout(()=>row.classList.remove("placing-down"),900);}
          }
          });*/
        lastOrder = parsed.teams.slice();
        // Sortable headers
        setTimeout(function(){
            document.querySelectorAll('.score-table th.sortable').forEach(th=>{
                th.onclick = function(){
                    let sf = th.getAttribute('data-sort');
                    if(sf) {
                        window.sortAsc = (window.sortField===sf) ? !window.sortAsc : false;
                        window.sortField = sf;
                        reRenderScore(parsed);
                        document.querySelectorAll('.score-table th').forEach(x=>x.classList.remove('sorted'));
                        th.classList.add('sorted');
                    }
                }
            });
        },10);
    }

    // Filtros e eventos de região

    // Tenta restaurar do localStorage o filtro ativo de região
    let savedRegionRegex = localStorage.getItem("score_region_filter");
    window.activeRegionRegex = savedRegionRegex ? savedRegionRegex : null;
    window.activeRegionFilterFun = savedRegionRegex ? (team => new RegExp(savedRegionRegex, "i").test(team.username)) : null;

    window.setRegionFilter = function(regex) {

        window.activeRegionRegex = regex;
        localStorage.setItem("score_region_filter", regex || "");
        window.activeRegionFilterFun = regex ? (team => new RegExp(regex, "i").test(team.username)) : null;
        reRenderScore(window.parsedScore);
    };
    window.toggleFavorite = window.toggleFavorite;
    //window.renderFavoriteBar = window.renderFavoriteBar;
    pollScore();

    //reRenderScore(window.parsedScore); // Chamado só para filtro inicial
    document.addEventListener("click",function(e){
        const th = e.target.closest('.score-table th.sortable');
        if(th) {
            let sf = th.getAttribute('data-sort');
            if(sf) {
                if(sf.startsWith("prob:")) {
                    window.sortField = sf;
                    window.sortAsc = false; // ICPC: decrescente, show accepted primeiro
                } else {
                    window.sortAsc = (window.sortField===sf) ? !window.sortAsc : false;
                    window.sortField = sf;
                }
                reRenderScore(window.parsedScore);
                document.querySelectorAll('.score-table th').forEach(x=>x.classList.remove('sorted'));
                th.classList.add('sorted');
            }
        }
    }, true);
});
