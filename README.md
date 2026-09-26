# StockInfo

Android app for daily stock prices from Yahoo Finance.

## Features

- Ticker lookup, default SPUS.
- Ranges: 7D, 14D, 31D, 60D, 90D, custom 1-120 days.
- Price chart with close, MA10, MA20.
- DIP and TAKE signals from off-high and 20-day low levels.
- Auto levels from median daily move, with manual override.
- LIVE row with provisional today price when market is open.
- 5m backfill for daily bars with missing closes.
- Remembers ticker, range, and levels between restarts.

## Run

```bash
nix develop
flutter run -d chrome
```

## Build release APK (arm64)

```bash
nix develop --command bash -c 'flutter build apk --release --target-platform android-arm64'
```

Output: `build/app/outputs/flutter-apk/app-release.apk` (~18 MB).

## Notes

- Data source: Yahoo Finance chart API, no API key needed.
- LIVE row uses the last 5m price and partial session volume. It can change before close.
- First shell entry stages writable SDK copies in `~/.cache/stockinfo/`.
