#!/usr/bin/env node
// Runs the official Lua test suite one file at a time, each in its own node process,
// and prints pass / fail / trap / timeout per file.
//   scripts/suite.js              run every file not skipped
//   scripts/suite.js math pm      run only these (skipped ones too)
//   scripts/suite.js -v math      also show the output tail of failures
import { spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";
import path from "node:path";
import fs from "node:fs";

const here = fileURLToPath(import.meta.url);
const dir = path.join(path.dirname(here), "..", "lua-5.5.1-tests");
const timeout = 120000;

// Files that only make sense for C Lua, or that run the whole suite.
// api, memerr & code skip themselves when T is missing, big does under _soft
const skip = {
	all: "runs the whole suite, try once the rest pass",
	files: "file system & os heavy, revisit once io is fuller",
	gengc: "tests the C collector's generational mode",
	heavy: "needs huge memory, not run by all.lua either",
	main: "runs the lua executable",
	tracegc: "helper module for gc.lua",
	verybig: "needs huge memory",
};

async function freshrt() {
	const { default: mkrt } = await import("../rt.js");
	const rt = await mkrt();
	console.log = () => {}; // rt.js echoes ops through console.log
	rt.mod.genesis();
	const env = rt.mkref(rt.mod.initPrelude());
	await rt.evalWait();
	return [rt, env];
}
const log = console.log;
const text = r => r instanceof Uint8Array ? Buffer.from(r).toString() : String(r);

// Child: run one file in a fresh runtime. Prints @@PASS, or @@FAIL / @@TRAP & the message.
// Errors carry their position & a traceback, load failures say "load" first
async function child(name) {
	const [rt, env] = await freshrt();
	const src = `_port = true _soft = true
local f, e = loadfile(${JSON.stringify(name + ".lua")})
if not f then return "FAIL load " .. tostring(e) end
local ok, e = xpcall(f, debug.traceback)
if ok then return "PASS" end
return "FAIL " .. tostring(e)`;
	let r;
	try {
		r = await rt.eval(env, rt.newstr(src));
	} catch (e) {
		// rt.js adds the Lua traceback of where it trapped
		console.log = log;
		log(String(e.stack || e));
		log("\n@@TRAP " + e.message + "\n" + (e.luaTraceback || ""));
		return;
	}
	console.log = log;
	log("\n@@" + text(r));
}

// First "file:line:" in a traceback that's in the test file, for traps
function place(name, msg) {
	const m = msg.match(new RegExp(`^\\s*(${name}\\.lua:\\d+):`, "m"));
	return m ? m[1] : "?";
}

function parent(args) {
	const verbose = args[0] === "-v";
	if (verbose) args = args.slice(1);
	const names = args.length ? args :
		fs.readdirSync(dir).filter(f => f.endsWith(".lua")).map(f => f.slice(0, -4)).sort();
	const counts = {};
	for (const name of names) {
		let status, detail = "";
		if (!args.length && skip[name]) {
			status = "skip";
			detail = skip[name];
		} else {
			const r = spawnSync(process.execPath, [here, "--one", name], { cwd: dir, timeout, encoding: "utf8", maxBuffer: 1 << 26 });
			const out = (r.stdout || "") + (r.stderr || "");
			const m = /\n@@(PASS|FAIL|TRAP) ?([^]*)$/.exec(r.stdout || "");
			if (r.error?.code === "ETIMEDOUT" || r.signal === "SIGTERM") {
				status = "timeout";
			} else if (m && m[1] === "PASS") {
				status = "pass";
			} else if (m) {
				status = m[1].toLowerCase();
				let msg = m[2].trim();
				if (msg.startsWith("load ")) {
					status = "load " + status;
					msg = msg.slice(5);
				}
				const first = msg.split("\n")[0];
				detail = status === "trap" ? `at ${place(name, msg)}: ${first}` : first;
			} else {
				status = "trap";
				// the first line naming the problem, like RuntimeError: unreachable
				detail = (out.match(/^\w*Error.*$/m) || [""])[0];
			}
			if (verbose && status !== "pass") {
				detail += "\n" + out.trim().split("\n").slice(-15).map(l => "    " + l).join("\n");
			}
		}
		counts[status] = (counts[status] || 0) + 1;
		console.log(`${name.padEnd(12)} ${status.padEnd(10)} ${detail.slice(0, verbose ? Infinity : 150)}`);
	}
	console.log(Object.entries(counts).map(([k, v]) => `${v} ${k}`).join(", "));
}

if (process.argv[2] === "--one") {
	child(process.argv[3]).catch(e => {
		console.error(e);
		process.exit(1);
	});
} else {
	parent(process.argv.slice(2));
}
