BINARY = cache-ttl

.PHONY: build clean

build:
	cargo build --release
	cp target/release/$(BINARY) .

clean:
	cargo clean
	rm -f $(BINARY)
