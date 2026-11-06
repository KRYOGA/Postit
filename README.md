# Postit

A simple macOS sticky note app built with SwiftUI. Notes are saved automatically, and a global keyboard shortcut brings the app back into view.

## Features

- Create, edit, and delete notes, with confirmation before deletion
- Switch between notes in the sidebar; the first non-empty line becomes the title
- Customize background color and transparency across all notes
- Automatically adjust text color based on the background
- Save changes locally as you type
- Show the app window with a global keyboard shortcut

## Requirements

- macOS 13 Ventura or later
- Xcode Command Line Tools, including the Swift compiler

If Command Line Tools are not installed, run:

```bash
xcode-select --install
```

## Build and Run

```bash
git clone https://github.com/KRYOGA/Postit.git
cd Postit
./build.sh
open Postit.app
```

The build script creates `Postit.app` in the project directory. You can move it to your Applications folder if desired.

## Usage

1. Click **+** in the toolbar to add a note.
2. Select a note in the sidebar and edit its text. Changes are saved automatically.
3. Click **Background** in the toolbar to customize the background color and transparency.
4. Click the trash button to delete the selected note.

In the **Background** panel, enable **Transparent Background** and adjust **Transparency** to reveal the desktop or windows behind the note. At 0%, the background is opaque; at 100%, the background color is fully transparent. Text and controls remain fully opaque.

Background color, transparency, and the transparency switch apply to all existing and new notes. Settings are preserved across app restarts.

| Shortcut | Action |
| --- | --- |
| `⌘N` | Add a note |
| `⌃⌥⌘P` (Control + Option + Command + P) | Show the window while the app is running |
| `⌘Q` | Quit the app |

Closing the window does not quit the app. If the global shortcut conflicts with another app, change that app's shortcut and restart Postit.

## Data Storage

Notes are stored locally as JSON in:

```text
~/Library/Application Support/Postit/notes.json
```

Shared background settings are stored in macOS app preferences (`UserDefaults`).

The app does not send data to external servers. Note files are not encrypted. To back up your notes, quit the app and copy `notes.json`; background preferences are stored separately.

Saved notes are outside the repository, and the generated `Postit.app` is excluded by `.gitignore`.
