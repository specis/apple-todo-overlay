SCHEME      = apple-todo-overlay
APP         = build/Debug/apple-todo-overlay.app
RELEASE_APP = build/Release/apple-todo-overlay.app
SYMROOT     = $(CURDIR)/build
ICONSET     = apple-todo-overlay/Assets.xcassets/AppIcon.appiconset
DMG_NAME    = apple-todo-overlay.dmg
DMG_STAGING = build/dmg_staging
VERSION     = $(shell defaults read "$(CURDIR)/$(RELEASE_APP)/Contents/Info" CFBundleShortVersionString 2>/dev/null || echo "1.0")

.PHONY: build run icon release package dmg kill clean

build:
	xcodebuild -scheme $(SCHEME) SYMROOT=$(SYMROOT) build | xcpretty 2>/dev/null || \
	xcodebuild -scheme $(SCHEME) SYMROOT=$(SYMROOT) build

run: build
	$(APP)/Contents/MacOS/apple-todo-overlay

icon:
	swift Scripts/generate_icon.swift "$(CURDIR)/$(ICONSET)"

release: icon
	xcodebuild -scheme $(SCHEME) SYMROOT=$(SYMROOT) -configuration Release build | xcpretty 2>/dev/null || \
	xcodebuild -scheme $(SCHEME) SYMROOT=$(SYMROOT) -configuration Release build
	@echo "Release build: $(RELEASE_APP)"

package: release
	ditto -c -k --sequesterRsrc --keepParent "$(RELEASE_APP)" apple-todo-overlay.zip
	@echo "Packaged: apple-todo-overlay.zip"

# Creates a distributable DMG with a drag-to-Applications installer layout.
# Usage: make dmg
dmg: release
	@echo "Building DMG v$(VERSION)…"
	rm -rf "$(DMG_STAGING)"
	mkdir -p "$(DMG_STAGING)"
	# Copy the app bundle into the staging area
	cp -R "$(RELEASE_APP)" "$(DMG_STAGING)/apple-todo-overlay.app"
	# Add an Applications symlink so users can drag-install
	ln -s /Applications "$(DMG_STAGING)/Applications"
	# Remove any existing DMG
	rm -f "$(DMG_NAME)"
	# Build a compressed, internet-ready DMG
	hdiutil create \
		-volname "apple-todo-overlay $(VERSION)" \
		-srcfolder "$(DMG_STAGING)" \
		-ov \
		-format UDZO \
		-imagekey zlib-level=9 \
		"$(DMG_NAME)"
	rm -rf "$(DMG_STAGING)"
	@echo "DMG ready: $(DMG_NAME)"

kill:
	pkill -x apple-todo-overlay 2>/dev/null || true

clean:
	rm -rf build $(DMG_NAME)
