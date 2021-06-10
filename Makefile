help:
	@echo "Usage: make <target>\n\n\
Choose one of the following targets to generate:\n\
  spm\t\t(recommended) Integration with Swift Package Manager\n\
  spm+lcp\t(recommended) Integration with Swift Package Manager and Readium LCP\n\
  carthage\tIntegration with Carthage\n\
  carthage+lcp\tIntegration with Carthage and Readium LCP\n\
  cocoapods\tIntegration with CocoaPods and Readium LCP\n\
  cocoapods+lcp\tIntegration with CocoaPods and Readium LCP\n\
  submodules\tIntegration with Git submodules and SPM, for contributors\n\
"

clean:
	@rm -f project.yml
	@rm -f Podfile*
	@rm -f Cartfile*
	@rm -rf Carthage
	@rm -rf Pods
	@rm -rf R2TestApp.xcodeproj
	@rm -rf R2TestApp.xcworkspace

spm: clean
	cp Integrations/SPM/project.yml .
	xcodegen generate
	open R2TestApp.xcodeproj

spm+lcp: LCP_URL = $(shell read -p "Enter the liblcp Carthage URL you received from EDRLab: " url; echo $$url)
spm+lcp: clean
	@echo "binary \"${LCP_URL}\"" > Cartfile
	carthage update --platform ios --cache-builds
	@cp Integrations/SPM/project+lcp.yml project.yml
	xcodegen generate
	open R2TestApp.xcodeproj

carthage: clean
	@cp Integrations/Carthage/project.yml .
	@cp Integrations/Carthage/Cartfile .
	carthage update --platform ios --use-xcframeworks --cache-builds
	xcodegen generate
	open R2TestApp.xcodeproj

carthage+lcp: LCP_URL = $(shell read -p "Enter the liblcp Carthage URL you received from EDRLab: " url; echo $$url)
carthage+lcp: clean
	@cp Integrations/Carthage/project+lcp.yml project.yml
	@cp Integrations/Carthage/Cartfile+lcp Cartfile
	@echo "binary \"${LCP_URL}\"" >> Cartfile
	carthage update --platform ios --use-xcframeworks --cache-builds
	xcodegen generate
	open R2TestApp.xcodeproj

cocoapods: clean
	@cp Integrations/CocoaPods/project.yml .
	@cp Integrations/CocoaPods/Podfile .
	xcodegen generate
	pod install
	open R2TestApp.xcworkspace

cocoapods+lcp: LCP_URL = $(shell read -p "Enter the liblcp CocoaPods URL you received from EDRLab: " url; \
	# Escape the URL for sed replacement \
	echo $$url | sed -e 's/[]\/$*.^[]/\\&/g')
cocoapods+lcp: clean
	@sed -e "s/LCP_URL/${LCP_URL}/g" Integrations/CocoaPods/Podfile+lcp > Podfile
	@cp Integrations/CocoaPods/project+lcp.yml project.yml
	xcodegen generate
	pod install
	open R2TestApp.xcworkspace

