return {
	Nop = 0,
	LoadNil = 1,
	LoadFalse = 2,
	LoadTrue = 3,
	CmpEq = 4,
	Add = 5,
	Idx = 6,
	Not = 7,
	Len = 8,
	TblNew = 9,
	TblSet = 10,
	TblAdd = 11,
	Return = 12,
	Call = 13,
	ReturnCall = 14,
	LoadConst = 15,
	LoadLocal = 16,
	StoreLocal = 17,
	Jmp = 18,
	Jif = 19,
	JifNot = 20,
	JifOrPop = 21,
	JifNotOrPop = 22,
	Pop = 23,
	Neg = 24,
	BNot = 25,
	CmpGe = 26,
	CmpGt = 27,
	CmpLe = 28,
	CmpLt = 29,
	LoadVarg = 30,
	Syscall = 31,
	LoadParam = 32,
	StoreParam = 33,
	LoadFreeBox = 34,
	StoreFreeBox = 35,
	LoadParamBox = 36,
	StoreParamBox = 37,
	BoxParam = 38,
	LoadLocalBox = 39,
	StoreLocalBox = 40,
	AppendCall = 41,
	CallVarg = 42,
	ReturnCallVarg = 43,
	AppendCallVarg = 44,
	ReturnVarg = 45,
	AppendVarg = 46,
	Sub = 47,
	Mul = 48,
	Div = 49,
	IDiv = 50,
	Pow = 51,
	Mod = 52,
	BAnd = 53,
	BXor = 54,
	BOr = 55,
	Shr = 56,
	Shl = 57,
	Concat = 58,
	LoadFree = 59,
	Append = 60,
	BoxLocal = 61,
	LoadFunc = 62,
}
