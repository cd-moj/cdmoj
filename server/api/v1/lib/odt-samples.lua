-- odt-samples.lua — no documento IMPRESSO (caderno, rota pandoc → ODT), os exemplos viram uma TABELA
-- de duas colunas "Exemplo de entrada N | Exemplo de saída N", com borda — o molde dos cadernos da
-- Maratona SBC. O HTML do enunciado traz os exemplos EMPILHADOS (`section.moj-exemplos` ›
-- `div.moj-exemplo` › h3 Entrada / pre / h3 Saída / pre [› div.moj-exemplo-nota]) porque é o certo no
-- celular; o site continua assim — a transformação é SÓ do papel, aqui, e nunca no gerador do HTML
-- (mojtools/statement-langs.sh, stmt_samples_html, que é a fonte única do site).
-- Empilhado, cada exemplo gastava duas caixas e dois títulos: o caderno da XIV Maratona UnB saía com
-- 33 páginas e várias quase vazias (a SBC, com 14 problemas, fica em ~22).
--
-- A tabela sai CRUA (RawBlock opendocument): o escritor de ODT do pandoc não põe borda em célula, e
-- o LibreOffice só aplica estilo de célula que seja AUTOMÁTICO no content.xml — os estilos
-- `MojSample*` de tabela/coluna/linha/célula são injetados pelo lib/odt-caderno.py; os de parágrafo
-- (`MojSampleHead`, `MojSampleText`) moram no etc/caderno-reference.odt. Sem o passo Python a tabela
-- sai sem borda, mas sai (fail-open).
-- Idioma dos rótulos: `-M moj-lang=pt|en|es` (default pt).

local LABELS = {
  pt = { 'Exemplo de entrada', 'Exemplo de saída', 'Explicação do exemplo' },
  en = { 'Sample input', 'Sample output', 'Explanation of sample' },
  es = { 'Ejemplo de entrada', 'Ejemplo de salida', 'Explicación del ejemplo' },
}
local lab = LABELS.pt

local function has_class(el, c)
  for _, k in ipairs(el.classes or {}) do if k == c then return true end end
  return false
end

local function esc(s)
  return (s:gsub('&', '&amp;'):gsub('<', '&lt;'):gsub('>', '&gt;'))
end

-- uma linha do exemplo → um parágrafo; espaço repetido/inicial e TAB viram text:s / text:tab
-- (o ODT colapsa espaço como o HTML; um exemplo com alinhamento por espaços tem de sair igual)
local function line_xml(l)
  l = esc(l:gsub('\r$', ''))
  l = l:gsub('\t', '<text:tab/>')
  l = l:gsub('^( +)', function(sp) return '<text:s text:c="' .. #sp .. '"/>' end)
  l = l:gsub('(  +)', function(sp) return ' <text:s text:c="' .. (#sp - 1) .. '"/>' end)
  return '<text:p text:style-name="MojSampleText">' .. l .. '</text:p>'
end

local function cell(head, text)
  local out = { '<table:table-cell table:style-name="MojSampleCell" office:value-type="string">' }
  if head then
    out[#out + 1] = '<text:p text:style-name="MojSampleHead">' .. esc(head) .. '</text:p>'
  else
    text = (text or ''):gsub('\n$', '')
    for l in (text .. '\n'):gmatch('(.-)\n') do out[#out + 1] = line_xml(l) end
  end
  out[#out + 1] = '</table:table-cell>'
  return table.concat(out)
end

local seq = 0
local function table_xml(n, input, output)
  seq = seq + 1
  return pandoc.RawBlock('opendocument', table.concat({
    '<table:table table:name="MojSample', seq, '" table:style-name="MojSampleTbl">',
    '<table:table-column table:style-name="MojSampleCol" table:number-columns-repeated="2"/>',
    '<table:table-header-rows><table:table-row table:style-name="MojSampleRow">',
    cell(lab[1] .. ' ' .. n), cell(lab[2] .. ' ' .. n),
    '</table:table-row></table:table-header-rows>',
    '<table:table-row table:style-name="MojSampleRow">', cell(nil, input), cell(nil, output), '</table:table-row>',
    '</table:table>' }))
end

local function kind_of(cb)
  for _, kv in ipairs(cb.attributes or {}) do
    if kv[1] == 'data-kind' or kv[1] == 'kind' then return kv[2] end
  end
  local a = cb.attributes and (cb.attributes['data-kind'] or cb.attributes['kind'])
  return a
end

-- um div.moj-exemplo → tabela + (explicação, com o título "Explicação do exemplo N")
local function one_sample(div, n)
  local inp, outp, extra = nil, nil, {}
  local codes = {}
  for _, b in ipairs(div.content) do
    if b.t == 'CodeBlock' then codes[#codes + 1] = b end
  end
  for _, cb in ipairs(codes) do
    local k = kind_of(cb)
    if k == 'input' and not inp then inp = cb.text
    elseif k == 'output' and not outp then outp = cb.text end
  end
  if not inp and codes[1] then inp = codes[1].text end
  if not outp and codes[2] then outp = codes[2].text end
  if not inp then return nil end               -- não é o formato esperado: fica como veio
  local blocks = { table_xml(n, inp, outp or '') }
  for _, b in ipairs(div.content) do
    if b.t == 'Div' and has_class(b, 'moj-exemplo-nota') then
      local first = true
      for _, x in ipairs(b.content) do
        if first and x.t == 'Header' then
          blocks[#blocks + 1] = pandoc.Header(3, { pandoc.Str(lab[3] .. ' ' .. n) })
        else
          blocks[#blocks + 1] = x
        end
        first = false
      end
    end
  end
  return blocks
end

local function samples(div)
  if not has_class(div, 'moj-exemplos') then return nil end
  local out, n = {}, 0
  for i, b in ipairs(div.content) do
    if i == 1 and b.t == 'Header' then
      -- o título "Exemplos" some: a própria tabela diz "Exemplo de entrada N"
    elseif b.t == 'Div' and has_class(b, 'moj-exemplo') then
      n = n + 1
      local t = one_sample(b, n)
      if t then for _, x in ipairs(t) do out[#out + 1] = x end else out[#out + 1] = b end
    elseif b.t == 'Div' and has_class(b, 'moj-exemplo-nota') and n > 0 then
      -- explicação solta, depois do exemplo (formato antigo): mesmo título
      local first = true
      for _, x in ipairs(b.content) do
        if first and x.t == 'Header' then
          out[#out + 1] = pandoc.Header(3, { pandoc.Str(lab[3] .. ' ' .. n) })
        else
          out[#out + 1] = x
        end
        first = false
      end
    else
      out[#out + 1] = b
    end
  end
  return out
end

return {
  { Meta = function(m)
      local l = m['moj-lang'] and pandoc.utils.stringify(m['moj-lang']) or 'pt'
      lab = LABELS[l] or LABELS.pt
    end },
  { Div = samples },
}
