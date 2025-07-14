window.showUserDetails = function(userInfo, locale) {
  let html = `<div id="user-title">${userInfo.name||userInfo.login}</div>
  <div id="user-login">Login: <b>${userInfo.login}</b></div><div id="user-more">`;
  if(userInfo.university) html += `<span><b>${locale==="pt"?"Universidade":"University"}:</b> ${userInfo.university}</span>`;
  if(userInfo.country) html += `<span><b>${locale==="pt"?"País":"Country"}:</b> ${userInfo.country}</span>`;
  html += "</div>";
  document.getElementById("user-details").innerHTML = html;
}
window.startContestCountdown = function(endEpoch, locale) {
  function fmtLeft(sec){ if(sec<0) sec=0; let h=Math.floor(sec/3600),m=Math.floor((sec%3600)/60),s=sec%60;
      let p=s=>s.toString().padStart(2,"0"); return h>0?`${p(h)}:${p(m)}:${p(s)}`:`${p(m)}:${p(s)}`; }
  function update() {
    const now = Math.floor(Date.now()/1000);
    let left = endEpoch - now;
    document.getElementById("countdown-contest").textContent =
      (locale==="pt" ? "Termina em: " : "Ends in: ") + fmtLeft(left);
    if(left>0) setTimeout(update, 1000);
    else document.getElementById("countdown-contest").textContent =
      (locale==="pt" ? "Competição encerrada" : "Contest ended");
  }
  update();
}
window.initLogout = function() {
  document.getElementById("logout-btn").onclick=function(){
      localStorage.removeItem(window.TOKEN_KEY); window.location.replace(`../${QUERYCONTEST}`);
  }
}
window.fmtDate = function(epoch, pt) {
  if(!epoch) return "";
  let d=new Date(epoch*1000);
  return pt ? d.toLocaleString("pt-BR",{year:'numeric',month:'2-digit',day:'2-digit',hour:'2-digit',minute:'2-digit'})
            : d.toLocaleString("en-US",{year:'numeric',month:'2-digit',day:'2-digit',hour:'2-digit',minute:'2-digit'});
}
