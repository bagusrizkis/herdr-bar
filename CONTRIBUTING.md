# Contributing

Thanks for helping out. A few ground rules to keep the project small and easy to review.

- **Build:** `scripts/build-app.sh debug` then `open "build/Herdr Bar.app"`. No Xcode project.
- **Style:** Swift 6 strict concurrency is on. Keep UI on `@MainActor`, keep socket I/O in
  `HerdrClient`, and avoid `nonisolated(unsafe)` outside the client.
- **Herdr API:** everything the app calls must exist in `herdr api schema --json` for the minimum
  supported Herdr version (0.9). Note new findings in `PLAN.md` under "Verifikasi".
- **Icons:** the menu bar glyph is drawn in code from the geometry in `Design/icons/menubar/*.svg`.
  Change both if you change one. Run `HERDRBAR_DUMP_ICONS=/tmp/icons build/Herdr\ Bar.app/Contents/MacOS/HerdrBar`
  to export every state as PNG.
- **Commits:** one change per commit, imperative subject line, English.
