.DEFAULT_GOAL := help

OS := linux
ifeq (${shell uname},Darwin)
	OS := darwin
endif
ARCH := amd64

help: ## show help message
	@awk 'BEGIN {FS = ":.*##"; printf "\nUsage:\n  make \033[36m\033[0m\n"} /^[$$()% a-zA-Z.\/_-]+:.*?##/ { printf "  \033[36m%-16s\033[0m %s\n", $$1, $$2 } /^##@/ { printf "\n\033[1m%s\033[0m\n", substr($$0, 5) } ' $(MAKEFILE_LIST)

deps: ## install dependencies for development
ifeq (${OS},linux)
	if [ -n "$$(command -v yum)" ]; then \
		yum -y install curl gzip jq python3-pip tar unzip; \
	elif [ -n "$$(command -v apt)" ]; then \
		apt -y install curl jq unzip; \
		if [ $$(cat /etc/lsb-release | grep REL | cut -d "=" -f 2 | cut -d . -f1) -lt 20 ]; then \
			apt install -y python3.7 python3-pip; \
		else \
			apt install -y python3 python3-pip; \
		fi; \
	fi; \
	python3 -m pip install --upgrade pip
else ifeq (${OS},darwin)
	if [ -n "$$(command -v brew)" ]; then brew install coreutils jq; else echo "brew required"; fi
endif

pre-commit: deps ## setup pre-commit
	@echo "You can install for docker alternatively. see: https://github.com/antonbabenko/pre-commit-terraform#1-install-dependencies"
ifeq (${OS},linux)
	pip3 install --no-cache-dir pre-commit checkov
	curl -L "$$(curl -s https://api.github.com/repos/terraform-docs/terraform-docs/releases/latest | grep -o -E -m 1 "https://.+?-linux-amd64.tar.gz")" > terraform-docs.tgz && tar -xzf terraform-docs.tgz terraform-docs && rm terraform-docs.tgz && chmod +x terraform-docs && sudo mv terraform-docs /usr/bin/
	curl -L "$$(curl -s https://api.github.com/repos/terraform-linters/tflint/releases/latest | grep -o -E -m 1 "https://.+?_linux_amd64.zip")" > tflint.zip && unzip tflint.zip && rm tflint.zip && sudo mv tflint /usr/bin/
	curl -L "$$(curl -s https://api.github.com/repos/aquasecurity/tfsec/releases/latest | grep -o -E -m 1 "https://.+?tfsec-linux-amd64")" > tfsec && chmod +x tfsec && sudo mv tfsec /usr/bin/
else ifeq (${OS},darwin)
	if [ -n "$$(command -v brew)" ]; then brew install pre-commit terraform-docs tflint checkov; else echo "brew required"; fi
endif
	pre-commit install
