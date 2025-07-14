window.getProblemShortNameMap = function(problems) {
  let map = {};
  problems.forEach(p=>{
    if(p.problem_id && p.short_name) map[p.problem_id] = p.short_name;
  });
  return map;
}
