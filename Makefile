APP      := CodexUsage
LABEL    := com.codexusage.widget
PREFIX   ?= $(HOME)/.local
BINDIR   := $(PREFIX)/bin
AGENT    := $(HOME)/Library/LaunchAgents/$(LABEL).plist
UID      := $(shell id -u)

.PHONY: build run install uninstall clean

build:
	swiftc -O $(APP).swift -o $(APP)

run: build
	./$(APP)

install: build
	mkdir -p $(BINDIR)
	install -m 755 $(APP) $(BINDIR)/$(APP)
	sed -e 's|@BINARY@|$(BINDIR)/$(APP)|g' -e 's|@LABEL@|$(LABEL)|g' \
		launchagent.plist.template > $(AGENT)
	-launchctl bootout gui/$(UID)/$(LABEL) 2>/dev/null
	launchctl bootstrap gui/$(UID) $(AGENT)
	@echo "Installed. Widget is running and will start at login."

uninstall:
	-launchctl bootout gui/$(UID)/$(LABEL) 2>/dev/null
	rm -f $(AGENT) $(BINDIR)/$(APP)
	@echo "Uninstalled."

clean:
	rm -f $(APP)
