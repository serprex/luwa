const metas = new WeakMap();

exports.metaget = (x, prop) => {
	let t = metas.get(x);
	return t && (t.get(prop) || null);
}

exports.getmetatable = x => metas.get(x) || null;

exports.setmetatable = (x, y) => {
	if (x && typeof x === "object" && typeof y === "object") {
		metas.set(x, y);
		return x;
	}
}

exports.add = (x, y) => {
	
};