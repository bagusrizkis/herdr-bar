#!/bin/sh
# Event hook: forward the agent status change to the app via URL scheme.
# The app treats this as a hint only; its socket subscription remains the source of truth.
exec open -g "herdrbar://event?json=$(printf '%s' "$HERDR_PLUGIN_EVENT_JSON" | python3 -c 'import sys,urllib.parse;print(urllib.parse.quote(sys.stdin.read()))')"
