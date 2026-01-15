# moussa_hls_player

Native **HLS video player** for Flutter using **real native players**
(ExoPlayer on Android & AVPlayer on iOS).

Designed for **production use**, not demos.

---

## ✨ Features

- 🎚️ **Multiple HLS qualities**
  - Manual quality switching  
  - Keeps playback position & volume  

- 🔄 **Event-driven architecture**
  - No polling from Flutter  
  - Unified events across Android & iOS  

- 📊 **Playback state**
  - position / duration  
  - buffering & buffer progress  
  - playing / paused / ended  

- 🚫 **No WebView / No iframe**
- 🌐 **Safe on Web & Desktop**
  - Gracefully disabled (no crashes)  

---

## 📦 Installation

Add the dependency to your `pubspec.yaml`:  

```yaml
dependencies:
  moussa_hls_player: ^0.1.3
```


## Usage
```dart
MoussaHlsPlayerView(
  onCreated: (controller) async {
    await controller.setSource(
      qualities: [
        MoussaHlsQuality(label: '1080p', url: 'https://example.com/1080.m3u8'),
        MoussaHlsQuality(label: '720p',  url: 'https://example.com/720.m3u8'),
      ],
      initialQuality: '720p',
      autoPlay: true,
    );
  },
);
```

## 🎛 Controller API

```dart
controller.play();
controller.pause();
controller.seekToMs(30 * 1000);
controller.setQuality('1080p');
controller.setVolume(0.8);
```

## 📡 Playback State
**Listen to real-time state updates:**

```dart
ValueListenableBuilder(
  valueListenable: controller.state,
  builder: (context, state, _) {
    return Column(
      children: [
        Text('Playing: ${state.isPlaying}'),
        Text('Buffering: ${state.isBuffering}'),
        Text('Position: ${state.positionMs} ms'),
        Text('Buffered to: ${state.bufferedToMs} ms'),
        Text('Quality: ${state.currentQuality}'),
      ],
    );
  },
);
```

## ⚠️ Error Handling

```dart
ValueListenableBuilder(
  valueListenable: controller.error,
  builder: (context, err, _) {
    if (err == null) return SizedBox.shrink();
    return Text(
      'Error (${err.platform}) ${err.code}: ${err.message}',
    );
  },
);
```

## Errors are:

- Normalized across Android & iOS  
- Safe to retry when possible  
- Never crash Flutter  

## 📄 License

MIT License © 2025 **MoussaIT**  
Developed by **Mostafa Azazy**  

See the LICENSE file for full details.


## 👨‍💻 Author

Mostafa Azazy  
Principal Mobile Engineer  
MoussaIT


## ⭐ Contributions

Contributions are welcome if they:  

- Improve production stability  
- Keep the API minimal & predictable 
- Avoid demo-only or experimental logic  


