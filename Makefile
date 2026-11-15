PREFIX ?= $(HOME)/.local
BIN = $(PREFIX)/bin/hyperkey
LABEL = com.drosam.hyperkey
PLIST = $(HOME)/Library/LaunchAgents/$(LABEL).plist
LOG = $(HOME)/Library/Logs/hyperkey.log
UID := $(shell id -u)

BUILD = build
SOURCES = main.swift HyperKeyState.swift

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

build: hyperkey

hyperkey: $(SOURCES)
	swiftc -O $(SOURCES) -o hyperkey

test:
	@mkdir -p $(BUILD)
	swiftc HyperKeyState.swift Tests/main.swift -o $(BUILD)/tests
	$(BUILD)/tests

install: hyperkey
	-launchctl bootout gui/$(UID)/$(LABEL) 2>/dev/null
	mkdir -p $(PREFIX)/bin $(HOME)/Library/LaunchAgents $(HOME)/Library/Logs
	install hyperkey $(BIN)
	xattr -c $(BIN)
	echo "$$PLIST_CONTENT" > $(PLIST)
	launchctl bootstrap gui/$(UID) $(PLIST)
	@echo "If you rebuilt the binary, toggle hyperkey off then on in the screen opening now."
	open "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"

uninstall:
	-launchctl bootout gui/$(UID)/$(LABEL) 2>/dev/null
	rm -f $(BIN) $(PLIST)
	hidutil property --set '{"UserKeyMapping":[]}' >/dev/null

clean:
	rm -rf $(BUILD) hyperkey

.PHONY: build test install uninstall clean
