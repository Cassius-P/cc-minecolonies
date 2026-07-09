local t    = require("helper")
local sha1 = require("common.sha1")

t.case("sha1 known vectors")
t.eq(sha1.hex(""), "da39a3ee5e6b4b0d3255bfef95601890afd80709", "empty")
t.eq(sha1.hex("abc"), "a9993e364706816aba3e25717850c26c9cd0d89d", "abc")
t.eq(sha1.hex("The quick brown fox jumps over the lazy dog"),
  "2fd4e1c67a2d28fced849ee1bb76e7391b93eb12", "fox")

t.case("sha1 spans multiple blocks")
-- 56 bytes forces an extra padding block; 64+ spans chunks.
t.eq(sha1.hex(("a"):rep(56)), "c2db330f6083854c99d4b5bfb6e8f29f201be699", "56 a's (padding edge)")
t.eq(sha1.hex(("a"):rep(1000)), "291e9a6c66994949b57ba5e650361e98fc36b1ba", "1000 a's")

t.case("git blob sha (blob <len>\\0<content>)")
-- git hash-object of an empty file.
t.eq(sha1.hex("blob 0\0"), "e69de29bb2d1d6434b8b29ae775ad8c2e48c5391", "empty blob")
-- git hash-object of a file containing "hello\n".
t.eq(sha1.hex("blob 6\0hello\n"), "ce013625030ba8dba906f756967f9e9ca394464a", "hello blob")
