# Nextune

**Your sound, reimagined.** A Flutter Android music player with local library artwork, live audio controls, playlists and a YouTube discovery/player tab.

## Features

- Fresh dark interface with a large now-playing screen and cover art
- Reads embedded title, artist, album and cover artwork from supported local audio files
- Local audio playback, seek, previous/next, favorites and playlists
- Pitch and playback-speed sliders, including Nightcore and Slowed + Reverb presets
- Android bass boost, equalizer/treble and reverb controls (hardware and device support can vary)
- YouTube search, embedded official player, thumbnail artwork, queue, shuffle/repeat, recommendations generated from YouTube search, recent history and favorites
- YouTube API key supplied at build time through the GitHub Actions secret `YOUTUBE_API_KEY`
- Export of a local library/playlist backup

## YouTube API setup

1. In Google Cloud, enable **YouTube Data API v3** for a project.
2. Create an API key and set appropriate application/API restrictions.
3. Add a GitHub Actions repository secret named `YOUTUBE_API_KEY`.
4. Run the **Build Android APK** workflow.

The app uses the key provided at compile time, so the user normally does not need to paste it into the app. **Important:** a key embedded in a mobile APK can be extracted. Do not use an unrestricted key for a public release; use strict Google Cloud restrictions or a backend proxy. YouTube search can also be affected by API quota, key restrictions and network connectivity.

## YouTube playback limits

Nextune uses the official embedded YouTube player and YouTube Data API. Not every video permits embedded playback, and no third-party app can guarantee that every search result will play. The recommendations in this version are search-based suggestions, not a copy of YouTube's private personalized Home feed. Pitch, speed and native effects apply to local audio only; the official YouTube player does not expose its audio stream for Nextune to process. The app does not download or extract YouTube audio.

## Build

The repository's GitHub Actions workflow generates the Android project, builds a release APK and uploads it as the `nextune-android-apk` artifact. Open **Actions → Build Android APK → latest successful run → Artifacts** to retrieve it.

For local development, install Flutter and Android Studio, then run:

```sh
flutter pub get
flutter run
```

## Notes

- Local audio files remain on the device; backups contain library metadata and paths, not the audio files themselves.
- Artwork is read from embedded metadata where the audio file format and file access allow it.
- Playback and audio-effect support varies by file format and Android device.
