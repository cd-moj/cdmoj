document.addEventListener("DOMContentLoaded", async function() {
  //--- Autenticação ---
  let host = window.location.hostname;
  let contestID = host.split(".")[0];
  let token = localStorage.getItem(window.TOKEN_KEY);
  let dest = encodeURIComponent(window.location.pathname + window.location.search + window.location.hash);
  let headersAuth = token ? { "Authorization": "Bearer " + token } : {};
  let isAuthenticated = false;
  if (!token) {
//    window.location.replace(`/~ribas/contest?next=${dest}`);
//    return;
  }
  try {
    let resp = await fetch(`/~ribas/api/auth/status.sh?contest=${encodeURIComponent(contestID)}`, {headers: headersAuth});
    let stat = await resp.json();
    isAuthenticated = !!stat.logged_in;
  } catch { isAuthenticated = false; }
  if (!isAuthenticated) {
 //   window.location.replace(`/~ribas/contest?next=${dest}`);
 //   return;
  }

  //--- Contest info/navbar/user ---
  let basic = await fetch(window.API_BASIC).then(r=>r.json());
  window.contestLocale = basic.locale || "pt";
  document.title = basic.contest_name;
  document.getElementById('contest-title').textContent = basic.contest_name;
  window.startContestCountdown(basic.end_time, window.contestLocale);
  let userInfo = await fetch(window.API_USERINFO, {headers: headersAuth}).then(r=>r.json());
  window.showUserDetails(userInfo, window.contestLocale);
  window.initLogout && window.initLogout();
  let quicknav = await fetch(window.API_QUICKNAV, {headers: headersAuth}).then(r=>r.json());
  window.buildContestNav(quicknav, window.contestLocale);

  //--- Problemas e lista de veredictos ---
  window.contestProblems = await fetch(window.API_PROBLEMS, {headers: headersAuth}).then(r=>r.json());
  let finalVerdicts = await fetch(window.API_FINAL_VERDICTS, {headers: headersAuth}).then(r=>r.json());
  //--- Submissions ---
  let resp = await fetch(window.API_SUBMISSIONS_JUDGE, {headers: headersAuth});
  let txt = await resp.text();
  let subs = [];
  if(txt) {
    subs = txt.trim().split('\n').map(line=>{
      let vals = line.split(":");
      return {
        time_from_start: vals[0],
        username: vals[1],
        problem_id: vals[2],
        filename: vals[3],
        verdict: vals[4],
        epoch: vals[5],
        submission_id: vals[6],
        team_name: vals[7] || "",
        univ_short: vals[8] || ""
      };
    });
  }
  window.renderJudgeSubmissions(subs, window.contestProblems, finalVerdicts, basic.contest_id, userInfo.login);
});
