BINARY = cache-ttl
OS = $(shell uname -s | tr '[:upper:]' '[:lower:]')
ARCH = $(shell uname -m)
MUSL_TARGET = x86_64-unknown-linux-musl

.PHONY: build dist dist-linux clean

# Local build: binary lands at the plugin root, where the manifest expects it.
build:
	cargo build --release
	cp target/release/$(BINARY) .

# Release artifact for this host, committed to dist/ and picked up by [[build]].
dist:
	cargo build --release
	mkdir -p dist
	cp target/release/$(BINARY) dist/$(BINARY)-$(OS)-$(ARCH)

# Linux artifact is static musl so one binary serves every distro.
dist-linux:
	rustup target add $(MUSL_TARGET)
	cargo build --release --target $(MUSL_TARGET)
	mkdir -p dist
	cp target/$(MUSL_TARGET)/release/$(BINARY) dist/$(BINARY)-linux-x86_64

clean:
	cargo clean
	rm -f $(BINARY)
