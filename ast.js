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
	let y = x.spawn(n, p);
	yield *rules[n](y, y);
});
var seq2 = (a, b) => function*(x, p) {
	let y = x.spawn(-1, p);
	for (let ax of a(y, y)) {
		yield *b(ax, y);
	}
};
var seq3 = (a, b, c) => function*(x, p) {
	let y = x.spawn(-1, p);
	for (let ax of a(y, y)) {
		for (let bx of b(ax, y)) {
			yield *c(bx, y);
		}
	}
};
var seq4 = (a, b, c, d) => function*(x, p) {
	let y = x.spawn(-1, p);
	for (let ax of a(x, y)) {
		for (let bx of b(ax, y)) {
			for (let cx of c(bx, y)) {
				yield *d(cx, y);
			}
		}
	}
};
var seq5 = (a, b, c, d, e) => function*(x, p) {
	let y = x.spawn(-1, p);
	for (let ax of a(y, y)) {
		for (let bx of b(ax, y)) {
			for (let cx of c(bx, y)) {
				for (let dx of d(cx, y)) {
					yield *e(dx, y);
				}
			}
		}
	}
};
var seq6 = (a, b, c, d, e, f) => function*(x, p) {
	let y = x.spawn(-1, p);
	for (let ax of a(y, y)) {
		for (let bx of b(ax, y)) {
			for (let cx of c(bx, y)) {
				for (let dx of d(cx, y)) {
					for (let ex of e(dx, y)) {
						yield *f(ex, y);
					}
				}
			}
		}
	}
};
var seq7 = (a, b, c, d, e, f, g) => function*(x, p) {
	let y = x.spawn(-1, p);
	for (let ax of a(y, y)) {
		for (let bx of b(ax, y)) {
			for (let cx of c(bx, y)) {
				for (let dx of d(cx, y)) {
					for (let ex of e(dx, y)) {
						for (let fx of f(ex, y)) {
							yield *g(fx, y);
						}
					}
				}
			}
		}
	}
};
var seq8 = (a, b, c, d, e, f, g, h) => function*(x, p) {
	let y = x.spawn(-1, p);
	for (let ax of a(y, y)) {
		for (let bx of b(ax, y)) {
			for (let cx of c(bx, y)) {
				for (let dx of d(cx, y)) {
					for (let ex of e(dx, y)) {
						for (let fx of f(ex, y)) {
							for (let gx of g(fx, y)) {
								yield *h(gx, y);
							}
						}
					}
				}
			}
		}
	}
};
var seq9 = (a, b, c, d, e, f, g, h, i) => function*(x, p) {
	let y = x.spawn(-1, p);
	for (let ax of a(y, y)) {
		for (let bx of b(ax, y)) {
			for (let cx of c(bx, y)) {
				for (let dx of d(cx, y)) {
					for (let ex of e(dx, y)) {
						for (let fx of f(ex, y)) {
							for (let gx of g(fx, y)) {
								for (let hx of h(gx, y)) {
									yield *i(hx, y);
								}
							}
						}
					}
				}
			}
		}
	}
};
var seq10 = (a, b, c, d, e, f, g, h, i, j) => function*(x, p) {
	let y = x.spawn(-1, p);
	for (let ax of a(y, y)) {
		for (let bx of b(ax, y)) {
			for (let cx of c(bx, y)) {
				for (let dx of d(cx, y)) {
					for (let ex of e(dx, y)) {
						for (let fx of f(ex, y)) {
							for (let gx of g(fx, y)) {
								for (let hx of h(gx, y)) {
									for (let ix of i(hx, y)) {
										yield *j(ix, y);
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
var many = f => {
	function* manyf(x, p) {
		for (let fx of f(x, p)) {
			yield *manyf(fx, p);
		}
		yield x;
	};
	return function (x, p) {
		let y = x.spawn(-2, p);
		return manyf(y, y);
	}
}
var maybe = f => function*(x, p) {
	yield *f(x, p);
	yield x;
};
function of() {
	var args = [];
	for (var i=0; i<arguments.length; i++) {
		args.push(arguments[i]);
	}
	return function*(x, p){
		var i = 100;
		for (let a of args) {
			let y = x.spawn(i++, p);
			yield *a(y, y);
		}
	}
}

function seq() {
	var args = [];
	Array.prototype.push.apply(args, arguments);
	return ([seq2, seq3, seq4, seq5, seq6, seq7, seq8, seq9, seq10][arguments.length - 2]).apply(null, args);
}

function *gmap(f, g) {
	for (let x of g) {
		yield f(x);
	}
}

var rules = [];
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
	return this.li+1 >= this.lx.lex.length ? null : new Builder(this.lx, this.li+1, this, p, -3);
}
Builder.prototype.spawn = function(ty, p) {
	return new Builder(this.lx, this.li, this, p, ty);
}

var _chunk = seq(rules[Block], s(0));
function parse(lx) {
	var root = new Builder(lx, -1, null, null, 0);
	return _chunk(root, root).next().value;
}

exports.parse = parse;
