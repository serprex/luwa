"use strict";
const opc = require("./bc"),
	env = require("./env"),
	Table = require("./table");


function vm(_G, stack, bc) {
	this._G = _G;
	this.pc = 0;
	this.stack = stack;
	this.bc = bc;
	this.locals = [];
}

vm.prototype.pop = function() {
	return this.stack.pop();
}
vm.prototype.push = function(x) {
	return this.stack.push(x);
}

vm.prototype.run = function() {
	var bc = this.bc.bc, lx = this.bc.lx;
	var labels = [];
	for (var i=0; i<bc.length; i += (bc[i] >> 6) + 1) {
		if (bc[i] == opc.LABEL) {
			labels[bc[i+1]] = i;
		}
	}
	while (true){
		let op = bc[this.pc], arg, arg2, arg3;
		switch (op >> 6) {
			// thru
			case 3:arg3 = bc[this.pc+3];
			case 2:arg2 = bc[this.pc+2];
			case 1:arg = bc[this.pc+1];
		}
		this.pc += (op >> 6) + 1;
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
				this.push(a.getlength());
				break;
			}
			case opc.UNARY_BNOT: {
				let a = this.pop();
				this.push(~a);
				break;
			}
			case opc.MAKE_TABLE: {
				this.push(new Table());
				break;
			}
			case opc.FORTIFY: {
				break;
			}
			case opc.FOR2: {
				let a = this.pop(), b = this.pop();
				if (b > a) {
					this.pc = labels[arg];
				}
				else {
					this._G.set(lx.ssr[bc[arg2]], b);
					this.push(b+1, a);
				}
				break;
			}
			case opc.FOR3: {
				let a = this.pop(), b = this.pop(), c = this.pop(), ca = c+a;
				if (Math.abs(ca - b) > Math.abs(c - b) && b != c) {
					this.pc = labels[arg];
				}
				else {
					this._G.set(lx.ssr[bc[arg2]], c);
					this.push(ca, b, a);
				}
				break;
			}
			case opc.LOAD_FUNC: {
				this.push(this.bc.fus[arg]);
				break;
			}
			case opc.POP: {
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
			case opc.LOAD_VARG: {
				break;
			}
			case opc.TABLE_SET: {
				let a = this.pop(), b = this.pop(), c = this.pop();
				c.set(b, a);
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
			case opc.APPEND: {
				let a = this.pop(), b = this.pop();
				b.add(a);
				this.push(b);
				break;
			}
			case opc.APPEND_CALL: {
				break;
			}
			case opc.APPEND_VARG_CALL: {
				break;
			}
			case opc.RETURN_CALL: {
				let endstl = this.stack.length - arg2 - 1;
				let fu = this.stack[endstl];
				for (var i=0; i<arg - 1; i++) {
					// TODO inner calls
				}
				if (typeof fu === 'function') {
					return fu(this, arg);
				} else {
					this.bc = fu;
					bc = this.bc.bc;
					lx = this.bc.lx;
					this.stack.length = endstl;
					this.pc = 0;
				}
				break;
			}
			case opc.RETURN_VARG_CALL: {
				break;
			}
			case opc.CALL: {
				let endstl = this.stack.length - arg2 - 1;
				let fu = this.stack[endstl];
				if (typeof fu === 'function') {
					fu(this);
				} else {
					let subvm = new vm(this._G, this.stack);
					subvm.run(fu);
				}
				break;
			}
			case opc.VARG_CALL: {
				break;
			}
			case opc.FOR_NEXT: {
				for (let i=arg2-1; i >= 0; i--) {
					this._G.set(lx.ssr[bc[this.pc+i]], this.pop());
				}
				this.pc += arg2
				break;
			}
		}
	}
}

function run(bc) {
	var e = env();
	var v = new vm(e, [], bc);
	v.run();
	console.log("vm", v);
	return v.stack;
}

exports.run = run;
