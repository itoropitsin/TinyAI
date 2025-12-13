# How to Generate the App Icon

## Option 1: Use the provided SVG (recommended)

1. Open `DeepAI/icon_template.svg` in any editor (for example, a browser or Figma)
2. Export PNG files in the following sizes:
   - 16x16, 32x32, 64x64, 128x128, 256x256, 512x512, 1024x1024
3. Save them into `DeepAI/Assets.xcassets/AppIcon.appiconset/` with these names:
   - `icon_16x16.png` (16x16)
   - `icon_16x16@2x.png` (32x32)
   - `icon_32x32.png` (32x32)
   - `icon_32x32@2x.png` (64x64)
   - `icon_128x128.png` (128x128)
   - `icon_128x128@2x.png` (256x256)
   - `icon_256x256.png` (256x256)
   - `icon_256x256@2x.png` (512x512)
   - `icon_512x512.png` (512x512)
   - `icon_512x512@2x.png` (1024x1024)

## Option 2: Use ImageMagick (automatic)

If you have ImageMagick installed:

```bash
cd DeepAI
./create_icon.sh
```

If ImageMagick is not installed:
```bash
brew install imagemagick
cd DeepAI
./create_icon.sh
```

## Option 3: Online converter

1. Open `icon_template.svg` in a browser
2. Use an online SVG-to-PNG converter (for example, https://cloudconvert.com/svg-to-png)
3. Generate PNG files in the required sizes
4. Save them into `Assets.xcassets/AppIcon.appiconset/` using the correct names

## Option 4: Use Xcode

1. Open the project in Xcode
2. Select `Assets.xcassets` → `AppIcon`
3. Drag and drop icons into the corresponding slots
4. Xcode will detect sizes automatically

## Icon design

The current icon includes:
- A blue gradient background (symbolizing technology)
- A translation symbol (A → B)
- An AI symbol (three connected nodes)
- White color for contrast

You can change the design by editing `icon_template.svg` in any vector editor.

