#!/usr/bin/env node
"use strict";
const assert = require("assert");

require("../rt")().then(async rt => {
	rt.mod.genesis();
	const env = rt.mkref(rt.mod.initPrelude());
	await rt.evalWait();

	// tables, straight through exports
	const newt = rt.newtbl();
	const news = rt.newstr("asdf");
	const newf = rt.newf64(4.2);
	assert.equal(rt.mod.tblget(newt.val, news.val), rt.nil.val);
	rt.mod.tblset(newt.val, news.val, newf.val);
	assert.equal(rt.mod.tblget(newt.val, news.val), newf.val);
	rt.free(news);
	rt.free(newf);
	rt.free(newt);

	// lua source, through the vm
	async function run(src) {
		const line = rt.newstr(src);
		try {
			return await rt.eval(env, line);
		} finally {
			rt.free(line);
		}
	}
	assert.equal(await run("return 1+2"), 3);
	assert.equal(await run("x = 3 * 5 + 2 return x"), 17);
	assert.equal(await run("local y = 0 while y < x do y = y + 1 end return y"), 17);
	console.log("ok");
}).catch(err => {
	console.log(err);
	process.exit(1);
});
