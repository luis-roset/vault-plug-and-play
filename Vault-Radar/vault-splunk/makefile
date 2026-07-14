VERSION?=1.0.6
APP_NAME="vault"
APP_ID=5093
SPLUNK_VERSIONS=8.1,8.2,9.0,9.1,9.2

SHELL := /usr/bin/env bash -euo pipefail -c

build-slim-image:
	@docker build --rm -t slim-build -f build/Slim.dockerfile .

build-appinspect-image:
	@docker build --rm -t appinspect-build -f build/AppInspect.dockerfile .

build-package: build-slim-image
	mkdir -p pkg
	@docker run -v "${PWD}":/splunk-app \
	-w /splunk-app \
	slim-build \
	slim package -o pkg app/vault

validate-package: build-slim-image
	@docker run -v "${PWD}":/splunk-app \
	-w /splunk-app \
	slim-build \
	slim validate pkg/vault-"${VERSION}".tar.gz

appinspect-package: build-appinspect-image
	mkdir -p test-results
	@docker run -v "${PWD}":/splunk-app \
	-w /splunk-app \
	appinspect-build \
	splunk-appinspect inspect pkg/vault-"${VERSION}".tar.gz \
	--data-format junitxml --output-file test-results/results.xml | grep "failure:\s 0" 

appinspect-package-cloud: build-appinspect-image
	mkdir -p test-results
	@docker run -v "${PWD}":/splunk-app \
	-w /splunk-app \
	appinspect-build \
	splunk-appinspect inspect pkg/vault-"${VERSION}".tar.gz --included-tags=cloud \
	--data-format junitxml --output-file test-results/cloud-results.xml | grep "failure:\s 0"

#run in CI
publish:
	@./build/publish.sh publish "$(APP_NAME)-$(VERSION)" "$(SPLUNK_VERSIONS)" "$(APP_ID)"
