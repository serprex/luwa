#!/usr/bin/env node
"use strict";

if (!('TRAVIS' in process.env)) {
	require("../rt")().then(rt => {
		const assert = require("assert"),
			lua = require("../luwa"),
			e = require("../env")();

		lua.eval(rt, "x = 3 * 5 + 2", e);
		assert.equal(e.get("x"), 17);
		lua.eval(rt, "y = 0 while y < x do y = y + 1 end", e);
		assert.equal(e.get("y"), 17);

		let newt = rt.newtable();
		let news = rt.newstr("asdf");
		let newf = rt.newf64(4.2);
		let shouldbenil = rt.mkref(rt.mod.tabget(newt.val, news.val));
		rt.mod.tabset(newt.val, news.val, newf.val);
		assert.equal(shouldbenil.val, rt.nil.val);
		assert.equal(rt.mod.tabget(newt.val, news.val), newf.val);
	}).catch(err => {
		console.log(err);
		process.exit(1);
	});
}