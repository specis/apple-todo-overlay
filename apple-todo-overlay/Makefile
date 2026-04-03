SCHEME      = apple-todo-overlay
APP         = build/Debug/apple-todo-overlay.app
RELEASE_APP = build/Release/apple-todo-overlay.app
SYMROOT     = $(CURDIR)/build
ICONSET     = apple-todo-overlay/Assets.xcassets/AppIcon.appiconset

.PHONY: build run icon release package kill clean

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

kill:
	pkill -x apple-todo-overlay 2>/dev/null || true

clean:
	rm -rf build
