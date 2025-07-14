window.renderRegionFilters = function(regions, activeRegex, onClick) {
  if (!Array.isArray(regions)) return "";
  function rec(rs,deep) {
    deep=deep||0;
    return rs.map(r=>{
      let active = r.regex === activeRegex;
      let links = [];
      if (r.subregions && r.subregions.length > 0) {
        links = r.subregions.map(subr=>{
          let subActive = subr.regex === activeRegex;
          let sublinks = subr.subregions && subr.subregions.length ?
            ' ('+subr.subregions.map(ssb=>{
              let sbA = ssb.regex===activeRegex;
              return `<a href="#" onclick="${onClick}('${ssb.regex}');return false;"
                        class="region-link${sbA?' active':''}">${ssb.name}</a>`;
            }).join(', ')+')' : '';
          return `<a href="#" onclick="${onClick}('${subr.regex}');return false;"
              class="region-link${subActive?' active':''}">${subr.name}</a>${sublinks}`;
        }).join('');
      }
      let region = `<a href="#" onclick="${onClick}('${r.regex}');return false;" class="region-link${active?' active':''}">${r.name}</a>`;
      return `<div class="region-filter-row">${region}${links?(' : '+links):""}</div>`;
    }).join('');
  }
  return `<div class="region-filter-list">Filtrar região:${rec(regions)}</div>`;
};
