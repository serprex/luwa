"use strict";
const opc = require("./bc");

function vm(_G, stack) {
	this._G = _G;
	this.pc = 0;
	this.stack = stack;
}

vm.prototype.pop = function() {
	return this.stack.pop();
}
vm.prototype.push = function(x) {
	return this.stack.push(x);
}

vm.prototype.run = function(Bc) {
	var bc = Bc.bc, lx = Bc.lx;
	var labels = [];
	for (var i=0; i<bc.length;) {
		if (bc[i] == opc.LABEL) {
			labels[bc[i+1]] = i;
		}
		if (i&128) i+=2;
		else i++;
	}
	while (true){
		let op = bc[this.pc], arg;
		if (op & 128) arg = bc[this.pc+1];
		switch (op) {
			case opc.LOAD_NIL: {
				this.push(null);
				break;
			}
			case opc.LOAD_FALSE: {
				this.push(false);
				break;
			}
			case opc.LOAD_TRUE: {
				this.push(true);
				break;
			}
			case opc.BIN_PLUS: {
				let a = this.pop(), b = this.pop();
				this.push(b + a);
				break;
			}
			case opc.BIN_MINUS: {
				let a = this.pop(), b = this.pop();
				this.push(b - a);
				break;
			}
			case opc.BIN_MUL: {
				let a = this.pop(), b = this.pop();
				this.push(b * a);
				break;
			}
			case opc.BIN_DIV: {
				let a = this.pop(), b = this.pop();
				this.push(b / a);
				break;
			}
			case opc.BIN_IDIV: {
				let a = this.pop(), b = this.pop();
				this.push(b / a | 0);
				break;
			}
			case opc.BIN_POW: {
				let a = this.pop(), b = this.pop();
				this.push(Math.pow(b, a));
				break;
			}
			case opc.BIN_MOD: {
				let a = this.pop(), b = this.pop();
				this.push(b % a);
				break;
			}
			case opc.BIN_BAND: {
				let a = this.pop(), b = this.pop();
				this.push(b & a);
				break;
			}
			case opc.BIN_BNOT: {
				let a = this.pop(), b = this.pop();
				this.push(b ^ a);
				break;
			}
			case opc.BIN_BOR: {
				let a = this.pop(), b = this.pop();
				this.push(b | a);
				break;
			}
			case opc.BIN_RSH: {
				let a = this.pop(), b = this.pop();
				this.push(b >> a);
				break;
			}
			case opc.BIN_LSH: {
				let a = this.pop(), b = this.pop();
				this.push(b << a);
				break;
			}
			case opc.BIN_DOTDOT: {
				let a = this.pop(), b = this.pop();
				this.push(b.toString() + a.toString());
				break;
			}
			case opc.BIN_LT: {
				let a = this.pop(), b = this.pop();
				this.push(b < a);
				break;
			}
			case opc.BIN_LTE: {
				let a = this.pop(), b = this.pop();
				this.push(b <= a);
				break;
			}
			case opc.BIN_GT: {
				let a = this.pop(), b = this.pop();
				this.push(b > a);
				break;
			}
			case opc.BIN_GTE: {
				let a = this.pop(), b = this.pop();
				this.push(b >= a);
				break;
			}
			case opc.BIN_EQ: {
				let a = this.pop(), b = this.pop();
				this.push(b == a);
				break;
			}
			case opc.BIN_NEQ: {
				let a = this.pop(), b = this.pop();
				this.push(b != a);
				break;
			}
			case opc.UNARY_MINUS: {
				this.push(-this.pop());
				break;
			}
			case opc.UNARY_NOT: {
				let a = this.pop();
				this.push(a !== false && a !== nil);
				break;
			}
			case opc.UNARY_HASH: {
				let a = this.pop();
				this.push(a.length);
				break;
			}
			case opc.UNARY_BNOT: {
				let a = this.pop();
				this.push(~a);
				break;
			}
			case opc.MAKE_TABLE: {
				this.push(new Map());
				break;
			}
			case opc.TABLE_ADD: {
				let a = this.pop(), b = this.pop();
				b.add(b.size, a);
				this.push(b);
				break;
			}
			case opc.FORTIFY: {
				break;
			}
			case opc.FOR2: {
				break;
			}
			case opc.FOR3: {
				break;
			}
			case opc.FOR_NEXT: {
				break;
			}
			case opc.POP2: {
				this.pop();
				this.pop();
				break;
			}
			case opc.POP3: {
				this.pop();
				this.pop();
				this.pop();
				break;
			}
			case opc.LOAD_INDEX: {
				let a = this.pop();
				this.push(a);
				break;
			}
			case opc.STORE_INDEX: {
				let a = this.pop(), b = this.pop(), c = this.pop();
				b.set(a, c); // TODO should be c.set(b, a)
				break;
			}
			case opc.LOAD_NUM: {
				this.push(lx.snr[arg]);
				break;
			}
			case opc.LOAD_STR: {
				this.push(lx.ssr[arg]);
				break;
			}
			case opc.LOAD_VARARG: {
				break;
			}
			case opc.LOAD_IDENT: {
				this.push(this._G.get(lx.ssr[arg]));
				break;
			}
			case opc.GOTO: {
				this.pc = labels[arg];
				break;
			}
			case opc.RETURN: {
				return;
			}
			case opc.STORE_IDENT: {
				this._G.set(lx.ssr[arg], this.pop());
				break;
			}
			case opc.CALL: {
				var subvm = new vm(this._G, this.stack);
				subvm.run(Bc.fu[this.stack[this.stack-arg-1]]);
				break;
			}
			case opc.STORE_INDEX_SWAP: {
				let a = this.pop(), b = this.pop(), c = this.pop();
				c.set(a, b);
				this.push(c);
				break;
			}
			case opc.TABLE_SET: {
				let a = this.pop(), b = this.pop(), c = this.pop();
				c.add(b, a);
				this.push(c);
				break;
			}
			case opc.JIF: {
				let a = this.pop();
				if (a !== false && a !== null) this.pc = labels[arg];
				break;
			}
			case opc.JIFNOT: {
				let a = this.pop();
				if (a === false || a === null) this.pc = labels[arg];
				break;
			}
			case opc.LOAD_METH: {
				let a = this.pop();
				this.push(a.get(lx.sir[arg]));
				this.push(a);
				break;
			}
			case opc.STORE_METH: {
				break;
			}
			case opc.JIF_OR_POP: {
				let a = this.pop();
				if (a !== false && a !== null) {
					this.push(a);
					this.pc = labels[arg];
				}
				break;
			}
			case opc.JIFNOT_OR_POP: {
				let a = this.pop();
				if (a === false || a === null) {
					this.push(a);
					this.pc = labels[arg];
				}
				break;
			}
			case opc.RETURN_CALL: {
				var subvm = new vm(this._G, this.stack);
				Bc = arg;
				bc = Bc.bc;
				lx = Bc.lx;
				this.pc = -2;
				break;
			}
		}
		if (op&128) this.pc += 2;
		else this.pc += 1
	}
}

function run(bc) {
	var _G = new Map();
	var io = new Map();
	io.set("write", x => console.log(x));
	io.set("clock", () => Date.now());
	_G.set("io", io);
	_G.set(_G, _G);
	var v = new vm(_G, []);
	v.run(bc);
	return v.stack;
}

exports.run = run;
