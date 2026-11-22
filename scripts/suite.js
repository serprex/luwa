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

// Child: run one file in a fresh runtime. Prints @@PASS, or @@FAIL / @@TRAP, the assert count & the message.
// The count is -1 while loading the file
async function child(name) {
	const [rt, env] = await freshrt();
	// count assert calls, so the parent can find the line with scripts/assertline.lua
	const src = `_port = true _soft = true
local real = assert
__nassert = -1
local f, e = loadfile(${JSON.stringify(name + ".lua")})
if not f then return "FAIL -1 " .. tostring(e) end
__nassert = 0
assert = function(...) __nassert = __nassert + 1 return real(...) end
local ok, e = pcall(f)
if ok then return "PASS" end
return "FAIL " .. __nassert .. " " .. tostring(e)`;
	let r;
	try {
		r = await rt.eval(env, rt.newstr(src));
	} catch (e) {
		// a trap leaves the runtime's objects readable, so the count is still there
		const n = rt.obj2js(rt.mod.tblget(env.val, rt.newstr("__nassert").val));
		console.log = log;
		log(String(e.stack || e));
		log("\n@@TRAP " + n + " " + e);
		return;
	}
	console.log = log;
	log("\n@@" + text(r));
}

// Child: does luwa load the first n lines of a file. Prints @@OK, or @@ERR & the message
async function parsechild(name, n) {
	const [rt, env] = await freshrt();
	const src = fs.readFileSync(path.join(dir, name + ".lua"), "utf8").split(/(?<=\n)/).slice(0, n).join("");
	const r = await rt.eval(env, rt.newstr("local f, e = load(...) return f and 'OK' or 'ERR ' .. tostring(e)"), rt.newstr(src));
	console.log = log;
	log("\n@@" + text(r));
}

// The first line luwa can't load. Host lua says which line prefixes are whole chunks,
// then a binary search finds the shortest one luwa fails on. Gives "from-to: line text"
function parseline(name) {
	const hr = spawnSync("lua", [path.join(path.dirname(here), "assertline.lua"), "parse", name + ".lua"], { cwd: dir, timeout: 60000, encoding: "utf8" });
	const ends = (hr.stdout || "").trim().split("\n").map(Number).filter(n => n > 0);
	const loads = n => /\n@@OK/.test(spawnSync(process.execPath, [here, "--parse", name, n], { cwd: dir, timeout, encoding: "utf8" }).stdout || "");
	let lo = 0, hi = ends.length - 1;
	if (hi < 0 || loads(ends[hi])) return "?";
	// ends[hi] fails, ends[lo-1] loads
	while (lo < hi) {
		const mid = (lo + hi) >> 1;
		if (loads(ends[mid])) lo = mid + 1;
		else hi = mid;
	}
	const from = lo > 0 ? ends[lo - 1] + 1 : 1, to = ends[lo];
	const lines = fs.readFileSync(path.join(dir, name + ".lua"), "utf8").split("\n");
	return `${name}.lua:${from}${to > from ? "-" + to : ""}: ${lines[from - 1].trim().slice(0, 60)}`;
}

// Where the n-th assert call is, by running the file under host lua
function assertline(name, n) {
	const r = spawnSync("lua", [path.join(path.dirname(here), "assertline.lua"), n, name + ".lua"], { cwd: dir, timeout: 30000, encoding: "utf8" });
	return (/\n@@(.*)\n$/.exec(r.stdout || "") || [, "?"])[1];
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
			const m = /\n@@(PASS|FAIL|TRAP)([^]*)$/.exec(r.stdout || "");
			if (r.error?.code === "ETIMEDOUT" || r.signal === "SIGTERM") {
				status = "timeout";
			} else if (m && m[1] === "PASS") {
				status = "pass";
			} else if (m) {
				// FAIL or TRAP, then the assert count & the message
				status = m[1].toLowerCase();
				const [, n, msg] = /^\s*(-?\d+) ([^]*)$/.exec(m[2]) || [, 0, m[2]];
				const first = msg.trim().split("\n")[0];
				if (n < 0) {
					status = "load " + status;
					detail = `${parseline(name)} -- ${first}`;
				} else {
					// a failed assert is call n, other errors & traps come after call n
					const at = n > 0 ? assertline(name, n) : "start";
					detail = `${status === "fail" && msg.startsWith("assertion failed") ? "at" : "after"} ${at}: ${first}`;
				}
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

if (process.argv[2] === "--one" || process.argv[2] === "--parse") {
	(process.argv[2] === "--one" ? child(process.argv[3]) : parsechild(process.argv[3], +process.argv[4])).catch(e => {
		console.error(e);
		process.exit(1);
	});
} else {
	parent(process.argv.slice(2));
}
