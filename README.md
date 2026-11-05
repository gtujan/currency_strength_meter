# Currency Strength Meter

Live currency strength and pair pressure dashboard, fed by the `CSMFeed.mq4` EA.

Shows the relative strength of 8 major currencies and gold in real time, and ranks forex pairs by buy/sell pressure with BUY/SELL signals. A small MetaTrader 4 EA (`CSMFeed`) reads each pair's daily high/low and streams a snapshot every second to a local Python server, which pushes it to a live web page in your browser. No external services or dependencies.

## Install (one line)

```bash
curl -fsSL https://raw.githubusercontent.com/gtujan/currency_strength_meter/main/install.sh | bash
```

This downloads the project to `~/currency_strength_meter`, creates `.venv`, installs `requirements.txt`,
and links `csmserve` into `~/.local/bin`. Re-run it any time to update.

Overrides: `CSM_DIR`, `CSM_BIN`, `CSM_BRANCH`, `CSM_REPO`.

## Use

```bash
csmserve run      # http://127.0.0.1:8765/
csmserve stop | restart | status | logs
```

Then in MT4: copy the precompiled `CSMFeed.ex4` into `MQL4/Experts` (File > Open Data Folder), restart MT4, attach it to a chart, and allow WebRequest for `http://127.0.0.1:8765`. No compiling needed; `CSMFeed.mq4` is the source.
