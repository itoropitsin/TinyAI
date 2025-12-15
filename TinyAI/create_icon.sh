#!/bin/bash

# Script to generate app icons from an SVG
# Requires: ImageMagick or sips (built into macOS)

SVG_FILE="icon_template.svg"
ICONSET_DIR="Assets.xcassets/AppIcon.appiconset"

echo "Generating app icons..."

# Check for ImageMagick
if command -v convert &> /dev/null; then
    echo "Using ImageMagick..."
    
    # Generate all required macOS sizes
    convert -background none "$SVG_FILE" -resize 16x16 "${ICONSET_DIR}/icon_16x16.png"
    convert -background none "$SVG_FILE" -resize 32x32 "${ICONSET_DIR}/icon_16x16@2x.png"
    convert -background none "$SVG_FILE" -resize 32x32 "${ICONSET_DIR}/icon_32x32.png"
    convert -background none "$SVG_FILE" -resize 64x64 "${ICONSET_DIR}/icon_32x32@2x.png"
    convert -background none "$SVG_FILE" -resize 128x128 "${ICONSET_DIR}/icon_128x128.png"
    convert -background none "$SVG_FILE" -resize 256x256 "${ICONSET_DIR}/icon_128x128@2x.png"
    convert -background none "$SVG_FILE" -resize 256x256 "${ICONSET_DIR}/icon_256x256.png"
    convert -background none "$SVG_FILE" -resize 512x512 "${ICONSET_DIR}/icon_256x256@2x.png"
    convert -background none "$SVG_FILE" -resize 512x512 "${ICONSET_DIR}/icon_512x512.png"
    convert -background none "$SVG_FILE" -resize 1024x1024 "${ICONSET_DIR}/icon_512x512@2x.png"
    
    echo "Icons generated successfully!"
    
elif command -v sips &> /dev/null; then
    echo "Using sips (built-in macOS tool)..."
    echo "You need to convert SVG to PNG first..."
    echo "Install ImageMagick: brew install imagemagick"
    echo "Or use an online converter to generate PNGs from the SVG"
    
else
    echo "Error: ImageMagick or sips not found"
    echo "Install ImageMagick: brew install imagemagick"
    exit 1
fi

