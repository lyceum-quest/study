## The JavaScript number operations that ts-fsrs uses, reproduced in pure Roc,
## so that the FSRS port in `Fsrs` matches ts-fsrs as it runs on V8 and gives
## the same bits on every Roc target (native and wasm32).
##
## The Elm port (`src/Fsrs/Math.elm`) needs only `exp`, because Elm compiles
## `^`, `logBase e`, `round`, `floor` and `String.fromFloat` to JavaScript's
## `Math.pow`, `Math.log`, `Math.round`, `Math.floor` and number-to-string.
## Roc lacks or differs from each, so this module ports them:
##
## - `exp`: fdlibm `e_exp.c` as adapted in V8 `src/base/ieee754.cc`, translated
##   from `src/Fsrs/Math.elm` (only double arithmetic; the high-word
##   comparisons are comparisons against the doubles with those high words).
##   Roc has no `F64.exp`.
## - `log`: fdlibm `e_log.c`, which V8 uses for `Math.log` (bit for bit equal to
##   Node 22 and 24). Roc has no `F64.log`; see
##   https://github.com/thebrandonlucas/roc-issues/tree/master/roc/IMPROVEMENT-008-f64-log-and-exp
##   (upstream roc-lang/roc#5107). Remove `exp` and `log` here once Roc's give
##   the same bits.
## - `pow`: fdlibm `e_pow.c`. `Math.pow` has no single definition to match:
##   V8 13 (Node 24, which produced the fixtures) calls the platform's
##   `std::pow`, and earlier V8 a modified fdlibm `pow`, so the Elm port gets
##   whichever the browser has. They differ in the last bit for a few percent of
##   arguments, which the 8-decimal rounding absorbs over every fixture. fdlibm's
##   is used so the result does not depend on how a Roc target implements
##   `F64.pow` (it currently gives the same bits).
## - `round`: `Math.round` (`F64.round_to_i64_try` rounds halves away from zero).
## - `floor`: `Math.floor`, as an `F64`.
## - `to_js_str`: `Number.prototype.toString()` (`F64.to_str` gives the same
##   shortest digits but writes exponents differently, e.g. `1e20`).
##
## `log`, `pow` and `scalbn` keep fdlibm's names (`hx` is the high word of `x`,
## `lx` its low word, and so on) so they can be read side by side with the C.
##
## fdlibm notice: Copyright (C) 1993-2004 by Sun Microsystems, Inc. All rights
## reserved. Developed at SunSoft, a Sun Microsystems, Inc. business. Permission
## to use, copy, modify, and distribute this software is freely granted, provided
## that this notice is preserved.
FsrsMath := [].{

	## fdlibm `__ieee754_exp` as in V8 `src/base/ieee754.cc`, matching V8's
	## `Math.exp` bit for bit. Thresholds are the doubles whose high words fdlibm
	## compares against (low word 0).
	exp : F64 -> F64
	exp = |x| {
		magnitude = x.abs()
		negative = x < 0.0
		if x.is_nan() {
			x
		} else if magnitude >= 709.7822265625 and x > 709.782712893384 {
			F64.infinity
		} else if magnitude >= 709.7822265625 and x < -745.1332191019411 {
			0.0
		} else if magnitude < 0.3465735912322998 and magnitude < 3.725290298461914e-9 {
			1.0 + x
		} else if magnitude < 0.3465735912322998 {
			exp_reduced(0.0, 0.0, x, 0)
		} else if magnitude < 1.0397205352783203 {
			if x == 1.0 {
				2.718281828459045
			} else if negative {
				high = x + ln2_hi
				exp_reduced(high, -ln2_lo, high + ln2_lo, -1)
			} else {
				high = x - ln2_hi
				exp_reduced(high, ln2_lo, high - ln2_lo, 1)
			}
		} else {
			k = truncate(inv_ln2 * x + (if (negative) -0.5 else 0.5))
			high = x - k.to_f64() * ln2_hi
			low = k.to_f64() * ln2_lo
			exp_reduced(high, low, high - low, k)
		}
	}

	## fdlibm `__ieee754_log` as in V8 `src/base/ieee754.cc` (`Math.log`).
	log : F64 -> F64
	log = |x0| {
		var $x = x0
		var $hx = high_word($x)
		lx = low_word($x)
		var $k = 0
		if $hx < 0x00100000 {
			if $hx.bitwise_and(0x7fffffff).bitwise_or(lx) == 0 {
				return -F64.infinity
			}
			if $hx < 0 {
				return F64.nan
			}
			$k = $k - 54
			$x = $x * two54
			$hx = high_word($x)
		}
		if $hx >= 0x7ff00000 {
			return $x + $x
		}
		$k = $k + $hx.shr_wrap(20) - 1023
		$hx = $hx.bitwise_and(0x000fffff)
		i = ($hx + 0x95f64).bitwise_and(0x100000)
		$x = with_high_word($x, $hx.bitwise_or(i.bitwise_xor(0x3ff00000)))
		$k = $k + i.shr_wrap(20)
		f = $x - 1.0
		dk = $k.to_f64()
		if (2 + $hx).bitwise_and(0x000fffff) < 3 {
			if f == 0.0 {
				return if ($k == 0) 0.0 else dk * ln2_hi + dk * ln2_lo
			}
			r = f * f * (0.5 - 0.33333333333333333 * f)
			return if ($k == 0) f - r else dk * ln2_hi - ((r - dk * ln2_lo) - f)
		}
		s = f / (2.0 + f)
		z = s * s
		w = z * z
		t1 = w * (lg2 + w * (lg4 + w * lg6))
		t2 = z * (lg1 + w * (lg3 + w * (lg5 + w * lg7)))
		r = t2 + t1
		if ($hx - 0x6147a).bitwise_or(0x6b851 - $hx) > 0 {
			half_f_squared = 0.5 * f * f
			if $k == 0 {
				f - (half_f_squared - s * (half_f_squared + r))
			} else {
				dk * ln2_hi - ((half_f_squared - (s * (half_f_squared + r) + dk * ln2_lo)) - f)
			}
		} else if $k == 0 {
			f - s * (f - r)
		} else {
			dk * ln2_hi - ((s * (f - r) - dk * ln2_lo) - f)
		}
	}

	## `Math.pow`: V8 returns NaN where ECMAScript differs from IEEE 754 (a NaN
	## exponent, or ±1 to an infinite power), then calls fdlibm `__ieee754_pow`.
	pow : F64, F64 -> F64
	pow = |x, y| {
		if y.is_nan() or (y.is_infinite() and (x == 1.0 or x == -1.0)) {
			F64.nan
		} else {
			ieee754_pow(x, y)
		}
	}

	## `Math.round`: the integer closest to `x`, halves rounding up.
	round : F64 -> F64
	round = |x| {
		whole = floor(x)
		if (x - whole >= 0.5) whole + 1.0 else whole
	}

	## `Math.floor`.
	floor : F64 -> F64
	floor = |x| {
		# Every double of magnitude 2^52 or more is an integer.
		if x.is_nan() or x.abs() >= 4503599627370496.0 {
			x
		} else {
			match F64.floor_to_i64_try(x) {
				Ok(whole) => whole.to_f64()
				Err(_) => x
			}
		}
	}

	## JavaScript's `String(x)` (`Number::toString`): the shortest digits that
	## read back as `x`, in plain notation from 1e-6 up to 1e21 and in exponent
	## notation (`1.5e+21`, `1e-7`) outside it.
	to_js_str : F64 -> Str
	to_js_str = |x| {
		if x.is_nan() {
			"NaN"
		} else if x == 0.0 {
			"0"
		} else if x < 0.0 {
			"-${to_js_str(-x)}"
		} else if x.is_infinite() {
			"Infinity"
		} else {
			shortest = shortest_digits(x)
			js_notation(shortest.digits, shortest.point)
		}
	}
}

# The digits of `x` (positive and finite) without leading or trailing zeros,
# and the position of the decimal point: `x = 0.<digits> × 10^point`.
# `F64.to_str` prints the shortest round-trip digits as `123.45`, `1e-7` or
# `1.5e20`; only its notation needs changing.
shortest_digits : F64 -> { digits : List(U8), point : I64 }
shortest_digits = |x| {
	text = x.to_str()
	(mantissa, exponent) = match text.split_first("e") {
		Ok({ before, after }) => (before, I64.from_str(after) ?? 0)
		Err(_) => (text, 0)
	}
	(whole, fraction) = match mantissa.split_first(".") {
		Ok({ before, after }) => (before, after)
		Err(_) => (mantissa, "")
	}
	var $digits = whole.to_utf8().concat(fraction.to_utf8())
	var $point = whole.count_utf8_bytes().to_i64_wrap() + exponent
	while $digits.first() == Ok('0') {
		$digits = $digits.drop_first(1)
		$point = $point - 1
	}
	while $digits.last() == Ok('0') {
		$digits = $digits.drop_last(1)
	}
	{ digits: $digits, point: $point }
}

# ECMAScript Number::toString's layout of `0.<digits> × 10^point`.
js_notation : List(U8), I64 -> Str
js_notation = |digits, point| {
	count = digits.len().to_i64_wrap()
	text = Str.from_utf8(digits) ?? ""
	if count <= point and point <= 21 {
		Str.concat(text, Str.repeat("0", (point - count).to_u64_wrap()))
	} else if 0 < point and point <= 21 {
		before = Str.from_utf8(digits.take_first(point.to_u64_wrap())) ?? ""
		after = Str.from_utf8(digits.drop_first(point.to_u64_wrap())) ?? ""
		"${before}.${after}"
	} else if -6 < point and point <= 0 {
		"0.${Str.repeat("0", (-point).to_u64_wrap())}${text}"
	} else {
		exponent = point - 1
		sign = if (exponent < 0) "-" else "+"
		magnitude = (if (exponent < 0) -exponent else exponent).to_str()
		if count == 1 {
			"${text}e${sign}${magnitude}"
		} else {
			first = Str.from_utf8(digits.take_first(1)) ?? ""
			rest = Str.from_utf8(digits.drop_first(1)) ?? ""
			"${first}.${rest}e${sign}${magnitude}"
		}
	}
}

# JavaScript's `x | 0` for the small values `exp` truncates.
truncate : F64 -> I64
truncate = |x| F64.to_i64_try(x) ?? 0

exp_reduced : F64, F64, F64, I64 -> F64
exp_reduced = |high, low, x, k| {
	t = x * x
	c = x - t * (0.16666666666666602 + t * (-0.0027777777777015593 + t * (0.00006613756321437934 + t * (-0.0000016533902205465252 + t * 4.1381367970572385e-8))))
	if k == 0 {
		1.0 - ((x * c) / (c - 2.0) - x)
	} else {
		y = 1.0 - ((low - (x * c) / (2.0 - c)) - high)
		if k >= -1021 {
			if k == 1024 {
				y * 2.0 * power_of_two(1023)
			} else {
				y * power_of_two(k)
			}
		} else {
			y * power_of_two(k + 1000) * 9.332636185032189e-302
		}
	}
}

# 2^k for -1022 <= k <= 1023, exactly (the Elm port's `2 ^ toFloat k`).
power_of_two : I64 -> F64
power_of_two = |k| F64.from_bits((k + 1023).to_u64_wrap().shl_wrap(52))

ln2_hi : F64
ln2_hi = 0.6931471803691238

ln2_lo : F64
ln2_lo = 1.9082149292705877e-10

inv_ln2 : F64
inv_ln2 = 1.4426950408889634

two54 : F64
two54 = 18014398509481984.0

lg1 : F64
lg1 = 6.666666666666735130e-01

lg2 : F64
lg2 = 3.999999999940941908e-01

lg3 : F64
lg3 = 2.857142874366239149e-01

lg4 : F64
lg4 = 2.222219843214978396e-01

lg5 : F64
lg5 = 1.818357216161805012e-01

lg6 : F64
lg6 = 1.531383769920937332e-01

lg7 : F64
lg7 = 1.479819860511658591e-01

# fdlibm's GET_HIGH_WORD: the sign, exponent and top 20 fraction bits, as a
# signed 32-bit integer.
high_word : F64 -> I64
high_word = |x| {
	high = x.to_bits().shr_wrap(32).to_i64_wrap()
	if (high >= 0x80000000) high - 0x100000000 else high
}

# fdlibm's GET_LOW_WORD: the low 32 fraction bits, unsigned.
low_word : F64 -> I64
low_word = |x| x.to_bits().bitwise_and(0xffffffff).to_i64_wrap()

# fdlibm's INSERT_WORDS; only the low 32 bits of each word are used.
from_words : I64, I64 -> F64
from_words = |high, low| {
	high_bits = high.to_u64_wrap().bitwise_and(0xffffffff).shl_wrap(32)
	F64.from_bits(high_bits.bitwise_or(low.to_u64_wrap().bitwise_and(0xffffffff)))
}

with_high_word : F64, I64 -> F64
with_high_word = |x, high| from_words(high, low_word(x))

with_low_word : F64, I64 -> F64
with_low_word = |x, low| from_words(high_word(x), low)

# fdlibm `__ieee754_pow` (FreeBSD `e_pow.c`), which V8's `Math.pow` uses.
ieee754_pow : F64, F64 -> F64
ieee754_pow = |x, y| {
	hx = high_word(x)
	lx = low_word(x)
	hy = high_word(y)
	ly = low_word(y)
	ix = hx.bitwise_and(0x7fffffff)
	iy = hy.bitwise_and(0x7fffffff)

	# y == 0: x^0 = 1; x == 1: 1^y = 1.
	if iy.bitwise_or(ly) == 0 or (hx == 0x3ff00000 and lx == 0) {
		return 1.0
	}

	# A NaN argument gives NaN.
	if ix > 0x7ff00000 or (ix == 0x7ff00000 and lx != 0) or iy > 0x7ff00000 or (iy == 0x7ff00000 and ly != 0) {
		return x + y
	}

	# When x < 0, whether y is an odd integer (1), an even integer (2) or not
	# an integer (0).
	y_is_integer =
		if hx >= 0 {
			0
		} else if iy >= 0x43400000 {
			2
		} else if iy >= 0x3ff00000 {
			k = iy.shr_wrap(20) - 0x3ff
			if k > 20 {
				j = ly.shr_wrap((52 - k).to_u8_wrap())
				if (j.shl_wrap((52 - k).to_u8_wrap()) == ly) 2 - j.bitwise_and(1) else 0
			} else if ly == 0 {
				j = iy.shr_wrap((20 - k).to_u8_wrap())
				if (j.shl_wrap((20 - k).to_u8_wrap()) == iy) 2 - j.bitwise_and(1) else 0
			} else {
				0
			}
		} else {
			0
		}

	# Special values of y.
	if ly == 0 {
		if iy == 0x7ff00000 {
			if ix == 0x3ff00000 and lx == 0 {
				return 1.0
			} else if ix >= 0x3ff00000 {
				return if (hy >= 0) y else 0.0
			} else {
				return if (hy < 0) -y else 0.0
			}
		}
		if iy == 0x3ff00000 {
			return if (hy < 0) 1.0 / x else x
		}
		if hy == 0x40000000 {
			return x * x
		}
		if hy == 0x3fe00000 and hx >= 0 {
			return x.sqrt()
		}
	}

	ax = x.abs()

	# Special values of x: ±0, ±infinity, ±1.
	if lx == 0 and (ix == 0x7ff00000 or ix == 0 or ix == 0x3ff00000) {
		z = if (hy < 0) 1.0 / ax else ax
		if hx < 0 {
			if ix == 0x3ff00000 and y_is_integer == 0 {
				return (z - z) / (z - z)
			} else if y_is_integer == 1 {
				return -z
			}
		}
		return z
	}

	# A negative x to a non-integer power is NaN.
	if hx < 0 and y_is_integer == 0 {
		return (x - x) / (x - x)
	}

	# The sign of the result: negative for a negative x to an odd power.
	sign = if (hx < 0 and y_is_integer == 1) -1.0 else 1.0

	# log2(ax) = t1 + t2.
	var $t1 = 0.0
	var $t2 = 0.0
	if iy > 0x41e00000 {
		# |y| > 2^31: overflow or underflow unless x is close to 1.
		if iy > 0x43f00000 {
			if ix <= 0x3fefffff {
				return if (hy < 0) huge * huge else tiny * tiny
			}
			if ix >= 0x3ff00000 {
				return if (hy > 0) huge * huge else tiny * tiny
			}
		}
		if ix < 0x3fefffff {
			return if (hy < 0) sign * huge * huge else sign * tiny * tiny
		}
		if ix > 0x3ff00000 {
			return if (hy > 0) sign * huge * huge else sign * tiny * tiny
		}
		# |1 - x| <= 2^-20, so log(x) is x - x^2/2 + x^3/3 - x^4/4.
		t = ax - 1.0
		w = (t * t) * (0.5 - t * (third - t * 0.25))
		u = ivln2_h * t
		v = t * ivln2_l - w * ivln2
		$t1 = with_low_word(u + v, 0)
		$t2 = v - ($t1 - u)
	} else {
		var $ax = ax
		var $ix = ix
		var $n = 0
		# Scale a subnormal x up.
		if $ix < 0x00100000 {
			$ax = $ax * two53
			$n = $n - 53
			$ix = high_word($ax)
		}
		$n = $n + $ix.shr_wrap(20) - 0x3ff
		j = $ix.bitwise_and(0x000fffff)
		# Normalize ax into [sqrt(2)/2, sqrt(2)) or [sqrt(3)/2, sqrt(3)).
		$ix = j.bitwise_or(0x3ff00000)
		var $k = 0
		if j <= 0x3988E {
			$k = 0
		} else if j < 0xBB67A {
			$k = 1
		} else {
			$k = 0
			$n = $n + 1
			$ix = $ix - 0x00100000
		}
		$ax = with_high_word($ax, $ix)
		bp = if ($k == 0) 1.0 else 1.5
		dp_h = if ($k == 0) 0.0 else 5.84962487220764160156e-01
		dp_l = if ($k == 0) 0.0 else 1.35003920212974897128e-08

		# ss = s_h + s_l = (ax - 1) / (ax + 1) or (ax - 1.5) / (ax + 1.5).
		u = $ax - bp
		v = 1.0 / ($ax + bp)
		ss = u * v
		s_h = with_low_word(ss, 0)
		# t_h = ax + bp, high part.
		t_h = from_words($ix.shr_wrap(1).bitwise_or(0x20000000) + 0x00080000 + $k.shl_wrap(18), 0)
		t_l = $ax - (t_h - bp)
		s_l = v * ((u - s_h * t_h) - s_h * t_l)

		# log(ax).
		s2 = ss * ss
		r = s2 * s2 * (l1 + s2 * (l2 + s2 * (l3 + s2 * (l4 + s2 * (l5 + s2 * l6))))) + s_l * (s_h + ss)
		s_h2 = s_h * s_h
		t_h3 = with_low_word(3.0 + s_h2 + r, 0)
		t_l3 = r - ((t_h3 - 3.0) - s_h2)
		# u3 + v3 = ss * (1 + ...).
		u3 = s_h * t_h3
		v3 = s_l * t_h3 + t_l3 * ss
		# 2 / (3 log 2) * (ss + ...).
		p_h = with_low_word(u3 + v3, 0)
		p_l = v3 - (p_h - u3)
		z_h = cp_h * p_h
		z_l = cp_l * p_h + p_l * cp + dp_l
		# log2(ax) = (ss + ...) * 2 / (3 log 2) = n + dp_h + z_h + z_l.
		t = $n.to_f64()
		$t1 = with_low_word(((z_h + z_l) + dp_h) + t, 0)
		$t2 = z_l - ((($t1 - t) - dp_h) - z_h)
	}

	# (y1 + y2) * (t1 + t2), with y split into y1 + y2.
	y1 = with_low_word(y, 0)
	p_l = (y - y1) * $t1 + y * $t2
	var $p_h = y1 * $t1
	z = p_l + $p_h
	j = high_word(z)
	i = low_word(z)
	if j >= 0x40900000 {
		# z >= 1024
		if j != 0x40900000 or i != 0 {
			return sign * huge * huge
		} else if p_l + ovt > z - $p_h {
			return sign * huge * huge
		}
	} else if j.bitwise_and(0x7fffffff) >= 0x4090cc00 {
		# z <= -1075
		if j.bitwise_and(0xffffffff) != 0xc090cc00 or i != 0 {
			return sign * tiny * tiny
		} else if p_l <= z - $p_h {
			return sign * tiny * tiny
		}
	}

	# 2^(p_h + p_l).
	magnitude = j.bitwise_and(0x7fffffff)
	var $k = magnitude.shr_wrap(20) - 0x3ff
	var $n = 0
	if magnitude > 0x3fe00000 {
		# |z| > 0.5: n = [z + 0.5].
		$n = j + (0x00100000).shr_wrap(($k + 1).to_u8_wrap())
		$k = $n.bitwise_and(0x7fffffff).shr_wrap(20) - 0x3ff
		t = from_words($n.bitwise_and((0x000fffff).shr_wrap($k.to_u8_wrap()).bitwise_not()), 0)
		$n = $n.bitwise_and(0x000fffff).bitwise_or(0x00100000).shr_wrap((20 - $k).to_u8_wrap())
		if j < 0 {
			# Not `-$n`, which Roc fails to parse:
			# https://github.com/thebrandonlucas/roc-issues/tree/master/roc/BUG-027-unary-minus-before-var-parse-error
			# (not yet reported upstream). Write `-$n` once that parses.
			$n = $n.negate()
		}
		$p_h = $p_h - t
	}
	t = with_low_word(p_l + $p_h, 0)
	u = t * pow_lg2_h
	v = (p_l - (t - $p_h)) * pow_lg2 + t * pow_lg2_l
	z2 = u + v
	w = v - (z2 - u)
	t2 = z2 * z2
	t3 = z2 - t2 * (p1 + t2 * (p2 + t2 * (p3 + t2 * (p4 + t2 * p5))))
	r = (z2 * t3) / (t3 - 2.0) - (w + z2 * w)
	z3 = 1.0 - (r - z2)
	high = high_word(z3) + $n.shl_wrap(20)
	if high < 0x00100000 {
		# A subnormal result.
		sign * scalbn(z3, $n)
	} else {
		sign * with_high_word(z3, high)
	}
}

# fdlibm `scalbn`: x * 2^n, rounded once.
scalbn : F64, I64 -> F64
scalbn = |x0, n| {
	var $x = x0
	var $hx = high_word($x)
	lx = low_word($x)
	var $k = $hx.bitwise_and(0x7ff00000).shr_wrap(20)
	if $k == 0 {
		# 0 or subnormal x
		if lx.bitwise_or($hx.bitwise_and(0x7fffffff)) == 0 {
			return $x
		}
		$x = $x * two54
		$hx = high_word($x)
		$k = $hx.bitwise_and(0x7ff00000).shr_wrap(20) - 54
		if n < -50000 {
			return tiny * $x
		}
	}
	if $k == 0x7ff {
		return $x + $x
	}
	$k = $k + n
	if $k > 0x7fe {
		return huge * copy_sign(huge, $x)
	}
	if $k > 0 {
		return with_high_word($x, $hx.bitwise_and(0x800fffff).bitwise_or($k.shl_wrap(20)))
	}
	if $k <= -54 {
		return if (n > 50000) huge * copy_sign(huge, $x) else tiny * copy_sign(tiny, $x)
	}
	with_high_word($x, $hx.bitwise_and(0x800fffff).bitwise_or(($k + 54).shl_wrap(20))) * twom54
}

copy_sign : F64, F64 -> F64
copy_sign = |magnitude, sign| if (high_word(sign) < 0) -magnitude.abs() else magnitude.abs()

huge : F64
huge = 1.0e300

tiny : F64
tiny = 1.0e-300

two53 : F64
two53 = 9007199254740992.0

twom54 : F64
twom54 = 5.55111512312578270212e-17

third : F64
third = 3.3333333333333331483e-01

ovt : F64
ovt = 8.0085662595372944372e-17

l1 : F64
l1 = 5.99999999999994648725e-01

l2 : F64
l2 = 4.28571428578550184252e-01

l3 : F64
l3 = 3.33333329818377432918e-01

l4 : F64
l4 = 2.72728123808534006489e-01

l5 : F64
l5 = 2.30660745775561754067e-01

l6 : F64
l6 = 2.06975017800338417784e-01

p1 : F64
p1 = 1.66666666666666019037e-01

p2 : F64
p2 = -2.77777777770155933842e-03

p3 : F64
p3 = 6.61375632143793436117e-05

p4 : F64
p4 = -1.65339022054652515390e-06

p5 : F64
p5 = 4.13813679705723846039e-08

pow_lg2 : F64
pow_lg2 = 6.93147180559945286227e-01

pow_lg2_h : F64
pow_lg2_h = 6.93147182464599609375e-01

pow_lg2_l : F64
pow_lg2_l = -1.90465429995776804525e-09

cp : F64
cp = 9.61796693925975554329e-01

cp_h : F64
cp_h = 9.61796700954437255859e-01

cp_l : F64
cp_l = -7.02846165095275826516e-09

ivln2 : F64
ivln2 = 1.44269504088896338700e+00

ivln2_h : F64
ivln2_h = 1.44269502162933349609e+00

ivln2_l : F64
ivln2_l = 1.92596299112661746887e-08
