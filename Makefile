APP_NAME := DiscScanner
BUILD_DIR := .build/release
APP_BUNDLE := build/$(APP_NAME).app

.PHONY: build test app run clean

build:
	swift build -c release

test:
	swift test

# The string tables go into the MAIN bundle: that is where macOS looks when
# it picks the app's language, and where the app reads them from. The
# SwiftPM resource bundle is copied unconditionally — a build missing it
# used to be skipped silently and shipped an app that crashed on first view.
app: build
	rm -rf $(APP_BUNDLE)
	mkdir -p $(APP_BUNDLE)/Contents/MacOS $(APP_BUNDLE)/Contents/Resources
	cp Resources/Info.plist $(APP_BUNDLE)/Contents/Info.plist
	cp Resources/AppIcon.icns $(APP_BUNDLE)/Contents/Resources/AppIcon.icns
	cp $(BUILD_DIR)/$(APP_NAME) $(APP_BUNDLE)/Contents/MacOS/$(APP_NAME)
	cp -R Sources/$(APP_NAME)/Resources/en.lproj Sources/$(APP_NAME)/Resources/de.lproj \
		$(APP_BUNDLE)/Contents/Resources/
	cp -R "$(BUILD_DIR)/$(APP_NAME)_$(APP_NAME).bundle" $(APP_BUNDLE)/Contents/Resources/
	codesign --force --sign - $(APP_BUNDLE)
	@echo "Built $(APP_BUNDLE)"

run: app
	open $(APP_BUNDLE)

clean:
	rm -rf .build build
