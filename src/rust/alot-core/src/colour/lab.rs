//! sRGB <-> XYZ <-> CIE Lab, as farver's `XyzConverter` and `LabConverter`
//! (`src/Conversion.cpp`). RGB channels run 0..255, XYZ 0..100.

/// A white reference: the XYZ tristimulus of farver's `as_white_ref()`.
pub type White = [f64; 3];

/// `farver::as_white_ref("D65")`, computed in R from the chromaticity
/// `c(0.31271, 0.32902)`. Not farver's C++ default (95.047, 100, 108.883),
/// which its R functions always override.
pub const D65: White = [
    f64::from_bits(0x4057_c2be_20f5_7eff),
    f64::from_bits(0x4059_0000_0000_0000),
    f64::from_bits(0x405b_38f6_5e15_817f),
];

fn finite(v: [f64; 3]) -> bool {
    v.iter().all(|x| x.is_finite())
}

/// `XyzConverter::ToColorSpace`.
pub fn rgb_to_xyz([r, g, b]: [f64; 3]) -> [f64; 3] {
    let lin = |c: f64| {
        let c = c / 255.0;
        (if c > 0.04045 { ((c + 0.055) / 1.055).powf(2.4) } else { c / 12.92 }) * 100.0
    };
    let (r, g, b) = (lin(r), lin(g), lin(b));
    [
        r * 0.4124564 + g * 0.3575761 + b * 0.1804375,
        r * 0.2126729 + g * 0.7151522 + b * 0.0721750,
        r * 0.0193339 + g * 0.1191920 + b * 0.9503041,
    ]
}

/// `XyzConverter::ToColor`. `None` if the XYZ colour is invalid (not all
/// finite, as the `Xyz` constructor checks); the RGB result itself may be
/// non-finite.
pub fn xyz_to_rgb(xyz: [f64; 3]) -> Option<[f64; 3]> {
    if !finite(xyz) {
        return None;
    }
    let [x, y, z] = xyz.map(|v| v / 100.0);
    let r = x * 3.2404542 + y * -1.5371385 + z * -0.4985314;
    let g = x * -0.9692660 + y * 1.8760108 + z * 0.0415560;
    let b = x * 0.0556434 + y * -0.2040259 + z * 1.0572252;
    let gamma = |c: f64| (if c > 0.0031308 { 1.055 * c.powf(1.0 / 2.4) - 0.055 } else { 12.92 * c }) * 255.0;
    Some([gamma(r), gamma(g), gamma(b)])
}

/// `LabConverter::ToColorSpace`, with no cap on L: the path of
/// `decode_colour(to = "lab")`. `None` for a non-finite RGB channel.
pub fn rgb_to_lab(rgb: [f64; 3], white: &White) -> Option<[f64; 3]> {
    if !finite(rgb) {
        return None;
    }
    let [x, y, z] = rgb_to_xyz(rgb);
    let f = |t: f64| if t > 0.008856 { t.cbrt() } else { 7.787 * t + 16.0 / 116.0 };
    let x = f(x / white[0]);
    let y = f(y / white[1]);
    let z = f(z / white[2]);
    Some([(116.0 * y) - 16.0, 500.0 * (x - y), 200.0 * (y - z)])
}

/// `Lab::Cap`: L into [0, 100]; a and b are left alone.
pub fn cap_lab([l, a, b]: [f64; 3]) -> [f64; 3] {
    [if l < 0.0 { 0.0 } else if l > 100.0 { 100.0 } else { l }, a, b]
}

/// `fill_rgb<Lab>`: the Lab colour is capped, then `LabConverter::ToColor`.
/// `None` where farver's RGB is invalid (encoded as NA).
pub fn lab_to_rgb(lab: [f64; 3], white: &White) -> Option<[f64; 3]> {
    if !finite(lab) {
        return None;
    }
    let [l, a, b] = cap_lab(lab);
    let y = (l + 16.0) / 116.0;
    let x = a / 500.0 + y;
    let z = y - b / 200.0;
    let f = |t: f64| {
        let t3 = t * t * t;
        if t3 > 0.008856 { t3 } else { (t - 16.0 / 116.0) / 7.787 }
    };
    xyz_to_rgb([f(x) * white[0], f(y) * white[1], f(z) * white[2]])
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn d65_matches_as_white_ref() {
        // as_white_ref(): tmp <- 100 / y; c(tmp * x, 100, tmp * (1 - sum(x)))
        let (x, y) = (0.31271_f64, 0.32902_f64);
        let tmp = 100.0 / y;
        assert_eq!(D65, [tmp * x, 100.0, tmp * (1.0 - (x + y))]);
    }

    #[test]
    fn invalid_input() {
        assert_eq!(lab_to_rgb([f64::NAN, 0.0, 0.0], &D65), None);
        assert_eq!(lab_to_rgb([50.0, f64::INFINITY, 0.0], &D65), None);
        assert_eq!(rgb_to_lab([0.0, f64::NAN, 0.0], &D65), None);
        // Finite Lab whose XYZ overflows is invalid too.
        assert_eq!(lab_to_rgb([50.0, 1e300, 0.0], &D65), None);
    }

    #[test]
    fn white_and_black() {
        // White's Y is 100 * 1.0000001, so L is just over 100 before capping.
        let [l, _, _] = rgb_to_lab([255.0; 3], &D65).unwrap();
        assert!(l > 100.0 && l < 100.001);
        assert_eq!(cap_lab([l, 1.0, 2.0]), [100.0, 1.0, 2.0]);
        assert_eq!(rgb_to_lab([0.0; 3], &D65), Some([0.0, 0.0, 0.0]));
        assert_eq!(lab_to_rgb([-5.0, 0.0, 0.0], &D65), Some([0.0, 0.0, 0.0]));
    }

    #[test]
    fn round_trip_is_close() {
        for rgb in [[12.0, 200.0, 99.0], [255.0, 0.0, 0.0], [1.0, 2.0, 3.0]] {
            let back = lab_to_rgb(rgb_to_lab(rgb, &D65).unwrap(), &D65).unwrap();
            for (a, b) in rgb.iter().zip(back) {
                assert!((a - b).abs() < 1e-3, "{rgb:?} -> {back:?}");
            }
        }
    }
}
