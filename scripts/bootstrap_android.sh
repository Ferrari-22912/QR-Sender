#!/usr/bin/env bash
set -euo pipefail

if ! command -v flutter >/dev/null 2>&1; then
  echo "Flutter is required. Install Flutter and add it to PATH first." >&2
  exit 1
fi

# This repository is Flutter-first; create the standard Android runner on demand.
if [[ ! -d android ]]; then
  flutter create --platforms=android --project-name qr_sender --org com.qrsender .
fi

manifest="android/app/src/main/AndroidManifest.xml"
if [[ ! -f "$manifest" ]]; then
  echo "Flutter did not generate $manifest" >&2
  exit 1
fi

python3 - "$manifest" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
text = path.read_text()
for permission in (
    'android.permission.INTERNET',
    'android.permission.CAMERA',
):
    tag = f'<uses-permission android:name="{permission}" />'
    if permission not in text:
        text = text.replace('<application', f'    {tag}\n    <application', 1)
if 'android:usesCleartextTraffic=' not in text:
    text = text.replace('<application', '<application android:usesCleartextTraffic="true"', 1)
if 'android.hardware.camera' not in text:
    text = text.replace('<application', '    <uses-feature android:name="android.hardware.camera" android:required="false" />\n    <application', 1)
path.write_text(text)
PY

echo "Android runner is ready. Check connected devices with: flutter devices"
echo "Run the app with: flutter run -d <android-device-id>"
