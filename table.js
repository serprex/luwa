module.exports = Table;

function Table() {
	this.keyidx = new Map();
	this.keys = [];
	this.rm = new Set();
	this.borders = [0];
	this.hash = new Map();
	this.metatable = null;
}

Table.prototype.hasborder = function(key) {
	let lo = 0, hi = this.borders.length;
	while (lo < hi) {
		let mid = lo + hi >> 1;
		if (this.borders[mid] > key) {
			lo = mid + 1;
		} else if (this.borders[mid] < key) {
			hi = mid;
		} else {
			return mid;
		}
	}
	return lo;
}

Table.prototype.set = function(key, val) {
	if (key === null || key !== key) {
		throw "table index is nil";
	}
	let isnum = (key|0) === key && key > 0;
	if (val === null) {
		if (this.hash.delete(key)) {
			this.rm.add(key);
			if (isnum) {
				let bidx = this.hasborder(key);
				if (this.borders[bidx] === key) {
					if (key !== 1 && this.hash.has(key-1)) {
						this.borders[bidx]--;
					} else if (this.borders.length) {
						this.borders.splice(bidx, 1);
					} else {
						this.borders[0] = 0;
					}
				} else if (this.borders[bidx] !== key && this.hash.has(key-1)) {
					this.borders.splice(bidx, 0, key-1);
				}
			}
		}
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
		if (isnum) {
			let bidx = this.hasborder(key - 1);
			if (this.borders[bidx] === key - 1) {
				if (bidx + 1 === this.borders.length && this.borders[bidx+1] !== key + 1) {
					this.borders[bidx]++;
				} else {
					this.borders.splice(bidx, 1);
				}
			} else if (this.borders[bidx] !== key && !this.hash.has(key + 1)) {
				this.borders.splice(bidx, 0, key);
			}
		}
	}
}

Table.prototype.get = function(key) {
	if (key === null || key != key) return null;
	let v = this.hash.get(key);
	return v === undefined ? null : v;
}

Table.prototype.getlength = function() {
	return this.borders[0];
}