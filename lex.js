"use strict";
const rekey = exports.rekey = /^(and|break|do|else|elseif|end|false|for|function|goto|if|in|local|nil|not|or|repeat|return|then|true|until|while)$/;
const _and = exports["and"] = exports._and = 1;
const _break = exports["break"] = exports._break = 2;
const _do = exports["do"] = exports._do = 3;
const _else = exports["else"] = exports._else = 4;
const _elseif = exports["elseif"] = exports._elseif = 5;
const _end = exports["end"] = exports._end = 6;
const _false = exports["false"] = exports._false = 7;
const _for = exports["for"] = exports._for = 8;
const _function = exports["function"] = exports._function = 9;
const _goto = exports["goto"] = exports._goto = 10;
const _if = exports["if"] = exports._if = 11;
const _in = exports["in"] = exports._in = 12;
const _local = exports["local"] = exports._local = 13;
const _nil = exports["nil"] = exports._nil = 14;
const _not = exports["not"] = exports._not = 15;
const _or = exports["or"] = exports._or = 16;
const _repeat = exports["repeat"] = exports._repeat = 17;
const _return = exports["return"] = exports._return = 18;
const _then = exports["then"] = exports._then = 19;
const _true = exports["true"] = exports._true = 20;
const _until = exports["until"] = exports._until = 21;
const _while = exports["while"] = exports._while = 22;
const _plus = exports._plus = 23;
const _minus = exports._minus = 24;
const _mul = exports._mul = 25;
const _div = exports._div = 26;
const _mod = exports._mod = 27;
const _pow = exports._pow = 28;
const _hash = exports._hash = 29;
const _band = exports._band = 30;
const _bnot = exports._bnot = 31;
const _bor = exports._bor = 32;
const _lsh = exports._lsh = 33;
const _rsh = exports._rsh = 34;
const _idiv = exports._idiv = 35;
const _eq = exports._eq = 36;
const _neq = exports._neq = 37;
const _lt = exports._lt = 38;
const _gt = exports._gt = 39;
const _lte = exports._lte = 40;
const _gte = exports._gte = 41;
const _set = exports._set = 42;
const _pl = exports._pl = 43;
const _pr = exports._pr = 44;
const _cl = exports._cl = 45;
const _cr = exports._cr = 46;
const _sl = exports._sl = 47;
const _sr = exports._sr = 48;
const _label = exports._label = 49;
const _semi = exports._semi = 50;
const _colon = exports._colon = 51;
const _comma = exports._comma = 52;
const _dot = exports._dot = 53;
const _dotdot = exports._dotdot = 54;
const _dotdotdot = exports._dotdotdot = 55;
const _ident = exports._ident = 0x8000000;
const _string = exports._string = 0x4000000;
const _number = exports._number = 0x2000000;

const digit = /^\d$/;
const alphascore = /^[a-zA-Z_]$/;
const alphanumscore = /^\w$/;
function Lex(src) {
	this.ss = { _ENV: 0 };
	this.ssr = ["_ENV"];
	this.sn = {};
	this.snr = [];
	const ss = this.ss, ssr = this.ssr, sn = this.sn, snr = this.snr;
	const lex = [];
	let ch;
	for (let i=0; i<src.length; i++){
		switch (ch = src[i]) {
		default:
			if (alphascore.test(ch)) {
				var ident = ch;
				for (i=i+1; i<src.length && alphanumscore.test(src[i]); i++) ident += src[i];
				i--;
				if (rekey.test(ident)) {
					lex.push(exports[ident]);
				} else if (ident in ss) {
					lex.push(_ident | ss[ident]);
				} else {
					lex.push(_ident | ssr.length);
					ss[ident] = ssr.length;
					ssr.push(ident);
				}
			} else if (!/^\s$/.test(ch)) {
				return console.log("Unexpected character", ch);
			}
			break;
		case '+':lex.push(_plus);break;
		case '-':
			if (src[i+1] == '-') {
				if (src[i+2] == '[') {
					let n = ']';
					while (src[i+n.length] == '=') n += '=';
					if (src[i+n.length] == '[') {
						n += ']';
						i = src.indexOf(n, i);
						if (i == -1) {
							return console.log("Unterminated comment " + n);
						}
						break;
					}
				}
				i += 3;
				while (i < src.length && src[i] != '\n') i++;
			} else lex.push(_minus);
			break;
		case '*':lex.push(_mul);break;
		case '/':
			if (src[i+1] == '/') {
				lex.push(_idiv);
				i++;
			}
			else lex.push(_div);
			break;
		case '>':
			if (src[i+1] == '>') {
				lex.push(_rsh);
				i++;
			} else if (src[i+1] == '=') {
				lex.push(_gte);
				i++;
			}
			else lex.push(_gt);
			break;
		case '<':
			if (src[i+1] == '<') {
				lex.push(_lsh);
				i++;
			} else if (src[i+1] == '=') {
				lex.push(_lte);
				i++;
			} else lex.push(_lt);
			break;
		case '%':lex.push(_mod);break;
		case '{':lex.push(_cl);break;
		case '}':lex.push(_cr);break;
		case '(':lex.push(_pl);break;
		case ')':lex.push(_pr);break;
		case ']':lex.push(_sr);break;
		case '&':lex.push(_band);break;
		case '^':lex.push(_pow);break;
		case '|':lex.push(_bor);break;
		case ';':lex.push(_semi);break;
		case ',':lex.push(_comma);break;
		case '#':lex.push(_hash);break;
		case '[':
			if (src[i+1] != '[' && src[i+1] != '=') {
				lex.push(_sl);
			} else {
				var n = ']';
				while (src[i+n.length] == '=') n += '=';
				if (src[i+n.length] == '[') {
					n += ']';
					let i0 = i+n.length;
					i = src.indexOf(n, i);
					if (i == -1) {
						return console.log("Unterminated string " + n);
					}
					let s = src.slice(i0, i);
					if (s in ss) {
						lex.push(_string | ss[s]);
					} else {
						lex.push(_string | ssr.length);
						ss[s] = ssr.length;
						ssr.push(s);
					}
					break;
				}
			}
			break;
		case "'":case '"': {
			let s = "";
			for (i++; src[i] != ch; i++) {
				let c = src[i];
				if (c == '\\') {
					switch (src[++i]) {
						case 'a':s == String.fromCharCode(7);break;
						case 'b':s += '\b';break;
						case '\n':case 'n':s += '\n';break;
						case '\r':case 'r':s += '\r';break;
						case 't':s += '\t';break;
						case 'v':s += '\v';break;
						case '\\':s += '\\';break;
						case '"':s += '"';break;
						case "'":s += "'";break;
						case "x": {
									  let c0 = src[i+1]||"x", c1 = src[i+2]||"x";
									  s += String.fromCharCode(parseInt(c0 + c1, 16));
									  i += /[0-9a-fA-F]/.test(c0) + /[0-9a-fA-F]/.test(c1);
									  break;
								  }
						case "0":case "1":case "2":case "3":case "4":case "5":case "6":case "7": {
								 let c1 = src[i+1]||"x", c2 = src[i+2]||"x";
								 s += String.fromCharCode(parseInt(src[i]+c1+c2, 8));
								 i += /[0-7]/.test(c1) + /[0-7]/.test(c2);
								 break;
							 }
						default:
								 return console.log("Invalid sequence");
					}
				} else if (c == '\n') {
					return console.log('newline in string');
				} else {
					s += c;
				}
			}
			if (s in ss) {
				lex.push(_string | ss[s]);
			} else {
				lex.push(_string | ssr.length);
				ss[s] = ssr.length;
				ssr.push(s);
			}
			break;
		}
		case ':':
			if (src[i+1] == ':') {
				lex.push(_label);
				i++;
			} else lex.push(_colon);
			break;
		case '~':
			if (src[i+1] == '=') {
				lex.push(_neq);
				i++;
			} else {
				lex.push(_bnot);
			}
			break;
		case '=':
			if (src[i+1] == '=') {
				lex.push(_eq);
				i++;
			} else {
				lex.push(_set);
			}
			break;
		case '.':
			if (src[i+1] == '.') {
				if (src[i+2] == '.') {
					lex.push(_dotdotdot);
					i += 2;
				} else {
					lex.push(_dotdot);
					i += 1;
				}
				break;
			} else if (!digit.test(src[i+1])) {
				lex.push(_dot);
				break;
			}
		case '0':case '1':case '2':case '3':case '4':case '5':case '6':case '7':case '8':case '9': {
				var val = ch == '.' ? 0 : parseFloat(ch), ident = ch, e = false, p = ch == '.', i0 = i;
				i++;
				if (ch == '0' && (src[i] == 'x' || src[i] == 'X')) {
					while (/[\da-fA-F]/.test(src[i+1])) i++;
					let n = parseInt(src.slice(i0 + 2, i+1));
					if (n in sn) {
						lex.push(_number | sn[n]);
					} else {
						lex.push(_number | snr.length);
						sn[n] = snr.length;
						snr.push(n);
					}
				} else {
					while (i < src.length) {
						let n = src[i], newident = ident + n, newval = parseFloat(newident);
						if (n != '0' && (e || n != 'e' && n != 'E') && (p || n != '.') && newval == val) {
							break;
						}
						e |= n == 'e' || n == 'E';
						p |= n == '.';
						val = newval;
						ident += n;
						i++;
					}
					if (val in sn) {
						lex.push(_number | sn[val]);
					} else {
						lex.push(_number | snr.length);
						sn[val] = snr.length;
						snr.push(val);
					}
				}
				i--;
				break;
			}
		}
	}
	lex.push(0);
	this.lex = new Uint32Array(lex);
}

exports.Lex = Lex;
