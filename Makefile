# -----------------------
# Config
# -----------------------
ENV ?= dev

LOCAL_DEPLOY_SCRIPT = scripts/deploy.sh
LOCAL_SYNC_SCRIPT = scripts/sync_git.sh

.DEFAULT_GOAL := help
.PHONY: help local local-up local-down local-status infra-up tdbcli-install tdbcli-uninstall tdbcli-install-user
.PHONY: clone debug-config doctor venv

TDBCLI_NAME ?= tdbcli
PREFIX ?= /usr/local
BINDIR ?= $(PREFIX)/bin

# -----------------------
# Targets
# -----------------------

help:
	@echo ""
	@echo "TalkingDB Infrastructure"
	@echo "--------------------------"
	@echo "Local:"
	@echo "  make local                 Deploy local packages"
	@echo "  make sync                  Sync local packages"
	@echo ""


local:
	@echo "Deploying Local packages"
	bash $(LOCAL_DEPLOY_SCRIPT) up

sync:
	@echo "Syncing Local packages"
	bash $(LOCAL_SYNC_SCRIPT)

logs:
	@echo "Tailing Local package logs"
	bash $(LOCAL_DEPLOY_SCRIPT) logs

kill:
	@echo "Stopping Local packages"
	bash $(LOCAL_DEPLOY_SCRIPT) kill

tdbcli-install:
	@echo "Installing $(TDBCLI_NAME) to $(BINDIR)/$(TDBCLI_NAME)"
	@chmod +x scripts/tdbcli.sh
	@sudo cp scripts/tdbcli.sh $(BINDIR)/$(TDBCLI_NAME)
	@sudo chmod +x $(BINDIR)/$(TDBCLI_NAME)
	@echo "Done. Try: which $(TDBCLI_NAME) && $(TDBCLI_NAME) --help"

tdbcli-uninstall:
	@echo "Uninstalling $(TDBCLI_NAME) (system + user) and cleaning config..."
	@echo "1) Removing system install: $(BINDIR)/$(TDBCLI_NAME)"
	@sudo rm -f "$(BINDIR)/$(TDBCLI_NAME)" || true
	@echo "2) Removing user install: $$HOME/.local/bin/$(TDBCLI_NAME)"
	@rm -f "$$HOME/.local/bin/$(TDBCLI_NAME)" || true
	@echo "3) Removing tdbcli global config: $$HOME/.tdbcli"
	@rm -rf "$$HOME/.tdbcli" || true
	@echo "Done."

tdbcli-install-user:
	@echo "Installing $(TDBCLI_NAME) to $$HOME/.local/bin/$(TDBCLI_NAME)"
	@chmod +x scripts/tdbcli.sh
	@mkdir -p $$HOME/.local/bin
	@cp scripts/tdbcli.sh $$HOME/.local/bin/$(TDBCLI_NAME)
	@chmod +x $$HOME/.local/bin/$(TDBCLI_NAME)
	@echo "Done. Ensure $$HOME/.local/bin is in your PATH."

clone:
	@bash scripts/clone-repo.sh

doctor: 
	@bash scripts/doctor.sh

venv:
	@echo "Run: source scripts/venv.sh"

debug-config:
	@python vscode/debug_launch.py
