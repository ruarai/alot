//! Colour strings as farver's `decode_colour()` reads them (farver 2.1.2
//! `src/decode.cpp`), which `scales::alpha()` and so ggplot2's
//! `alpha()`/`fill_alpha()` use: hex (`#RGB`, `#RGBA`, `#RRGGBB`,
//! `#RRGGBBAA`, either case), R's colour names ignoring case and spaces,
//! `"transparent"`, and `"NA"`. farver reads numeric strings as indices into
//! its own fixed palette; those decline here, as do strings farver rejects.

use super::names::NAMES;

/// A decoded colour.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Colour {
    /// Non-premultiplied RGBA bytes.
    Rgba([u8; 4]),
    /// `NA`: `alpha()` keeps it NA, and it draws nothing.
    Na,
}

/// Decodes a colour string, or `None` (decline) for numeric palette
/// indices and anything farver would reject.
pub fn parse_colour(s: &[u8]) -> Option<Colour> {
    if s == b"NA" {
        return Some(Colour::Na);
    }
    if s.first() == Some(&b'#') {
        let digit = |c: u8| (c as char).to_digit(16).map(|d| d as u8);
        let d: Vec<u8> = s[1..].iter().map(|&c| digit(c)).collect::<Option<_>>()?;
        let rgba = match d.len() {
            3 | 4 => {
                let mut v = [255u8; 4];
                for (k, &x) in d.iter().enumerate() {
                    v[k] = x * 17;
                }
                v
            }
            6 | 8 => {
                let mut v = [255u8; 4];
                for k in 0..d.len() / 2 {
                    v[k] = d[2 * k] << 4 | d[2 * k + 1];
                }
                v
            }
            _ => return None,
        };
        return Some(Colour::Rgba(rgba));
    }
    let name: Vec<u8> = s.iter().filter(|&&c| c != b' ').map(|c| c.to_ascii_lowercase()).collect();
    if name.first().map_or(true, |c| c.is_ascii_digit()) {
        return None;
    }
    if name == b"transparent" {
        return Some(Colour::Rgba([255, 255, 255, 0]));
    }
    let i = NAMES.binary_search_by(|(n, _)| (*n).cmp(&name[..])).ok()?;
    let [r, g, b] = NAMES[i].1;
    Some(Colour::Rgba([r, g, b, 255]))
}

#[cfg(test)]
mod tests {
    use super::*;

    fn rgba(s: &str) -> Option<[u8; 4]> {
        match parse_colour(s.as_bytes())? {
            Colour::Rgba(v) => Some(v),
            Colour::Na => None,
        }
    }

    #[test]
    fn parses_hex_names_and_na() {
        assert_eq!(rgba("#440154"), Some([0x44, 0x01, 0x54, 255]));
        assert_eq!(rgba("#fde7254c"), Some([0xFD, 0xE7, 0x25, 0x4C]));
        assert_eq!(rgba("#aBc"), Some([0xAA, 0xBB, 0xCC, 255]));
        assert_eq!(rgba("#abcd"), Some([0xAA, 0xBB, 0xCC, 0xDD]));
        assert_eq!(rgba("Light Blue"), Some([173, 216, 230, 255]));
        assert_eq!(rgba("grey50"), Some([127, 127, 127, 255]));
        assert_eq!(rgba("aliceblue"), Some([240, 248, 255, 255]));
        assert_eq!(rgba("yellowgreen"), Some([154, 205, 50, 255]));
        assert_eq!(rgba("Transparent "), Some([255, 255, 255, 0]));
        assert_eq!(parse_colour(b"NA"), Some(Colour::Na));
    }

    #[test]
    fn declines_what_farver_rejects_or_indexes() {
        for s in ["#12345G", "#a", "#abcde", "#ABC ", "bogus", "", "1", "0", "1.5", "na", "NA ", "light\tblue"] {
            assert_eq!(parse_colour(s.as_bytes()), None, "{s:?}");
        }
    }
}
