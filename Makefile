
rust:
	cd rs && \
	cargo test && \
	cargo build --release

bindgen:
	cd rs && \
	cbindgen --output rust-atomics.h

clean:
	rm -rf tmp rs/target
