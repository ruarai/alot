// Forward routine registration from C to Rust so the linker keeps the
// static library.

void R_init_alot_extendr(void *dll);
void register_extendr_panic_hook(void);

void R_init_alot(void *dll) {
    register_extendr_panic_hook();
    R_init_alot_extendr(dll);
}
