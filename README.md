# DeepSeek Monitor

[简体中文](README.zh-CN.md)

A macOS menu bar app that displays real-time DeepSeek API platform metrics including balance, monthly cost, per-model token usage, and consumption trends.

## Features

- Current balance & monthly cost
- Per-model cost breakdown + token usage progress bar (cap: 100M tokens)
- 7-day token consumption trend bar chart
- Auto-refresh every hour, with manual refresh support

## Screenshot

![DeepSeek Monitor UI](DeepSeekMonitor_UI.png)

## Getting Started

### 1. Get credentials

Log in to [DeepSeek Platform](https://platform.deepseek.com), then:

- **Cookie**: DevTools → Application → Cookies → copy all cookies for the site
- **Token**: DevTools → Network → pick any API request → copy the `Authorization` header (`Bearer xxx`)

### 2. Set credentials

Edit `main.swift` lines 108-109:

```swift
private let cookie = "YOUR_COOKIE_HERE"
private let auth = "Bearer YOUR_TOKEN_HERE"
```

### 3. Build & Run

```bash
./build.sh && open DeepSeekMonitor.app
```

## Tech

- SwiftUI + Swift Charts for UI
- `NSStatusBar` + `NSPopover` for menu bar integration
- `LSUIElement = true` to hide the Dock icon (menu bar only)
- `DispatchGroup` for concurrent API requests, `Timer` for periodic refresh

## License

MIT
