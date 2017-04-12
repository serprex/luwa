module.exports = Table;

function Table() {
	this.keyidx = new Map();
	this.keys = [];
	this.rm = new Set();
	this.hash = new Map();
	this.array = [];
}

Table.prototype.set = function(key, val) {
	if (key === null) {
		throw "table index is nil";
	}
	else if ((key|0) === key && key > 0) {
		if (val === null) {
			delete this.array[key];
			this.rm.add(key);
		} else {
			if (!this.keyidx.has(key)) {
				for (let k of this.rm) {
					this.keys.splice(this.keyidx.get(k), 1);
					this.keyidx.delete(k);
				}
				this.rm.clear();
				this.keyidx.set(key, this.keys.length);
				this.keys.push(key);
			}
			this.array[key] = val;
		}
	} else if (val === null) {
		this.hash.delete(key);
		this.rm.add(key);
	} else {
		if (!this.keyidx.has(key)) {
			for (let k of this.rm) {
				this.keys.splice(this.keyidx.get(k), 1);
				this.keyidx.delete(k);
			}
			this.rm.clear();
			this.keyidx.set(key, this.keys.length);
			this.keys.push(key);
		}
		this.hash.set(key, val);
	}
}

Table.prototype.add = function(val) {
	if (val !== null) {
		let key = this.array.length || 1;
		this.array[key] = val;
		this.keyidx.set(key, this.keys.length);
		this.keys.push(key);
	}
}

Table.prototype.get = function(key) {
	if (key === null || key != key) return null;
	let v = (key|0) === key ? this.array[key] : this.hash.get(key);
	return v === undefined ? null : v;
}

Table.prototype.getlength = function() {
	return this.array.length - 1;
}