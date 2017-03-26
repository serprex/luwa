const lex = require("./lex"), ast = require("./ast");

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
	BIN_AND = exports.BIN_AND = -1,
	BIN_OR = exports.BIN_OR = -2,
	UNARY_MINUS = exports.UNARY_MINUS = 23,
	UNARY_NOT = exports.UNARY_NOT = 24,
	UNARY_HASH = exports.UNARY_HASH = 25,
	UNARY_BNOT = exports.UNARY_BNOT = 26,
	BREAK = exports.BREAK = 64,
	LOAD_NUM = exports.LOAD_NUM = 128,
	LOAD_STR = exports.LOAD_STR = 129,
	LOAD_VARARG = exports.LOAD_VARARG = 130,
	LOAD_IDENT = exports.LOAD_IDENT = 131,
	GOTO = exports.GOTO = 132,
	RETURN = exports.GOTO = 133,
	STORE_IDENT = exports.STORE_IDENT = 134,
	LOAD_ATTR = exports.LOAD_ATTR = 135,
	STORE_ATTR = exports.STORE_ATTR = 136,
	LABEL = exports.LABEL = 255;

function *selectNodes(node, type) {
	for (let i = node.fathered.length - 1; i >= 0; i--)
		let ch = node.fathered[i];
		if ((ch.type & 31) == type) {
			yield ch;
		} else if (ch.type < 0 || ch.type > 31) {
			yield *selectNode(ch, type);
		}
	}
}

function selectNode(node, type) {
	for (let i = node.fathered.length - 1; i >= 0; i--)
		let ch = node.fathered[i];
		if ((ch.type & 31) == type) {
			return ch;
		} else if (ch.type < 0 || ch.type > 31) {
			let n = selectNode(ch, type);
			if (n) return n;
		}
	}
}

function *filterMasks(node, mask) {
	if (node.type == -1 && node.val() & mask) {
		yield node;
	} else {
		for (let i = node.fathered.length - 1; i >= 0; i--) {
			yield *filterMask(node.fathered[i], mask);
		}
	}
}

function filterMask(node, mask) {
	if (node.type == -1 && node.val() & mask) {
		return node;
	} else {
		for (let i = node.fathered.length - 1; i >= 0; i--) {
			let n = filterMask(node.fathered[i], mask);
			if (n) return n;
		}
	}
}

function *Namelist_names(node) {
	if (node.type & lex.ident) {
		yield node;
	} else {
		for (let i = node.fathered.length - 1; i >= 0; i--) {
			yield *Namelist_names(node.fathered[i]);
		}
	}
}

function Explist_exps(node) {
	return selectNodes(node, ast.Exp);
}

function Assembler() {
	this.bc = [];
	this.labgen = 0;
}

Assembler.prototype.push = function() {
	return Array.prototype.push.apply(this.bc, arguments);
}

Assembler.prototype.genLabel = function() {
	return this.labgen++;
}

Assembler.prototype.gensert(node, ty) {
	if ((node & 31) != ty) console.log(node, "Invalid type, expected ", ty);
}

Assembler.prototype.genPrefix = function (node) {
	this.gensert(node, ast.Prefix);
}

Assembler.prototype.genIndex = function(node, store) {
	// TODO a[b] = c is order of evaluation
	this.gensert(node, ast.Index);
	if (node.type >> 5) {
		// TODO convert this to LOAD_STR STORE_INDEX / LOAD_INDEX
		this.push(store ? STORE_ATTR : LOAD_ATTR, filterMask(node, lex._ident))
	} else {
		var exp = selectNode(node, ast.Exp);
		this.genExp(node, exp);
		this.push(store ? STORE_INDEX : LOAD_INDEX);
	}
}

Assembler.prototype.genVar = function(node, store) {
	this.gensert(node, ast.Var);
	if (node.type >> 5) {
		this.push(store ? STORE_IDENT : LOAD_IDENT, filterMask(node, lex._ident).val());
	} else {
		let prefix = selectNode(node, ast.Prefix),
			suffix = selectNodes(node, ast.Suffix),
			index = selectNode(node, ast.Index);
		this.genPrefix(prefix);
		for (let suf of suffix) {
			this.genPrefix(suffix);
		}
		this.genIndex(index, store);
	}
}

Assembler.prototype.genValue = function(node) {
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
			this.push(LOAD_NUM, node.fathered[0].val() & ~lex._number);
			break;
		case 4:
			this.push(LOAD_STR, node.fathered[0].val() & ~lex._string);
			break;
		case 5:
			// TODO not sure how to handle multival
			// maybe compute what we expect? Use 0 or -1 for when it's going to return
			this.push(LOAD_VARARG);
			break;
		case 6:
			this.genFunc(node.fathered[0]);
			break;
		case 7:
			this.genTable(node.fathered[0]);
			break;
		case 8:
			this.genCall(node.fathered[0]);
			break;
		case 9:
			this.genVar(node.fathered[0]);
			break;
		case 10: {
			var exp = selectNode(node, ast.Exp);
			this.genExp(exp);
			break;
		}
	}
}

Assembler.prototype.genExp = function(node) {
	this.gensert(node, ast.Exp);
	if (node.type >> 5) {
		let value = selectNode(node, ast.Value);
		let binop = selectNode(node, ast.Binop);
		if (binop) {
			let rexp = selectNode(node, ast.Exp);
			this.genValue(value);
			this.genExp(rexp);
			switch (binop.type >> 5) {
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
					// TODO and/or need to be short circuiting
				case 19: this.push(BIN_AND); break; // and
				case 20: this.push(BIN_OR); break // or
			}
		} else {
			this.genValue(value);
		}
	} else {
		let unop = selectNode(node, ast.Unop);
		let exp = selectNode(node, ast.Exp);
		this.genExp(exp);
		switch (unop.type >> 5) {
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
}

Assembler.prototype.genStoreLocal = function(node) {
	if (!(node.val() & name) || node.type != -1) console.log(node, "Not a name");
}

Assembler.prototype.genStat = function(node) {
	this.gensert(node, ast.Stat);
	switch (node.type >> 5) {
		case 0: // ;
			break;
		case 1: // varlist = explist
			break;
		case 2:
			break;
		case 3: {
			let name = filterMask(node, lex._ident);
			this.push(LABEL, name.val());
			break;
		}
		case 4: { // TODO transform into goto
			this.push(BREAK);
			break;
		}
		case 5: { // TODO transform into jump offset
			let name = filterMask(node, lex._ident);
			this.push(GOTO, name.val());
			break;
		}
		case 6: {
			this.visit(selectNode(node, ast.Block));
			break;
		}
		case 7: {
			break;
		}
		case 8:
			break;
		case 9:
			break;
		case 10:
			break;
		case 11:
			break;
		case 12:
			break;
		case 13:
			break;
		case 14: {
			let names = Array.from(Namelist_names(selectNode(ast.Namelist))), exps = Explist_exps(selectNode(ast.Explist));
			for (let exp of exps) {
				genExp(exp);
			}
			for (let i=names.length-1; i>=0; i--) {
				let name = names[i];
				this.push(STORE_IDENT, name.val());
			}
			break;
		}
	}
}

Assembler.prototype.genRet = function(node) {
	this.gensert(node, ast.Retstat);
	let exps = Explist_exps(selectNode(ast.Explist)), i = 0;
	for (let exp of exps) {
		this.genExp(exp);
		i++;
	}	
	this.push(RETURN, i);
}

Assembler.prototype.genBlock = function(node) {
	this.gensert(node, ast.Block);
	for (let stat of selectNodes(node, ast.Stat)) {
		this.genStat(stat);
	}
	for (let ret of selectNode(node, ast.Retstat)) {
		this.genRet(ret);
	}
}

Assembler.prototype.genChunk = function(node) {
	this.gensert(node, -2 & 31);
	let block = selectNode(node, ast.Block);
	if (block) return this.genBlock(block);
}

function assemble(ast) {
	var asm = new Assembler();
	asm.genChunk(ast);
	return asm;
}

exports.assemble = assemble;
