# Plasma Panel Lyrics — Spotify

A lightweight KDE Plasma 6 panel widget that shows the currently playing
Spotify track's lyrics, synchronized with playback, right in your panel —
no backend, no server, just MPRIS + the [LRCLIB](https://lrclib.net) API.

```
┌──────────────────────────────────────────┐
│ [cover]  I've become so numb              │
└──────────────────────────────────────────┘
```

## Features

- **Live MPRIS detection** — polls Spotify's MPRIS interface directly via
  `busctl` (no private Plasma APIs, no extra dependencies beyond what a
  standard KDE Plasma install already has).
- **Synced lyrics** — fetches time-stamped lyrics from LRCLIB, parses the
  `.lrc` timestamps, and shows the line matching the current playback
  position, updated a few times a second.
- **Smooth panel text** — long lines that don't fit the panel scroll as a
  seamless marquee instead of getting truncated; line changes cross-fade
  rather than cutting abruptly.
- **Track-art thumbnail** in the panel strip, pulled from the track's own
  MPRIS metadata.
- **"Now Playing" popup** — click the widget for cover art, title/artist,
  the current lyric line, a seekbar, and previous/play-pause/next controls.
- **Lyrics on/off toggle** — right in the popup. Off just shows the song
  name and skips the LRCLIB API call entirely; on resumes immediately.
- **In-session caching** — a song's lyrics are only fetched once; caches by
  artist + title, so replaying or seeking never re-hits the API.
- **Configurable** — font size, max panel width, and text alignment via the
  widget's own settings.

## Requirements

- KDE Plasma 6
- `busctl` (part of `systemd`, present on virtually every modern Linux
  desktop)
- Spotify running with MPRIS enabled (the default on Linux)

## Installation

```sh
git clone https://github.com/RAN-GAN/plasma-panel-lyrics.git
cd plasma-panel-lyrics
kpackagetool6 --type Plasma/Applet --install com.example.panellyrics
```

Then right-click your panel → **Add or Manage Widgets…** and add **Plasma
Panel Lyrics - Spotify**.

To pick up an update after pulling new changes:

```sh
kpackagetool6 --type Plasma/Applet --upgrade com.example.panellyrics
```

You may need to log out and back in (or restart `plasmashell`) for KDE to
pick up a freshly installed or upgraded widget.

## Configuration

Right-click the widget → **Configure Panel Lyrics** for:

- **Font size** — panel text size (default: match the panel's own font).
- **Maximum width** — panel space budget in pixels before the marquee
  scroll kicks in.
- **Text alignment** — left, center, or right.

## How it works

```
Spotify → MPRIS/D-Bus → Artist + Title + Position
        → LRCLIB API → Timestamped lyrics (.lrc)
        → parse + match to current position
        → display in panel
```

MPRIS access goes through `busctl` subprocesses (run via Plasma's
`Plasma5Support.DataSource` executable engine) rather than any
Plasma-private QML module, so it stays stable across Plasma versions.

## Project structure

```
com.example.panellyrics/
├── metadata.json
└── contents/
    ├── ui/
    │   ├── main.qml          # panel + popup UI
    │   ├── config.qml        # settings page registration
    │   └── configGeneral.qml # settings page UI
    ├── config/
    │   └── main.xml          # settings schema
    └── code/
        ├── mpris.js          # MPRIS via busctl
        ├── lyrics.js         # LRCLIB fetch + caching
        └── lrc.js            # .lrc parsing + sync matching
```

## License

[GPL-3.0-or-later](LICENSE)
