#!/bin/bash

# --- 配置变量 ---
APP_NAME="DeepSeekMonitor"
BINARY_NAME="DeepSeekMonitorApp"
ICON_NAME="deepseek_avatar.png"
BUNDLE_ID="com.local.deepseekmonitor"

echo "🚀 开始构建 $APP_NAME..."

# 1. 编译代码
echo "📦 正在编译 main.swift..."
if ! swiftc main.swift -o $BINARY_NAME; then
    echo "❌ 编译失败，请检查代码语法。"
    exit 1
fi

# 2. 重建 .app 结构
echo "📂 正在初始化 App 包结构..."
rm -rf ${APP_NAME}.app
mkdir -p ${APP_NAME}.app/Contents/MacOS
mkdir -p ${APP_NAME}.app/Contents/Resources

# 3. 移动文件
mv $BINARY_NAME ${APP_NAME}.app/Contents/MacOS/
if [ -f "$ICON_NAME" ]; then
    cp $ICON_NAME ${APP_NAME}.app/Contents/Resources/
    echo "✅ 图标已存入资源目录。"
else
    echo "⚠️ 未找到图标文件 $ICON_NAME，程序将使用默认系统图标。"
fi

# 4. 生成 Info.plist
echo "📝 写入 Info.plist 配置..."
cat <<EOF > ${APP_NAME}.app/Contents/Info.plist
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>$BINARY_NAME</string>
    <key>CFBundleIdentifier</key>
    <string>$BUNDLE_ID</string>
    <key>CFBundleName</key>
    <string>$APP_NAME</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>LSUIElement</key>
    <true/>
</dict>
</plist>
EOF

# 5. 彻底清理环境（解决 M1 签名报错的关键）
echo "🧹 清理 Finder 扩展属性与影子文件..."
xattr -cr ${APP_NAME}.app
dot_clean ${APP_NAME}.app

# 6. 本地重签名
echo "🔏 正在进行 Ad-hoc 签名..."
codesign --force --deep --sign - ${APP_NAME}.app

echo "✨ 构建完成！"
echo "👉 现在你可以双击运行 ${APP_NAME}.app 或在终端输入: open ${APP_NAME}.app"