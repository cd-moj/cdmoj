-- docs/md2html-links.lua — filtro pandoc do build-html.sh: reescreve alvo de link.
--
-- Doc em PORTUGUÊS (a fonte; sem `moj-lang`): link RELATIVO mesmo-diretório `X.md[#âncora]` vira
-- `X.html[#âncora]` (o nginx de produção serve só o docs/html/ gerado; o fonte .md continua navegável
-- no editor/GitHub). Não toca URL absoluta (/…, http…), nem menção `X.md` em crase (code-span é Code,
-- não Link — o filtro só visita Link).
--
-- Doc TRADUZIDO (docs/en|es/, `-M moj-lang=en|es -M moj-translated=A,B,…` — docs/I18N.md, "Documentação"):
--   * `X.md` relativo → `X.html` se X também está traduzido (o mesmo idioma), senão `../X.html` (o PT —
--     a documentação técnica só existe em português); `../X.md` → `../X.html`;
--   * `/docs/X.html` absoluto → `/docs/<lang>/X.html` se X está traduzido;
--   * página do SITE (`/…` terminando em `.html` ou `/`, fora de /api/ e /docs/) ganha `?lang=<lang>`:
--     o leitor do manual em inglês abre a tela citada em inglês (o `?lang=` do web/shared/i18n.js GRAVA
--     a escolha — é o que esse leitor quer). `?…`/`#…` existentes são preservados.
local lang, tr = nil, {}

local function meta(m)
  if m['moj-lang'] then lang = pandoc.utils.stringify(m['moj-lang']) end
  if m['moj-translated'] then
    for n in pandoc.utils.stringify(m['moj-translated']):gmatch('[^,%s]+') do tr[n] = true end
  end
end

local function split(t)  -- caminho, sufixo (?query#frag)
  local i = t:find('[?#]')
  if i then return t:sub(1, i - 1), t:sub(i) end
  return t, ''
end

local function link(el)
  local t = el.target
  local path, rest = split(t)
  -- relativo mesmo-diretório (ou ../X.md, do traduzido p/ o PT)
  local up, name = path:match('^(%.%./)([^/:]+)%.md$')
  if not name then name = path:match('^([^/:]+)%.md$') end
  if name then
    if not lang or up then
      el.target = (up or '') .. name .. '.html' .. rest
    elseif tr[name] then
      el.target = name .. '.html' .. rest
    else
      el.target = '../' .. name .. '.html' .. rest
    end
    return el
  end
  if not lang or not path:match('^/') or path:match('^//') then return el end
  -- /docs/X.html → a versão traduzida
  local d = path:match('^/docs/([^/]+)%.html$')
  if d then
    if tr[d] then el.target = '/docs/' .. lang .. '/' .. d .. '.html' .. rest end
    return el
  end
  if path:match('^/api/') or path:match('^/docs/') then return el end
  if not (path:match('%.html$') or path:match('/$')) then return el end
  local q, f = rest:match('^(%?[^#]*)(.*)$')
  if not q then q, f = '', rest end
  if q:match('[?&]lang=') then return el end
  el.target = path .. (q == '' and '?' or q .. '&') .. 'lang=' .. lang .. f
  return el
end

-- dois passes: o Meta roda DEPOIS dos elementos numa passada só (ordem do pandoc)
return { { Meta = meta }, { Link = link } }
