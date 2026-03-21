#!/bin/bash
# ─────────────────────────────────────────────────────────────
# AirDraw — скрипт сборки и упаковки .app для macOS
# ─────────────────────────────────────────────────────────────

set -e

APP_NAME="AirDraw"
BUNDLE="$APP_NAME.app"
BINARY_DIR=".build/release/$APP_NAME"

echo "╔══════════════════════════════════════╗"
echo "║  AirDraw — Сборка                    ║"
echo "╚══════════════════════════════════════╝"

# 1. Сборка
echo ""
echo "▶ Сборка Swift Package (Release)..."
swift build -c release 2>&1 | grep -E "(error:|warning:|Build complete)"

if [ ! -f "$BINARY_DIR" ]; then
    echo "✗ Ошибка: бинарник не найден в $BINARY_DIR"
    exit 1
fi

# 2. Создание структуры .app
echo "▶ Создание $BUNDLE..."
rm -rf "$BUNDLE"
mkdir -p "$BUNDLE/Contents/MacOS"
mkdir -p "$BUNDLE/Contents/Resources"

# 3. Копирование файлов
cp "$BINARY_DIR" "$BUNDLE/Contents/MacOS/$APP_NAME"
cp "Info.plist"  "$BUNDLE/Contents/"

# 4. Подпись (ad-hoc) — необходима для доступа к камере
echo "▶ Подпись приложения (ad-hoc)..."
codesign --force --deep --sign - \
    --entitlements entitlements.plist 2>/dev/null \
    "$BUNDLE" 2>/dev/null || \
codesign --force --deep --sign - "$BUNDLE"

echo ""
echo "╔══════════════════════════════════════╗"
echo "║  ✓ Готово! $BUNDLE создан             "
echo "╚══════════════════════════════════════╝"
echo ""
echo "Запустить: open $BUNDLE"
echo ""

# 5. Запрашиваем запуск
read -p "Запустить AirDraw прямо сейчас? (y/n): " RUN
if [[ "$RUN" == "y" || "$RUN" == "Y" ]]; then
    echo "▶ Запуск..."
    open "$BUNDLE"
fi
