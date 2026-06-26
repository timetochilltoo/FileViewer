#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="FileViewer"
APP_BUNDLE="$ROOT_DIR/build/$APP_NAME.app"
EXECUTABLE="$ROOT_DIR/.build/release/$APP_NAME"
ICONSET="$ROOT_DIR/build/AppIcon.iconset"
ICON_FILE="$APP_BUNDLE/Contents/Resources/AppIcon.icns"

cd "$ROOT_DIR"

swift build -c release

rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS" "$APP_BUNDLE/Contents/Resources"
cp "$EXECUTABLE" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
chmod +x "$APP_BUNDLE/Contents/MacOS/$APP_NAME"

rm -rf "$ICONSET"
mkdir -p "$ICONSET"
python3 - <<'PY'
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

root = Path("build/AppIcon.iconset")
sizes = {
    "icon_16x16.png": 16,
    "icon_16x16@2x.png": 32,
    "icon_32x32.png": 32,
    "icon_32x32@2x.png": 64,
    "icon_128x128.png": 128,
    "icon_128x128@2x.png": 256,
    "icon_256x256.png": 256,
    "icon_256x256@2x.png": 512,
    "icon_512x512.png": 512,
    "icon_512x512@2x.png": 1024,
}

def rounded_rectangle(draw, box, radius, fill):
    draw.rounded_rectangle(box, radius=radius, fill=fill)

for name, size in sizes.items():
    scale = size / 1024
    image = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(image)
    rounded_rectangle(draw, [int(72*scale), int(72*scale), int(952*scale), int(952*scale)], int(205*scale), (31, 111, 235, 255))
    rounded_rectangle(draw, [int(172*scale), int(156*scale), int(700*scale), int(868*scale)], int(54*scale), (248, 250, 252, 255))
    draw.polygon(
        [
            (int(700*scale), int(156*scale)),
            (int(852*scale), int(308*scale)),
            (int(700*scale), int(308*scale)),
        ],
        fill=(214, 226, 246, 255),
    )
    line_color = (38, 64, 92, 255)
    for y in [388, 462, 536, 610]:
        draw.rounded_rectangle(
            [int(270*scale), int(y*scale), int(752*scale), int((y+30)*scale)],
            radius=max(1, int(15*scale)),
            fill=line_color,
        )
    draw.rounded_rectangle(
        [int(270*scale), int(700*scale), int(548*scale), int(730*scale)],
        radius=max(1, int(15*scale)),
        fill=(46, 168, 119, 255),
    )
    image.save(root / name)
PY
iconutil -c icns "$ICONSET" -o "$ICON_FILE"

cat > "$APP_BUNDLE/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleDevelopmentRegion</key>
	<string>en</string>
	<key>CFBundleDisplayName</key>
	<string>FileViewer</string>
	<key>CFBundleExecutable</key>
	<string>FileViewer</string>
	<key>CFBundleIdentifier</key>
	<string>com.codex.fileviewer</string>
	<key>CFBundleIconFile</key>
	<string>AppIcon</string>
	<key>CFBundleInfoDictionaryVersion</key>
	<string>6.0</string>
	<key>CFBundleName</key>
	<string>FileViewer</string>
	<key>CFBundlePackageType</key>
	<string>APPL</string>
	<key>CFBundleShortVersionString</key>
	<string>0.1.0</string>
	<key>CFBundleVersion</key>
	<string>1</string>
	<key>LSApplicationCategoryType</key>
	<string>public.app-category.productivity</string>
	<key>LSMinimumSystemVersion</key>
	<string>26.0</string>
	<key>NSHighResolutionCapable</key>
	<true/>
	<key>NSSupportsAutomaticGraphicsSwitching</key>
	<true/>
</dict>
</plist>
PLIST

codesign --force --deep --sign - "$APP_BUNDLE"
codesign --verify --deep --strict "$APP_BUNDLE"

echo "Packaged $APP_BUNDLE"
