-- odt-center.lua — o bloco `::: center` do enunciado CENTRALIZADO também no PDF da prova.
--
-- No enunciado, `::: center … :::` vira `<div class="center">`; no site o `.center` do ui.css
-- centraliza (página do problema, sanfona da prova, aba HTML e o Pré-visualizar do editor). Na rota
-- do caderno (`pandoc -f html -t odt` → soffice, lib/contest-docs.sh) o pandoc DESCARTA a classe
-- do bloco e tudo saía à esquerda. Aqui o bloco ganha o `custom-style="Center"` (o parágrafo
-- `Center` do etc/caderno-reference.odt: centralizado, sem o recuo da 1ª linha do corpo), que o
-- escritor de ODT do pandoc aplica aos PARÁGRAFOS de dentro — mas não à figura (imagem com
-- legenda), que tem estilo próprio: ela vira dois parágrafos, a imagem e a legenda em itálico
-- (a cara da legenda de figura do reference-doc).
-- Uso: pandoc -f html -t odt --lua-filter odt-center.lua …   (fora do bloco, nada muda)

local function flat(blocks)
  local out = pandoc.List()
  for _, b in ipairs(blocks) do
    if b.t == 'Figure' then
      out:insert(pandoc.Para(pandoc.utils.blocks_to_inlines(b.content)))
      if b.caption and b.caption.long and #b.caption.long > 0 then
        out:insert(pandoc.Para({ pandoc.Emph(pandoc.utils.blocks_to_inlines(b.caption.long)) }))
      end
    else
      out:insert(b)
    end
  end
  return out
end

function Div(el)
  if el.classes:includes('center') then
    el.content = flat(el.content)
    el.attributes['custom-style'] = 'Center'
    return el
  end
end
