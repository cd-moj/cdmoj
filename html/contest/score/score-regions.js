window.loadScoreRegions = async function() {
  try {
    let res = await fetch(window.API_REGIONS, {
      headers: { "Authorization": "Bearer " + localStorage.getItem(window.TOKEN_KEY) }
    });
    let regions = await res.json();
    window.scoreRegions = regions;
    return regions;
  } catch (e) {
    window.scoreRegions = [];
    return [];
  }
};

window.renderRegionFilters = function(regions, activeRegex, onClick) {
  if (!Array.isArray(regions)) return "";
  function rec(rs) {
    return rs.map(r=>{
      let active = r.regex === activeRegex;
      let subr = "";
      if (r.subregions && r.subregions.length > 0) {
        let subs = r.subregions.map(sub => {
          let subact = sub.regex === activeRegex;
          let lbl = `<a href="#" onclick="${onClick}('${sub.regex}');return false;"
                        style="font-weight:${subact ? "bold":"normal"};
                        text-decoration:${subact ? "underline":"none"};
                        color:${subact?"#1850a9":"#3b4b7c"}">
                        ${sub.name}
                    </a>`;
          // Busca subsubregiões e cola como (AAA,BBB) ao lado
          let ss = sub.subregions && sub.subregions.length
            ? ` (<span style="font-weight:normal;">${
                sub.subregions.map(ssb=>{
                  let subsubact = ssb.regex === activeRegex;
                  return `<a href="#" onclick="${onClick}('${ssb.regex}');return false;"
                    style="font-weight:${subsubact ? "bold":"normal"};
                    text-decoration:${subsubact ? "underline":"none"};
                    color:${subsubact?"#1850a9":"#3b4b7c"};"
                  >${ssb.name}</a>`;
                }).join(', ')
              }</span>)` : '';
          return `${lbl}${ss}`;
        }).join(' : ');
        subr = ": " + subs;
      }
      let reglbl = `<a href="#" onclick="${onClick}('${r.regex}');return false;"
                     style="font-weight:${active ? "bold":"normal"};
                     text-decoration:${active ? "underline":"none"};
                     color:${active?"#1850a9":"#3b4b7c"};">
                     ${r.name}
                   </a>`;
      return `<div style="margin-bottom:.3em;">${reglbl}${subr}</div>`;
    }).join('');
  }
  return `<div style="margin-bottom:1em;">Filtrar região:${rec(regions)}</div>`;
};
