-- Jukebox for CC:Tweaked
-- Lists every .dfpwm file in your GitHub repo and lets you pick one.
-- Controls: Up/Down = choose, Enter = play, R = refresh list, Q = quit
-- While playing: N = next song, S or Space = stop

local USER, REPO, BRANCH = "callumcrump1105-tech", "mc-music", "main"
local RAW = ("https://raw.githubusercontent.com/%s/%s/%s/"):format(USER, REPO, BRANCH)
local API = ("https://api.github.com/repos/%s/%s/contents?ref=%s"):format(USER, REPO, BRANCH)

-- Used if the GitHub file list can't be loaded
local FALLBACK = { "trapqueen.dfpwm", "violet.dfpwm" }

local dfpwm = require("cc.audio.dfpwm")
local speaker = peripheral.find("speaker")
if not speaker then
  error("No speaker found. Place a speaker next to this computer.", 0)
end

local current -- open download handle, so it can be closed on stop

local function pretty(name)
  return (name:gsub("%.dfpwm$", ""):gsub("[_%-]", " "))
end

local function loadSongs()
  local res = http.get(API, { ["User-Agent"] = "cc-jukebox" })
  if not res then return FALLBACK end
  local data = textutils.unserializeJSON(res.readAll())
  res.close()
  local songs = {}
  for _, f in ipairs(data or {}) do
    if f.type == "file" and f.name:match("%.dfpwm$") then
      table.insert(songs, f.name)
    end
  end
  table.sort(songs)
  if #songs == 0 then return FALLBACK end
  return songs
end

local function play(name)
  local h, err = http.get(RAW .. name:gsub(" ", "%%20"), nil, true)
  if not h then return false, err end
  current = h
  local decoder = dfpwm.make_decoder()
  while true do
    local chunk = h.read(16 * 1024)
    if not chunk then break end
    local buffer = decoder(chunk)
    while not speaker.playAudio(buffer) do
      os.pullEvent("speaker_audio_empty")
    end
  end
  h.close()
  current = nil
  os.pullEvent("speaker_audio_empty") -- let the last bit finish
  return true
end

local function header(w)
  term.setBackgroundColor(colors.black)
  term.clear()
  term.setCursorPos(1, 1)
  term.setTextColor(colors.white)
  term.write("== Jukebox ==")
  term.setTextColor(colors.lightGray)
end

local function drawMenu(songs, sel, scroll)
  local w, h = term.getSize()
  header(w)
  term.setCursorPos(1, 2)
  term.write("Enter play  R refresh  Q quit")
  for i = 1, h - 3 do
    local idx = scroll + i
    local s = songs[idx]
    if not s then break end
    local line = (" %d. %s"):format(idx, pretty(s))
    line = (line .. string.rep(" ", w)):sub(1, w)
    term.setCursorPos(1, i + 3)
    if idx == sel then
      term.setBackgroundColor(colors.white)
      term.setTextColor(colors.black)
    else
      term.setBackgroundColor(colors.black)
      term.setTextColor(colors.white)
    end
    term.write(line)
  end
  term.setBackgroundColor(colors.black)
end

local function nowPlaying(name, idx, total, msg)
  local w = term.getSize()
  header(w)
  term.setCursorPos(1, 3)
  term.write(("Now playing (%d/%d):"):format(idx, total))
  term.setCursorPos(1, 4)
  term.setTextColor(colors.white)
  term.write(pretty(name))
  term.setCursorPos(1, 6)
  term.setTextColor(colors.lightGray)
  term.write(msg or "N next   S stop")
end

local function playFrom(songs, idx)
  while idx <= #songs do
    nowPlaying(songs[idx], idx, #songs)
    local result
    parallel.waitForAny(
      function()
        local ok, err = play(songs[idx])
        result = ok and "done" or ("Couldn't load: " .. tostring(err))
      end,
      function()
        while true do
          local _, key = os.pullEvent("key")
          if key == keys.n then result = "next" return end
          if key == keys.s or key == keys.space then result = "stop" return end
        end
      end
    )
    speaker.stop()
    if current then pcall(current.close); current = nil end
    if result == "stop" then return end
    if result ~= "done" and result ~= "next" then
      nowPlaying(songs[idx], idx, #songs, result)
      sleep(3)
    end
    idx = idx + 1
  end
end

local songs = loadSongs()
local sel, scroll = 1, 0
while true do
  local _, h = term.getSize()
  local rows = h - 3
  if sel <= scroll then scroll = sel - 1 end
  if sel > scroll + rows then scroll = sel - rows end
  drawMenu(songs, sel, scroll)
  local _, key = os.pullEvent("key")
  if key == keys.up then
    sel = math.max(1, sel - 1)
  elseif key == keys.down then
    sel = math.min(#songs, sel + 1)
  elseif key == keys.enter or key == keys.numPadEnter then
    playFrom(songs, sel)
  elseif key == keys.r then
    songs = loadSongs()
    sel, scroll = 1, 0
  elseif key == keys.q then
    break
  end
end

sleep(0.1) -- swallow the "q" so it doesn't show up in the shell
term.setBackgroundColor(colors.black)
term.setTextColor(colors.white)
term.clear()
term.setCursorPos(1, 1)
