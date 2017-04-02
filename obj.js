const metas = new WeakMap();

exports.getmetatable = x => {
	return metas.get(x) || null;
}

exports.setmetatable = (x, y) => {
	if (x && typeof x === "object" && typeof y === "object") {
		metas.set(x, y);
		return x;
	}
}

exports.add = (x, y) => {
	
};