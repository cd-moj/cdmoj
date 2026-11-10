// shared/roles.js — GERADO por server/bin/roles-gen.sh a partir de server/etc/roles.tsv. NÃO EDITE À MÃO.
// Os papéis do MOJ são o SUFIXO do login (fulano.staff). Login sem sufixo do registro = time.
export const ROLES = [{"suffix":"admin","nav":"admin","cls":"org","scoped":false,"can":["*"]},{"suffix":"judge","nav":"judge","cls":"org","scoped":false,"can":["julgar","placar_full","rodadas_privadas"]},{"suffix":"cjudge","nav":"chief","cls":"org","scoped":false,"can":["julgar","chefe","placar_full","rodadas_privadas"]},{"suffix":"mon","nav":"mon","cls":"org","scoped":false,"can":["monitorar","como_time","placar_full","rodadas_privadas"]},{"suffix":"animeitor","nav":"animeitor","cls":"org","scoped":false,"can":["telao","foto","musica","placar_full"]},{"suffix":"staff","nav":"staff","cls":"sala","scoped":true,"can":["fila","rodadas_privadas"]},{"suffix":"cstaff","nav":"cstaff","cls":"sala","scoped":true,"can":["fila_leitura","etiquetas","cerimonia","foto","musica","rodadas_privadas"]},{"suffix":"foto","nav":"foto","cls":"sala","scoped":true,"can":["foto"]},{"suffix":"musica","nav":"musica","cls":"sala","scoped":true,"can":["musica"]},{"suffix":"sistemas","nav":"sistemas","cls":"sala","scoped":true,"can":["maquinas"]},{"suffix":"diretor","nav":"diretor","cls":"org","scoped":true,"can":["placar_recorte"]}];
export const ROLE_RE = /[.](admin|judge|cjudge|mon|animeitor|staff|cstaff|foto|musica|sistemas|diretor)$/;
const BY = Object.fromEntries(ROLES.map((r) => [r.suffix, r]));
// roleOf('x.staff') → 'staff'; time → ''
export const roleOf = (login) => { const m = ROLE_RE.exec(String(login || '')); return m ? m[1] : ''; };
export const isRoleAccount = (login) => ROLE_RE.test(String(login || ''));
// 'org' | 'sala' | 'time'
export const roleClass = (login) => { const r = BY[roleOf(login)]; return r ? r.cls : 'time'; };
export const roleScoped = (login) => !!(BY[roleOf(login)] || {}).scoped;
export const roleCan = (login, cap) => { const r = BY[roleOf(login)]; return !!r && (r.can.includes('*') || r.can.includes(cap)); };
// sufixos com escopo (staff-filters.json): .staff .cstaff .foto …
export const SCOPED_SUFFIXES = ROLES.filter((r) => r.scoped).map((r) => r.suffix);
