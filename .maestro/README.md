# Maestro flows (optional)

Quick exploratory checks with [Maestro](https://maestro.dev). The real UI suite is XCUITest (`The BlockUITests`); these flows are a convenience, not required to build or test the app.

| Flow | Launch | Checks |
|---|---|---|
| `smoke.yaml` | `-market off` | App launches, inventory list loads |
| `live.yaml` | `-market fast` | Bid on the first lot, then the simulated market outbids you |
| `accessibility.yaml` | `-market off` | Screenshots inventory, detail, and bid sheet for a visual UX-2 check; set dark mode and the text size on the simulator first (see the file header) |
| `outbid-banner-sheet.yaml` | `-market fast` | Bid on D-0010; the outbid banner shows over the open bid sheet (ALERT-1) |
| `ipad-mybids.yaml` | `-market off` | iPad only: My bids opens in the list column and each tapped lot shows beside it (MYBIDS-1) |

Run (app installed on a booted simulator, bundle id `com.softie.dev.The-Block`):

```sh
maestro test .maestro --exclude-tags ipad  # all flows on an iPhone simulator
maestro test .maestro --include-tags smoke  # one tag
maestro test .maestro --include-tags ipad   # iPad flows, on an iPad simulator
```
