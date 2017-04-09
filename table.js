module.exports = Table;

function Table() {
	this.hash = new Map();
	this.array = [];
}

Table.prototype.set = function(key, val) {
	if ((key|0) === key && key > 0) {
		if (val === null) {
			delete this.array[key];
		} else {
			this.array[key] = val;
		}
	} else if (val === null) {
		this.hash.delete(key);
	} else {
		this.hash.set(key, val);
	}
}

Table.prototype.add = function(val) {
	if (val !== null) {
		this.array[this.array.length || 1] = val;
	}
}

Table.prototype.get = function(key) {
	let v = (key|0) === key ? this.array[key] : this.hash.get(key);
	return v === undefined ? null : v;
}

Table.prototype.getlength = function() {
	return this.array.length - 1;
}