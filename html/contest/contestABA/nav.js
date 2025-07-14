window.buildContestNav = function(nav, locale) {
  let navdiv = document.getElementById("contest-nav"), currPath = window.location.pathname;
  navdiv.innerHTML = nav.map(nb=>{
    let label = (locale==="pt") ? nb.label_pt : nb.label_en,
        sel = currPath===(nb.url)?"selected":"";
    return `<a class="nav-btn ${sel}" href="${nb.url}">${label}</a>`;
  }).join("");
}
