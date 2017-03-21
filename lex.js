exports["and"] = exports._and = 1;
exports["break"] = exports._break = 2;
exports["do"] = exports._do = 3;
exports["else"] = exports._else = 4;
exports["elseif"] = exports._elseif = 5;
exports["end"] = exports._end = 6;
exports["false"] = exports._false = 7;
exports["for"] = exports._for = 8;
exports["function"] = exports._function = 9;
exports["goto"] = exports._goto = 10;
exports["if"] = exports._if = 11;
exports["in"] = exports._in = 12;
exports["local"] = exports._local = 13;
exports["nil"] = exports._nil = 14;
exports["not"] = exports._not = 15;
exports["or"] = exports._or = 16;
exports["repeat"] = exports._repeat = 17;
exports["return"] = exports._return = 18;
exports["then"] = exports._then = 19;
exports["true"] = exports._true = 20;
exports["until"] = exports._until = 21;
exports["while"] = exports._while = 22;
exports["+"] = exports._plus = 23;
exports["-"] = exports._minus = 24;
exports["*"] = exports._mul = 25;
exports["/"] = exports._div = 26;
exports["%"] = exports._mod = 27;
exports["^"] = exports._bxor = 28;
exports["#"] = exports._hash = 29;
exports["&"] = exports._band = 30;
exports["~"] = exports._bnot = 31;
exports["|"] = exports._bor = 32;
exports["<<"] = exports._lsh = 33;
exports[">>"] = exports._rsh = 34;
exports["//"] = exports._idiv = 35;
exports["=="] = exports._eq = 36;
exports["~="] = exports._neq = 37;
exports["<"] = exports._lt = 38;
exports[">"] = exports._gt=  39;
exports["<="] = exports._lte = 40;
exports[">="] = exports._gte = 41;
exports["="] = exports._set = 42;
exports["("] = exports._lp = 43;
exports[")"] = exports._rp = 44;
exports["{"] = exports._cl = 45;
exports["}"] = exports._cr = 46;
exports["["] = exports._sl = 47;
exports["]"] = exports._sr = 48;
exports["::"] = exports._label = 49;
exports[";"] = exports._semi = 50;
exports[":"] = exports._colon = 51;
exports[","] = exports._comma = 52;
exports["."] = exports._dot = 53;
exports[".."] = exports._dotdot = 54;
exports["..."] = exports._dotdotdot = 55;
exports['"'] = exports["'"] = exports._quote = 56;
exports._ident = 57;

function Lex(src) {
	this.ss = {};
	this.lex = null;
	let it = /--\[\[|\[=*\[/, res, sid = 1;
	while (res = it.exec(src)) {
		let res0 = res[0];
		let idx = res.index;
		let idx1 = idx + res0.length;
		if (res0 == '--[[') {
			let idx2 = src.indexOf(']]', idx1);
			if (!~idx2) console.log("Expected ]] somewhere after " + idx1);
			src = src.slice(0, idx) + src.slice(idx2 + 2);
		} else {
			let idx2 = src.indexOf(res0.replace(/\[/g, ']'), idx1);
			if (!~idx2) console.log("Expected ]] somewhere after " + idx1);
			let st = src.slice(idx1, idx2);
			let si = this.ss[st];
			if (!si) {
				this.ss[st] = sid;
				si = sid++;
			}
			src = src.slice(0, idx) + ('\0' + si + '\0') + src.slice(idx2 + res0.length);
		}
	}
	// TODO quoted newlines
	let qit = /'|"/, qre;
	while (qre = qit.exec(src)) {
		let idx = qre.index, idx2 = idx, qch = qre[0], st = "";
		while (true) {
			idx2 += 1;
			if (idx2 >= src.length || src[idx2] == qch) {
				break;
			}
			if (src[idx2] == '\\') {
				idx2++;
				switch (src[idx2]) {
					case 'a':st == String.fromCharCode(7);break;
					case 'b':st += '\b';break;
					case '\n':case 'n':st += '\n';break;
					case '\r':case 'r':st += '\r';break;
					case 't':st += '\t';break;
					case 'v':st += '\v';break;
					case '\\':st += '\\';break;
					case '"':st += '"';break;
					case "'":st += "'";break;
					case "x": {
						let c0 = src[idx2+1]||"x", c1 = src[idx2+2]||"x";
						st += String.fromCharCode(parseInt(c0 + c1, 16));
						idx += 2;
						break;
					}
					case "0":case "1":case "2":case "3":case "4":case "5":case "6":case "7":case "8":case "9":
						let c1 = src[idx2+1]||"x", c2 = src[idx2+2]||"x";
						st += String.fromCharCode(parseInt(src[idx2]+c1+c2, 8));
						idx += 2;
						break;
					default:
						console.log("Invalid sequence");
						return;
				}
			} else {
				st += src[idx2];
			}
		}
		let si = this.ss[st];
		if (!si) {
			this.ss[st] = sid;
			si = sid++;
		}
		src = src.slice(0, idx) + ('\0' + si + '\0') + src.slice(idx2 + 1);
	}
	this.lex = src.
		replace(/--.*\n?/g, ' ').
		replace(/(\+|-|\*|\/\/|\/|%|\^|#|&|==|~=|~|\||<=|>=|=|<<|<|>>|>|{|}|\(|\)|\[|\]|::|:|;|,|\.\.\.|\.\.|\.)/g, ' $1 ').
		trim().
		split(/\s+/);
}

exports.Lex = Lex;