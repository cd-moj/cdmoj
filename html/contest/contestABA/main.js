document.addEventListener("DOMContentLoaded", async function(){
    // 1. Descobre contest_id do subdomínio, exemplo: icpc2025.moj.naquadah.com.br -> icpc2025
    let host = window.location.hostname;
    let contestID = host.split(".")[0];

    const token = localStorage.getItem("contest_token");
    let dest = encodeURIComponent(window.location.pathname + window.location.search + window.location.hash);

    if (!token) {
        window.location.replace(`/~ribas/contest?next=${dest}`);
        return;
    }
    // Agora faz a verificação autenticada
    let resp;
    try {
        resp = await fetch(`/~ribas/api/auth/status.sh?contest=${encodeURIComponent(contestID)}`, {
            headers: { "Bearer": token }
        });
    } catch(e) {
        // Falha na requisição, trata como não logado
        //window.location.replace(`/~ribas/contest?next=${dest}`);
        //return;
    }
    let stat = await resp.json();
    if (!stat.logged_in) {
       // window.location.replace(`/~ribas/contest?next=${dest}`);
       // return;
    }


    // 1. Contest basic info (sem autenticação)
    let basic = await fetch(window.API_BASIC).then(r=>r.json());
    window.contestLocale = basic.locale || "pt";
    document.title = basic.contest_name;
    document.getElementById('contest-title').textContent = basic.contest_name;
    window.startContestCountdown(basic.end_time, window.contestLocale);

    // 2. Userinfo e nav com token
    let tok = localStorage.getItem(window.TOKEN_KEY);
    let headersAuth = tok ? {'Authorization':'Bearer '+tok} : {};
    let userInfo, quicknav;
    try {
        userInfo = await fetch(window.API_USERINFO, {headers: headersAuth}).then(r=>r.json());
        quicknav = await fetch(window.API_QUICKNAV, {headers: headersAuth}).then(r=>r.json());
        window.buildContestNav(quicknav, window.contestLocale);
        window.showUserDetails(userInfo, window.contestLocale);
        window.contestUserInfo = userInfo;
        window.canViewLog = !!userInfo.show_log;
    } catch(e) {}

    window.initLogout && window.initLogout();

    // 3. News/resources autenticadas (podem falhar)
    try {
        let news = await fetch(window.API_NEWS, {headers: headersAuth}).then(r=>r.json());
        document.getElementById("info-news-section").style.display = "";
        document.getElementById("info-news-title").textContent = window.contestLocale==="pt"?"Informações & Notícias":"Info & News";
        let nlist=document.getElementById("news-list");
        nlist.innerHTML = news.map(n=>`<li><b style="color:#236;">${n.title}</b>
      <span style="color:#7e7d84;font-size:.9em">(${
      window.fmtDate(n.date,window.contestLocale==="pt")})</span><br>${n.text}</li>`).join('');
    } catch(e){ document.getElementById("info-news-section").style.display="none"; }
    try {
        let resources=await fetch(window.API_RESOURCES,{headers:headersAuth}).then(r=>r.json());
        if(resources && resources.length){
            document.getElementById("resources-section").style.display="";
            let resc=document.getElementById("resources-list");
            resc.innerHTML=resources.map(r=>`<li><a href="${r.url}">${r.label}</a></li>`).join('');
        } else {document.getElementById("resources-section").style.display="none"; }
    } catch(e){ document.getElementById("resources-section").style.display="none"; }

    // 4. Problems autenticados
    window.contestProblems = await fetch(window.API_PROBLEMS, {headers: headersAuth}).then(r=>r.json());
    let shortNameToId = {}, idToShortName = {};
    window.contestProblems.forEach(p=>{
        if(p.short_name&&p.problem_id){
            shortNameToId[p.short_name]=p.problem_id;
            idToShortName[p.problem_id]=p.short_name;
        }
    });
    window.currProb = window.contestProblems.length > 0 ? window.contestProblems[0].problem_id : "";

    // Popula select do form
    let globalSelect = document.getElementById("problem-choice");
    globalSelect.innerHTML = window.contestProblems.filter(p=>p.show!==false)
        .map(p=>`<option value="${p.problem_id}">${p.short_name}: ${p.full_name}</option>`).join('');
    globalSelect.value = window.currProb;

    // Abas + painéis
    document.getElementById('problem-tabs').innerHTML = window.makeProblemTabs(window.contestProblems, window.currProb);
    document.getElementById('problem-panels').innerHTML = window.makeProblemPanels(window.contestProblems, window.currProb);
    window.normalizeVerdict = function(str) {
        str=str.trim();
        if (/^(Accepted)/i.test(str)) return "Accepted";
        if (/^(Wrong|Wrong Answer)/i.test(str)) return "Wrong Answer";
        if (/^(Time Limit)/i.test(str)) return "Time Limit Exceeded";
        if (/^(Possible Runtime|Runtime)/i.test(str)) return "RunTime Error";
        if (/^(Compilation Error|Language)/i.test(str)) return "Compilation Error";
        return str.replace(/,.*/,"").trim();
    };
    // Sincronização de tabs, form, panels
    function syncTabPanelAndForm(pid) {
        window.currProb = pid;
        let sel = document.getElementById("problem-choice");
        if(sel) sel.value = pid;
        document.querySelectorAll('.prob-tab').forEach(tab =>
            tab.classList.toggle('active', tab.dataset.pb === pid));
        document.querySelectorAll('.prob-panel').forEach(pn =>
            pn.classList.toggle('active', pn.dataset.prob === pid));
    }

    document.querySelectorAll('.prob-tab').forEach(btn=>{
        btn.onclick = function() { syncTabPanelAndForm(this.dataset.pb); }
    });
    globalSelect.onchange = function() { syncTabPanelAndForm(this.value); };
    syncTabPanelAndForm(window.currProb);

    // Monta submit global (submit.js)
    window.setupProblemSubmit && window.setupProblemSubmit(
        window.contestProblems,
        window.fetchAndRenderSubmissions // callback após submit
    );

    // Poll/filtro/sort da table de submissões (submissions.js)
    window.fetchAndRenderSubmissions && window.fetchAndRenderSubmissions();

});
