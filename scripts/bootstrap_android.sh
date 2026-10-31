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
import re
import sys

manifest = Path(sys.argv[1])
text = manifest.read_text()
for permission in ('android.permission.INTERNET', 'android.permission.CAMERA'):
    tag = f'<uses-permission android:name="{permission}" />'
    if permission not in text:
        text = text.replace('<application', f'    {tag}\n    <application', 1)
if 'android:usesCleartextTraffic=' not in text:
    text = text.replace('<application', '<application android:usesCleartextTraffic="true"', 1)
if 'android.hardware.camera' not in text:
    text = text.replace('<application', '    <uses-feature android:name="android.hardware.camera" android:required="false" />\n    <application', 1)
manifest.write_text(text)

# Keep the app and Flutter plugin modules aligned with current plugin AAR metadata.
for gradle in (Path('android/app/build.gradle'), Path('android/app/build.gradle.kts')):
    if gradle.exists():
        source = gradle.read_text()
        source, count = re.subn(
            r'compileSdk(?:Version)?\s*=\s*flutter\.compileSdkVersion',
            'compileSdk = 36', source, count=1,
        )
        if not count:
            source, count = re.subn(
                r'compileSdkVersion\s+flutter\.compileSdkVersion',
                'compileSdkVersion 36', source, count=1,
            )
        gradle.write_text(source)

marker = '// QR_SENDER_COMPILE_SDK_OVERRIDE_V2'

root_gradle = Path('android/build.gradle')
if root_gradle.exists():
    source = root_gradle.read_text()
    # Replace any earlier override block, which ran too early in plugin configuration.
    if '// QR_SENDER_COMPILE_SDK_OVERRIDE' in source:
        source = source.split('// QR_SENDER_COMPILE_SDK_OVERRIDE', 1)[0].rstrip()
    source += '''\n\n// QR_SENDER_COMPILE_SDK_OVERRIDE_V2\n// Set the SDK after each Android plugin has finished configuring its module.\nsubprojects { subproject ->\n    subproject.afterEvaluate {\n        def androidExtension = subproject.extensions.findByName("android")\n        if (androidExtension != null) {\n            def setter = androidExtension.class.methods.find {\n                it.name == "compileSdkVersion" && it.parameterCount == 1\n            }\n            if (setter != null) {\n                setter.invoke(androidExtension, 36)\n            } else {\n                androidExtension.compileSdk = 36\n            }\n        }\n    }\n}\n'''
    root_gradle.write_text(source)

root_gradle_kts = Path('android/build.gradle.kts')
if root_gradle_kts.exists():
    source = root_gradle_kts.read_text()
    if '// QR_SENDER_COMPILE_SDK_OVERRIDE' in source:
        source = source.split('// QR_SENDER_COMPILE_SDK_OVERRIDE', 1)[0].rstrip()
    source += '''\n\n// QR_SENDER_COMPILE_SDK_OVERRIDE_V2\n// Set the SDK after each Android plugin has finished configuring its module.\nsubprojects { subproject ->\n    subproject.afterEvaluate {\n        val androidExtension = subproject.extensions.findByName("android")\n        val setter = androidExtension?.javaClass?.methods?.firstOrNull {\n            it.name == "compileSdkVersion" && it.parameterCount == 1\n        }\n        if (setter != null) {\n            setter.invoke(androidExtension, 36)\n        } else if (androidExtension != null) {\n            androidExtension.javaClass.methods.firstOrNull { it.name == "setCompileSdk" }\n                ?.invoke(androidExtension, 36)\n        }\n    }\n}\n'''
    root_gradle_kts.write_text(source)
PY

echo "Android runner is ready (compileSdk 36). Check connected devices with: flutter devices"
echo "Run the app with: flutter run -d <android-device-id>"
