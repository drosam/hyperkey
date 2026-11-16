PREFIX ?= $(HOME)/.local
BIN = $(PREFIX)/bin/hyperkey
LABEL = com.drosam.hyperkey
BREW_LABEL = homebrew.mxcl.hyperkey
PLIST = $(HOME)/Library/LaunchAgents/$(LABEL).plist
LOG = $(HOME)/Library/Logs/hyperkey.log
UID := $(shell id -u)

VERSION ?= $(shell git describe --tags --always --dirty 2>/dev/null || echo dev)
MACOS_MIN ?= 13.0
ARCH ?= $(shell uname -m)
ARCHS = arm64 x86_64
# Self-signed keychain cert name; keeps Accessibility across rebuilds. "-" forces ad-hoc.
SIGN_ID ?= hyperkey-dev

BUILD = build
SOURCES = main.swift HyperKeyState.swift
SWIFTFLAGS = -O
DIST_NAME = hyperkey-$(VERSION)
DIST_ZIP = $(BUILD)/$(DIST_NAME).zip

define PLIST_CONTENT
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>Label</key>
	<string>$(LABEL)</string>
	<key>ProgramArguments</key>
	<array>
		<string>$(BIN)</string>
	</array>
	<key>RunAtLoad</key>
	<true/>
	<key>KeepAlive</key>
	<dict>
		<key>SuccessfulExit</key>
		<false/>
	</dict>
	<key>StandardOutPath</key>
	<string>$(LOG)</string>
	<key>StandardErrorPath</key>
	<string>$(LOG)</string>
</dict>
</plist>
endef
export PLIST_CONTENT

define sign
	@if [ "$(SIGN_ID)" != "-" ] && security find-identity -p codesigning | grep -qF "\"$(SIGN_ID)\""; then \
		codesign --force --sign "$(SIGN_ID)" --options runtime --identifier $(LABEL) $(1) && \
		echo "signed with $(SIGN_ID): Accessibility survives rebuilds"; \
	else \
		codesign --force --sign - --options runtime --identifier $(LABEL) $(1) && \
		echo "ad-hoc signed: Accessibility must be re-granted after each rebuild (see CONTRIBUTING.md)"; \
	fi
endef

build: $(BUILD)/hyperkey

$(BUILD)/Version.swift: FORCE
	@mkdir -p $(BUILD)
	@echo 'let hyperkeyVersion = "$(VERSION)"' > $@.tmp
	@if cmp -s $@.tmp $@; then rm $@.tmp; else mv $@.tmp $@; fi

# Unsigned per-architecture slices; static pattern so it never matches the dist zip.
$(addprefix $(BUILD)/hyperkey-,$(ARCHS)): $(BUILD)/hyperkey-%: $(SOURCES) $(BUILD)/Version.swift
	swiftc $(SWIFTFLAGS) -target $*-apple-macos$(MACOS_MIN) $(SOURCES) $(BUILD)/Version.swift -o $@

$(BUILD)/hyperkey: $(BUILD)/hyperkey-$(ARCH)
	cp $< $@
	$(call sign,$@)

universal: $(addprefix $(BUILD)/hyperkey-,$(ARCHS))
	lipo -create -output $(BUILD)/hyperkey $^
	$(call sign,$(BUILD)/hyperkey)

test:
	@mkdir -p $(BUILD)
	swiftc -target $(ARCH)-apple-macos$(MACOS_MIN) HyperKeyState.swift Tests/main.swift -o $(BUILD)/tests
	$(BUILD)/tests

dist: universal
	rm -rf $(BUILD)/$(DIST_NAME) $(DIST_ZIP) $(BUILD)/SHA256SUMS.txt
	mkdir -p $(BUILD)/$(DIST_NAME)
	cp $(BUILD)/hyperkey LICENSE README.md $(BUILD)/$(DIST_NAME)/
	ditto -c -k --norsrc --noextattr --noqtn --keepParent $(BUILD)/$(DIST_NAME) $(DIST_ZIP)
	cd $(BUILD) && shasum -a 256 $(DIST_NAME).zip > SHA256SUMS.txt

# Release checks, run by CI and before tagging: make dist verify VERSION=X.Y.Z
verify:
	@archs="$$(lipo -archs $(BUILD)/hyperkey)"; \
	for required in $(ARCHS); do \
		echo "$$archs" | grep -qw "$$required" || { echo "error: missing $$required slice (have: $$archs)"; exit 1; }; \
	done
	codesign --verify --strict --verbose $(BUILD)/hyperkey
	@codesign -d -vv $(BUILD)/hyperkey 2>&1 | grep -q 'flags=.*runtime' || { echo "error: hardened runtime missing"; exit 1; }
	test "$$($(BUILD)/hyperkey --version)" = "hyperkey $(VERSION)"
	cd $(BUILD) && shasum -a 256 -c SHA256SUMS.txt

install: $(BUILD)/hyperkey
	@if launchctl print gui/$(UID)/$(BREW_LABEL) >/dev/null 2>&1; then \
		echo "error: hyperkey is running via brew services; run 'brew services stop hyperkey' first"; \
		exit 1; \
	fi
	-launchctl bootout gui/$(UID)/$(LABEL) 2>/dev/null
	mkdir -p $(PREFIX)/bin $(HOME)/Library/LaunchAgents $(HOME)/Library/Logs
	install $(BUILD)/hyperkey $(BIN)
	xattr -c $(BIN)
	echo "$$PLIST_CONTENT" > $(PLIST)
	launchctl bootstrap gui/$(UID) $(PLIST)
	@echo "If hyperkey does not react after an ad-hoc rebuild, toggle it off and on in the screen opening now."
	open "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"

uninstall:
	-launchctl bootout gui/$(UID)/$(LABEL) 2>/dev/null
	@# Old binaries ignore unknown flags and would start, so check --help first.
	@if [ -x $(BIN) ] && $(BIN) --help | grep -q -- --clear-remap; then \
		$(BIN) --clear-remap; \
	else \
		hidutil property --set '{"UserKeyMapping":[]}' >/dev/null; \
	fi
	rm -f $(BIN) $(PLIST)

clean:
	rm -rf $(BUILD) hyperkey

FORCE:

.PHONY: build universal test dist verify install uninstall clean FORCE
