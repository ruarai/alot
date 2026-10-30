//! `#RRGGBB(AA)` encoding, as farver's `encode_colour()`: the R wrapper
//! (`R/encode.R`, `encode_c`) and `encode_impl` (`src/encode.cpp`).

use super::lab::{self, White};

const HEX: &[u8; 16] = b"0123456789ABCDEF";

/// farver's `double2int` on little-endian machines: add 1.5 * 2^52 and keep
/// the low 32 bits. Rounds half to even for |d| < 2^31; anything else
/// (large values, infinities) gives whatever those bits hold. NaN keeps its
/// low word, as the x86 addition propagates the NaN operand, so `NA_real_`
/// gives 1954 and R's `NaN` 0.
pub fn double2int(d: f64) -> i32 {
    let bits = if d.is_nan() { d.to_bits() } else { (d + 6755399441055744.0).to_bits() };
    bits as u32 as i32
}

fn cap0255(x: i32) -> u8 {
    x.clamp(0, 255) as u8
}

/// An encoded colour: `#RRGGBB` or `#RRGGBBAA`.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct Hex {
    buf: [u8; 9],
    len: u8,
}

impl Hex {
    pub fn as_str(&self) -> &str {
        std::str::from_utf8(&self.buf[..self.len as usize]).unwrap()
    }
}

/// Hex for RGB doubles (0..255), each channel through `double2int` and
/// capped, with an optional alpha byte.
pub fn encode_rgb(rgb: [f64; 3], alpha: Option<u8>) -> Hex {
    let mut buf = [b'#'; 9];
    let mut put = |i: usize, v: u8| {
        buf[i] = HEX[(v >> 4) as usize];
        buf[i + 1] = HEX[(v & 15) as usize];
    };
    for (k, c) in rgb.into_iter().enumerate() {
        put(1 + 2 * k, cap0255(double2int(c)));
    }
    let len = match alpha {
        Some(a) => {
            put(7, a);
            9
        }
        None => 7,
    };
    Hex { buf, len }
}

/// The `alpha` argument of `encode_colour()`, as its R wrapper resolves it.
/// Alpha values are on the 0..1 scale; the wrapper multiplies by 255.
#[derive(Clone, Copy, Debug)]
pub enum Alpha<'a> {
    /// No suffix: `alpha` is `NULL` or empty, or a single value that is NA
    /// or whose `alpha * 255` is 1 (so `alpha = 1 / 255` drops the suffix
    /// while `alpha = 1` gives `FF`).
    None,
    /// A single value: this byte is appended to every colour, `FF`
    /// included.
    Fixed(u8),
    /// Several values, recycled over the rows (`rep_len()`). A row whose
    /// byte is 255 gets no suffix.
    Rows(&'a [f64]),
}

impl<'a> Alpha<'a> {
    pub fn new(alpha: Option<&'a [f64]>) -> Self {
        match alpha {
            None | Some([]) => Alpha::None,
            Some(&[a]) => {
                let a = a * 255.0;
                if a.is_nan() || a == 1.0 {
                    Alpha::None
                } else {
                    // `R_finite()` fails only for Inf here; NaN went above.
                    Alpha::Fixed(if a.is_finite() { cap0255(double2int(a)) } else { 255 })
                }
            }
            Some(v) => Alpha::Rows(v),
        }
    }

    /// The alpha byte for row `i`, `None` for no suffix.
    pub fn byte(&self, i: usize) -> Option<u8> {
        match *self {
            Alpha::None => None,
            Alpha::Fixed(a) => Some(a),
            Alpha::Rows(v) => {
                let a = v[i % v.len()];
                // `alpha * 255` in R; a NaN keeps its payload, so NA stays NA.
                let a = if a.is_nan() { a } else { a * 255.0 };
                Some(cap0255(double2int(a))).filter(|&a| a != 255)
            }
        }
    }
}

/// `encode_colour(lab, alpha, from = "lab", white)` for row `i`; `None`
/// is NA.
pub fn encode_lab(lab: [f64; 3], alpha: &Alpha, i: usize, white: &White) -> Option<Hex> {
    lab::lab_to_rgb(lab, white).map(|rgb| encode_rgb(rgb, alpha.byte(i)))
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::colour::lab::D65;

    const NA_REAL: f64 = f64::from_bits(0x7FF0_0000_0000_07A2);

    fn enc(lab: [f64; 3], alpha: &Alpha, i: usize) -> Option<String> {
        encode_lab(lab, alpha, i, &D65).map(|h| h.as_str().to_string())
    }

    #[test]
    fn double2int_rounds_half_to_even() {
        let got: Vec<i32> = [0.5, 1.5, 2.5, -0.5, -1.5, 254.5, 255.49].map(double2int).to_vec();
        assert_eq!(got, [0, 2, 2, 0, -2, 254, 255]);
        assert_eq!(double2int(f64::INFINITY), 0);
        assert_eq!(double2int(f64::NEG_INFINITY), 0);
        assert_eq!(double2int(NA_REAL), 1954);
        assert_eq!(double2int(f64::NAN), 0);
    }

    // Expected strings from farver 2.1.2.
    #[test]
    fn matches_farver() {
        let lab = [50.0, 10.0, -10.0];
        assert_eq!(enc(lab, &Alpha::new(None), 0).as_deref(), Some("#807288"));
        assert_eq!(enc(lab, &Alpha::new(Some(&[1.0])), 0).as_deref(), Some("#807288FF"));
        assert_eq!(enc(lab, &Alpha::new(Some(&[1.0 / 255.0])), 0).as_deref(), Some("#807288"));
        let rows = [NA_REAL, f64::NAN, 1.0];
        let a = Alpha::new(Some(&rows));
        let got: Vec<_> = (0..3).map(|i| enc(lab, &a, i).unwrap()).collect();
        assert_eq!(got, ["#807288", "#80728800", "#807288"]);
        assert_eq!(enc([50.0, 1e100, 0.0], &Alpha::None, 0).as_deref(), Some("#00FF00"));
        assert_eq!(enc([50.0, 1e300, 0.0], &Alpha::None, 0), None);
        assert_eq!(enc([f64::NAN, 0.0, 0.0], &Alpha::Fixed(0), 0), None);
    }

    #[test]
    fn alpha_rules() {
        assert!(matches!(Alpha::new(Some(&[])), Alpha::None));
        assert!(matches!(Alpha::new(Some(&[NA_REAL])), Alpha::None));
        assert!(matches!(Alpha::new(Some(&[f64::INFINITY])), Alpha::Fixed(255)));
        assert!(matches!(Alpha::new(Some(&[0.5])), Alpha::Fixed(128)));
        let rows = [0.0, 0.5];
        let a = Alpha::new(Some(&rows));
        assert_eq!((0..4).map(|i| a.byte(i)).collect::<Vec<_>>(), [Some(0), Some(128), Some(0), Some(128)]);
    }

    #[test]
    fn rgb_hex() {
        assert_eq!(encode_rgb([0.0, 255.0, 300.0], None).as_str(), "#00FFFF");
        assert_eq!(encode_rgb([-3.0, 10.5, 11.5], Some(0x0A)).as_str(), "#000A0C0A");
    }
}

/// Parses `#RRGGBB` or `#RRGGBBAA` (either case) to RGBA bytes, alpha 255
/// when absent. `None` for anything else, such as colour names.
pub fn parse_hex(s: &[u8]) -> Option<[u8; 4]> {
    let digit = |c: u8| (c as char).to_digit(16).map(|d| d as u8);
    let byte = |i: usize| Some(digit(s[i])? << 4 | digit(s[i + 1])?);
    match s {
        [b'#', ..] if s.len() == 7 => Some([byte(1)?, byte(3)?, byte(5)?, 255]),
        [b'#', ..] if s.len() == 9 => Some([byte(1)?, byte(3)?, byte(5)?, byte(7)?]),
        _ => None,
    }
}

#[cfg(test)]
mod parse_tests {
    use super::*;

    #[test]
    fn parses_hex_with_and_without_alpha() {
        assert_eq!(parse_hex(b"#440154"), Some([0x44, 0x01, 0x54, 255]));
        assert_eq!(parse_hex(b"#fde7254c"), Some([0xFD, 0xE7, 0x25, 0x4C]));
        assert_eq!(parse_hex(b"black"), None);
        assert_eq!(parse_hex(b"#12345G"), None);
    }
}
