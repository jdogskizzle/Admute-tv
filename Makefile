# Shortcuts for building on a Mac. See README.md for the full steps.
PROJECT = AdmuteTV.xcodeproj
SCHEME  = AdmuteTV
SIM    ?= Apple TV 4K (3rd generation)

.PHONY: project open build sim clean

project:            ## generate the Xcode project from project.yml
	xcodegen generate

open: project       ## generate and open in Xcode
	open $(PROJECT)

build: project      ## compile for the simulator, no signing needed
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration Debug \
		-destination 'generic/platform=tvOS Simulator' CODE_SIGNING_ALLOWED=NO build

sim: project        ## build, install and launch on a simulator ($(SIM))
	xcrun simctl boot "$(SIM)" 2>/dev/null || true
	open -a Simulator
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration Debug \
		-destination 'platform=tvOS Simulator,name=$(SIM)' -derivedDataPath build CODE_SIGNING_ALLOWED=NO build
	xcrun simctl install booted build/Build/Products/Debug-appletvsimulator/AdmuteTV.app
	xcrun simctl launch booted com.example.admute.tv

clean:
	rm -rf build $(PROJECT)
