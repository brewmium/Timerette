.PHONY: build run clean install uninstall test

APP_NAME = Timerette
TARGET = timerette
BUILD_DIR = .build/release
APP_BUNDLE = $(APP_NAME).app

build:
	swift build -c release
	mkdir -p "$(APP_BUNDLE)/Contents/MacOS"
	mkdir -p "$(APP_BUNDLE)/Contents/Resources"
	cp "$(BUILD_DIR)/$(TARGET)" "$(APP_BUNDLE)/Contents/MacOS/$(APP_NAME)"
	cp "Resources/Info.plist" "$(APP_BUNDLE)/Contents/"
	codesign --force --sign - "$(APP_BUNDLE)"

run: build
	open "$(APP_BUNDLE)"

test:
	swift test

clean:
	swift package clean
	rm -rf "$(APP_BUNDLE)"

install: build
	cp -r "$(APP_BUNDLE)" /Applications/

uninstall:
	rm -rf "/Applications/$(APP_BUNDLE)"
