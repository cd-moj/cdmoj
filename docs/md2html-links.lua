-- docs/md2html-links.lua — filtro pandoc do build-html.sh: reescreve alvo de link
-- RELATIVO mesmo-diretório `X.md` -> `X.html` (o nginx de produção serve só o docs/html/
-- gerado; o fonte .md continua navegável no editor/GitHub). Não toca URL absoluta
-- (/…, http…), nem menção `X.md` em crase (code-span é Code, não Link — o filtro só
-- visita Link). `X.md#ancora` não é reescrito (nenhum doc usa hoje; ajustar se surgir).
function Link(el)
  el.target = el.target:gsub('^([^/:]+)%.md$', '%1.html')
  return el
end
