SHELL := /bin/bash

BACKEND_MANIFEST := backend/Cargo.toml
UI_PACKAGE_PATH := macos
BACKEND_HOST ?= 127.0.0.1
BACKEND_PORT ?= 8787
BACKEND_DATA_DIR ?= $(HOME)/Library/Application Support/GraphAlfred

.PHONY: help setup build check fmt clean backend-build backend-run ui-build ui-run run run-detached dev

help:
	@echo "GraphAlfred commands:"
	@echo "  make setup         Build backend + UI once"
	@echo "  make build         Build backend + UI"
	@echo "  make check         cargo check + swift build"
	@echo "  make fmt           cargo fmt"
	@echo "  make backend-run   Run Rust backend only"
	@echo "  make ui-run        Run Swift macOS UI only"
	@echo "  make run           Run backend + UI together"
	@echo "  make run-detached  Run backend + UI in background and return prompt"
	@echo "  make dev           Alias of make run"
	@echo "  make clean         Clean backend + UI build artifacts"

setup: build

build: backend-build ui-build

check:
	cargo check --manifest-path $(BACKEND_MANIFEST)
	swift build --package-path $(UI_PACKAGE_PATH)

fmt:
	cargo fmt --manifest-path $(BACKEND_MANIFEST)

backend-build:
	cargo build --manifest-path $(BACKEND_MANIFEST)

backend-run:
	cargo run --manifest-path $(BACKEND_MANIFEST) -- --host $(BACKEND_HOST) --port $(BACKEND_PORT) --data-dir "$(BACKEND_DATA_DIR)"

ui-build:
	swift build --package-path $(UI_PACKAGE_PATH)

ui-run:
	swift run --package-path $(UI_PACKAGE_PATH)

run:
	@set -euo pipefail; \
	EXISTING_BACKEND_PIDS=$$(lsof -tiTCP:$(BACKEND_PORT) -sTCP:LISTEN 2>/dev/null || true); \
	if [[ -n "$$EXISTING_BACKEND_PIDS" ]]; then \
		echo "Stopping existing backend on port $(BACKEND_PORT): $$EXISTING_BACKEND_PIDS"; \
		kill $$EXISTING_BACKEND_PIDS >/dev/null 2>&1 || true; \
		sleep 0.30; \
	fi; \
	echo "Starting backend on http://$(BACKEND_HOST):$(BACKEND_PORT)"; \
	cargo run --manifest-path $(BACKEND_MANIFEST) -- --host $(BACKEND_HOST) --port $(BACKEND_PORT) --data-dir "$(BACKEND_DATA_DIR)" >/tmp/graphalfred-backend.log 2>&1 & \
	BACKEND_PID=$$!; \
	cleanup() { \
		kill $$BACKEND_PID >/dev/null 2>&1 || true; \
	}; \
	trap cleanup EXIT INT TERM; \
	READY=0; \
	for i in $$(seq 1 120); do \
		if curl -fsS "http://$(BACKEND_HOST):$(BACKEND_PORT)/health" >/dev/null 2>&1; then \
			READY=1; \
			break; \
		fi; \
		if ! kill -0 $$BACKEND_PID >/dev/null 2>&1; then \
			break; \
		fi; \
		sleep 0.25; \
	done; \
	if [[ $$READY -ne 1 ]]; then \
		echo "Backend failed to start. Logs:"; \
		tail -n 120 /tmp/graphalfred-backend.log || true; \
		exit 1; \
	fi; \
	echo "Backend ready. Launching macOS UI..."; \
	echo "Terminal stays attached while app runs. Close app or Ctrl+C to stop all."; \
	swift run --package-path $(UI_PACKAGE_PATH)

run-detached:
	@set -euo pipefail; \
	EXISTING_BACKEND_PIDS=$$(lsof -tiTCP:$(BACKEND_PORT) -sTCP:LISTEN 2>/dev/null || true); \
	if [[ -n "$$EXISTING_BACKEND_PIDS" ]]; then \
		echo "Stopping existing backend on port $(BACKEND_PORT): $$EXISTING_BACKEND_PIDS"; \
		kill $$EXISTING_BACKEND_PIDS >/dev/null 2>&1 || true; \
		sleep 0.30; \
	fi; \
	echo "Starting backend on http://$(BACKEND_HOST):$(BACKEND_PORT)"; \
	cargo run --manifest-path $(BACKEND_MANIFEST) -- --host $(BACKEND_HOST) --port $(BACKEND_PORT) --data-dir "$(BACKEND_DATA_DIR)" >/tmp/graphalfred-backend.log 2>&1 & \
	BACKEND_PID=$$!; \
	READY=0; \
	for i in $$(seq 1 120); do \
		if curl -fsS "http://$(BACKEND_HOST):$(BACKEND_PORT)/health" >/dev/null 2>&1; then \
			READY=1; \
			break; \
		fi; \
		if ! kill -0 $$BACKEND_PID >/dev/null 2>&1; then \
			break; \
		fi; \
		sleep 0.25; \
	done; \
	if [[ $$READY -ne 1 ]]; then \
		echo "Backend failed to start. Logs:"; \
		tail -n 120 /tmp/graphalfred-backend.log || true; \
		kill $$BACKEND_PID >/dev/null 2>&1 || true; \
		exit 1; \
	fi; \
	swift run --package-path $(UI_PACKAGE_PATH) >/tmp/graphalfred-ui.log 2>&1 & \
	UI_PID=$$!; \
	echo "GraphAlfred started."; \
	echo "  Backend PID: $$BACKEND_PID (log: /tmp/graphalfred-backend.log)"; \
	echo "  UI PID:      $$UI_PID (log: /tmp/graphalfred-ui.log)"; \
	echo "Stop with: kill $$UI_PID $$BACKEND_PID"

dev: run

clean:
	cargo clean --manifest-path $(BACKEND_MANIFEST)
	rm -rf $(UI_PACKAGE_PATH)/.build
