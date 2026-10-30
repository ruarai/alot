//! Colour encoding, ported from farver 2.1.2 (`src/ColorSpace.cpp`,
//! `src/Conversion.cpp`, `src/encode.cpp`), which `scales::colour_ramp()`
//! calls to decode its palette to Lab and encode interpolated Lab as hex.
//! The hex strings must match farver's byte for byte, so the arithmetic is
//! copied operation for operation. Lab -> RGB needs only `pow`, which both
//! sides take from the system libm, so encoding is exact. RGB -> Lab also
//! needs `cbrt`, which Rust links from its own `compiler_builtins` port
//! rather than glibc's, so decoded Lab can differ from farver's in the last
//! bits (well within 1e-8).

pub mod hex;
pub mod lab;
