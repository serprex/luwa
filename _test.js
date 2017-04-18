const lua = require("./luwa"),
	e = require("./env")();

lua.eval("x = 3 * 5 + 2", e);
assert.equal(e.get("x"), 17);