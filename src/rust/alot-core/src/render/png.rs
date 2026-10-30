//! PNG encoding for rendered pages. ragg's PNG writer (libpng at its
//! default zlib level) costs more than drawing a busy plot, so `alot_png()`
//! draws on a capture device and encodes here with fdeflate's fast mode.

/// Encodes nativeRaster pixels (`R | G << 8 | B << 16 | A << 24`, row-major
/// from the top-left) as an 8-bit PNG: RGB if every pixel is opaque, else
/// RGBA.
pub fn encode(width: u32, height: u32, pixels: &[u32]) -> Result<Vec<u8>, png::EncodingError> {
    let opaque = pixels.iter().all(|&p| p >> 24 == 0xFF);
    let data: Vec<u8> = if opaque {
        pixels.iter().flat_map(|&p| [p as u8, (p >> 8) as u8, (p >> 16) as u8]).collect()
    } else {
        pixels.iter().flat_map(|&p| p.to_le_bytes()).collect()
    };
    let mut out = Vec::new();
    {
        let mut enc = png::Encoder::new(&mut out, width, height);
        enc.set_color(if opaque { png::ColorType::Rgb } else { png::ColorType::Rgba });
        enc.set_depth(png::BitDepth::Eight);
        enc.set_compression(png::Compression::Fast);
        let mut writer = enc.write_header()?;
        writer.write_image_data(&data)?;
    }
    Ok(out)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn round_trips() {
        let px = [0xFF0000FFu32, 0xFF00FF00, 0xFFFF0000, 0xFFFFFFFF, 0xFF000000, 0xFF808080];
        let bytes = encode(3, 2, &px).unwrap();
        let mut reader = png::Decoder::new(&bytes[..]).read_info().unwrap();
        let mut buf = vec![0; reader.output_buffer_size()];
        let info = reader.next_frame(&mut buf).unwrap();
        assert_eq!(info.color_type, png::ColorType::Rgb);
        assert_eq!(&buf[..info.buffer_size()][..6], &[255, 0, 0, 0, 255, 0]);
    }
}
