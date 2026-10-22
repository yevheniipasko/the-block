# Maestro flows (optional)

Quick exploratory checks with [Maestro](https://maestro.dev). The real UI suite is XCUITest (`The BlockUITests`); these flows are a convenience, not required to build or test the app.

| Flow | Launch | Checks |
|---|---|---|
| `smoke.yaml` | `-market off` | App launches, inventory list loads |
| `live.yaml` | `-market fast` | Bid on the first lot, then the simulated market outbids you |

Run (app installed on a booted simulator, bundle id `com.softie.dev.The-Block`):

```sh
maestro test .maestro                       # all flows
maestro test .maestro --include-tags smoke  # one tag
```
