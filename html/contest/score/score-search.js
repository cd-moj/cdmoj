window.fuzzyTeamFilter = function(list, term) {
  if(!term) return list;
  term = term.trim().toLowerCase();
  return list.filter(entry =>
    (entry.username||"").toLowerCase().includes(term) ||
    (entry["team name"]||"").toLowerCase().includes(term) ||
    (entry["univ short"]||"").toLowerCase().includes(term) ||
    (entry["univ full"]||"").toLowerCase().includes(term)
  );
};
