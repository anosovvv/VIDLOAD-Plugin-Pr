# VIDLOAD Engine API — draft

The UXP panel does not run `yt-dlp` or FFmpeg itself. It talks only to a local
VIDLOAD Engine on `127.0.0.1:17383`. The loopback address keeps job details and
media paths on the creator's computer.

## `GET /v1/health`

```json
{ "status": "ready", "version": "0.1.0" }
```

## `POST /v1/downloads`

```json
{ "url": "https://example.com/video", "format": "mp4", "consumer": "premiere" }
```

```json
{ "id": "9C3E…", "status": "queued" }
```

## `GET /v1/downloads/:id`

```json
{
  "id": "9C3E…",
  "status": "running",
  "stage": "downloading",
  "progress": 42.4,
  "detail": "12.5 MiB/s · 00:13 remaining"
}
```

`stage` values: `preparing`, `downloading`, `converting`, `importing`.

When a job completes, the response also contains:

```json
{ "status": "completed", "outputPath": "/Users/example/Downloads/VIDLOAD/clip.mp4" }
```

## `DELETE /v1/downloads/:id`

Cancels an active job.
