#!/usr/bin/env bash
# Thin wrapper: install lives in the `revenant` CLI.
exec bash "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/revenant" install "$@"
