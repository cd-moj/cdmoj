const sonicImages = [
    'https://media.tenor.com/0d9u7FDYIyMAAAAi/sonic.gif',
    'https://media.tenor.com/1omfDli6KCEAAAAj/sonic-sonic-the-hedgehog.gif',
    'https://media.tenor.com/42FLUDoGy58AAAAj/sonic-ring-sonic.gif',
    'https://media.tenor.com/5frl25WiIZMAAAAj/superknuckles-sonic.gif',
    'https://media.tenor.com/7pVopZZ9VagAAAAj/sonic3-sonic.gif',
    'https://media.tenor.com/8dV75SPpJWgAAAAj/sonic-the-hedgehog-sonic-mania.gif',
    'https://media.tenor.com/aFxaR-xnilkAAAAj/sonic-fear.gif',
    'https://media.tenor.com/BgRhHvJtmZwAAAAj/sanic-weird.gif',
    'https://media.tenor.com/_bMflfsK-pkAAAAj/sonic-the-hedgehog.gif',
    'https://media.tenor.com/c8iSzIs3if0AAAAj/sonic-the.gif',
    'https://media.tenor.com/CPoRb3M0JXMAAAAj/tails-sonic-tails.gif',
    'https://media.tenor.com/d7jgDuI-rjIAAAAj/sonic-the-hedgehog-sonic.gif',
    'https://media.tenor.com/e94GdKRbWkAAAAAj/sega-the-death-egg.gif',
    'https://media.tenor.com/enihTZnEU9MAAAAj/sonic-fnf.gif',
    'https://media.tenor.com/EyjY9IVeyegAAAAj/sonic-holds-on.gif',
    'https://media.tenor.com/-f39UNfUasoAAAAj/sonic-the-hedgehog.gif',
    'https://media.tenor.com/FAUhgUjW2VoAAAAj/sonic.gif',
    'https://media.tenor.com/F-OLy-dTBQIAAAAi/sonic-fortnite-dance.gif',
    'https://media.tenor.com/HdPg4vrZJwwAAAAj/super-sonic-in-sonic1.gif',
    'https://media.tenor.com/hO325th5zlkAAAAj/fnf-sonic.gif',
    'https://media.tenor.com/If2ncKAUATcAAAAj/sonic-wow.gif',
    'https://media.tenor.com/iM7gI7yiV3MAAAAj/knuckles-dancing.gif',
    'https://media.tenor.com/IyKvqYp5DW8AAAAj/sonic-the-hedgehog.gif',
    'https://media.tenor.com/jA7VHRE-f-QAAAAj/tails-sonic-tails.gif',
    'https://media.tenor.com/k1adCGAcWmEAAAAj/fleetway-super-sonic.gif',
    'https://media.tenor.com/M46uN9EhkAwAAAAj/fortnite-pixel.gif',
    'https://media.tenor.com/NIVbXrmMPNwAAAAj/sonic-advance.gif',
    'https://media.tenor.com/osjfCirlN4MAAAAj/sonic-the-hedgehog.gif',
    'https://media.tenor.com/RvCf_01rx-YAAAAi/sonic-the-hedgehog-prey-fnf.gif',
    'https://media.tenor.com/RyDqT7JsYxAAAAAj/sanic-dance-sanic.gif',
    'https://media.tenor.com/SI9Z-5BNjzsAAAAj/sonic-fnf.gif',
    'https://media.tenor.com/sSIORuWA99AAAAAj/sonic-the-hedgehog.gif',
    'https://media.tenor.com/VEp3WM5DV3UAAAAi/sonic.gif',
    'https://media.tenor.com/w2MnXF-FiPwAAAAj/sonic-pushing-retro-old-sth.gif',
    'https://media.tenor.com/weesaMMiVVMAAAAj/sonic.gif',
    'https://media.tenor.com/WIEKeqWCP5UAAAAi/srb2kart-sonic.gif',
    'https://media.tenor.com/XDn1FGmrwlEAAAAj/sonic-the-hedgehog.gif'
];

// Função utilitária para escolher aleatoriamente
function pickRandom(arr) {
    return arr[Math.floor(Math.random() * arr.length)];
}
// Retorna o index (fixo) do Sonic para um submissionId. Se não existir, sorteia, salva e retorna.
function getSonicIndexForSubmission(submissionId) {
    // Pega cache do localStorage
    const cacheKey = 'submissionSonicCache';
    let cache = {};
    try {
        cache = JSON.parse(localStorage.getItem(cacheKey)) || {};
    } catch (e) {
        // Se der erro, cache fica vazio
    }

    // Retorna já associado
    if (cache[submissionId] !== undefined) {
        return cache[submissionId];
    }

    // Se não houver, sorteia novo, salva, persiste
    const newIdx = Math.floor(Math.random() * sonicImages.length);
    cache[submissionId] = newIdx;
    localStorage.setItem(cacheKey, JSON.stringify(cache));
    return newIdx;
}
// Função para gerar o "ícone" da submissão
function getSubmissionIcon(status,submissionId) {
    const sonicEnabled = window.balloonColors["enableSonic"];
    const balloon = '<span class="balloon correct"></span>';
    const spinner = '<span class="spinner"></span>';

    if (sonicEnabled && submissionId) {
        const idx = getSonicIndexForSubmission(submissionId);
        const chosen = sonicImages[idx];

        if (status === "pending") {
            return `<img src="${chosen}" alt="Sonic" height="24">`;
        }
        if (status === "correct") {
            return `<img src="${chosen}" height="64" alt="Sonic">`;
        }

    }

    if (status === "pending") {
        return spinner;
    }
    if (status === "correct") {
        return balloon;
    }
    return '';
}
document.addEventListener("DOMContentLoaded", async function() {
    // --- LOGIN CHECK ---
    contestID = getContestID();
    let token = localStorage.getItem(`contest_token_${contestID}`);
    let dest = encodeURIComponent(window.location.pathname + window.location.search + window.location.hash);

    if (!token) {
    //    window.location.replace(`../?next=${dest}&contest=${contestID}`);
      //  return;
    }

    // Check login authenticated
    let userInfo = await fetch(`${API_USERINFO}/${contestID}/auth/status/`, {
        headers: { "Bearer": token }
    }).catch(() => null);
    let stat = userInfo ? await userInfo.json() : null;
    if (!stat || !stat.logged_in) {
//        window.location.replace(`../?next=${dest}&contest=${contestID}`);
  //      return;
    }
    userInfo=stat;
    // --- Contest info ---
    let basic = await fetch(`${window.API_BASIC}?contest=${contestID}`).then(r=>r.json());
    window.contestLocale = basic.locale || "pt";
    document.title = basic.contest_name;
    document.getElementById('contest-title').textContent = basic.contest_name;
    window.startContestCountdown(basic.end_time, window.contestLocale);

    // --- Auth header for all APIs ---
    let headersAuth = { "Bearer": token };

    // --- User & nav ---
    let quicknav = await fetch(`${window.API_QUICKNAV}?contest=${contestID}`, {headers: headersAuth}).then(r=>r.json());
    window.buildContestNav(quicknav, window.contestLocale);
    window.showUserDetails(stat, window.contestLocale);
    window.contestUserInfo = userInfo;
    window.canViewLog = !!userInfo.show_log;

    window.initLogout && window.initLogout();

    // --- News/resources (podem falhar) ---
    try {
        let news = await fetch(`${window.API_NEWS}?contest=${contestID}`, {headers: headersAuth}).then(r=>r.json());
        document.getElementById("info-news-section").style.display = "";
        document.getElementById("info-news-title").textContent = window.contestLocale==="pt"?"Informações & Notícias":"Info & News";
        let nlist=document.getElementById("news-list");
        nlist.innerHTML = news.map(n=>`<li><b style="color:#236;">${n.title}</b>
      <span style="color:#7e7d84;font-size:.9em">(${
      window.fmtDate(n.date,window.contestLocale==="pt")})</span><br>${n.text}</li>`).join('');
    } catch(e){ document.getElementById("info-news-section").style.display="none"; }
    try {
        let resources=await fetch(`${window.API_RESOURCES}?contest=${contestID}`,{headers:headersAuth}).then(r=>r.json());
        if(resources && resources.length){
            document.getElementById("resources-section").style.display="";
            let resc=document.getElementById("resources-list");
            resc.innerHTML=resources.map(r=>`<li><a href="${r.url}">${r.label}</a></li>`).join('');
        } else {document.getElementById("resources-section").style.display="none"; }
    } catch(e){ document.getElementById("resources-section").style.display="none"; }

    //Ballon Colors
    try {
        const bcResp = await fetch(`${window.API_BALLOON_COLORS}?contest=${contestID}`, {headers: { "Authorization": "Bearer " + localStorage.getItem("contest_token") }});
        window.balloonColors = await bcResp.json();
    } catch(e) { window.balloonColors = null; }
    
    // --- Problems/autenticados & accordion-list ---
    let problemsResp = await fetch(`${window.API_PROBLEMS}?contest=${contestID}`, {headers: headersAuth});
    if (!problemsResp.ok) return; // ou mostre mensagem amigável
    window.contestProblems = await problemsResp.json();
    if (!Array.isArray(window.contestProblems) || !window.contestProblems.length) return;

    // Monta a lista de problemas (accordion) só quando realmente existe
    if(window.renderProblemsList)
        window.renderProblemsList(window.contestProblems);

    // Inicializa accordion (expansão/collapse)
    document.getElementById('problem-list').onclick = function(e){
        let tgt = e.target.closest('.acc-header-left');
        if(tgt) {
            let pid = tgt.parentNode.id.replace(/^acc-/,'');
            window.expandCollapseProblem && window.expandCollapseProblem(pid);
        }
    };

    // Setup submit local em cada problema (arquivo problems.js ou no main.js)
    window.contestProblems.forEach(p=>{
        //if(!p.show) return;
        let form = document.getElementById("problem-send-"+p.problem_id);
        let btn = document.getElementById("sbmbt-"+p.problem_id);
        let msg = document.getElementById("submit-msg-"+p.problem_id);
        if(form) {
            console.log(form.onsubmit);
            form.onsubmit = function(e) {
                e.preventDefault();
                let fileInput = document.getElementById("file-upload-"+p.problem_id);
                if(!fileInput.files[0]){msg.textContent="Escolha um arquivo";return;}
                let file = fileInput.files[0];
                btn.disabled = true;
                msg.innerHTML = `<span class="loader-animation"></span> Lendo arquivo...`;
                let reader = new FileReader();
                reader.onload = function(event) {
                    msg.innerHTML = `<span class="loader-animation"></span> Enviando...`;
                    let raw = new Uint8Array(event.target.result), binary="";
                    for(let i=0;i<raw.length;i++) binary+=String.fromCharCode(raw[i]);
                    let code_b64 = btoa(binary);
                    fetch(`${window.API_SUBMIT}/${contestID}/submission/submit/`,
                          {method:"POST",
                           body:JSON.stringify({problem_id:p.problem_id,filename:file.name,code_b64:code_b64}),
                           headers:{ "Content-Type":"application/json", "Bearer": token}
                          }).then(r=>r.json()).then(resp=>{
                              msg.innerHTML = resp.success ? "Enviado!" : `<span style="color:red">Erro: ${resp.error||"Falha"}</span>`;
                              if(resp.success && window.fetchAndRenderSubmissions) setTimeout(window.fetchAndRenderSubmissions, 1200);
                              btn.disabled = false;
                          }).catch(()=>{
                              msg.textContent="Falha ao enviar."; btn.disabled = false;
                          });
                };
                reader.readAsArrayBuffer(file);
            }
            console.log(form.onsubmit);
        }
    });
    window.normalizeVerdict = function(str) {
        str=str.trim();
        if (/^(Accepted)/i.test(str)) return "Accepted";
        if (/^(Wrong|Wrong Answer)/i.test(str)) return "Wrong Answer";
        if (/^(Time Limit)/i.test(str)) return "Time Limit Exceeded";
        if (/^(Possible Runtime|Runtime)/i.test(str)) return "RunTime Error";
        if (/^(Compilation Error|Language)/i.test(str)) return "Compilation Error";
        return str.replace(/,.*/,"").trim();
    };
    // Poll/filtro/sort da table de submissões
    window.fetchAndRenderSubmissions && window.fetchAndRenderSubmissions();
});
