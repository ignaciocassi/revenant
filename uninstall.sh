#!/usr/bin/env bash
# Thin wrapper: uninstall lives in the `revenant` CLI.
exec bash "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/revenant" uninstall "$@"
