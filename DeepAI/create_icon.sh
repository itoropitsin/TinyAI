#!/bin/bash

# Скрипт для создания иконки приложения из SVG
# Требует: ImageMagick или sips (встроен в macOS)

SVG_FILE="icon_template.svg"
ICONSET_DIR="Assets.xcassets/AppIcon.appiconset"

echo "Создание иконки приложения..."

# Проверяем наличие ImageMagick
if command -v convert &> /dev/null; then
    echo "Используем ImageMagick..."
    
    # Создаем все необходимые размеры для macOS
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
    
    echo "Иконки созданы успешно!"
    
elif command -v sips &> /dev/null; then
    echo "Используем sips (встроенный инструмент macOS)..."
    echo "Сначала нужно конвертировать SVG в PNG..."
    echo "Установите ImageMagick: brew install imagemagick"
    echo "Или используйте онлайн-конвертер для создания PNG из SVG"
    
else
    echo "Ошибка: не найден ImageMagick или sips"
    echo "Установите ImageMagick: brew install imagemagick"
    exit 1
fi

