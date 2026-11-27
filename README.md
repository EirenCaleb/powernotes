# PowerNotes

A notepad that does more than Notepad. One Flutter app for **Windows** and **Android**, working fully offline and syncing through your own PHP/MySQL server on Hostinger.

## What's inside

| Area | Features |
|---|---|
| Writing | Markdown with headings, checklists you can tick, tables, code blocks, quotes. Edit, preview, or side-by-side. |
| Organizing | Folders, tags, pinned notes, tabs for open notes on the laptop, trash with restore. |
| Finding | Instant search across titles, tags and text, with ranked results and snippets. |
| Safety | Autosave, version history going back days (Ctrl+S saves a version on demand), PIN plus fingerprint or Windows Hello lock for the whole app or single notes, optional end-to-end encryption. |
| Sync | Offline first. Syncs laptop and phone through your server, latest edit wins. |
| Capture | Share to PowerNotes from any Android app, voice typing, audio file transcription, photo or scan to text (works on handwriting too), Ctrl+Alt+N quick note from anywhere on the laptop, Android long-press shortcuts. |
| Smart | AI summarize, rewrite, fix grammar, English and Tagalog translation, turn into a to-do list, outline, continue writing, ask about a note. Reminders on any line. `[[Wiki links]]` between notes with a "Linked from" list. |
| Ministry and teaching | Insert Bible verses by reference (KJV, WEB, ASV, BBE, YLT). Templates for sermon outline, lesson plan, meeting minutes, Bible study, to-do and journal. Export to PDF, Word and Markdown, print, and share a read-only link. |
| Look | Light, dark or auto, six accent colors, adjustable text size, focus mode (F11), word count and reading time. |

## Folders

```
app/      Flutter app (Windows, Android)
server/   PHP API for Hostinger (sync, AI, share links)
```

## 1. Set up the server on Hostinger

1. In hPanel, create a MySQL database and user (e.g. `u123_powernotes`).
2. Open phpMyAdmin for it and run `server/schema.sql`.
3. Pick where it lives, for example a subdomain `notes.yourdomain.com`. Upload everything inside `server/` to that site's `public_html/`.
4. Copy `server/config.sample.php` to **one folder above** `public_html/`, rename it `powernotes_config.php`, and fill in the database details, `base_url`, and your Gemini key from https://aistudio.google.com/apikey. It must not be inside `public_html`.
5. Open `https://notes.yourdomain.com/` in a browser. You should see `PowerNotes server is running`.

The first account you create in the app is always allowed. After that, sign-ups are closed unless you set `allow_register` to `true`.

For audio transcription of long recordings, raise `upload_max_filesize` and `post_max_size` to 25M in hPanel > Advanced > PHP Configuration.

## 2. Run the app

Requires Flutter 3.50 or newer (run `flutter upgrade` first).

```bash
cd app
flutter pub get
flutter run -d windows     # laptop
flutter run                # Android phone or emulator
```

Build installers:

```bash
flutter build windows --release   # app\build\windows\x64\runner\Release\
flutter build apk --release       # app\build\app\outputs\flutter-apk\app-release.apk
```

Every push to `main` also builds both on GitHub Actions. Download them from the **Actions** tab under "Build apps", in the run's Artifacts.

Then in the app: **Settings > Sign in or create account**, enter your server address and an email and password. Do the same on the other device to sync.

## Keyboard shortcuts (laptop)

| Keys | Action |
|---|---|
| Ctrl+Alt+N | Quick note from anywhere, even when PowerNotes is in the background |
| Ctrl+N / Ctrl+Shift+N | New note / new from template |
| Ctrl+B, Ctrl+I | Bold, italic |
| Ctrl+K | Link to another note `[[ ]]` |
| Ctrl+E | Switch edit and preview |
| Ctrl+S | Save a version to history now |
| Ctrl+W | Close tab |
| F11 | Focus mode |

## Writing tips

- `- [ ] task` makes a checkbox you can tick in preview.
- Add a reminder to any line with the alarm button, or type `@remind(2026-12-01 09:00)` or `@due(2026-12-01)`. All of them show under **Reminders**.
- `[[Note title]]` links to another note. Clicking a link to a note that doesn't exist creates it.

## Security notes

- The Gemini key and database password live only in `powernotes_config.php` on the server.
- Passwords are stored with `password_hash`. API tokens are stored as SHA-256 hashes.
- With end-to-end encryption on, titles and bodies are encrypted on the device with AES-256-GCM before upload. If you forget the passphrase, synced notes cannot be recovered. AI and share links send the note text you choose to the server.
