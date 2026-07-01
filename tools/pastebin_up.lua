--[[ up.lua -- upload a file from this computer to paste.rs, print link
     usage: up <path>                                                  ]]

local args = { ... }
local path = args[1]
if not path then
  print("Usage: up <file>")
  return
end

path = shell.resolve(path)
if not fs.exists(path) or fs.isDir(path) then
  printError("No such file: " .. path)
  return
end

local f = fs.open(path, "r")
local body = f.readAll()
f.close()

if not body or #body == 0 then
  printError("File is empty: " .. path)
  return
end

local resp, err = http.post("https://paste.rs", body)
if not resp then
  printError("Upload failed: " .. tostring(err))
  return
end

local link = resp.readAll()
resp.close()
print((link:gsub("%s+$", "")))
