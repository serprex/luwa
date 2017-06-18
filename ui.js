(function(){"use strict";
const taBoard = document.getElementById("taBoard");
const prOut = document.getElementById("prOut");
const assert = {
	equal: (x, y) => {
		if (x != y) {
			throw ["assert.equal", x, y];
		} else {
			console.log("assert.equal", x);
		}
	}
};
const util = require("./util");
document.getElementById("btnRt").addEventListener("click", (s, e) => {
	require("./rt")().then(rt => {
		console.log(window.mod = rt);
		let newt = rt.newtable();
		let news = rt.newstr("asdf");
		let news2 = rt.newstr("asdf");
		assert.equal(util.fromUtf8(rt.strbytes(news)), "asdf");
		let newf = rt.newf64(4.2);
		let nil = rt.mkref(rt.mod.tabget(newt.val, news.val));
		rt.mod.tabset(newt.val, news.val, newf.val);
		assert.equal(nil.val, rt.nil.val);
		assert.equal(rt.mod.tabget(newt.val, news.val), newf.val);
		assert.equal(rt.mod.tabget(newt.val, news2.val), newf.val);
		let newf2 = rt.newf64(5.4);
		let newf3 = rt.newf64(6.6);
		let newf4 = rt.newf64(7.8);
		rt.mod.tabset(newt.val, newf2.val, newf3.val);
		rt.mod.tabset(newt.val, newf3.val, newf4.val);
		rt.mod.tabset(newt.val, newf4.val, newf2.val);
		console.log("newt", newt.val, "news", news.val, news2.val, "newf", newf.val,
			newf2.val, newf3.val, newf4.val);
		assert.equal(rt.mod.tabget(newt.val, newf2.val), newf3.val);
		assert.equal(rt.mod.tabget(newt.val, newf3.val), newf4.val);
		assert.equal(rt.mod.tabget(newt.val, newf4.val), newf2.val);
		assert.equal(rt.mod.tabget(newt.val, newf.val), nil.val);
		console.log("Tested newtab/tabget/tabset. Next: string gc pressure");
		let s = "0123456789", ss = [];
		for (var i=0; i<10; i++) s += s;
		for (var j=0; j<2; j++) {
			for (var i=0; i<8; i++) {
				ss.push(rt.newstr(s));
				console.log(rt.mem.buffer.byteLength, ss.map(x => x.val), Array.from(rt.handles).map(x => x.val));
			}
			while (ss.length) {
				rt.free(ss.pop());
			}
			console.log("Freed" + (j?". Next: lex":". Now to do it again"));
		}
		let codestr = rt.newstr("local x = 3 * 5 + 2; local y = 'x' + 'z'");
		console.log(codestr.val, rt.strbytes(rt.mkref(rt.mod.lex(codestr.val))), codestr.val);
	}).catch(err => {
		console.log("ERR", err);
	});
});
document.getElementById("btnGo").addEventListener("click", (s, e) => {
	const lua = require("./luwa");
	const imp = {
		"": {
			p: x => prOut.textContent += x + " ",
			q: x => prOut.textContent += String.fromCharCode(x),
			i: () => prompt("Number", "")|0,
			c: () => prompt("Character", "").charCodeAt(0)|0,
			m: new WebAssembly.Memory({ initial: 1 }),
		}
	};
	prOut.textContent = "";
	lua.runSource(taBoard.value, imp);
});
})();
