local t         = require("helper")
local installer = require("common.installer")
local sha1      = require("common.sha1")

t.case("gitBlobSha matches git hash-object")
t.eq(installer.gitBlobSha(""), "e69de29bb2d1d6434b8b29ae775ad8c2e48c5391", "empty file")
t.eq(installer.gitBlobSha("hello\n"), "ce013625030ba8dba906f756967f9e9ca394464a", "hello file")

t.case("decide: config preserved")
t.eq(installer.decide({ preserve = true, exists = true }), "keep", "existing config kept")
t.eq(installer.decide({ preserve = true, exists = false, diff = false }), "get", "missing config fetched")

t.case("decide: no diff -> always get")
t.eq(installer.decide({ diff = false, exists = true }), "get")
t.eq(installer.decide({ diff = true, exists = true, remote = nil }), "get", "remote unknown -> get")

t.case("decide: diff skips identical")
local sha = sha1.hex("blob 3\0abc")
local calls = 0
local function localSha() calls = calls + 1; return sha end
t.eq(installer.decide({ diff = true, exists = true, remote = { sha = sha, size = 3 },
  localSize = 3, localSha = localSha }), "skip", "same size + sha -> skip")
t.eq(calls, 1, "hash computed once for size match")

t.case("decide: size mismatch skips the hash")
calls = 0
t.eq(installer.decide({ diff = true, exists = true, remote = { sha = sha, size = 999 },
  localSize = 3, localSha = localSha }), "get", "size differs -> get")
t.eq(calls, 0, "no hash when sizes differ")

t.case("decide: sha mismatch -> get")
t.eq(installer.decide({ diff = true, exists = true, remote = { sha = "deadbeef", size = 3 },
  localSize = 3, localSha = function() return sha end }), "get", "same size, different sha")

t.case("decide: missing local -> get")
t.eq(installer.decide({ diff = true, exists = false, remote = { sha = sha, size = 3 } }), "get")
