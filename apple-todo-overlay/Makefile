SCHEME   = apple-todo-overlay
APP      = build/Debug/apple-todo-overlay.app
SYMROOT  = $(CURDIR)/build

.PHONY: build run clean kill

build:
	xcodebuild -scheme $(SCHEME) SYMROOT=$(SYMROOT) build | xcpretty 2>/dev/null || xcodebuild -scheme $(SCHEME) SYMROOT=$(SYMROOT) build

run: build
	open $(APP)

kill:
	pkill -x apple-todo-overlay 2>/dev/null || true

clean:
	rm -rf build
