#!/usr/bin/env node
// Tests make.lua's WasmGC support: builds scripts/maketest.lua's module & runs it
import assert from "node:assert";
import { execFileSync } from "node:child_process";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";

const out = path.join(os.tmpdir(), "luwa-maketest.wasm");
execFileSync("lua", ["scripts/maketest.lua", out], { cwd: path.join(import.meta.dirname, ".."), stdio: "inherit" });

WebAssembly.instantiate(fs.readFileSync(out)).then(({ instance }) => {
	const e = instance.exports;
	assert.strictEqual(e.sumlist(4), 10n);
	assert.deepStrictEqual(e.divmod(17, 5), [3, 2]);
	assert.strictEqual(e.swapsub(10, 3), -7);
	assert.strictEqual(e.classify(null), 0);
	assert.strictEqual(e.classify(5), 1);
	assert.strictEqual(e.classify(e.mkfbox(1.5)), 2);
	assert.strictEqual(e.classify({}), 3);
	assert.strictEqual(e.hello(), 5101);
	assert.strictEqual(e.apply(21), 42);
	assert.strictEqual(e.fact(5n, 1n), 120n);
	e.tblset(1, 7);
	assert.strictEqual(e.tblget(1), 7);
	assert.strictEqual(e.tblget(0), null);
	assert.strictEqual(e.glen(), 2);
	assert.strictEqual(e.pick(1, 8, 9), 8);
	assert.strictEqual(e.pick(0, 8, 9), 9);
	console.log("make.lua gc test ok");
}).catch(err => {
	console.error(err);
	process.exit(1);
});