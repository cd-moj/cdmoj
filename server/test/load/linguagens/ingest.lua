-- ingest.lua — o ingest-drain em Lua 5.4 puro (sem lib externa).
-- os.rename existe ⇒ ATÔMICO; mas Lua não tem listdir (io.popen find, 1 fork) nem
-- JSON/base64 na stdlib (extração por PATTERN de campos conhecidos + b64 manual —
-- as mesmas concessões do awk, com atomicidade do perl).
local RUN = os.getenv("RUNDIR"); local CTS = os.getenv("CONTESTSDIR")
local SPOOL = RUN .. "/spool/submissions"; local DONE = RUN .. "/spool/submissions-done"
local now = os.time()

local B = {}
do
  local a = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
  for i = 1, 64 do B[a:sub(i, i)] = i - 1 end
end
local function b64dec(s)
  local out, val, bits = {}, 0, 0
  for i = 1, #s do
    local c = s:sub(i, i)
    if c == "=" then break end
    local v = B[c]
    if v then
      val = val * 64 + v; bits = bits + 6
      if bits >= 8 then
        bits = bits - 8
        out[#out + 1] = string.char(math.floor(val / 2 ^ bits) % 256)
      end
    end
  end
  return table.concat(out)
end
local function jget(s, k)
  return s:match('"' .. k .. '":"([^"]*)"') or s:match('"' .. k .. '":(-?%d+)')
end

local p = io.popen("find '" .. SPOOL .. "' -maxdepth 1 -type f -name '*:result:*'")
for path in p:lines() do
  local fh = io.open(path, "r")
  if fh then
    local line = fh:read("*l"); fh:close()
    local c, sid, login = jget(line, "contest"), jget(line, "id"), jget(line, "login")
    local verdict = jget(line, "verdict") or "Judge Error"
    if c and sid and login and c ~= "_testrun" then
      local udir = CTS .. "/" .. c .. "/users/" .. login
      local hf = udir .. "/history"
      local lines, idx = {}, nil
      local sfx = ":" .. sid
      local h = io.open(hf, "r")
      if h then
        for hl in h:lines() do
          lines[#lines + 1] = hl
          if hl:sub(-#sfx) == sfx then idx = #lines end
        end
        h:close()
      end
      if idx then
        local F = {}
        for fld in lines[idx]:gmatch("[^:]*") do F[#F + 1] = fld end
        -- gmatch com [^:]* gera vazios intercalados; refaz com split simples
        F = {}
        for fld in (lines[idx] .. ":"):gmatch("([^:]*):") do F[#F + 1] = fld end
        lines[idx] = table.concat({ F[1], F[2], F[3], verdict, F[#F - 1], F[#F] }, ":")
        local o = io.open(hf .. ".tmp.lua", "w")
        o:write(table.concat(lines, "\n"), "\n"); o:close()
        os.rename(hf .. ".tmp.lua", hf)
        local hb = jget(line, "report_html_b64")
        if hb then
          o = io.open(udir .. "/mojlog/." .. sid .. ".tmp", "w")
          o:write(b64dec(hb)); o:close()
          os.rename(udir .. "/mojlog/." .. sid .. ".tmp", udir .. "/mojlog/" .. sid .. ".html")
        end
        local res = line:gsub(',"report_html_b64":"[^"]*"', '')
        res = res:sub(1, -2) .. ',"report_html":"mojlog/' .. sid .. '.html","finalized_at":' .. now .. '}'
        for _, rf in ipairs({ udir .. "/results/" .. sid .. ".json", RUN .. "/results/" .. sid .. ".json" }) do
          o = io.open(rf .. ".tmp.lua", "w")
          o:write(res); o:close()
          os.rename(rf .. ".tmp.lua", rf)
        end
        os.rename(path, DONE .. "/" .. path:match("[^/]+$"))
      end
    end
  end
end
p:close()
