# VIDLOAD Plugin Pr 0.1.2

## What changed

- The link field now clears itself after media has been successfully imported
  into the active Premiere Pro project.
- Instagram carousel posts no longer fail the whole operation when one item
  does not expose a downloadable video stream; available media can still be
  processed.
- Download errors now describe the actual issue instead of showing only a
  generic yt-dlp exit code.

## Install

Download and open `VIDLOAD-Plugin-Pr-0.1.2.pkg`. The single installer includes
the Premiere panel, local VIDLOAD Engine, yt-dlp, and FFmpeg. Close Premiere
before installing, then reopen it and use **Window → UXP Plugins → VIDLOAD
Plugin Pr**.

No Homebrew, Terminal commands, or separate Engine installation are required.
This independently distributed build is not signed with an Apple Developer ID,
so macOS may display its standard warning before installation.
