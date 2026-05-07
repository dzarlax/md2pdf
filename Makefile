.PHONY: build install uninstall release

BUILD_DIR := target/release
INSTALL_DIR := $(HOME)/.local/bin
SERVICES_DIR := $(HOME)/Library/Services

build:
	cargo build --release

install: build
	@bash install.sh

release:
	@bash release.sh

uninstall:
	rm -f $(INSTALL_DIR)/md2pdf
	rm -f $(INSTALL_DIR)/typst
	rm -rf "$(SERVICES_DIR)/Convert to PDF.workflow"
	rm -rf "/Applications/md2pdf Helper.app"
	-/System/Library/CoreServices/pbs -update 2>/dev/null
	@echo "Uninstalled."
