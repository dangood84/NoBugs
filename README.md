# No Bugs

A small parade of ants, ladybirds, beetles and caterpillars. They walk the tops of your windows and along the Dock, and every so often one of them keeps going, straight off the edge of the screen.

Every so often a ridiculous voice clears its throat and announces that there are no bugs.

Lazarus is not required. The program is built with the Free Pascal compiler alone.

## The joke, told accurately

On System 7.5 you could type `secret about box` into SimpleText and drag those words onto the desktop. A window opened: a flag over Cupertino, and if you waited, a picture of the team with the names scrolling past. The original Macintosh cases were signed on the inside of the mold. That was the machine introducing its authors.

It never said “No bugs!” The freshly installed system was simply pleased with itself. What did talk, in that season, was MacinTalk: SimpleText’s Sound menu, and Kathy, the American woman. This program shouts “No bugs!” in that voice, recorded at 11025 Hz and played at 22050. The samples and her pitches stay as they are. Only the rate in the header is a lie, so she finishes in half the time and an octave higher, while the evidence strolls along the title bars.

The walking is the old desktop-lemming idea. The windows are the level. A title bar is a kerb. The Dock is a promenade. When the kerb stops at the bezel, some of them turn around. The rest remember their training.

## Build

You need [Free Pascal](https://www.freepascal.org/) 3.2 or newer. On a Mac you also need the command-line tools, because a few lines of C run before Pascal starts. See [WORKINGS.md](WORKINGS.md) for why.

```bash
make
make test
./bin/nobugs
```

On Raspberry Pi OS or Debian, the host is GTK 2, the same family Lemmings Overlay uses, with the panel icon Eyes uses:

```bash
sudo apt install fpc libgtk2.0-dev libttspico-utils mpv
make linux
./bin/nobugs
```

On Windows 10, from a Free Pascal prompt:

```bash
make windows
bin\nobugs.exe
```

`make test` runs the geometry and parade checks and does not open a window. The Mac build is the one exercised here. Linux and Windows are built on those machines; the compiler there pulls in GTK or Win32, which this Mac does not have.

`make app` wraps the Mac build as `No Bugs.app`, a menu-bar extra with no Dock icon of its own. Double-click that, or copy it to Applications.

A sprite sheet, if you want to see the cast without the parade:

```bash
make preview
```

That writes `bin/preview.bmp`.

## Running it

The program does not take over the keyboard or the mouse. Clicks pass through. Look for the ladybird: in the Mac menu bar, in the Windows notification area, or in the Raspberry Pi panel.

- **Say "No bugs!"** — the chime, then Kathy’s shout, recorded at 11 kHz and played at 22 kHz
- **Pause the parade** — they hold still
- **About the signatures** — the System 7.5 note
- **Quit No Bugs** — or press Ctrl-C in the terminal

The first announcement arrives a few seconds after launch, so you know the voice works. After that it waits an irregular while. It is not a metronome.

On Windows the same program enumerates top-level windows, walks the taskbar, and asks for an American woman’s voice when one is installed. The ladybird sits in the notification area; right-click it for the menu. On Linux, pico2wave records an American woman and mpv plays the wav, through the same desktop sound a video uses. The overlay is a GTK 2 window that stays off the panel: no override-redirect, and no RGBA colormap unless a compositor is actually running, because on a Pi that colormap is a white sheet. The ladybird in the panel is a GtkStatusIcon, the call Eyes uses. Right-click it, or press Ctrl-C. A pure Wayland session still needs XWayland, which Raspberry Pi OS provides. The Mac build is the one that was run and watched.

## Layout

| Path | What it is |
| --- | --- |
| `src/launch.c` | Runs before Pascal. Pool, and the floating-point traps. |
| `src/nobugs.pas` | Entry point |
| `src/nbgeom.pas` | Ledges, including the parts a nearer window has buried |
| `src/nbsim.pas` | Walk, pause, hop, fall, leave |
| `src/nbsprites.pas` | The cast |
| `src/nbsound.pas` | The chime and the line |
| `src/hostmacos.pas` | Cocoa overlay |
| `src/hostwindows.pas` | Win32 overlay |
| `src/hostlinux.pas` | GTK 2 overlay and panel icon |
| [WORKINGS.md](WORKINGS.md) | How the pieces fit |
| [EXECUTION_FLOW.md](EXECUTION_FLOW.md) | What happens from launch to one frame |
