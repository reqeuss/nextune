# Nextune

**Your sound. Your rules.** A local-first Android music-player prototype built with Flutter.

## Prototype features
- Import audio files from your Android device
- Play, pause, skip and seek through local tracks
- Favorites saved locally
- Create, rename and delete local playlists
- Add tracks to playlists and play them offline when the source file is on the device
- Export and import a JSON backup
- Dark violet interface with live playback-speed controls and Android Bass Boost, BassMax and reverb effects where the device supports them

**Not implemented yet:** YouTube/SoundCloud catalog search, provider artwork, and provider-authorized offline downloads. These integrations require official API access and must respect each provider's playback and download terms. Nextune does not extract audio from provider pages.

## Build a test APK on Windows

### 1. Install the tools
- Install the Flutter SDK: https://docs.flutter.dev/get-started/install/windows
- Install Android Studio: https://developer.android.com/studio
- In Android Studio, install Android SDK Platform 35 and Android SDK Build-Tools.
- Add the Flutter SDK's `bin` directory to your Windows PATH.

### 2. Open PowerShell in the cloned repository
```powershell
git clone https://github.com/reqeuss/nextune.git
cd nextune
flutter doctor
flutter create --platforms=android --org com.reqeuss .
flutter pub get
flutter build apk --debug
```

If you already cloned the repository, just run the commands from `flutter doctor` onward inside the Nextune folder. The `flutter create` command generates the standard Android project files.

### 3. Find the APK
`build\app\outputs\flutter-apk\app-debug.apk`

Send that file to your Android phone using USB, cloud storage, or a messaging app. Open it on your phone and allow installation from that source if Android asks.

For a smaller, optimized test build, you can use `flutter build apk --release` after the first successful debug build.

## Notes
- The backup stores metadata and local file paths, not the audio files themselves. Paths usually differ on another phone, so transfer your music separately and import it there.
- Import/play only audio files you have the right to use.
- Future streaming integrations must respect the providers' APIs and terms.
