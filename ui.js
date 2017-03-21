(function(){"use strict";
const lua = require("./luwa");
const taBoard = document.getElementById("taBoard");
const prOut = document.getElementById("prOut");
document.getElementById("btnGo").addEventListener("click", (s, e) => {
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
