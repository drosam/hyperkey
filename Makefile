PREFIX ?= $(HOME)/.local
BIN = $(PREFIX)/bin/hyperkey
LABEL = com.drosam.hyperkey
PLIST = $(HOME)/Library/LaunchAgents/$(LABEL).plist
LOG = $(HOME)/Library/Logs/hyperkey.log
UID := $(shell id -u)

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

hyperkey: main.swift
	swiftc -O main.swift -o hyperkey

install: hyperkey
	-launchctl bootout gui/$(UID)/$(LABEL) 2>/dev/null
	mkdir -p $(PREFIX)/bin $(HOME)/Library/LaunchAgents $(HOME)/Library/Logs
	install hyperkey $(BIN)
	echo "$$PLIST_CONTENT" > $(PLIST)
	launchctl bootstrap gui/$(UID) $(PLIST)

uninstall:
	-launchctl bootout gui/$(UID)/$(LABEL) 2>/dev/null
	rm -f $(BIN) $(PLIST)
	hidutil property --set '{"UserKeyMapping":[]}' >/dev/null

clean:
	rm -f hyperkey

.PHONY: build install uninstall clean
