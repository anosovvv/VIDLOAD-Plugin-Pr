# VIDLOAD Plugin Pr

An Adobe Premiere Pro UXP panel that sends a permitted media download to a
local VIDLOAD Engine and imports the completed file into the open Premiere
project.

## Current milestone

This repository contains the first working development slice:

- Premiere-native dockable panel design;
- Russian and English interface;
- video (H.264/AAC MP4) and audio (MP3) choices;
- accurate, stage-based progress UI;
- automatic import into the current insertion bin through the Premiere API;
- a local Swift VIDLOAD Engine with an HTTP API on `127.0.0.1:17383`;
- a documented Engine contract.

The Engine already reuses the download and conversion approach of the
standalone VIDLOAD app. During development it discovers the bundled yt-dlp and
FFmpeg tools from `/Applications/VIDLOAD.app`; release packaging will place the
same tools inside the Engine app bundle.

## Development requirements

- Adobe Premiere Pro 25.6 or newer;
- Adobe UXP Developer Tool;
- VIDLOAD Engine running on `http://127.0.0.1:17383`.

## Running the Engine in development

```sh
cd Engine
swift run VIDLOADPluginEngine
```

The Engine saves output to `~/Downloads/VIDLOAD Plugin Pr`. It handles only
public YouTube and Instagram links in this first version and produces an
H.264/AAC MP4 for video downloads so Premiere receives a broadly compatible
file.

## Loading the panel for development

1. In UXP Developer Tool, choose **Add Plugin** and select this folder.
2. Load the plugin into Premiere Pro.
3. Open **Window → UXP Plugins → VIDLOAD Plugin Pr**.

## Privacy model

The panel requests network access only to the local loopback VIDLOAD Engine.
It does not send links, download history, browser cookies, or media file paths
to a remote server. Any later Safari-session option must remain off by default
and be handled solely by the local Engine after an explicit user choice.

The MVP does not yet expose Safari-session access in the plugin. It will be
added only after the Engine has a clear, one-time macOS permission flow.
