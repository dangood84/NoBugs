# How No Bugs works

The program is one parade and three doors. The parade — ledges, bugs, sprites, the chime, the sentence — is ordinary Pascal and does not know which operating system it is on. A host watches the real desktop and paints the parade on top of it.

Lazarus is not in this picture. On a Mac the host calls Cocoa through the units that ship with Free Pascal. On Windows it calls Win32. On Linux it calls GTK 2, and X11 only to read the window list and the panel strut.

## Why a C file runs first

`src/launch.c` is a constructor, so it runs before `PASCALMAIN`.

Two things go wrong if it does not.

Cocoa autoreleases objects into a pool. Free Pascal’s own startup does not create one. The first AppKit object can then leak, complain, or abort. The constructor allocates an `NSAutoreleasePool` while the corridor is still empty.

Cocoa also produces denormal floating-point values as a matter of course. The Pascal runtime treats those as fatal exceptions. The constructor clears the trap bits in `FPCR`. `RunHost` masks them again with `SetExceptionMask`, because the RTL may reset the control register while it is starting up.

The pool and the mask are the whole of the C file. After that it is Pascal.

## Coordinates

Every ledge and every bug lives in one space:

- X grows to the right
- Y grows up
- The origin is the bottom-left of the primary display

That is AppKit’s space, and it is the space the simulation uses on every platform.

The Mac window server does not speak it. `CGWindowListCopyWindowInfo` returns rectangles whose origin is the top-left of the main display, with Y growing down. The host flips them once:

```
top    = primaryTop - cgY
bottom = primaryTop - (cgY + cgHeight)
```

Windows and X11 do the same flip from their own top-left, Y-down coordinates. Nothing past the host ever sees a downward Y.

## Ledges

`BuildLedges` in `nbgeom.pas` turns rectangles into pavement.

A window contributes its top edge, and only the part of that edge a nearer window has not covered. The window list arrives front to back. For each window, the spans already claimed by windows in front of it are subtracted. A buried title bar is not a floor. A bug standing there would be drawn in front of a window that is actually in front, which is a worse lie than the voice tells.

Two further cuts:

- An edge up inside the menu bar is dropped. The menu bar is busy.
- An edge with less than a bug’s height of air under the menu bar is dropped too. A maximised window’s top sits flush with that bar, and a creature standing on it would be hidden behind the clock. The Dock is still there.

The Dock, or the taskbar, is its own ledge. On a Mac the Dock process owns more windows than the Dock itself — one of them can be the full screen — so a candidate is kept only when it is a short strip sitting in the reserved margin. If none qualifies, the ledge is the top of that margin, across the width of the screen. That is the line the bugs were standing on when this was tried: just above the icons.

A centred Dock also leaves two lower floors, one on each side, at the bottom of the glass. Falling off the end of the Dock can land there. From there the screen edge is close.

Side Docks and side taskbars become vertical walls. The bugs walk up them.

## The parade

Each bug is a small state machine in `nbsim.pas`.

| State | What it is doing |
| --- | --- |
| Walk | Stepping along a ledge. If the window moves a little, the bug snaps to the new height and rides it. |
| Pause | A short loaf. Antennae still, feet still. |
| Fall | Gravity at 1500 points per second squared. Rising counts as falling, so a hop does not instantly re-stick to the ledge it left. On the way down, the highest ledge crossed is the landing. |
| Exit | The walk continues past the bezel. No gravity. When the sprite no longer touches any display, the bug is gone. |

At the lip of a ledge the bug rolls a die. Away from the screen edge it usually turns back, falls, or hops. On the Dock or the floor, close to the edge of the glass, it usually leaves. The population drifts back up afterwards, one arrival at a time, so a departure is visible instead of a pop.

A long pause in the run loop is clamped. One huge time step would let a beetle pass through a title bar without the crossing test noticing. Thirty-three milliseconds is the intended step. Fifty is the ceiling.

## Drawing

The cast is drawn into small RGBA sprites, two pixels per point, so a retina screen can show them 1:1. Feet are the anchor. The body sits above the ledge, with a soft shadow just under it. Left-facing frames are mirrors. Vertical frames are the same art turned, for a Dock that lives on the side.

The Mac host turns each sprite into a `CGImage` once and draws it with interpolation off. The window is borderless, non-opaque, click-through, and at level 21: above the Dock (20) and below the menu bar (24). One window per display, joined to every Space, ignored by the window cycle. The menu extra is a ladybird `NSImage`, installed the way Eyes installs its pair: the status item is retained, the image is not a template, and the title is not drawn beside it.

Windows blits into a top-down 32-bit DIB, swaps to BGRA, and hands it to `UpdateLayeredWindow`. The tray icon is `Shell_NotifyIconA` with a colour icon, which is the call that actually appears on Windows 10. Linux is GTK 2. The panel icon is `gtk_status_icon_new`, declared by hand because FPC's gtk2 unit omits it, which is how Eyes gets a picture into the Raspberry Pi panel. The picture is a 24 by 24 tray slot. The panel reserves that slot and paints nothing into it, so the ladybird is a small window drawn the same way as the parade. It stays hidden while the panel is still shuffling that slot past the clock and the language icon, then it is placed once on the slot’s left edge. A click on that window opens the menu. The overlay does not use override-redirect. It takes an RGBA colormap only when a compositor owns `_NET_WM_CM_S0`. Otherwise the bugs are a 1-bit shape, punched in after an empty shape, so the first frame is not a white sheet. The input shape is cleared again after every mask, because the mask call puts clicks back.

## The voice

`nbsound.pas` builds a short mallet chime, C-E-G, as a WAV in memory, and picks a sentence. Seven times out of ten the sentence is “No bugs!” The other lines are there so the second hearing is not a metronome.

The sentence is not spoken live. Kathy — MacinTalk’s American woman, the one SimpleText used on System 7.5 — records “No! Bugs!” at 11025 Hz. Samantha is the understudy. `SoundMasterWav` then rewrites the sample-rate field to 22050 and leaves every sample where it was, so her pitches go up exactly one octave and the shout finishes in half the time. `NSSound` plays the chime at its honest rate, and the lied wav as soon as `say` has finished writing it. The first one is scheduled for a few seconds after launch. Later ones wait somewhere between half a minute and a minute and a half, and they wait out a pause in the parade.

That finished wave is stored in the program. Windows plays the bytes with `PlaySound`. Linux opens one raw `pw-play` stream when the program starts and keeps writing silence into it, then writes Kathy’s samples into that same stream when a line is due. A copy of the wave is also left at a temp path. Neither machine records a voice of its own.

## What was watched

On this Mac the self-test passed, the Dock ledge landed on the top of the Dock, and the bugs were visible walking it: beetles, ladybirds, caterpillars, ants. The menu bar shows a ladybird. The headcount dipped whenever one of them walked off and came back a moment later. The spoken line is Kathy, recorded at 11025 Hz and played at 22050. Linux and Windows are compiled on those machines.
