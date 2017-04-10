const metas = new WeakMap(),
	Table = require("./table");


const stringMetatable = new Table();
stringMetatable.set("__index", require("./string"));

exports.metaget = metaget;
function metaget(x, prop) {
	let t = getmetatable(x);
	return t && (t.get(prop) || null);
}

function getmetatable(x) {
	return typeof x == "string" ? stringMetatable : metas.get(x) || null;
}
exports.getmetatable = getmetatable;

exports.setmetatable = (x, y) => {
	if (x && typeof x === "object" && typeof y === "object") {
		metas.set(x, y);
		return x;
	}
}

exports.index = function index(x, key) {
	let v = x instanceof Table ? x.get(key) : null;
	if (v === null) {
		let __index = metaget(x, "__index");
		if (__index) return index(__index, key);
	}
	return v;
}

exports.add = (x, y) => {

}