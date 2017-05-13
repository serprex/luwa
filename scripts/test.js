#!/usr/bin/env node

const assert = require("assert"),
	lua = require("../luwa"),
	e = require("../env")();

lua.eval("x = 3 * 5 + 2", e);
assert.equal(e.get("x"), 17);
lua.eval("y = 0 while y < x do y = y + 1 end", e);
assert.equal(e.get("y"), 17);