#!/usr/bin/env node
"use strict";
const assert = require("assert"),
	lua = require("../luwa"),
	util = require('../util');

require("../rt")().then(rt => {
	const e = require("../env")();
	rt.initstack();

	let newt = rt.newtbl();
	let news = rt.newstr("asdf");
	let newf = rt.newf64(4.2);
	let shouldbenil = rt.mkref(rt.mod.tblget(newt.val, news.val));
	rt.mod.tblset(newt.val, news.val, newf.val);
	assert.equal(shouldbenil.val, rt.nil.val);
	assert.equal(rt.mod.tblget(newt.val, news.val), newf.val);
	rt.free(shouldbenil);
	rt.free(news);
	rt.free(newf);
	rt.free(newt);

	lua.eval(rt, "x = 3 * 5 + 2", e);
	assert.equal(e.get("x"), 17);
	lua.eval(rt, "y = 0 while y < x do y = y + 1 end", e);
	console.log(e);
	assert.equal(e.get("y"), 17);

}).catch(err => {
	console.log(err);
	process.exit(1);
});