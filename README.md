# moussa_hls_player

Native HLS video player for Flutter (Android & iOS).

## Features
- Native player  
- Multiple quality HLS support  
- No WebView / No iframe  
- Safe on Web / Desktop (no crash)  

## 📦 Installation

Add the dependency to your pubspec.yaml:  

```yaml
dependencies:
  moussa_hls_player: ^0.1.0
```


## Usage
```dart
MoussaHlsPlayerView(
  onCreated: (controller) async {
    await controller.setSource(
      qualities: [
        MoussaHlsQuality(label: '1080p', url: '...'),
        MoussaHlsQuality(label: '720p', url: '...'),
      ],
      initialQuality: '720p',
    );
    controller.play();
  },
);
```


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
- Keep the API clean and minimal  
- Avoid demo-only or experimental logic  


