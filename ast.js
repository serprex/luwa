"use strict";
var lex = require("./lex");

// Thanks lua-users.org/lists/lua-l/2010-12/msg00699.html
var Chunk = 0,
	Block = 1,
	Stat = 2,
	Retstat = 3,
	Label = 4,
	Funcname = 5,
	Varlist = 6,
	Var = 7,
	Namelist = 8,
	Explist = 9,
	Exp = 10,
	Prefix = 11,
	Functioncall = 12,
	Args = 13,
	Functiondef = 14,
	Funcbody = 15,
	Parlist = 16,
	Tableconstructor = 17,
	Fieldlist = 18,
	Field = 19,
	Fieldsep = 20,
	Binop = 21,
	Unop = 22,
	Value = 23,
	Index = 24,
	Call = 25,
	Suffix = 26;

var name = function*(x) {
	var t = x.next();
	if (t && t.val() & lex._ident)
		yield t;
};
var number = function*(x) {
	var t = x.next();
	if (t && t.val() & lex._number)
		yield t;
};
var slit = function*(x) {
	var t = x.next();
	if (t && t.val() & lex._string)
		yield t;
};
var s = r => function*(x) {
	var t = x.next();
	if (t && t.val() == r) {
		yield t;
	}
};
var o = n => function*(x) {
	yield *rules[n](x);
};
var seq2 = (a, b) => function*(x) {
	for (let ax of a(x)) {
		yield *b(ax);
	}
};
var seq3 = (a, b, c) => function*(x) {
	for (let ax of a(x)) {
		for (let bx of b(ax)) {
			yield *c(bx);
		}
	}
};
var seq4 = (a, b, c, d) => function*(x) {
	for (let ax of a(x)) {
		for (let bx of b(ax)) {
			for (let cx of c(bx)) {
				yield *d(cx);
			}
		}
	}
};
var seq5 = (a, b, c, d, e) => function*(x) {
	for (let ax of a(x)) {
		for (let bx of b(ax)) {
			for (let cx of c(bx)) {
				for (let dx of d(cx)) {
					yield *e(dx);
				}
			}
		}
	}
};
var seq6 = (a, b, c, d, e, f) => function*(x) {
	for (let ax of a(x)) {
		for (let bx of b(ax)) {
			for (let cx of c(bx)) {
				for (let dx of d(cx)) {
					for (let ex of e(dx)) {
						yield *f(ex);
					}
				}
			}
		}
	}
};
var seq7 = (a, b, c, d, e, f, g) => function*(x) {
	for (let ax of a(x)) {
		for (let bx of b(ax)) {
			for (let cx of c(bx)) {
				for (let dx of d(cx)) {
					for (let ex of e(dx)) {
						for (let fx of f(ex)) {
							yield *g(fx);
						}
					}
				}
			}
		}
	}
};
var seq8 = (a, b, c, d, e, f, g, h) => function*(x) {
	for (let ax of a(x)) {
		for (let bx of b(ax)) {
			for (let cx of c(bx)) {
				for (let dx of d(cx)) {
					for (let ex of e(dx)) {
						for (let fx of f(ex)) {
							for (let gx of g(fx)) {
								yield *h(gx);
							}
						}
					}
				}
			}
		}
	}
};
var seq9 = (a, b, c, d, e, f, g, h, i) => function*(x) {
	for (let ax of a(x)) {
		for (let bx of b(ax)) {
			for (let cx of c(bx)) {
				for (let dx of d(cx)) {
					for (let ex of e(dx)) {
						for (let fx of f(ex)) {
							for (let gx of g(fx)) {
								for (let hx of h(gx)) {
									yield *i(hx);
								}
							}
						}
					}
				}
			}
		}
	}
};
var seq10 = (a, b, c, d, e, f, g, h, i, j) => function*(x) {
	for (let ax of a(x)) {
		for (let bx of b(ax)) {
			for (let cx of c(bx)) {
				for (let dx of d(cx)) {
					for (let ex of e(dx)) {
						for (let fx of f(ex)) {
							for (let gx of g(fx)) {
								for (let hx of h(gx)) {
									for (let ix of i(hx)) {
										yield *j(ix);
									}
								}
							}
						}
					}
				}
			}
		}
	}
};
var of2 = (a, b) => function*(x) {
	yield *a(x);
	yield *b(x);
};
var many = f => function* manyf(x) {
	for (let fx of f(x)) {
		yield *manyf(fx);
	}
	yield x;
};
var maybe = f => function*(x) {
	yield *f(x);
	yield x;
};
function of() {
	var args = [];
	for (var i=0; i<arguments.length; i++) {
		args.push(arguments[i]);
	}
	return function*(x){
		for (let a of args) {
			yield *a(x);
		}
	}
}

function seq(a, b) {
	var args = [];
	for (var i=0; i<arguments.length; i++) {
		args.push(arguments[i]);
	}
	return ([seq2, seq3, seq4, seq5, seq6, seq7, seq8, seq9, seq10][arguments.length - 2]).apply(null, args);
}

var rules = [];
rules[Chunk] = seq(o(Block), s(0));
rules[Block] = seq(many(o(Stat)), maybe(o(Retstat)));
rules[Stat] = of(
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
rules[Retstat] = seq(s(lex._return), maybe(o(Explist)), maybe(s(lex._semi)));
rules[Label] = seq(s(lex._label), name, s(lex._label));
rules[Funcname] = seq(name, many(seq(s(lex._dot), name)), maybe(s(lex._colon), name));
rules[Varlist] = seq(o(Var), many(seq(s(lex._comma), o(Var))));
rules[Var] = of(seq(o(Prefix), maybe(o(Suffix)), o(Index)), name);
rules[Namelist] = seq(name, many(seq(s(lex._comma), name)));
rules[Explist] = seq(o(Exp), many(seq(s(lex._comma), o(Exp))));
rules[Exp] = of(seq(o(Unop), o(Exp)), seq(o(Value), maybe(seq(o(Binop), o(Exp)))));
rules[Prefix] = of(seq(s(lex._pl), o(Exp), s(lex._pr)), name);
rules[Functioncall] = seq(o(Prefix), maybe(o(Suffix)), o(Call));
rules[Args] = of(seq(s(lex._pl), maybe(o(Explist)), s(lex._pr)), o(Tableconstructor), slit)
rules[Functiondef] = seq(s(lex._function), o(Funcbody));
rules[Funcbody] = seq(s(lex._pl), maybe(o(Parlist)), s(lex._pr), o(Block), s(lex._end));
rules[Parlist] = of(
	seq(o(Namelist), maybe(seq(s(lex._comma), s(lex._dotdotdot)))),
	s(lex._dotdotdot));
rules[Tableconstructor] = seq(s(lex._cl), maybe(o(Fieldlist)), s(lex._cr));
rules[Fieldlist] = seq(o(Field), maybe(seq(o(Fieldsep), o(Field))), maybe(o(Fieldsep)));
rules[Field] = of(
	seq(s(lex._sl), o(Exp), s(lex._sr), s(lex._set), o(Exp)),
	seq(name, s(lex._set), o(Exp)),
	o(Exp));
rules[Fieldsep] = of(s(lex._comma), s(lex._semi));
rules[Binop] = of(s(lex._plus), s(lex._minus), s(lex._mul), s(lex._div), s(lex._idiv), s(lex._pow), s(lex._mod), s(lex._band),
	s(lex._bnot), s(lex._bor), s(lex._rsh), s(lex._lsh), s(lex._dotdot), s(lex._lt), s(lex._lte), s(lex._gt), s(lex._gte), s(lex._eq), s(lex._neq), s(lex._and), s(lex._or));
rules[Unop] = of(s(lex._minus), s(lex._not), s(lex._hash), s(lex._bnot));
rules[Value] = of(s(lex._nil), s(lex._false), s(lex._true), number, slit, s(lex._dotdotdot), o(Functiondef), o(Tableconstructor), o(Functioncall), o(Var), seq(s(lex._pl), o(Exp), s(lex._pr)));
rules[Index] = of(
	seq(s(lex._sl), o(Exp), s(lex._sr)),
	seq(s(lex._dot), name));
rules[Call] = of(o(Args), seq(s(lex._colon), name, o(Args)));
rules[Suffix] = of(o(Call), o(Index));

function Builder(lx, li) {
	this.lx = lx;
	this.li = li;
}
Builder.prototype.val = function() {
	return this.lx.lex[this.li];
}
Builder.prototype.next = function() {
	return this.li+1 >= this.lx.lex.length ? null : new Builder(this.lx, this.li+1);
}

function parse(lx) {
	for (var x of rules[Chunk](new Builder(lx, -1))) {
		if (x.li+1 == lx.lex.length) {
			return x;
		}
	}
}

exports.parse = parse;
