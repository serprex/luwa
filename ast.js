"use strict";
var lex = require("./lex");

// Thanks lua-users.org/lists/lua-l/2010-12/msg00699.html
var Block = 0,
	Stat = 1,
	Retstat = 2,
	Label = 3,
	Funcname = 4,
	Varlist = 5,
	Var = 6,
	Namelist = 7,
	Explist = 8,
	Exp = 9,
	Prefix = 10,
	Functioncall = 11,
	Args = 12,
	Functiondef = 13,
	Funcbody = 14,
	Parlist = 15,
	Tableconstructor = 16,
	Fieldlist = 17,
	Field = 18,
	Fieldsep = 19,
	Binop = 20,
	Unop = 21,
	Value = 22,
	Index = 23,
	Call = 24,
	Suffix = 25;

var name = function*(x, p) {
	var t = x.next(p);
	if (t && t.val() & lex._ident)
		yield t;
};
var number = function*(x, p) {
	var t = x.next(p);
	if (t && t.val() & lex._number)
		yield t;
};
var slit = function*(x, p) {
	var t = x.next(p);
	if (t && t.val() & lex._string)
		yield t;
};
var _s = [], s = r => _s[r] || (_s[r] = function*(x, p) {
	var t = x.next(p);
	if (t && t.val() == r) {
		yield t;
	}
});
var _o = [], o = n => _o[n] || (_o[n] = function*(x, p) {
	yield *rules[n](x, p);
});
function seqcore(args) {
	function *seqf(x, p, i) {
		if (i == args.length - 1) {
			yield *args[i](x, p);
		} else {
			for (let ax of args[i](x, p)) {
				yield *seqf(ax, p, i+1);
			}
		}
	}
	return seqf;
}
function seq() {
	var args = [];
	for (var i=0; i<arguments.length; i++) args[i] = arguments[i];
	var seqf = seqcore(args);
	return (x, p) => seqf(x, p, 0);
}
function seqo(o) {
	var args = [];
	for (var i=1; i<arguments.length; i++) args[i-1] = arguments[i];
	var seqf = seqcore(args);
	return (x, p) => seqf(x, x.spawn(o, p), 0);
}
var many = f => {
	function* manyf(x, p) {
		for (let fx of f(x, p)) {
			yield *manyf(fx, p);
		}
		yield x;
	};
	return (x, p) => manyf(x, p);
}
var maybe = f => function*(x, p) {
	yield *f(x, p);
	yield x;
};
function of(o) {
	var args = [];
	for (var i=1; i<arguments.length; i++) args[i-1] = arguments[i];
	return function*(x, p){
		var i = o;
		for (let a of args) {
			yield *a(x, x.spawn(i, p));
			i += 32;
		}
	}
}

var rules = [];
rules[Block] = seqo(Block, many(o(Stat)), maybe(o(Retstat)));
rules[Stat] = of(Stat,
	s(lex._semi),
	seq(o(Varlist), s(lex._set), o(Explist)),
	o(Functioncall),
	o(Label),
	s(lex._break),
	seq(s(lex._goto), name),
	seq(s(lex._do), o(Block), s(lex._end)),
	seq(s(lex._while), o(Exp), s(lex._do), o(Block), s(lex._end)),
	seq(s(lex._repeat), o(Block), s(lex._until), o(Exp)),
	seq(s(lex._if), o(Exp), s(lex._then), o(Block), many(seq(s(lex._elseif), o(Exp), s(lex._then), o(Block))), maybe(seq(s(lex._else), o(Block))), s(lex._end)),
	seq(s(lex._for), name, s(lex._set), o(Exp), s(lex._comma), o(Exp), maybe(seq(s(lex._comma), o(Exp))), s(lex._do), o(Block), s(lex._end)),
	seq(s(lex._for), o(Namelist), s(lex._in), o(Explist), s(lex._do), o(Block), s(lex._end)),
	seq(s(lex._function), o(Funcname), o(Funcbody)),
	seq(s(lex._local), s(lex._function), name, o(Funcbody)),
	seq(s(lex._local), o(Namelist), maybe(seq(s(lex._set), o(Explist))))
);
rules[Retstat] = seqo(Retstat, s(lex._return), maybe(o(Explist)), maybe(s(lex._semi)));
rules[Label] = seqo(Label, s(lex._label), name, s(lex._label));
rules[Funcname] = seqo(Funcname, name, many(seq(s(lex._dot), name)), maybe(s(lex._colon), name));
rules[Varlist] = seqo(Varlist, o(Var), many(seq(s(lex._comma), o(Var))));
rules[Var] = of(Var, seq(o(Prefix), maybe(o(Suffix)), o(Index)), name);
rules[Namelist] = seqo(Namelist, name, many(seq(s(lex._comma), name)));
rules[Explist] = seqo(Explist, o(Exp), many(seq(s(lex._comma), o(Exp))));
rules[Exp] = of(Exp, seq(o(Unop), o(Exp)), seq(o(Value), maybe(seq(o(Binop), o(Exp)))));
rules[Prefix] = of(Prefix, seq(s(lex._pl), o(Exp), s(lex._pr)), name);
rules[Functioncall] = seqo(Functioncall, o(Prefix), maybe(o(Suffix)), o(Call));
rules[Args] = of(Args, seq(s(lex._pl), maybe(o(Explist)), s(lex._pr)), o(Tableconstructor), slit)
rules[Functiondef] = seqo(Functiondef, s(lex._function), o(Funcbody));
rules[Funcbody] = seqo(Funcbody, s(lex._pl), maybe(o(Parlist)), s(lex._pr), o(Block), s(lex._end));
rules[Parlist] = of(Parlist,
	seq(o(Namelist), maybe(seq(s(lex._comma), s(lex._dotdotdot)))),
	s(lex._dotdotdot));
rules[Tableconstructor] = seqo(Tableconstructor, s(lex._cl), maybe(o(Fieldlist)), s(lex._cr));
rules[Fieldlist] = seqo(Fieldlist, o(Field), maybe(seq(o(Fieldsep), o(Field))), maybe(o(Fieldsep)));
rules[Field] = of(Field,
	seq(s(lex._sl), o(Exp), s(lex._sr), s(lex._set), o(Exp)),
	seq(name, s(lex._set), o(Exp)),
	o(Exp));
rules[Fieldsep] = of(Fieldsep, s(lex._comma), s(lex._semi));
rules[Binop] = of(Binop,
	s(lex._plus), s(lex._minus), s(lex._mul), s(lex._div), s(lex._idiv), s(lex._pow), s(lex._mod),
	s(lex._band), s(lex._bnot), s(lex._bor), s(lex._rsh), s(lex._lsh), s(lex._dotdot),
	s(lex._lt), s(lex._lte), s(lex._gt), s(lex._gte), s(lex._eq), s(lex._neq), s(lex._and), s(lex._or));
rules[Unop] = of(Unop, s(lex._minus), s(lex._not), s(lex._hash), s(lex._bnot));
rules[Value] = of(Value,
	s(lex._nil),
	s(lex._false),
	s(lex._true),
	number,
	slit,
	s(lex._dotdotdot),
	o(Functiondef),
	o(Tableconstructor),
	o(Functioncall),
	o(Var),
	seq(s(lex._pl), o(Exp), s(lex._pr)));
rules[Index] = of(Index,
	seq(s(lex._sl), o(Exp), s(lex._sr)),
	seq(s(lex._dot), name));
rules[Call] = of(Call, o(Args), seq(s(lex._colon), name, o(Args)));
rules[Suffix] = of(Suffix, o(Call), o(Index));

function Builder(lx, li, mo, fa, ty) {
	this.lx = lx;
	this.li = li;
	this.mother = mo;
	this.father = fa;
	this.type = ty;
}
Builder.prototype.val = function() {
	return this.lx.lex[this.li];
}
Builder.prototype.next = function(p) {
	return new Builder(this.lx, this.li+1, this, p, -1);
}
Builder.prototype.spawn = function(ty, p) {
	return new Builder(this.lx, this.li, this, p, ty);
}

var _chunk = seq(rules[Block], s(0));
function parse(lx) {
	var root = new Builder(lx, -1, null, null, -2);
	var end = _chunk(root, root).next().value, start = end;
	console.log(window.PARSE = end);
	console.log(window.ROOT = root);
	while (start.mother) start = start.mother;
	makeChildren(end);
	//var bc = [];
	//astVisit(root, bc);
	//console.log(window.BYTES = bc);
}

function *selectNode(node, type) {
	for (let ch of node.fathered) {
		if (ch.type < 0 || ch.type > 31) {
			yield *selectNode(ch, type);
		} else if (ch.type == type) {
			yield ch;
		}
	}
}

function *filterMask(node, mask) {
	if (node.type == -1 && node.val() & mask) {
		yield node;
	} else if (node.fathered) {
		for (let ch of node.fathered) {
			yield *filterMask(ch, mask);
		}
	}
}

function *Namelist_names(node) {
	if (!node.fathered) {
		if (node.type & lex.ident) {
			yield node;
		}
	} else {
		for (let ch of node.fathered) {
			yield *Namelist_names(ch);
		}
	}
}

function Explist_exps(node) {
	return selectNode(node, Exp);
}

function genValue(node, bc) {
	if ((node.type & 31) != Value) console.log(node, "Not a Val");
	switch (node.type >> 5) {
		case 0:
			bc.push(LOAD_NIL);
			break;
		case 1:
			bc.push(LOAD_FALSE);
			break;
		case 2:
			bc.push(LOAD_TRUE);
			break;
		case 3:
			bc.push(LOAD_NUM, node.fathered[0].val() & ~lex._number);
			break;
		case 4:
			bc.push(LOAD_STR, node.fathered[0].val() & ~lex._string);
			break;
		case 5:
			// uhhh not sure how to handle multival
			// maybe compute what we expect? Use 0 or -1 for when it's going to return
			bc.push(LOAD_VARARG);
			break;
		case 6:
			genFunc(node.fathered[0], bc);
			break;
		case 7:
			genTable(node.fathered[0], bc);
			break;
		case 8:
			genCall(node.fathered[0], bc);
			break;
		case 9:
			genVar(node.fathered[0], bc);
			break;
		case 10: {
			var exp = selectNode(node, Exp).next().value;
			genExp(exp, bc);
			break;
		}
	}
}

function genExp(node, bc) {
	if ((node.type & 31) != Exp) console.log(node, "Not an Exp");
	if (node.type >> 5) {
		let value = selectNode(node, Value).next().value;
		let binop = selectNode(node, Binop).next().value;
		if (binop) {
			let rexp = selectNode(node, Exp);
			genValue(value, bc);
			genExp(rexp, bc);
			switch (binop.type >> 5) {
				case 0: bc.push(BIN_PLUS); break; // plus
				case 1: bc.push(BIN_MINUS); break; // minus
				case 2: bc.push(BIN_MUL); break; // mul
				case 3: bc.push(BIN_DIV); break; // div
				case 4: bc.push(BIN_IDIV); break; // idiv
				case 5: bc.push(BIN_POW); break; // pow
				case 6: bc.push(BIN_MOD); break; // mod
				case 7: bc.push(BIN_BAND); break; // band
				case 8: bc.push(BIN_BNOT); break; // bnot
				case 9: bc.push(BIN_BOR); break; // bor
				case 10: bc.push(BIN_RSH); break; // rsh
				case 11: bc.push(BIN_LSH); break; // lsh
				case 12: bc.push(BIN_DOTDOT); break; // dotdot
				case 13: bc.push(BIN_LT); break; // lt
				case 14: bc.push(BIN_LTE); break; // lte
				case 15: bc.push(BIN_GT); break; // gt
				case 16: bc.push(BIN_GTE); break; // gte
				case 17: bc.push(BIN_EQ); break; // eq
				case 18: bc.push(BIN_NEQ); break; // neq
					// TODO and/or need to be short circuiting
				case 19: bc.push(BIN_AND); break; // and
				case 20: bc.push(BIN_OR); break // or
			}
		} else {
			genValue(value, bc);
		}
	} else {
		let unop = selectNode(node, Unop);
		let exp = selectNode(node, Exp);
		genExp(exp, bc);
		switch (unop.type >> 5) {
			case 0: // minus
				bc.push(UNARY_MINUS);
				break;
			case 1: // not
				bc.push(UNARY_NOT);
				break;
			case 2: // hash
				bc.push(UNARY_HASH);
				break;
			case 3: // bnot
				bc.push(UNARY_BNOT);
				break;
		}
	}
}

function genStoreLocal(node, bc) {
	if (!(node.val() & name) || node.type != -1) console.log(node, "Not a name");
	var val = node.val();
	bc.push(LOAD_IDENT, node.val());
}

function astVisit(node, bc) {
	switch (node.type&31) {
	case 30: // -2
		for (let child of node.fathered) {
			astVisit(node);
		}
		break;
	case 31: // -1
		console.log(node, "Unexpected terminal");
		break;
	case 0: // Block
		for (let child of node.fathered) {
			astVisit(node);
		}
		break;
	case 1: { // Stat
		switch (node.type >> 5) {
			case 0:
				break;
			case 1:
				break;
			case 2:
				break;
			case 3:
				break;
			case 4:
				break;
			case 5:
				break;
			case 6:
				break;
			case 7:
				break;
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
				let names = Array.from(Namelist_names(selectNode(Namelist).next().value)), exps = Explist_exps(selectNode(Explist).next().value);
				for (let exp of exps) {
					genExp(exp);
				}
				for (let i=names.length-1; i>=0; i--) {
					genStoreLocal(names[i]);
				}
				break;
			}
		}
		break;
	}
	case 2: // Retstat
		break;
	case 3: // Label
		break;
	case 4: // Funcname
		break;
	case 5: // Varlist
		break;
	case 6: // Var
		break;
	case 7: // Namelist
		break;
	case 8: // Explist
		break;
	case 9: // Exp
		break;
	case 10: // Prefix
		break;
	case 11: // Functioncall
		break;
	case 12: // Args
		break;
	case 13: // Functiondef
		break;
	case 14: // Funcbody
		break;
	case 15: // Parlist
		break;
	case 16: // Tableconstructor
		break;
	case 17: // Fieldlist
		break;
	case 18: // Field
		break;
	case 19: // Fieldsep
		break;
	case 20: // Binop
		break;
	case 21: // Unop
		break;
	case 22: // Value
		break;
	case 23: // Index
		break;
	case 24: // Call
		break;
	case 25: // Suffix
		break;
	default:
		console.log(node, "Unexpected of");
		break;
	}
}

function makeChildren(child) {
	if (!child) return;
	if (child.mother){
		if (!child.mother.mothered) {
			child.mother.mothered = [child];
			makeChildren(child.mother);
		}
		else child.mother.mothered.push(child);
	}
	if (child.father){
		if (!child.father.fathered) {
			child.father.fathered = [child];
			makeChildren(child.father);
		}
		else child.father.fathered.push(child);
	}
}


exports.parse = parse;
