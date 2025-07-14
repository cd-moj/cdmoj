const API_BASIC = "../api/contest/json/basic.json";
const API_COUNTRIES = "../api/contest/json/participating-flags.json";
const API_LOGIN = "../api/julgador//login.sh";
TOKEN_KEY = "contest_token";
let QUERYCONTEST="";
let contestLocale = "pt";
let contestStart = 0, loginStart = 0, currentCountdownEPOCH = null;
let countdownTimer = null, pollBasicTimer = null, animatingCountdown = false;
let countdownTargetValue = 0;
let contestID="unknowncontest";

function getQueryParam(name) {
    const url = new URL(window.location.href);
    return url.searchParams.get(name) || "";
}

function getContestID(){
    let host = window.location.hostname;
    let contestID = host.split(".")[0];
    let contestIDparam=getQueryParam("contest");
    if(contestID=="moj" && contestIDparam!="") {
        contestID=`${contestIDparam}`;
        QUERYCONTEST=`?contest=${contestIDparam}`;
    }
    else if(contestID=="localhost" && contestIDparam=="")
        contestID="unknowncontest";
    else if(contestID=="localhost" && contestIDparam!="") {
        contestID=`${contestIDparam}`;
        QUERYCONTEST=`?contest=${contestIDparam}`;
    }
    else if(contestID!="moj" && contestIDparam=="")
        contestID=`contest_token_${contestID}`;
    else
        contestID="unknowncontest";
    TOKEN_KEY=`contest_token_${contestID}`;
    return contestID;
}

function showCountdownLeft(left) {
    document.getElementById("countdown-box").style.display = "";
    document.getElementById("countdown-time").textContent = fmtLeft(left);
}

function hideCountdown() {
    document.getElementById("countdown-box").style.display = "none";
}

function setLoginFormVisible(visible) {
    let f = document.getElementById("login-form");
    if (visible) {
        f.style.display = "";
        setTimeout(() => f.classList.add("visible"), 50);
    } else {
        f.style.display = "none";
        f.classList.remove("visible");
    }
}

// Nova animação robusta
function animateCountdownTransition(oldLeft, newLeft, onDone) {
    animatingCountdown = true;
    clearTimeout(countdownTimer);
    let steps = Math.min(Math.abs(newLeft - oldLeft), 20), current = oldLeft, s = 0;
    if (steps === 0) { 
        showCountdownLeft(newLeft); 
        animatingCountdown = false;
        if (onDone) onDone();
        return; 
    }
    let perStep = (newLeft - oldLeft) / steps;
    function go() {
        current = oldLeft + perStep * s;
        showCountdownLeft(Math.round(current));
        s++;
        if (s <= steps) {
            countdownTimer = setTimeout(go, 25); // cada frame rápido
        } else {
            showCountdownLeft(newLeft);
            animatingCountdown = false;
            if (onDone) onDone();
        }
    }
    go();
}

// Poll sempre pega fresh values
async function pollBasic() {
    let basic = await fetch(`${API_BASIC}?contest=${contestID}`).then(r=>r.json());
    contestLocale = basic.locale || "pt";
    contestStart = basic.start_time;
    loginStart = basic.login_start_time != null ? basic.login_start_time : basic.start_time;
    document.getElementById("contest-name").textContent = basic.contest_name;
    document.getElementById("contest-times").innerHTML =
        contestLocale==="pt"
        ? `Início: ${fmtDate(basic.start_time,true)}<br>Término: ${fmtDate(basic.end_time,true)}`
        : `Start: ${fmtDate(basic.start_time,false)}<br>End: ${fmtDate(basic.end_time,false)}`;
    document.getElementById("lbl-user").textContent = contestLocale==="pt" ? "Login:" : "Username:";
    document.getElementById("lbl-pass").textContent = contestLocale==="pt" ? "Senha:" : "Password:";
    document.querySelector(".login-btn").textContent = contestLocale==="pt" ? "Entrar" : "Login";
    document.getElementById("countdown-lbl").textContent =
        contestLocale === "pt" ? "Abertura em" : "Opens in";

    let now = Math.floor(Date.now()/1000);
    let left = loginStart - now;

    // Se já animando, aguarde terminar
    if (animatingCountdown) return;

    if (typeof countdownTargetValue === 'undefined') countdownTargetValue = left;
    // Se login_start_time mudou, faça animação mês próximo
    if (currentCountdownEPOCH !== null && loginStart !== currentCountdownEPOCH) {
        let oldLeft = countdownTargetValue; // valor final real exibido
        currentCountdownEPOCH = loginStart;
        countdownTargetValue = left;
        animateCountdownTransition(oldLeft, left, () => {
            // Após animação, retome o polling normal
            pollBasicSchedule();
            updateCountdownAndShowLogin();
        });
        return;
    }
    currentCountdownEPOCH = loginStart;
    countdownTargetValue = left;
    if (left > 0) {
        setLoginFormVisible(false);
        showCountdownLeft(left);
        pollBasicSchedule();
        updateCountdownAndShowLogin();
    } else {
        hideCountdown();
        setLoginFormVisible(true);
    }
}

function pollBasicSchedule() {
    clearTimeout(pollBasicTimer);
    let now = Math.floor(Date.now()/1000);
    let left = loginStart - now;
    pollBasicTimer = setTimeout(pollBasic, left>60 ? 10000 : 6000);
}

function updateCountdownAndShowLogin() {
    if (animatingCountdown) return;
    let now = Math.floor(Date.now()/1000);
    let left = loginStart - now;
    if (left > 0) {
        showCountdownLeft(left);
        countdownTimer = setTimeout(updateCountdownAndShowLogin, 1000);
    } else {
        pollBasic();
    }
}

function setFadeIn() {
    setTimeout(()=>document.body.classList.add("faded"), 25);
}

document.addEventListener("DOMContentLoaded", () => {
    setFadeIn();
    contestID=getContestID();
    if(contestID == "unknowncontest" )
    {
        document.getElementById("contest-name").textContent =
            (contestLocale="BAD Contest NAME, please follow correct URL");
        return false;
    }
    pollBasic();
    fetch(`${API_COUNTRIES}?contest=${contestID}`).then(r=>r.json()).then(updateCountriesFlagBar);
    document.getElementById("login-form").onsubmit = function(e){
        e.preventDefault();
        let btn = this.querySelector('.login-btn');
        btn.disabled = true;
        document.getElementById("login-error").innerHTML = "";
        fetch(`../api/julgador/${contestID}/auth/login/`,{
            method:"POST",
            body:JSON.stringify({
                username:this["login-user"].value,
                password:this["login-pass"].value
            }),
            headers:{"Content-Type":"application/json"}
        })
            .then(r=>r.json())
            .then(data=>{
                btn.disabled = false;
                if (data.success && data.token) {
                    localStorage.setItem(TOKEN_KEY, data.token);
                    let u = new URLSearchParams(window.location.search), go = u.get('next')||`contest${QUERYCONTEST}`;
                    window.location.href = go;
                } else {
                    document.getElementById("login-error").textContent =
                        (contestLocale==="pt" ? "Erro de login, tente novamente" : "Login error, try again");
                }
            });
        return false;
    };
});

function updateCountriesFlagBar(countries) {
    let flagBar = document.getElementById("flagbar");
    flagBar.innerHTML = countries.map(c=>{
        let cc = c.code.toLowerCase();
        return `<img src="https://flagcdn.com/${cc}.svg" title="${c.name}" alt="${c.name}"><span class="flag-lbl">${c.name}</span>`;
    }).join(" ");
}
function setLoginFormVisible(visible) {
    let f = document.getElementById("login-form");
    if (visible) {
        f.style.display = "";
        setTimeout(() => f.classList.add("visible"), 50);
    } else {
        f.style.display = "none";
        f.classList.remove("visible");
    }
}

function fmtDate(epoch, pt) {
    if (!epoch) return '';
    let d = new Date(epoch*1000);
    return pt ? d.toLocaleString("pt-BR",{year:'numeric',month:'2-digit',day:'2-digit',hour:'2-digit',minute:'2-digit'})
        : d.toLocaleString("en-US",{year:'numeric',month:'2-digit',day:'2-digit',hour:'2-digit',minute:'2-digit'});
}
function showCountdownLeft(left) {
    document.getElementById("countdown-box").style.display = "";
    document.getElementById("countdown-time").textContent = fmtLeft(left);
}
function hideCountdown() {
    document.getElementById("countdown-box").style.display = "none";
}
function fmtLeft(sec) {
    if(sec < 0) sec = 0;
    let h=Math.floor(sec/3600),m=Math.floor((sec%3600)/60),s=sec%60;
    let p = s => s.toString().padStart(2,'0');
    return h > 0 ? `${p(h)}:${p(m)}:${p(s)}` : `${p(m)}:${p(s)}`;
}
