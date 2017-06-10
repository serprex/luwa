#!/usr/bin/env node
"use strict";

const assert = require("assert"),
	lua = require("../luwa"),
	e = require("../env")();

lua.eval("x = 3 * 5 + 2", e);
assert.equal(e.get("x"), 17);
lua.eval("y = 0 while y < x do y = y + 1 end", e);
assert.equal(e.get("y"), 17);

require("../rt")().then(rt => {
	let newt = rt.newtable();
	let news = rt.newstr("asdf");
	let newf = rt.newf64(4.2);
	let nil = rt.mod.tabget(newt.val, news.val);
	rt.mod.tabset(newt.val, news.val, newf.val);
	assert.equal(nil.val, 0); // todo should export a getter for nil/true/false
	assert.equal(rt.mod.tabget(newt.val, news.val), newf.val);
}).catch(err => {
	console.log(err);
	process.exit(1);
});