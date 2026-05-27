# ListeningTo

`ListeningTo` is a lightweight, cross-platform Windows, Linux, and macOS system tray application that bridges your local active music playbacks to your Discord Rich Presence. 

It automatically detects active native desktop media players (such as Apple Music, Spotify, VLC, MusicBee, foobar2000, Tidal, and Lollypop) while intelligently filtering out web browsers (like Chrome, Firefox, Edge, and Brave) to prevent YouTube videos or other web media from polluting your Discord status.

## Key Features

- **Headless Background Process**: Runs silently in the system tray or menu bar with no GUI window or taskbar bloat.
- **Universal Desktop Media Support**: Reads title, artist, album, duration, and position directly from the system.
- **Zero Browser Spam**: Automatically ignores playback events coming from web browsers.
- **Auto-Reconnection**: Automatically detects when Discord is opened/closed and safely resumes Rich Presence updates.
- **Cross-Platform**: Uses Windows SMTC on Windows, MPRIS2 over D-Bus on Linux, and MediaRemote/ScriptingBridge on macOS.
- **Ultra-low Footprint**: Built natively in Rust + Tauri (Windows/Linux) and Swift (macOS), consuming negligible CPU and RAM.

---

## Tech Stack

- **Language**: Rust (Windows/Linux) & Swift (macOS)
- **Framework**: [Tauri v2](https://tauri.app/) (configured for tray-only headless execution on Windows/Linux)
- **Windows Backend**: Windows Runtime (WinRT) SMTC APIs (`windows` crate)
- **Linux Backend**: MPRIS2 client protocol (`mpris` and `dbus` crates)
- **macOS Backend**: Native `MediaRemote` (universal player monitoring) and `ScriptingBridge` (fallback API)
- **Discord Communication**: Local IPC Rich Presence Client (`discord-rich-presence` crate for Rust; direct Unix domain socket IPC for Swift)

---

## Prerequisites

To compile the application from source:

- **All platforms**: [Rust and Cargo](https://www.rust-lang.org/tools/install) (for Windows/Linux)
- **macOS**: Xcode Command Line Tools (for Swift compilation):
  ```bash
  xcode-select --install
  ```
- **Linux Specific**: You need D-Bus development headers and the Ayatana AppIndicator library:
  ```bash
  # Debian / Ubuntu / Mint / Pop!_OS:
  sudo apt install libayatana-appindicator3-dev libdbus-1-dev build-essential

  # Arch Linux / Manjaro:
  sudo pacman -S libayatana-appindicator dbus base-devel

  # Fedora / RHEL / CentOS:
  sudo dnf install libayatana-appindicator-devel dbus-devel
  ```

---

## Getting Started

### 1. Clone the Repository
```bash
git clone https://github.com/user/listeningto.git
cd listeningto
```

### 2. Run in Development Mode
```powershell
# Windows
cargo run --manifest-path src-tauri/Cargo.toml

# Linux
cargo run --manifest-path src-tauri/Cargo.toml

# macOS (Swift)
cd macos-swift && swift run
```

### 3. Build the Optimized Binary
To build the final production release executable:

#### Windows & Linux (Tauri)
1. Install the Tauri CLI tool (if you don't have it):
   ```bash
   cargo install tauri-cli
   ```
2. Build the production package:
   ```bash
   cargo tauri build
   ```

The compiled standalone executable will be located in:
- **Windows**: `src-tauri/target/release/ListeningTo.exe`
- **Linux**: `src-tauri/target/release/ListeningTo`

#### macOS (Swift native)
Build the release executable using Swift Package Manager:
```bash
cd macos-swift
swift build -c release
```
The compiled standalone executable will be located in:
- **macOS**: `macos-swift/.build/release/ListeningTo`

---

## Architecture Overview

```
[Media Player (Spotify, VLC, Apple Music...)] 
      │ 
      ▼ (Platform Media APIs)
  [Windows SMTC / Linux MPRIS / macOS MediaRemote & ScriptingBridge] 
      │ 
      ▼ (media_reader.rs / MusicReader.swift - platform implementations)
  [ListeningTo background loop (5s interval)]
      │ 
      ▼ (Local IPC via socket/named pipe)
[Discord Desktop Client]
```

### Platform Implementations:
- **Windows** (`src-tauri/src/media_reader.rs`): Regularly calls `GlobalSystemMediaTransportControlsSessionManager` to read active media sessions. It queries session App IDs to filter out browsers, then reads the media properties and timeline.
- **Linux** (`src-tauri/src/media_reader.rs`): Queries D-Bus using the `mpris` crate. It queries active MPRIS player identities, filters out browsers, and extracts song track info and current playback timeline.
- **macOS** (`macos-swift/Sources/ListeningTo/MusicReader.swift`): Dynamically loads Apple's private `MediaRemote` framework to capture track info from any system player. In case of macOS sandbox/entitlement restrictions (macOS 15.4+), it automatically falls back to `ScriptingBridge` queries for Apple Music and Spotify.

---

## Troubleshooting

### VLC player not showing on Windows
Unlike Spotify or Apple Music, VLC on Windows does not enable its SMTC (media controls integration) plugin by default. To make it show up in `ListeningTo`:
1. In VLC, go to **Tools** > **Preferences** (Ctrl + P).
2. Set "Show settings" at the bottom to **All** (Advanced settings).
3. Navigate to **Interface** > **Control interfaces**.
4. Check **System Media Transport Controls** (SMTC) integration.
5. Click **Save** and restart VLC.

---

## Running on Linux Startup (Autostart)
To make `ListeningTo` run automatically in the background when you log into your Linux desktop session:
1. Create an autostart desktop entry:
   ```bash
   nano ~/.config/autostart/listeningto.desktop
   ```
2. Paste the following configuration, ensuring you replace `/path/to/ListeningTo` with the absolute path to your compiled binary:
   ```ini
   [Desktop Entry]
   Type=Application
   Name=ListeningTo
   Comment=Discord Rich Presence Media Bridge
   Exec=/path/to/ListeningTo
   Terminal=false
   Categories=AudioVideo;Utility;
   ```
