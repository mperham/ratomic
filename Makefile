
rust:
	cd rs && \
	cargo test && \
	cargo build --release && \
	strip target/release/librust_atomics.{a,rlib} && \
	cbindgen --output rust-atomics.h

clean:
	rm -rf tmp rs/target