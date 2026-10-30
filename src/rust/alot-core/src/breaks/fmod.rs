//! R's `%%` on doubles (`myfmod()` in R's src/main/arithmetic.c):
//!
//! ```c
//! if (fabs(x2) * c_eps > 1 && R_FINITE(x1) && fabs(x1) <= fabs(x2))
//!     return (fabs(x1) == fabs(x2)) ? 0 : (differing signs) ? x1 + x2 : x1;
//! double q = x1 / x2;
//! if (R_FINITE(q) && (fabs(q) * c_eps > 1)) warning("probable complete loss of accuracy in modulus");
//! LDOUBLE tmp = (LDOUBLE)x1 - floor(q) * (LDOUBLE)x2;
//! return (double) (tmp - floorl(tmp/x2) * x2);
//! ```
//!
//! `LDOUBLE` is x87 extended precision (a 64-bit significand) on x86_64
//! Linux, and plain doubles give different remainders, so [`Ext`] emulates
//! the four extended operations used here with round-to-nearest-even.
//! `c_eps` is then `LDBL_EPSILON` (2^-63), as R 4.6.1's warning threshold
//! confirms.

/// A finite extended-precision value `(-1)^neg * man * 2^exp`, with `man`
/// either 0 or normalised (top bit set). Exponents never overflow here.
#[derive(Clone, Copy, Debug, PartialEq)]
struct Ext {
    neg: bool,
    exp: i32,
    man: u64,
}

impl Ext {
    const ZERO: Ext = Ext { neg: false, exp: 0, man: 0 };

    fn from_f64(x: f64) -> Ext {
        let bits = x.to_bits();
        let neg = bits >> 63 == 1;
        let e = ((bits >> 52) & 0x7ff) as i32;
        let f = bits & ((1 << 52) - 1);
        let (m, e) = if e == 0 { (f, -1074) } else { (f | (1 << 52), e - 1075) };
        Ext::round(neg, e, m as u128, false)
    }

    /// Rounds `(-1)^neg * (m + sticky fraction) * 2^exp` to a 64-bit
    /// significand. `sticky` says bits below `m` were non-zero.
    fn round(neg: bool, exp: i32, m: u128, sticky: bool) -> Ext {
        if m == 0 {
            return Ext { neg, ..Ext::ZERO };
        }
        let lz = m.leading_zeros();
        let m = m << lz;
        let mut exp = exp - lz as i32 + 64;
        let mut hi = (m >> 64) as u64;
        let lo = m as u64;
        let half = lo >> 63 == 1;
        let rest = (lo << 1) != 0 || sticky;
        if half && (rest || hi & 1 == 1) {
            hi = hi.wrapping_add(1);
            if hi == 0 {
                hi = 1 << 63;
                exp += 1;
            }
        }
        Ext { neg, exp, man: hi }
    }

    fn mul(self, other: Ext) -> Ext {
        let m = self.man as u128 * other.man as u128;
        Ext::round(self.neg != other.neg, self.exp + other.exp, m, false)
    }

    fn sub(self, other: Ext) -> Ext {
        self.add(Ext { neg: !other.neg, ..other })
    }

    fn add(self, other: Ext) -> Ext {
        if other.man == 0 {
            // x - 0 and 0 - 0 as in IEEE arithmetic: -0 only for -0 + -0.
            return if self.man == 0 { Ext { neg: self.neg && other.neg, ..Ext::ZERO } } else { self };
        }
        if self.man == 0 {
            return other;
        }
        let (big, small) = if (self.exp, self.man) >= (other.exp, other.man) { (self, other) } else { (other, self) };
        // 62 guard bits below each significand; the smaller one is shifted
        // right by the exponent difference, keeping a sticky bit.
        let b = (big.man as u128) << 62;
        let d = (big.exp - small.exp) as u32;
        let s_full = (small.man as u128) << 62;
        let (s, sticky) = if d >= 128 { (0, true) } else { (s_full >> d, d > 0 && s_full & ((1 << d) - 1) != 0) };
        let exp = big.exp - 62;
        if big.neg == small.neg {
            Ext::round(big.neg, exp, b + s, sticky)
        } else if b == s && !sticky {
            Ext::ZERO
        } else {
            // A sticky remainder makes the true difference slightly smaller
            // than b - s; at least 62 guard bits keep the rounding exact.
            Ext::round(big.neg, exp, b - s - sticky as u128, sticky)
        }
    }

    fn div(self, other: Ext) -> Ext {
        if self.man == 0 {
            return Ext { neg: self.neg != other.neg, ..Ext::ZERO };
        }
        let b = other.man as u128;
        let num = (self.man as u128) << 64;
        let (mut q, mut r) = (num / b, num % b);
        let mut exp = self.exp - 64 - other.exp;
        // At least 66 quotient bits, so the rounding bit is a real one.
        while q < 1 << 66 {
            r <<= 1;
            q <<= 1;
            if r >= b {
                q |= 1;
                r -= b;
            }
            exp -= 1;
        }
        Ext::round(self.neg != other.neg, exp, q, r != 0)
    }

    fn floor(self) -> Ext {
        if self.man == 0 || self.exp >= 0 {
            return self;
        }
        if self.exp <= -64 {
            // |x| < 1.
            return if self.neg { Ext::round(true, 0, 1, false) } else { Ext::ZERO };
        }
        let fb = (-self.exp) as u32;
        let mut int = self.man >> fb;
        let frac = self.man & ((1u64 << fb) - 1) != 0;
        if self.neg && frac {
            int += 1;
        }
        Ext::round(self.neg, 0, int as u128, false)
    }

    /// Rounds to a double; `None` if the result would be subnormal or overflow.
    fn to_f64(self) -> Option<f64> {
        if self.man == 0 {
            return Some(if self.neg { -0.0 } else { 0.0 });
        }
        let mut hi = self.man >> 11;
        let mut exp = self.exp + 11;
        let half = (self.man >> 10) & 1 == 1;
        let rest = self.man & 0x3ff != 0;
        if half && (rest || hi & 1 == 1) {
            hi += 1;
            if hi == 1 << 53 {
                hi >>= 1;
                exp += 1;
            }
        }
        let e = exp + 52 + 1023;
        if !(1..=2046).contains(&e) {
            return None;
        }
        let bits = ((self.neg as u64) << 63) | ((e as u64) << 52) | (hi & ((1 << 52) - 1));
        Some(f64::from_bits(bits))
    }
}

const C_EPS: f64 = 1.0 / 9_223_372_036_854_775_808.0; // 2^-63

/// Whether R's `x1 %% x2` warns "probable complete loss of accuracy in
/// modulus".
pub fn r_mod_warns(x1: f64, x2: f64) -> bool {
    let early = x2.abs() * C_EPS > 1.0 && x1.is_finite() && x1.abs() <= x2.abs();
    let q = x1 / x2;
    !early && q.is_finite() && q.abs() * C_EPS > 1.0
}

/// R's `x1 %% x2` for finite `x1` and `x2 > 0`. `None` where R would warn
/// (see [`r_mod_warns`]), or the result would be subnormal.
pub fn r_mod(x1: f64, x2: f64) -> Option<f64> {
    if x2.abs() * C_EPS > 1.0 && x1.is_finite() && x1.abs() <= x2.abs() {
        return Some(if x1.abs() == x2.abs() {
            0.0
        } else if (x1 < 0.0 && x2 > 0.0) || (x2 < 0.0 && x1 > 0.0) {
            x1 + x2
        } else {
            x1
        });
    }
    if r_mod_warns(x1, x2) {
        return None;
    }
    let q = x1 / x2;
    let (l1, l2) = (Ext::from_f64(x1), Ext::from_f64(x2));
    let tmp = l1.sub(Ext::from_f64(q.floor()).mul(l2));
    tmp.sub(tmp.div(l2).floor().mul(l2)).to_f64()
}

#[cfg(test)]
mod tests {
    use super::*;

    fn ext(x: f64) -> Ext {
        Ext::from_f64(x)
    }

    #[test]
    fn round_trips_doubles() {
        for x in [0.0, 1.0, -2.5, 0.1, 1e300, -1e-300, f64::MAX] {
            assert_eq!(ext(x).to_f64().map(f64::to_bits), Some(x.to_bits()));
        }
        assert_eq!(ext(5e-324).to_f64(), None);
    }

    #[test]
    fn arithmetic_is_exact_where_doubles_are() {
        assert_eq!(ext(3.0).mul(ext(0.5)).to_f64(), Some(1.5));
        assert_eq!(ext(3.0).sub(ext(5.0)).to_f64(), Some(-2.0));
        assert_eq!(ext(1.0).div(ext(4.0)).to_f64(), Some(0.25));
        assert_eq!(ext(-2.5).floor().to_f64(), Some(-3.0));
        assert_eq!(ext(2.5).floor().to_f64(), Some(2.0));
        assert_eq!(ext(-0.25).floor().to_f64(), Some(-1.0));
        assert_eq!(ext(0.25).floor().to_f64(), Some(0.0));
    }

    #[test]
    fn keeps_extended_precision() {
        // 1 + 2^-60 is representable in extended precision but not as a
        // double; subtracting 1 recovers 2^-60.
        let tiny = 2f64.powi(-60);
        assert_eq!(ext(1.0).add(ext(tiny)).sub(ext(1.0)).to_f64(), Some(tiny));
        // 1 + 2^-64 rounds to even (1); 1 + 3 * 2^-65 rounds up.
        assert_eq!(ext(1.0).add(ext(2f64.powi(-64))).sub(ext(1.0)).to_f64(), Some(0.0));
        assert_eq!(ext(1.0).add(ext(3.0 * 2f64.powi(-65))).sub(ext(1.0)).to_f64(), Some(2f64.powi(-63)));
        // 1/3 to 64 bits, times 3, is 1 - 2^-64 (exactly representable).
        let third = ext(1.0).div(ext(3.0));
        assert_eq!(third.man, 0xAAAA_AAAA_AAAA_AAAB);
    }

    #[test]
    fn matches_r_mod() {
        // Values from R 4.6.1.
        assert_eq!(r_mod(0.3, 0.1), Some(0.09999999999999997780));
        assert_eq!(r_mod(5.0, 3.0), Some(2.0));
        assert_eq!(r_mod(-5.0, 3.0), Some(1.0));
        assert_eq!(r_mod(0.0, 0.1), Some(0.0));
        assert_eq!(r_mod(1e20, 1.0), None);
        assert!(r_mod_warns(1e20, 1.0) && !r_mod_warns(5e15, 0.7));
        // No warning below 2^63.
        assert_eq!(r_mod(5e15, 0.7), Some(0.21728515625));
    }
}
