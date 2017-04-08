"use strict";
const lex = require("./lex"), ast = require("./ast"), Func = require("./func");

const NOP = exports.NOP = 0,
	LOAD_NIL = exports.LOAD_NIL = 1,
	LOAD_FALSE = exports.LOAD_FALSE = 2,
	LOAD_TRUE = exports.LOAD_TRUE = 3,
	BIN_PLUS = exports.BIN_PLUS = 4,
	BIN_MINUS = exports.BIN_MINUS = 5,
	BIN_MUL = exports.BIN_MUL = 6,
	BIN_DIV = exports.BIN_DIV = 7,
	BIN_IDIV = exports.BIN_IDIV = 8,
	BIN_POW = exports.BIN_POW = 9,
	BIN_MOD = exports.BIN_MOD = 10,
	BIN_BAND = exports.BIN_BAND = 11,
	BIN_BNOT = exports.BIN_BNOT = 12,
	BIN_BOR = exports.BIN_BOR = 13,
	BIN_RSH = exports.BIN_RSH = 14,
	BIN_LSH = exports.BIN_LSH = 15,
	BIN_DOTDOT = exports.BIN_DOTDOT = 16,
	BIN_LT = exports.BIN_LT = 17,
	BIN_LTE = exports.BIN_LTE = 18,
	BIN_GT = exports.BIN_GT = 19,
	BIN_GTE = exports.BIN_GTE = 20,
	BIN_EQ = exports.BIN_EQ = 21,
	BIN_NEQ = exports.BIN_NEQ = 22,
	UNARY_MINUS = exports.UNARY_MINUS = 23,
	UNARY_NOT = exports.UNARY_NOT = 24,
	UNARY_HASH = exports.UNARY_HASH = 25,
	UNARY_BNOT = exports.UNARY_BNOT = 26,
	MAKE_TABLE = exports.MAKE_TABLE = 27,
	APPEND = exports.APPEND = 28,
	FORTIFY = exports.FORTIFY = 29,
	TABLE_SET = exports.TABLE_SET = 30,
	POP = exports.POP = 32,
	LOAD_INDEX = exports.LOAD_INDEX = 35,
	STORE_INDEX = exports.STORE_INDEX = 36,
	RETURN = exports.RETURN = 37,
	RETURN_VARG = exports.RETURN_VARG = 38,
	APPEND_VARG = exports.APPEND_VARG = 39,
	STORE_INDEX2 = exports.STORE_INDEX2 = 40,
	LOAD_NUM = exports.LOAD_NUM = 64,
	LOAD_STR = exports.LOAD_STR = 65,
	LOAD_DEREF = exports.LOAD_DEREF = 66,
	STORE_DEREF = exports.STORE_DEREF = 67,
	GOTO = exports.GOTO = 68,
	LOAD_LOCAL = exports.LOAD_LOCAL = 69,
	STORE_LOCAL = exports.STORE_LOCAL = 70,
	LOAD_VARG = exports.LOAD_VARG = 71,
	JIF = exports.JIF = 73,
	JIFNOT = exports.JIFNOT = 74,
	LOAD_METH = exports.LOAD_METH = 75,
	STORE_METH = exports.STORE_METH = 76,
	JIF_OR_POP = exports.JIF_OR_POP = 77,
	JIFNOT_OR_POP = exports.JIFNOT_OR_POP = 78,
	RETURN_VARG_CALL = exports.RETURN_VARG_CALL = 79,
	APPEND_VARG_CALL = exports.APPEND_VARG_CALL = 80,
	FOR2 = exports.FOR2 = 81,
	FOR3 = exports.FOR3 = 82,
	LOAD_FUNC = exports.LOAD_FUNC = 83,
	LABEL = exports.LABEL = 127,
	VARG_CALL = exports.VARG_CALL = 129,
	FOR_NEXT = exports.FOR_NEXT = 130,
	RETURN_CALL = exports.RETURN_CALL = 131,
	APPEND_CALL = exports.APPEND_CALL = 132,
	CALL = exports.CALL = 192;

function *selectNodes(node, type) {
	for (let i = node.fathered.length - 1; i >= 0; i--) {
		let ch = node.fathered[i];
		if ((ch.type & 31) == type) {
			yield ch;
		}
	}
}

function selectNode(node, type) {
	for (let i = node.fathered.length - 1; i >= 0; i--) {
		let ch = node.fathered[i];
		if ((ch.type & 31) == type) {
			return ch;
		}
	}
}

function Assembler(lx, pcount, isdotdotdot, uplink) {
	this.idgen = uplink ? uplink.idgen : {value: 0};
	this.id = this.idgen.value++;
	this.lx = lx;
	this.bc = [];
	this.fus = [];
	this.fuli = [];
	this.labgen = 0;
	this.loops = [];
	this.pcount = pcount;
	this.lcount = 0;
	this.fcount = 0;
	this.locals = [];
	this.frees = [];
	this.local2free = [];
	this.scopes = [];
	this.upfree = new Map();
	this.uplink = uplink;
	this.isdotdotdot = isdotdotdot;
}

Assembler.prototype.hasLiteral = function(node, lit) {
	return node.fathered.some(ch => ch.type == -1 && ch.val(this.lx) == lit);
}

Assembler.prototype.filterMasks = function*(node, mask) {
	for (let i = node.fathered.length - 1; i >= 0; i--) {
		let ch = node.fathered[i], v;
		if (ch.type == -1 && (v = ch.val(this.lx)) & mask) {
			yield v & 0xffffff;
		}
	}
}

Assembler.prototype.filterMask = function(node, mask) {
	for (let i = node.fathered.length - 1; i >= 0; i--) {
		let ch = node.fathered[i], v;
		if (ch.type == -1 && (v = ch.val(this.lx)) & mask) {
			return v & 0xffffff;
		}
	}
}

Assembler.prototype.identIndices = function*(node) {
	for (let i = node.fathered.length - 1; i >= 0; i--) {
		let ch = node.fathered[i], v;
		if (ch.type == -1 && (v = ch.val(this.lx)) & lex._ident) {
			yield { name: v & 0xffffff, li: ch.li };
		}
	}
}

Assembler.prototype.identIndex = function(node) {
	for (let i = node.fathered.length - 1; i >= 0; i--) {
		let ch = node.fathered[i], v;
		if (ch.type == -1 && (v = ch.val(this.lx)) & lex._ident) {
			return { name: v & 0xffffff, li: ch.li };
		}
	}
}
Assembler.prototype.push = function() {
	return Array.prototype.push.apply(this.bc, arguments);
}

Assembler.prototype.genLabel = function() {
	return this.labgen++;
}

Assembler.prototype.pushLoop = function(lab) {
	this.loops.push(lab);
	return this.pushLocal();
}

Assembler.prototype.popLoop = function() {
	this.loops.pop();
	return this.popLocal();
}

Assembler.prototype.getLoop = function() {
	return this.loops.length ? this.loops[this.loops.length - 1] : null;
}

Assembler.prototype.pushLocal = function() {
	return this.locals.push([]);
}

Assembler.prototype.popLocal = function() {
	return this.locals.pop();
}

Assembler.prototype.getLocal = function(name) {
	for (let i=this.locals.length - 1; i>=0; i--) {
		let n = this.locals[i][name];
		if (n !== undefined) return n;
	}
	return -1;
}

Assembler.prototype.pushScope = function() {
	return this.locals.push([]);
}

Assembler.prototype.popScope = function() {
	return this.locals.pop();
}

Assembler.prototype.nameScope = function(name, li) {
	return this.scopes[li] = this.locals[this.locals.length - 1][name] = { op: LOAD_LOCAL, n: this.lcount++ };
}

Assembler.prototype.getScope = function(name, li, chain = []) {
	let base = chain.length == 0;
	for (let i = this.locals.length - 1; i >= 0; i--) {
		let scope = this.locals[i][name];
		if (scope) {
			if (base) {
				this.scopes[li] = scope;
			} else if (scope.op == LOAD_LOCAL) {
				scope.op = LOAD_DEREF;
				this.local2free[scope.n] = this.fcount;
				scope.n = this.fcount++;
				this.frees[scope.n] = new Map();
			}
			return scope;
		}
	}
	chain.push(this);
	if (this.uplink) {
		let scope = this.uplink.getScope(name, li, chain);
		if (scope) {
			if (!this.upfree.has(scope)) {
				let subscope = { op: LOAD_DEREF, n: this.fcount++ };
				this.uplink.frees[scope.n].set(chain.pop().id, subscope.n);
				this.upfree.set(scope, subscope);
				scope = subscope;
			} else {
				scope = this.upfree.get(scope);
			}
			if (base) {
				this.scopes[li] = scope;
			}
			return scope;
		} else if (base) {
			let envscope = this.getScope(0, -1);
			this.scopes[li] = { op: -1, n: name, asm: envscope };
		}
	} else if (base) {
		this.scopes[li] = { op: -1, n: name, asm: this.locals[0][0] };
	}
	return null;
}

Assembler.prototype.gensert = function(node, ty) {
	if ((node.type & 31) != ty) throw [node, ty];
}

Assembler.prototype.genLoadIdent = function(scope) {
	if (~scope.op) {
		this.push(scope.op, scope.n);
	} else {
		this.push(scope.asm.op, scope.asm.n, LOAD_STR, scope.n, LOAD_INDEX);
	}
}

Assembler.prototype.genStoreIdent = function(scope) {
	if (~scope.op) {
		this.push(scope.op+1, scope.n);
	} else {
		this.push(scope.asm.op, scope.asm.n, LOAD_STR, scope.n, STORE_INDEX);
	}
}

Assembler.prototype.genPrefix = function (node) {
	this.gensert(node, ast.Prefix);
	if (node.type >> 5) {
		this.genExpOr(selectNode(node, ast.ExpOr), 1);
	} else {
		let name = this.identIndex(node);
		this.genLoadIdent(this.scopes[name.li]);
	}
}

Assembler.prototype.genSuffix = function (node) {
	this.gensert(node, ast.Suffix);
	if (node.type >> 5) {
		this.genIndex(selectNode(node, ast.Index), false);
	} else {
		this.genCall(selectNode(node, ast.Call));
	}
}

Assembler.prototype.genIndex = function(node, store) {
	// TODO a[b] = c is order of evaluation
	this.gensert(node, ast.Index);
	if (node.type >> 5) {
		this.push(LOAD_STR, this.filterMask(node, lex._ident));
	} else {
		this.genExpOr(node, selectNode(node, ast.ExpOr), 1);
	}
	this.push(store ? STORE_INDEX : LOAD_INDEX);
}

Assembler.prototype.genTable = function(node) {
	this.gensert(node, ast.Tableconstructor);
	this.push(MAKE_TABLE);
	let list = selectNode(node, ast.Fieldlist);
	if (list) {
		let fields = Array.from(selectNodes(list, ast.Field));
		for (let i=0; i<fields.length; i++) {
			let field = fields[i];
			switch (field.type >> 5) {
				case 0:
					for (let exp of selectNodes(field, ast.ExpOr)) {
						this.genExpOr(exp, 1);
					}
					this.push(TABLE_SET);
					break;
				case 1:
					this.push(LOAD_STR, this.filterMask(field, lex._ident));
					this.genExpOr(selectNode(field, ast.ExpOr), 1);
					this.push(TABLE_SET);
					break;
				case 2:
					this.genExpOr(selectNode(field, ast.ExpOr), -1, 2);
					break;
			}
		}
	}
}

Assembler.prototype.genVar = function(node, store) {
	this.gensert(node, ast.Var);
	if (node.type >> 5) {
		this.genPrefix(selectNode(node, ast.Prefix));
		for (let suf of selectNodes(node, ast.Suffix)) {
			this.genSuffix(suffix);
		}
		this.genIndex(selectNode(node, ast.Index), store);
	} else {
		let name = this.identIndex(node), scope = this.scopes[name.li];
		if (store) {
			this.genStoreIdent(scope);
		} else {
			this.genLoadIdent(scope);
		}
	}
}

Assembler.prototype.genArgs = function(node, ismeth, vals, endvals, ret, calls) {
	this.gensert(node, ast.Args);
	calls = calls || [];
	switch (node.type >> 5) {
		case 0: {
			let explist = selectNode(node, ast.Explist);
			if (explist) {
				let exps = Array.from(selectNodes(explist, ast.ExpOr));
				calls.push(exps.length + ismeth - 1);
				for (let i=0; i<exps.length - 1; i++) {
					this.genExpOr(exps[i], 1);
				}
				this.genExpOr(exps[exps.length - 1], -1, endvals, ret, calls);
				return;
			} else {
				calls.push(ismeth);
			}
			break;
		}
		case 1:
			this.genTable(selectNode(node, ast.Tableconstructor));
			calls.push(ismeth + 1);
			break;
		case 2: {
			let str = this.filterMask(node, lex._string);
			this.push(LOAD_STR, str);
			calls.push(ismeth + 1)
			break;
		}
	}
	this.handleRet(-1, vals, endvals, ret, calls);
}

Assembler.prototype.genCall = function(node, vals, endvals, ret, calls) {
	this.gensert(node, ast.Call);
	if (node.type >> 5) {
		let name = this.filterMask(node, lex._ident);
		this.push(LOAD_METH, name);
	}
	let args = selectNode(node, ast.Args);
	this.genArgs(args, node.type >> 5, vals, endvals, ret, calls);
}

Assembler.prototype.genFuncCall = function(node, vals, endvals, ret, calls) {
	this.gensert(node, ast.Functioncall);
	this.genPrefix(selectNode(node, ast.Prefix));
	for (let suf of selectNodes(node, ast.Suffix)) {
		this.genSuffix(suf);
	}
	this.genCall(selectNode(node, ast.Call), vals, endvals, ret, calls);
}

Assembler.prototype.genFuncname = function(node) {
	this.gensert(node, ast.Funcname);
	let names = Array.from(this.filterMasks(node, lex._ident));
	let name0 = this.identIndex(node), scope = this.scopes[name0.li];
	if (names.length == 1) {
		this.genStoreIdent(scope);
	} else {
		this.genLoadIdent(scope);
		let colon = this.hasLiteral(node, lex._colon);
		for (var i=1; i<names.length - 1; i++) {
			this.push(LOAD_STR, names[i], LOAD_INDEX);
		}
		this.push(LOAD_STR, names[names.length - 1].val(this.lx) & 0xffffff);
		this.push(colon ? STORE_METH : STORE_INDEX);
	}
}

Assembler.prototype.genFuncbody = function(node) {
	this.gensert(node, ast.Funcbody);
	this.push(LOAD_FUNC, this.fuli[node.li]);
}

Assembler.prototype.genValue = function(node, vals, endvals, ret, calls) {
	this.gensert(node, ast.Value);
	switch (node.type >> 5) {
		case 0:
			this.push(LOAD_NIL);
			break;
		case 1:
			this.push(LOAD_FALSE);
			break;
		case 2:
			this.push(LOAD_TRUE);
			break;
		case 3:
			this.push(LOAD_NUM, this.filterMask(node, lex._number));
			break;
		case 4:
			this.push(LOAD_STR, this.filterMask(node, lex._string));
			break;
		case 5:
			if (!this.isdotdotdot) {
				console.log("Unexpected ...");
				return;
			} else if (vals) {
				if (calls) {
					if (!ret) {
						this.push(CALL_VARG, endvals);
					} else {
						this.push(ret == 1 ? RETURN_VARG_CALL : APPEND_VARG_CALL);
					}
					this.push(calls.length, ...calls);
				} else if (!ret) {
					this.push(LOAD_VARG, vals);
				} else {
					this.push(ret == 1 ? RETURN_VARG : APPEND_VARG);
				}
			}
			return;
		case 6:
			this.genFuncbody(selectNode(node, ast.Funcbody));
			break;
		case 7:
			this.genTable(selectNode(node, ast.Tableconstructor));
			break;
		case 8:
			this.genFuncCall(selectNode(node, ast.Functioncall), vals, endvals, ret, calls);
			return;
		case 9:
			this.genVar(selectNode(node, ast.Var), false);
			break;
		case 10:
			this.genExpOr(selectNode(node, ast.ExpOr), 1);
			break;
	}
	this.handleRet(1, vals, endvals, ret, calls);
}

const _precedence = [7, 7, 8, 8, 8, 9, 8, 5, 4, 3, 6, 6, 2, 1, 1, 1, 1, 1, 1],
	precedence = x => (x.type & 31) == ast.Binop ? _precedence[x.type>>5] : 0;

Assembler.prototype.handleRet = function(made, vals, endvals, ret, calls) {
	if (~made) {
		if (~vals) {
			while (made > vals) {
				this.push(POP);
				made--;
			}
			while (made < vals) {
				this.push(LOAD_NIL);
				made++;
			}
		}
		if (calls) calls[calls.length - 1] += made;
	}
	if (ret) {
		if (calls) {
			this.push(ret == 1 ? RETURN_CALL : APPEND_CALL, calls.length, ...calls);
		} else {
			this.push(ret == 1 ? RETURN : APPEND);
		}
	} else if (calls) {
		this.push(CALL, endvals, calls.length, ...calls)
	}
}

Assembler.prototype.genExpOr = function(node, vals, endvals = vals, ret = 0, calls = null) {
	this.gensert(node, ast.ExpOr);
	if (vals === undefined) console.log("genExpOr: vals undefined");
	let exps = Array.from(selectNodes(node, ast.ExpAnd));
	if (exps.length == 1) {
		this.genExpAnd(exps[0], vals, endvals, ret, calls);
	} else {
		let lab = this.genLabel();
		for (let i=0; i<exps.length - 1; i++) {
			this.genExpAnd(exps[i], 1, 0, null);
			this.push(JIF_OR_POP, lab);
		}
		this.genExpAnd(exps[exps.length - 1], 1, 0);
		this.push(LABEL, lab);
		this.handleRet(1, vals, endvals, ret, calls);
	}
}

Assembler.prototype.genExpAnd = function(node, vals, endvals, ret, calls) {
	this.gensert(node, ast.ExpAnd);
	let exps = Array.from(selectNodes(node, ast.Exp));
	if (exps.length == 1) {
		this.genExp(exps[0], vals, endvals, ret, calls);
	} else {
		let lab = this.genLabel();
		for (let i=0; i<exps.length - 1; i++) {
			this.genExp(exps[i], 1, 0);
			this.push(JIFNOT_OR_POP, lab);
		}
		this.genExp(exps[exps.length - 1], 1, 0);
		this.push(LABEL, lab);
		this.handleRet(1, vals, endvals, ret, calls);
	}
}

const Exp32 = ast.Exp|32;
function*shunt(lx, node) {
	var ops = [];
	while (node.type == Exp32 && node.fathered.length == 3) {
		let [rson, op, lson] = node.fathered;
		yield lson;
		while (ops.length && precedence(ops[ops.length-1]) >= precedence(op) && precedence(op) != 9) {
			yield ops.pop();
		}
		ops.push(op);
		node = rson;
	}
	yield node.type == Exp32 ? selectNode(node, ast.Value) : node;
	for (let i=ops.length-1; i>=0; i--) {
		yield ops[i];
	}
}

Assembler.prototype.genExp = function(node, vals, endvals, ret, calls) {
	this.gensert(node, ast.Exp);
	if (node.fathered.length == 1) {
		return this.genValue(node.fathered[0], vals, endvals, ret, calls);
	} else if (node.type >> 5) {
		for (let op of shunt(this.lx, node)) {
			switch (op.type & 31) {
				case ast.Binop:
					switch (op.type >> 5) {
						case 0: this.push(BIN_PLUS); break; // plus
						case 1: this.push(BIN_MINUS); break; // minus
						case 2: this.push(BIN_MUL); break; // mul
						case 3: this.push(BIN_DIV); break; // div
						case 4: this.push(BIN_IDIV); break; // idiv
						case 5: this.push(BIN_POW); break; // pow
						case 6: this.push(BIN_MOD); break; // mod
						case 7: this.push(BIN_BAND); break; // band
						case 8: this.push(BIN_BNOT); break; // bnot
						case 9: this.push(BIN_BOR); break; // bor
						case 10: this.push(BIN_RSH); break; // rsh
						case 11: this.push(BIN_LSH); break; // lsh
						case 12: this.push(BIN_DOTDOT); break; // dotdot
						case 13: this.push(BIN_LT); break; // lt
						case 14: this.push(BIN_LTE); break; // lte
						case 15: this.push(BIN_GT); break; // gt
						case 16: this.push(BIN_GTE); break; // gte
						case 17: this.push(BIN_EQ); break; // eq
						case 18: this.push(BIN_NEQ); break; // neq
					}
					break;
				case ast.Value:
					this.genValue(op, 1, 0);
					break;
				case ast.Exp:
					if (op.type >> 5) {
						console.log("shunt error: returned binop exp");
					} else this.genExp(op, 1, 0);
					break;
			}
		}
	} else {
		this.genExp(selectNode(node, ast.Exp), 1, 0);
		switch (selectNode(node, ast.Unop).type >> 5) {
			case 0: // minus
				this.push(UNARY_MINUS);
				break;
			case 1: // not
				this.push(UNARY_NOT);
				break;
			case 2: // hash
				this.push(UNARY_HASH);
				break;
			case 3: // bnot
				this.push(UNARY_BNOT);
				break;
		}
	}
	this.handleRet(1, vals, endvals, ret, calls);
}

Assembler.prototype.genStat = function(node) {
	this.gensert(node, ast.Stat);
	switch (node.type >> 5) {
		case 0: // ;
			break;
		case 1: { // varlist = explist
			let vars = Array.from(selectNodes(selectNode(node, ast.Varlist), ast.Var)),
				exps = Array.from(selectNodes(selectNode(node, ast.Explist), ast.ExpOr));
			for (let i=0; i<exps.length; i++) {
				this.genExpOr(exps[i], i >= vars.length ? 0 : i == exps.length-1 ? vars.length-exps.length+1 : 1);
			}
			for (let i=vars.length-1; i>=0; i--) {
				this.genVar(vars[i], true);
			}
			break;
		}
		case 2:
			this.genFuncCall(selectNode(node, ast.Functioncall), 0, 0);
			break;
		case 3: {
			this.push(LABEL, this.filterMask(node, lex._ident));
			break;
		}
		case 4: {
			let scope = this.getLoop();
			if (!scope) console.log("Break out of scope");
			else this.push(GOTO, scope);
			break;
		}
		case 5: { // TODO transform into jump offset
			let name = this.filterMask(node, lex._ident);
			this.push(GOTO, name);
			break;
		}
		case 6:
			this.genBlock(selectNode(node, ast.Block));
			break;
		case 7: { // while
			let lab0 = this.genLabel(), lab1 = this.genLabel();
			this.pushLoop(lab1);
			this.push(LABEL, lab0);
			this.genExpOr(selectNode(node, ast.ExpOr), 1);
			this.push(JIFNOT, lab1);
			this.genBlock(selectNode(node, ast.Block), true);
			this.push(GOTO, lab0);
			this.push(LABEL, lab1);
			this.popLoop();
			break;
		}
		case 8: { // repeat
			let lab0 = this.genLabel(), lab1 = this.genLabel();
			this.pushLoop(lab1);
			this.push(LABEL, lab0);
			this.genBlock(selectNode(node, ast.Block), true);
			this.genExpOr(selectNode(node, ast.ExpOr), 1);
			this.push(JIFNOT, lab0);
			this.push(LABEL, lab1);
			this.popLoop();
			break;
		}
		case 9: {
			/* If there's an else then exps.length != blocks.length
			*/
			let exps = Array.from(selectNodes(node, ast.ExpOr));
			let blocks = Array.from(selectNodes(node, ast.Block));
			let endlab = this.genLabel();
			for (var i=0; i<exps.length; i++) {
				let lab = this.genLabel();
				this.genExpOr(exps[i], 1);
				this.push(JIFNOT, lab);
				this.genBlock(blocks[i]);
				if (i+1 < blocks.length) this.push(GOTO, endlab);
				this.push(LABEL, lab);
			}
			if (i < blocks.length) {
				this.genBlock(blocks[i]);
			}
			this.push(LABEL, endlab);
			break;
		}
		case 10: {
			let lab0 = this.genLabel(), endlab = this.genLabel();
			this.pushLoop(endlab);
			let exps = Array.from(selectNodes(node, ast.ExpOr));
			this.genExpOr(exps[0], 1);
			this.genExpOr(exps[1], 1);
			if (exps.length > 2) {
				this.genExpOr(exps[2], 1);
				this.push(LABEL, lab0, FOR3, endlab);
			} else {
				this.push(LABEL, lab0, FOR2, endlab);
			}
			let name = this.identIndex(node);
			this.genStoreIdent(this.scopes[name.li]);
			this.genBlock(selectNode(node, ast.Block), true);
			this.push(GOTO, lab0);
			this.push(LABEL, endlab);
			this.popLoop();
			break;
		}
		case 11: {
			let lab0 = this.genLabel(), endlab = this.genLabel();
			this.pushLoop(endlab);
			let exps = Array.from(selectNodes(selectNode(node, ast.Explist), ast.ExpOr));
			for (let i=0; i<exps.length; i++) {
				this.genExpOr(exps[i], i > 2 ? 0 : i == exps.length - 1 ? 3 - i : 1);
			}
			this.push(FORTIFY, LABEL, lab0);
			let names = Array.from(this.identIndices(selectNode(node, ast.Namelist)));
			this.push(FOR_NEXT, endlab, names.length);
			for (let i = names.length - 1; i >= 0; i--) {
				this.genStoreIdent(this.scopes[name.li]);
			}
			this.genBlock(selectNode(node, ast.Block), true);
			this.push(GOTO, lab0);
			this.popLoop();
			break;
		}
		case 12: {
			this.genFuncbody(selectNode(node, ast.Funcbody));
			this.genFuncname(selectNode(node, ast.Funcname));
			break;
		}
		case 13: {
			this.genFuncbody(selectNode(node, ast.Funcbody));
			let name = this.identIndex(node);
			this.genStoreIdent(this.scopes[name.li]);
			break;
		}
		case 14: {
			let explist = selectNode(node, ast.Explist);
			let names = Array.from(this.identIndices(selectNode(node, ast.Namelist)));
			if (explist) {
				let exps = Array.from(selectNodes(explist, ast.ExpOr));
				for (let i=0; i<exps.length; i++) {
					this.genExpOr(exps[i], i >= names.length ? 0 : i == exps.length-1 ? names.length-exps.length+1 : 1);
				}
			} else {
				for (let i=0; i<names.length; i++) {
					this.push(LOAD_NIL);
				}
			}
			for (let i=names.length-1; i>=0; i--) {
				this.genStoreIdent(this.scopes[names[i].li]);
			}
			break;
		}
	}
}

Assembler.prototype.genRet = function(node) {
	this.gensert(node, ast.Retstat);
	let explist = selectNode(node, ast.Explist);
	if (explist) {
		let exps = Array.from(selectNodes(explist, ast.ExpOr)), i = 0;
		for (let i = 0; i<exps.length-1; i++) {
			this.genExpOr(exps[i], 1, 0);
		}
		this.genExpOr(exps[exps.length - 1], -1, 1);
	} else {
		this.push(RETURN);
	}
}

Assembler.prototype.genBlock = function(node, nolocal = false) {
	this.gensert(node, ast.Block);
	if (!nolocal) this.pushLocal();
	for (let stat of selectNodes(node, ast.Stat)) {
		this.genStat(stat);
	}
	let ret = selectNode(node, ast.Retstat);
	if (ret) this.genRet(ret);
	if (!nolocal) this.popLocal();
}

Assembler.prototype.scopeExpOr = function(node) {
	this.gensert(node, ast.ExpOr);
	for (let exp of selectNodes(node, ast.ExpAnd)) {
		this.scopeExpAnd(exp);
	}
}

Assembler.prototype.scopeExpAnd = function(node) {
	this.gensert(node, ast.ExpAnd);
	for (let exp of selectNodes(node, ast.Exp)) {
		this.scopeExp(exp);
	}
}

Assembler.prototype.scopeExp = function(node) {
	this.gensert(node, ast.Exp);
	if (node.fathered.length == 1) {
		this.scopeValue(node.fathered[0]);
	} else if (node.type >> 5) {
		for (let child of node.fathered) {
			switch (child.type & 31) {
				case ast.Value:
					this.scopeValue(child);
					break;
				case ast.Exp:
					this.scopeExp(child);
					break;
			}
		}
	} else {
		this.scopeExp(selectNode(node, ast.Exp));
	}
}

Assembler.prototype.scopeValue = function(node) {
	this.gensert(node, ast.Value);
	switch (node.type >> 5) {
		case 6:
			this.scopeFuncbody(selectNode(node, ast.Funcbody));
			break;
		case 7:
			this.scopeTable(selectNode(node, ast.Tableconstructor));
			break;
		case 8:
			this.scopeFuncCall(selectNode(node, ast.Functioncall));
			return;
		case 9:
			this.scopeVar(selectNode(node, ast.Var));
			break;
		case 10:
			this.scopeExpOr(selectNode(node, ast.ExpOr));
			break;
	}
}

Assembler.prototype.scopeTable = function(node) {
	this.gensert(node, ast.Tableconstructor);
	let list = selectNode(node, ast.Fieldlist);
	for (let field of selectNodes(list, ast.Field)) {
		for (let exp of selectNodes(field, ast.ExpOr)) {
			this.scopeExpOr(exp);
		}
	}
}

Assembler.prototype.scopePrefix = function(node) {
	this.gensert(node, ast.Prefix);
	if (node.type >> 5) {
		this.scopeExpOr(selectNode(node, ast.ExpOr));
	} else {
		let name = this.identIndex(node);
		this.getScope(name.name, name.li);
	}
}

Assembler.prototype.scopeIndex = function(node) {
	this.gensert(node, ast.Index);
	if (!(node.type >> 5)) {
		this.scopeExpOr(node, selectNode(node, ast.ExpOr));
	}
}

Assembler.prototype.scopeSuffix = function(node) {
	this.gensert(node, ast.Suffix);
	if (node.type >> 5) {
		this.scopeIndex(selectNode(node, ast.Index));
	} else {
		this.scopeCall(selectNode(node, ast.Call));
	}
}

Assembler.prototype.scopeVar = function(node) {
	this.gensert(node, ast.Var);
	if (node.type >> 5) {
		this.scopePrefix(selectNode(node, ast.Prefix));
		for (let suf of selectNodes(node, ast.Suffix)) {
			this.scopeSuffix(suffix);
		}
		this.scopeIndex(selectNode(node, ast.Index));
	} else {
		let name = this.identIndex(node);
		this.getScope(name.name, name.li);
	}
}

Assembler.prototype.scopeFuncbody = function(node) {
	this.gensert(node, ast.Funcbody);
	// TODO handle parlist, add to func's locals
	let parlist = selectNode(node, ast.Parlist);
	let namelist = parlist && selectNode(parlist, ast.Namelist);
	let names = namelist && Array.from(this.identIndices(namelist));
	let dotdotdot = parlist && this.hasLiteral(parlist, lex._dotdotdot);
	var subasm = new Assembler(this.lx, names ? names.length : 0, !!dotdotdot, this);
	subasm.pushScope();
	if (names) {
		for (let name of names) {
			subasm.nameScope(name.name, name.li);
		}
	}
	subasm.scopeBlock(selectNode(node, ast.Block), true);
	subasm.popScope();
	subasm.genBlock(selectNode(node, ast.Block));
	subasm.push(RETURN);
	this.fuli[node.li] = this.fus.length;
	this.fus.push(new Func(subasm));
}

Assembler.prototype.scopeFuncname = function(node) {
	this.gensert(node, ast.Funcname);
	let name = this.identIndex(node);
	this.getScope(name.name, name.li);
}

Assembler.prototype.scopeFuncCall = function(node) {
	this.gensert(node, ast.Functioncall);
	this.scopePrefix(selectNode(node, ast.Prefix));
	for (let suf of selectNodes(node, ast.Suffix)) {
		this.scopeSuffix(suf);
	}
	this.scopeCall(selectNode(node, ast.Call));
}

Assembler.prototype.scopeCall = function(node) {
	this.gensert(node, ast.Call);
	let args = selectNode(node, ast.Args);
	this.scopeArgs(args);
}

Assembler.prototype.scopeArgs = function(node) {
	this.gensert(node, ast.Args);
	switch (node.type >> 5) {
		case 0: {
			let explist = selectNode(node, ast.Explist);
			if (explist) {
				for (let exp of selectNodes(explist, ast.ExpOr)) {
					this.scopeExpOr(exp);
				}
			}
			break;
		}
		case 1:
			this.scopeTable(selectNode(node, ast.Tableconstructor));
			break;
	}
}

Assembler.prototype.scopeStat = function(node) {
	this.gensert(node, ast.Stat);
	switch (node.type >> 5) {
		case 1:
			let vars = Array.from(selectNodes(selectNode(node, ast.Varlist), ast.Var)),
				exps = Array.from(selectNodes(selectNode(node, ast.Explist), ast.ExpOr));
			for (let i=0; i<exps.length; i++) {
				this.scopeExpOr(exps[i]);
			}
			for (let i=vars.length-1; i>=0; i--) {
				this.scopeVar(vars[i]);
			}
			break;
		case 2:
			this.scopeFuncCall(selectNode(node, ast.Functioncall));
			break;
		case 6:
			this.scopeBlock(selectNode(node, ast.Block));
			break;
		case 7:
			this.pushScope();
			this.scopeBlock(selectNode(node, ast.Block), true);
			this.scopeExpOr(selectNode(node, ast.ExpOr));
			this.popScope();
			break;
		case 8: {
			this.pushScope();
			this.scopeBlock(selectNode(node, ast.Block), true);
			this.scopeExpOr(selectNode(node, ast.ExpOr));
			this.popScope();
			break;
		}
		case 9: {
			for (let exp of selectNodes(node, ast.ExpOr)) {
				this.scopeExpOr(exp);
			}
			for (let block of selectNodes(node, ast.Block)) {
				this.scopeBlock(block);
			}
			break;
		}
		case 10: {
			for (let exp of selectNodes(node, ast.ExpOr)) {
				this.scopeExpOr(exp);
			}
			this.pushScope();
			let name = this.identIndex(node);
			this.nameScope(name.name, name.li);
			this.scopeBlock(selectNode(node, ast.Block), true);
			this.popScope();
			break;
		}
		case 11: {
			for (let exp of selectNodes(selectNode(node, ast.Explist), ast.ExpOr)) {
				this.scopeExpOr(exp);
			}
			this.pushScope();
			for (let name of this.identIndices(selectNode(node, ast.Namelist))) {
				this.nameScope(name.name, name.li);
			}
			this.scopeBlock(selectNode(node, ast.Block), true);
			this.popScope();
			break;
		}
		case 12: {
			this.scopeFuncbody(selectNode(node, ast.Funcbody));
			this.scopeFuncname(selectNode(node, ast.Funcname));
			break;
		}
		case 13: {
			let name = this.identIndex(node);
			this.nameScope(names[i].name, names[i].li);
			this.scopeFuncbody(selectNode(node, ast.Funcbody));
			break;
		}
		case 14: {
			for (let name of this.identIndices(selectNode(node, ast.Namelist))) {
				this.nameScope(name.name, name.li);
			}
			let explist = selectNode(node, ast.Explist);
			if (explist) {
				for (let exp of selectNodes(explist, ast.ExpOr)) {
					this.scopeExpOr(exp);
				}
			}
			break;
		}
	}
}

Assembler.prototype.scopeRet = function(node) {
	this.gensert(node, ast.Retstat);
	let explist = selectNode(node, ast.Explist);
	if (explist) {
		for (let exp of selectNodes(explist, ast.ExpOr)) {
			this.scopeExpOr(exp);
		}
	}
}

Assembler.prototype.scopeBlock = function(node, nolocal = false) {
	this.gensert(node, ast.Block);
	if (!nolocal) this.pushLocal();
	for (let stat of selectNodes(node, ast.Stat)) {
		this.scopeStat(stat);
	}
	let ret = selectNode(node, ast.Retstat);
	if (ret) this.scopeRet(ret);
	if (!nolocal) this.popLocal();
}

function assemble(lx, root) {
	var asm = new Assembler(lx, 0, false, null);
	asm.pushScope();
	asm.nameScope(0, -1);
	asm.scopeBlock(root);
	asm.popScope();
	asm.genBlock(root);
	asm.push(RETURN);
	return new Func(asm);
}

exports.assemble = assemble;
