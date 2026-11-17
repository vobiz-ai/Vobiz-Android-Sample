# vobiz_inbound

The sample's two runnable parts:

| Folder | What it is |
| --- | --- |
| [`apps/vobiz_demo`](./apps/vobiz_demo) | The Flutter app, on the [`vobiz_webrtc`](https://pub.dev/packages/vobiz_webrtc) SDK |
| [`Vobiz-RTC-demo`](./Vobiz-RTC-demo) | The sample server: Answer URL, access tokens, push registration, transfer |

Setup, configuration, the call flows and the integration guide are in the
[repository README](../README.md).

Quick start, once `Vobiz-RTC-demo/.env` is filled in:

```bash
# Terminal 1: the server
cd Vobiz-RTC-demo && npm install && npm start

# Terminal 2: a public HTTPS address for it (then set PUBLIC_URL and the Answer URL)
cloudflared tunnel --url http://localhost:3000

# Terminal 3: the app
cd apps/vobiz_demo
flutter run --dart-define=VOBIZ_BACKEND_URL=https://<your-public-url> \
            --dart-define=VOBIZ_APP_KEY=<the server's APP_KEY>
```
