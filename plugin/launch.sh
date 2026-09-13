#!/bin/sh
# Startup hook: bring up Herdr Bar if it is not running. Bundle id is a placeholder until the Xcode project exists.
pgrep -xq "Herdr Bar" || open -gb me.bagus.herdrbar
