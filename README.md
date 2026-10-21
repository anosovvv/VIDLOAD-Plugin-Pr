# VIDLOAD Plugin Pr

An Adobe Premiere Pro UXP panel that sends a permitted media download to a
local VIDLOAD Engine and imports the completed file into the open Premiere
project.

## Features

- Premiere-native dockable panel design;
- Russian and English interface;
- video (H.264/AAC MP4) and audio (MP3) choices;
- accurate, stage-based progress UI;
- automatic import into the current insertion bin through the Premiere API;
- a local Swift VIDLOAD Engine with an HTTP API on `127.0.0.1:17383`;
- automatic clearing of the completed link, ready for the next import.

The release Engine includes its own yt-dlp and FFmpeg tools. It does not require
Homebrew, Terminal, or a separate VIDLOAD application.

## Release installer

The public release is a single macOS installer package:
`VIDLOAD-Plugin-Pr-0.1.3.pkg`.

It contains the Premiere plugin, VIDLOAD Plugin Pr Engine, yt-dlp and FFmpeg.
The installer puts the Engine in `/Applications`, installs a background launch
agent so the Engine is ready after sign-in, and asks Adobe's official installer
to install the included `.ccx` plugin package. Users do not need Homebrew,
Terminal, or a separate Engine download.

Because this first independent release is not signed with an Apple Developer
ID, macOS will show its standard warning before installation. Open the package
only after downloading it from the official release page, then restart Premiere
and open **Window → UXP Plugins → VIDLOAD Plugin Pr**.

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
