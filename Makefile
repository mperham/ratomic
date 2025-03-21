
rust:
	cd rs && \
	cargo test && \
	cargo build --release && \
	cbindgen --output rust-atomics.h

clean:
	rm -rf tmp rs/target