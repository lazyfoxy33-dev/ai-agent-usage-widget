# Widget Package

This directory contains the installable Übersicht widget.

For requirements, privacy details, provider setup, troubleshooting, and
contribution guidelines, see the [project README](../README.md).

## Install

```bash
bash install.sh
```

Start Übersicht and enable `usage-widget` from its menu. Data refreshes
automatically every 60 seconds; disable and re-enable the widget to reload it
immediately.

## Test

```bash
python3 -m unittest discover -v
```
