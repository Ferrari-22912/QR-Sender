QR Sender
A responsive Flutter web application for pairing devices on a trusted local network, sending files/video, and using a phone-like trackpad/keyboard interface. The UI runs in Chrome with:

Bash

flutter pub get
flutter run -d chrome
Local relay setup (required for pairing)
The Flutter client talks to a small WebSocket rendezvous/relay. Start it in a separate terminal on the PC that will host the session:

Bash

cd server
npm install
npm start
It listens on port 8787 on all network interfaces. Allow that port through your computer firewall only on a trusted/private network.

Start the relay, then launch Flutter with flutter run -d chrome.
In the app, set Local relay address to the PC's LAN address, e.g. ws://192.168.1.20:8787 (find it with ipconfig on Windows or ip addr on Linux/macOS).
Choose Host / Display receiver and show the QR / 10-digit pairing code.
Open the app on the other device and enter the same relay address and OTP. Scanning the QR can fill both fields; camera access requires a secure browser context, so manual code entry is the fallback.
Both devices must be able to reach that PC and port 8787. Guest Wi-Fi/client isolation can prevent this.
To let a phone open the Flutter web app from the PC's LAN, run the web-server device instead of Chrome:

Bash

flutter run -d web-server --web-hostname 0.0.0.0 --web-port 8080
Then visit http://<PC-LAN-IP>:8080 on the phone. Camera QR scanning typically requires HTTPS outside localhost; OTP entry works without the camera.

What is implemented
Responsive dashboard and receiver/sender pairing UI; server-generated 10-digit OTPs expire after 10 minutes and allow one sender.
QR pairing payload includes the relay URL and OTP.
Relative pointer deltas, click events, and typed text are relayed to the peer.
File selection and chunked/base64 file transfer; received files are offered to the browser download/save flow.
Video file transfer and an in-app player for browser-decodable formats (MP4/H.264/AAC is the safest choice).
Important architecture and browser limitations
This starter uses a local WebSocket relay, not a direct WebRTC data channel: payloads pass through the Node process on your LAN. It needs that separate relay process; flutter run -d chrome alone cannot broker two devices. The relay uses an unencrypted ws:// connection for local development. Do not expose it to the internet or an untrusted network. For internet deployment, add TLS (wss://), authentication, rate limits, origin validation, and relay hardening; for strict end-to-end P2P, replace the relay data path with WebRTC plus signaling.

A browser sandbox cannot move the operating system's real mouse or inject keystrokes into other desktop applications. QR Sender relays these input events, and the host UI shows an in-app pointer preview; real desktop-wide control requires a separately installed native companion with OS accessibility/input permissions. Similarly, movie transfer currently buffers the selected file and sends it before playback rather than live-streaming a filesystem path. Very large files can consume significant browser memory.

Android app
The same Flutter app can run on Android. Install Flutter plus Android Studio/Android SDK, connect a phone with USB debugging enabled (or start an emulator), then generate the Android runner and required manifest permissions:

Bash

bash scripts/bootstrap_android.sh
flutter doctor
flutter devices
flutter run -d <android-device-id>
The script creates the standard Android project files, adds Internet and optional camera permissions, and sets Android compileSdk to API 36 for current Flutter plugin requirements. Install Android SDK Platform 36 in Android Studio's SDK Manager (or run sdkmanager --install "platforms;android-36" "build-tools;36.0.0") before building locally. The GitHub Actions workflow installs this platform automatically. For Android, use the receiver PC's LAN address (not localhost) in the relay URL. Keep the devices on the same trusted Wi-Fi. Cleartext ws:// is enabled for local development; use TLS and disable cleartext for a production deployment.

GitHub / automated builds
GitHub Actions configuration is included at 
flutter.yml
. To include generated native Android project files in the repository, run bash scripts/bootstrap_android.sh first and commit the resulting android/ folder. (The CI workflow also generates it automatically if absent.) Create an empty repository on GitHub, then push the project:

Bash

git init
git add .
git commit -m "Add QR Sender Flutter app"
git branch -M main
git remote add origin https://github.com/<your-account>/<your-repository>.git
git push -u origin main
The workflow builds the web app and Android debug APK on pushes, pull requests, and manual dispatch. Download artifacts from the completed workflow run under Actions → run → Artifacts. The APK is a debug build for testing; a signed release APK/AAB needs a release keystore and signing secrets configured in GitHub. No GitHub account or repository is connected to this workspace, so the files are prepared for you to push; they have not been pushed remotely.

Project layout
text

lib/
  main.dart
  screens/dashboard_screen.dart
  services/relay_service.dart
  widgets/trackpad.dart
server/
  server.js
  package.json
scripts/
  bootstrap_android.sh
.github/workflows/
  flutter.yml
web/
  index.html
  manifest.json
