----------------------------------------------------------------------------
-- ui/theme.lua -- cc-mek-scada palettes (graphics/themes.lua) + semantic map.
--
-- Theme is GLOBAL: apply() sets the active semantic map `C` (mutated in place
-- so every module that required it sees the change) and pushes the palette to
-- every monitor. The `brown` slot is repurposed as the card body shade.
----------------------------------------------------------------------------

local M = {}

M.ORDER = { "deepslate", "smooth_stone", "sandstone", "basalt" }

M.THEMES = {
  deepslate = {
    palette = {
      [colors.red] = 0xeb6a6c, [colors.orange] = 0xf2b86c, [colors.yellow] = 0xd9cf81,
      [colors.lime] = 0x80ff80, [colors.green] = 0x70e19b, [colors.cyan] = 0x7ccdd0,
      [colors.lightBlue] = 0x99ceef, [colors.blue] = 0x60bcff, [colors.purple] = 0xc38aea,
      [colors.pink] = 0xff7fb8, [colors.magenta] = 0xf980dd, [colors.white] = 0xd9d9d9,
      [colors.lightGray] = 0x949494, [colors.gray] = 0x575757, [colors.black] = 0x262626,
      [colors.brown] = 0x333333,
    },
    sem = {
      screen = colors.black, card = colors.brown, cardTitle = colors.gray, titleText = colors.white,
      text = colors.white, dim = colors.lightGray, accent = colors.blue, accent2 = colors.cyan,
      good = colors.green, warn = colors.orange, bad = colors.red, note = colors.yellow,
      btn = colors.orange, btnText = colors.black, btnOk = colors.green, btnBad = colors.red,
    },
  },
  smooth_stone = {
    palette = {
      [colors.red] = 0xdf4949, [colors.orange] = 0xffb659, [colors.yellow] = 0xfffc79,
      [colors.lime] = 0x80ff80, [colors.green] = 0x4aee8a, [colors.cyan] = 0x34bac8,
      [colors.lightBlue] = 0x6cc0f2, [colors.blue] = 0x0096ff, [colors.purple] = 0xb156ee,
      [colors.pink] = 0xf26ba2, [colors.magenta] = 0xf9488a, [colors.white] = 0xf0f0f0,
      [colors.lightGray] = 0xcacaca, [colors.gray] = 0x575757, [colors.black] = 0x191919,
      [colors.brown] = 0xe6e6e6,
    },
    sem = {
      screen = colors.lightGray, card = colors.brown, cardTitle = colors.gray, titleText = colors.white,
      text = colors.black, dim = colors.gray, accent = colors.blue, accent2 = colors.cyan,
      good = colors.green, warn = colors.orange, bad = colors.red, note = colors.orange,
      btn = colors.orange, btnText = colors.black, btnOk = colors.green, btnBad = colors.red,
    },
  },
  sandstone = {
    palette = {
      [colors.red] = 0xdf4949, [colors.orange] = 0xffb659, [colors.yellow] = 0xf9fb53,
      [colors.lime] = 0x6be551, [colors.green] = 0x16665a, [colors.cyan] = 0x6cc0f2,
      [colors.lightBlue] = 0x6cc0f2, [colors.blue] = 0x0096ff, [colors.purple] = 0x85862c,
      [colors.pink] = 0x672223, [colors.magenta] = 0xe3bc2a, [colors.white] = 0xf0f0f0,
      [colors.lightGray] = 0xb1b8b3, [colors.gray] = 0x575757, [colors.black] = 0x191919,
      [colors.brown] = 0xdcd9ca,
    },
    sem = {
      screen = colors.lightGray, card = colors.brown, cardTitle = colors.gray, titleText = colors.white,
      text = colors.black, dim = colors.gray, accent = colors.blue, accent2 = colors.lightBlue,
      good = colors.lime, warn = colors.orange, bad = colors.red, note = colors.orange,
      btn = colors.orange, btnText = colors.black, btnOk = colors.lime, btnBad = colors.red,
    },
  },
  basalt = {
    palette = {
      [colors.red] = 0xf18486, [colors.orange] = 0xffb659, [colors.yellow] = 0xefe37c,
      [colors.lime] = 0x7ae175, [colors.green] = 0x436b41, [colors.cyan] = 0x7dc6f2,
      [colors.lightBlue] = 0x7dc6f2, [colors.blue] = 0x56aae6, [colors.purple] = 0x757040,
      [colors.pink] = 0x512d2d, [colors.magenta] = 0xe9cd68, [colors.white] = 0xbfbfbf,
      [colors.lightGray] = 0x848794, [colors.gray] = 0x5c5f68, [colors.black] = 0x333333,
      [colors.brown] = 0x4d4e52,
    },
    sem = {
      screen = colors.black, card = colors.brown, cardTitle = colors.gray, titleText = colors.white,
      text = colors.white, dim = colors.lightGray, accent = colors.blue, accent2 = colors.lightBlue,
      good = colors.lime, warn = colors.orange, bad = colors.red, note = colors.yellow,
      btn = colors.orange, btnText = colors.black, btnOk = colors.lime, btnBad = colors.red,
    },
  },
}

-- Active semantic colors. Mutated in place by apply(); required by draw/sections.
M.C = {}

function M.isTheme(name) return M.THEMES[name] ~= nil end

-- apply(name, screens, config): set semantic map + palette on every monitor.
function M.apply(name, screens, config)
  local key = M.THEMES[name] and name or "deepslate"
  config.theme = key
  local t = M.THEMES[key]
  for k in pairs(M.C) do M.C[k] = nil end
  for k, v in pairs(t.sem) do M.C[k] = v end
  for _, s in ipairs(screens) do
    for c, hex in pairs(t.palette) do s.mon.setPaletteColour(c, hex) end
  end
end

function M.restore(screens)
  for _, s in ipairs(screens) do
    for i = 0, 15 do
      local c = 2 ^ i
      s.mon.setPaletteColour(c, term.nativePaletteColour(c))
    end
  end
end

-- Advance to the next theme in ORDER; returns the new name.
function M.cycle(config)
  local idx = 1
  for i, n in ipairs(M.ORDER) do if n == config.theme then idx = i end end
  return M.ORDER[(idx % #M.ORDER) + 1]
end

return M
