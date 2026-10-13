unit hostlinux;

{
  Raspberry Pi and other Linux desktops. GTK 2, not a raw X window.

  Lemmings Overlay taught the expensive lessons, and this host keeps them:

  An override-redirect window sits on top of the panel menus and the
  desktop stops redrawing. This one is an ordinary undecorated window.

  An RGBA colormap on this Pi paints a white sheet even when the visual
  exists. The bugs stay on a normal visual as a 1-bit shape, and the
  first frame is an empty shape so the desktop is never covered in white.

  shape_combine_mask clears the input shape. Clicks are punched through
  again after every reshape, or the parade would steal the panel.

  A guessed panel height of 36 pixels leaves a white strip over the
  tray. The height comes from the work area and the strut, and anything
  under 56 is lifted to 56, which is what cleared that strip.

  FPC's gtk2 unit does not declare the status-icon calls. They are
  cdecl externals. The panel picture is a 24 by 24 pixbuf on that
  icon, the same way The Grouch Tribute does it, and the menu is
  built once. There is no second window. Ctrl-C still quits.

  Window ids come from libX11.so.6. The x and xlib Pascal units are
  not in this unit; their record layouts do not match the library.
}

{$mode objfpc}{$H+}

interface

procedure RunHost;

implementation

{$IFDEF LINUX}

uses
  SysUtils, Classes, Process, Math, BaseUnix, Unix, ctypes,
  gtk2, gdk2, gdk2pixbuf, glib2,
  nbtypes, nbgeom, nbsprites, nbsim, nbsound, nbvoice;

type
  PGtkStatusIcon = Pointer;
  TXDisplay = Pointer;
  TXWindow = culong;
  PXWindow = ^TXWindow;
  TXAtom = culong;
  TXWindowAttributes = record
    x, y: cint;
    width, height: cint;
    border_width: cint;
    depth: cint;
    visual: Pointer;
    root: TXWindow;
    class_: cint;
    bit_gravity: cint;
    win_gravity: cint;
    backing_store: cint;
    backing_planes: culong;
    backing_pixel: culong;
    save_under: cint;
    colormap: culong;
    map_installed: cint;
    map_state: cint;
    all_event_masks: clong;
    your_event_mask: clong;
    do_not_propagate_mask: clong;
    override_redirect: cint;
    screen: Pointer;
  end;

function gtk_status_icon_new: PGtkStatusIcon; cdecl; external;
procedure gtk_status_icon_set_from_pixbuf(icon: PGtkStatusIcon; pixbuf: PGdkPixbuf); cdecl; external;
procedure gtk_status_icon_set_visible(icon: PGtkStatusIcon; visible: gboolean); cdecl; external;
procedure gtk_status_icon_set_tooltip(icon: PGtkStatusIcon; text: Pgchar); cdecl; external;
function gtk_widget_get_window(widget: PGtkWidget): PGdkWindow; cdecl; external;
function gdk_screen_get_rgba_colormap(screen: PGdkScreen): PGdkColormap; cdecl; external;
procedure gdk_window_input_shape_combine_region(window: PGdkWindow;
  shape_region: PGdkRegion; offset_x, offset_y: gint); cdecl; external;
procedure gdk_window_shape_combine_region(window: PGdkWindow;
  shape_region: PGdkRegion; offset_x, offset_y: gint); cdecl; external;
function gdk_x11_get_default_xdisplay: TXDisplay; cdecl; external;
function gdk_x11_drawable_get_xid(drawable: PGdkDrawable): TXWindow; cdecl; external;

function XDefaultRootWindow(dpy: TXDisplay): TXWindow; cdecl; external 'libX11.so.6';
function XInternAtom(dpy: TXDisplay; name: PChar; onlyIfExists: LongInt): TXAtom; cdecl; external 'libX11.so.6';
function XGetWindowProperty(dpy: TXDisplay; w: TXWindow; prop: TXAtom;
  long_offset, long_length: clong; delete: LongInt; req_type: TXAtom;
  actual_type: Pointer; actual_format: Pointer; nitems: Pointer;
  bytes_after: Pointer; prop_return: Pointer): cint; cdecl; external 'libX11.so.6';
function XGetWindowAttributes(dpy: TXDisplay; w: TXWindow; attr: Pointer): cint; cdecl; external 'libX11.so.6';
function XFree(p: Pointer): cint; cdecl; external 'libX11.so.6';
function XGetSelectionOwner(dpy: TXDisplay; selection: TXAtom): TXWindow; cdecl; external 'libX11.so.6';
function XTranslateCoordinates(dpy: TXDisplay; src, dest: TXWindow;
  src_x, src_y: cint; dest_x, dest_y: Pcint; child_return: Pointer): LongInt;
  cdecl; external 'libX11.so.6';

const
  XA_WINDOW = 33;
  XA_CARDINAL = 6;
  XIsViewable = 2;
  ShapeAlpha = 48;
  { Same size as The Grouch Tribute's panel picture. }
  BarW = 24;
  BarH = 24;

var
  Overlay: PGtkWidget;
  OverlayPix: PGdkPixbuf;
  IconPix: PGdkPixbuf;
  StatusIcon: PGtkStatusIcon;
  BarMenu: PGtkWidget;
  OverlayPm: PGdkPixmap;
  OverlayPmW, OverlayPmH: Integer;
  ScreenW, ScreenH, PanelTop: Integer;
  OverlayXid: TXWindow;
  NeedShape: Boolean;
  WantQuit: Boolean;
  KathyPath: string;
  KathyUntil: TDateTime;
  ChannelRetry: TDateTime;
  Player: TProcess;
  ShoutPcm, Pending: TBytes;

function Dpy: TXDisplay;
begin
  Result := gdk_x11_get_default_xdisplay;
end;

function PropCardinal(Win: TXWindow; const Name: string; Index: Integer): Integer;
var
  Atom, Kind: TXAtom;
  Format: cint;
  NItems, After: culong;
  Prop: Pointer;
  Vals: pculong;
begin
  Result := -1;
  if Dpy = nil then
    Exit;
  Atom := XInternAtom(Dpy, PChar(Name), 0);
  Prop := nil;
  if (Atom = 0) or (XGetWindowProperty(Dpy, Win, Atom, 0, 16, 0, XA_CARDINAL,
    @Kind, @Format, @NItems, @After, @Prop) <> 0) then
    Exit;
  { Format 32 comes back as C long. On a 64-bit Pi that is 8 bytes, not 4. }
  if (Prop <> nil) and (Integer(NItems) > Index) then
  begin
    Vals := pculong(Prop);
    Result := Integer(Vals[Index]);
  end;
  if Prop <> nil then
    XFree(Prop);
end;

function CompositorRunning: Boolean;
var
  Atom: TXAtom;
begin
  Result := False;
  if Dpy = nil then
    Exit;
  Atom := XInternAtom(Dpy, '_NET_WM_CM_S0', 1);
  if Atom = 0 then
    Exit;
  Result := XGetSelectionOwner(Dpy, Atom) <> 0;
end;

function ReadPanelTop: Integer;
var
  Root: TXWindow;
  ListAtom, Kind: TXAtom;
  Format: cint;
  NItems, After: culong;
  Prop: Pointer;
  Wins: PXWindow;
  I, V, RootX, RootY: Integer;
  Child: TXWindow;
  Attr: TXWindowAttributes;
begin
  Result := 0;
  if Dpy = nil then
    Exit;
  Root := XDefaultRootWindow(Dpy);
  V := PropCardinal(Root, '_NET_WORKAREA', 1);
  if V > Result then
    Result := V;
  Prop := nil;
  ListAtom := XInternAtom(Dpy, '_NET_CLIENT_LIST', 0);
  if (ListAtom <> 0) and (XGetWindowProperty(Dpy, Root, ListAtom, 0, 256, 0,
    XA_WINDOW, @Kind, @Format, @NItems, @After, @Prop) = 0) and (Prop <> nil) then
  begin
    Wins := PXWindow(Prop);
    for I := 0 to Integer(NItems) - 1 do
    begin
      V := PropCardinal(Wins[I], '_NET_WM_STRUT_PARTIAL', 2);
      if V < 0 then
        V := PropCardinal(Wins[I], '_NET_WM_STRUT', 2);
      if V > Result then
        Result := V;
      FillChar(Attr, SizeOf(Attr), 0);
      if XGetWindowAttributes(Dpy, Wins[I], @Attr) = 0 then
        Continue;
      if Attr.map_state <> XIsViewable then
        Continue;
      RootX := Attr.x;
      RootY := Attr.y;
      Child := 0;
      XTranslateCoordinates(Dpy, Wins[I], Root, 0, 0, @RootX, @RootY, @Child);
      if (RootY <= 4) and (ScreenW > 0) and (Attr.width >= ScreenW - 16) and
         (Attr.height > 8) and (Attr.height <= 96) and (Attr.height > Result) then
        Result := Attr.height;
    end;
  end;
  if Prop <> nil then
    XFree(Prop);
  if Result < 56 then
    Result := 56;
  if Result > 96 then
    Result := 52;
end;

procedure RefreshStage;
var
  Root: TXWindow;
  ListAtom, Kind: TXAtom;
  Format: cint;
  NItems, After: culong;
  Prop: Pointer;
  Wins: PXWindow;
  I: Integer;
  Attr: TXWindowAttributes;
  Boxes: array of TBox;
  Displays: array[0..0] of TDisplay;
  Ledges: TLedgeList;
  WorkY, WorkH: Integer;
begin
  SetLength(Boxes, 0);
  if Dpy = nil then
    Exit;
  Root := XDefaultRootWindow(Dpy);
  ListAtom := XInternAtom(Dpy, '_NET_CLIENT_LIST', 0);
  Prop := nil;
  if (ListAtom <> 0) and (XGetWindowProperty(Dpy, Root, ListAtom, 0, 1024, 0,
    XA_WINDOW, @Kind, @Format, @NItems, @After, @Prop) = 0) and (Prop <> nil) then
  begin
    Wins := PXWindow(Prop);
    for I := 0 to Integer(NItems) - 1 do
    begin
      if Wins[I] = OverlayXid then
        Continue;
      FillChar(Attr, SizeOf(Attr), 0);
      if XGetWindowAttributes(Dpy, Wins[I], @Attr) = 0 then
        Continue;
      if Attr.map_state <> XIsViewable then
        Continue;
      if (Attr.width < 80) or (Attr.height < 48) then
        Continue;
      SetLength(Boxes, Length(Boxes) + 1);
      Boxes[High(Boxes)].Left := Attr.x;
      Boxes[High(Boxes)].Right := Attr.x + Attr.width;
      Boxes[High(Boxes)].Top := ScreenH - Attr.y;
      Boxes[High(Boxes)].Bottom := ScreenH - (Attr.y + Attr.height);
    end;
  end;
  if Prop <> nil then
    XFree(Prop);

  FillChar(Displays[0], SizeOf(Displays[0]), 0);
  Displays[0].Frame.Right := ScreenW;
  Displays[0].Frame.Top := ScreenH;
  Displays[0].Work := Displays[0].Frame;
  Displays[0].DockEdge := deNone;
  WorkY := PropCardinal(Root, '_NET_WORKAREA', 1);
  WorkH := PropCardinal(Root, '_NET_WORKAREA', 3);
  if (WorkY >= 0) and (WorkH > 0) then
  begin
    Displays[0].Work.Top := ScreenH - WorkY;
    Displays[0].Work.Bottom := ScreenH - (WorkY + WorkH);
    Displays[0].Work.Left := PropCardinal(Root, '_NET_WORKAREA', 0);
    Displays[0].Work.Right := Displays[0].Work.Left + PropCardinal(Root, '_NET_WORKAREA', 2);
    if Displays[0].Work.Bottom > 24 then
      Displays[0].DockEdge := deBottom;
  end;
  BuildLedges(Boxes, Displays, Ledges);
  if Parade = nil then
    Parade := TWorld.Create;
  Parade.SetStage(Displays, Ledges);
end;

procedure PaintParade;
var
  Pixels: PByte;
  I, W, H: Integer;
  B: TBug;
  YDraw: Double;
begin
  if OverlayPix = nil then
    Exit;
  W := gdk_pixbuf_get_width(OverlayPix);
  H := gdk_pixbuf_get_height(OverlayPix);
  Pixels := PByte(gdk_pixbuf_get_pixels(OverlayPix));
  FillChar(Pixels^, H * gdk_pixbuf_get_rowstride(OverlayPix), 0);
  if Parade = nil then
    Exit;
  for I := 0 to High(Parade.Bugs) do
  begin
    B := Parade.Bugs[I];
    if not B.Alive then
      Continue;
    YDraw := B.Y;
    if (B.State = stWalk) or (B.State = stExit) then
      YDraw := YDraw + Sin(B.Phase * 1.6) * 0.85;
    BlitSprite(SpriteFor(B), B.X, YDraw, 0, ScreenH - PanelTop, Pixels, W, H,
      gdk_pixbuf_get_rowstride(OverlayPix));
  end;
end;

procedure HardenAlpha(Pix: PGdkPixbuf);
var
  Pixels, P: PByte;
  X, Y, W, H, Stride: Integer;
begin
  if (Pix = nil) or not gdk_pixbuf_get_has_alpha(Pix) then
    Exit;
  W := gdk_pixbuf_get_width(Pix);
  H := gdk_pixbuf_get_height(Pix);
  Stride := gdk_pixbuf_get_rowstride(Pix);
  Pixels := PByte(gdk_pixbuf_get_pixels(Pix));
  for Y := 0 to H - 1 do
  begin
    P := Pixels + Y * Stride;
    for X := 0 to W - 1 do
    begin
      if P[3] < ShapeAlpha then
      begin
        P[0] := 0;
        P[1] := 0;
        P[2] := 0;
        P[3] := 0;
      end
      else
        P[3] := 255;
      Inc(P, 4);
    end;
  end;
end;

procedure PunchInput(Win: PGdkWindow);
var
  Region: PGdkRegion;
begin
  if Win = nil then
    Exit;
  Region := gdk_region_new;
  gdk_window_input_shape_combine_region(Win, Region, 0, 0);
  gdk_region_destroy(Region);
end;

procedure HideAll(Win: PGdkWindow);
var
  Region: PGdkRegion;
begin
  if Win = nil then
    Exit;
  Region := gdk_region_new;
  gdk_window_shape_combine_region(Win, Region, 0, 0);
  gdk_region_destroy(Region);
end;

procedure ShapeToBugs(Win: PGdkWindow);
var
  Mask: PGdkPixmap;
  W, H: Integer;
begin
  if Win = nil then
    Exit;
  if OverlayPix = nil then
  begin
    HideAll(Win);
    PunchInput(Win);
    Exit;
  end;
  W := gdk_pixbuf_get_width(OverlayPix);
  H := gdk_pixbuf_get_height(OverlayPix);
  Mask := gdk_pixmap_new(Win, W, H, 1);
  if Mask = nil then
    Exit;
  gdk_pixbuf_render_threshold_alpha(OverlayPix, Mask, 0, 0, 0, 0, W, H, ShapeAlpha);
  gdk_window_shape_combine_mask(Win, Mask, 0, 0);
  g_object_unref(Mask);
  PunchInput(Win);
end;

procedure PresentShaped(Win: PGdkWindow);
var
  Gc: PGdkGC;
  Src: Pguchar;
begin
  if (Win = nil) or (OverlayPix = nil) then
    Exit;
  if (OverlayPm = nil) or (OverlayPmW <> gdk_pixbuf_get_width(OverlayPix)) or
     (OverlayPmH <> gdk_pixbuf_get_height(OverlayPix)) then
  begin
    if OverlayPm <> nil then
      g_object_unref(OverlayPm);
    OverlayPmW := gdk_pixbuf_get_width(OverlayPix);
    OverlayPmH := gdk_pixbuf_get_height(OverlayPix);
    OverlayPm := gdk_pixmap_new(Win, OverlayPmW, OverlayPmH, -1);
  end;
  if OverlayPm = nil then
    Exit;
  Gc := gdk_gc_new(OverlayPm);
  Src := gdk_pixbuf_get_pixels(OverlayPix);
  gdk_draw_rgb_32_image(OverlayPm, Gc, 0, 0, OverlayPmW, OverlayPmH,
    GDK_RGB_DITHER_NONE, Src, gdk_pixbuf_get_rowstride(OverlayPix));
  g_object_unref(Gc);
  gdk_window_set_back_pixmap(Win, OverlayPm, False);
  ShapeToBugs(Win);
  gdk_window_clear(Win);
end;

procedure Present;
var
  Win: PGdkWindow;
begin
  PaintParade;
  if NeedShape then
    HardenAlpha(OverlayPix);
  Win := gtk_widget_get_window(Overlay);
  if NeedShape then
    PresentShaped(Win)
  else if Overlay <> nil then
  begin
    PunchInput(Win);
    gtk_widget_queue_draw(Overlay);
  end;
end;

function WavePcm(const Wav: TBytes): TBytes;
var
  I, N: Integer;
begin
  Result := nil;
  I := 12;
  while I + 8 <= Length(Wav) do
  begin
    N := Integer(Wav[I + 4]) or (Integer(Wav[I + 5]) shl 8) or
      (Integer(Wav[I + 6]) shl 16) or (Integer(Wav[I + 7]) shl 24);
    if (Wav[I] = Ord('d')) and (Wav[I + 1] = Ord('a')) and
      (Wav[I + 2] = Ord('t')) and (Wav[I + 3] = Ord('a')) then
    begin
      if (N < 0) or (I + 8 + N > Length(Wav)) then
        N := Length(Wav) - (I + 8);
      SetLength(Result, N);
      if N > 0 then
        Move(Wav[I + 8], Result[0], N);
      Exit;
    end;
    if N < 0 then
      Break;
    I := I + 8 + N;
  end;
end;

procedure InstallKathy;
var
  Wav: TBytes;
  F: File;
begin
  Wav := KathyShout;
  ShoutPcm := WavePcm(Wav);
  KathyPath := IncludeTrailingPathDelimiter(GetTempDir) + 'nobugs-kathy.wav';
  AssignFile(F, KathyPath);
  Rewrite(F, 1);
  if Length(Wav) > 0 then
    BlockWrite(F, Wav[0], Length(Wav));
  CloseFile(F);
  KathyUntil := 0;
  ChannelRetry := 0;
  Pending := nil;
end;

procedure EnqueueSilence(N: Integer);
var
  Old: Integer;
begin
  if (N <= 0) or (Length(Pending) > 44100) then
    Exit;
  Old := Length(Pending);
  SetLength(Pending, Old + N);
  FillChar(Pending[Old], N, 0);
end;

procedure Pump;
var
  Got: Integer;
begin
  if (Player = nil) or not Player.Running or (Length(Pending) = 0) then
    Exit;
  Got := FileWrite(Player.Input.Handle, Pending[0], Length(Pending));
  if Got > 0 then
    Delete(Pending, 0, Got);
end;

procedure DrainPlayer;
var
  Buf: array[0..255] of Byte;
  N: Integer;
begin
  if (Player = nil) or (Player.Output = nil) then
    Exit;
  repeat
    N := FileRead(Player.Output.Handle, Buf, SizeOf(Buf));
  until N <= 0;
end;

procedure Unblock(H: THandle);
var
  Flags: cint;
begin
  Flags := fpfcntl(H, F_GETFL);
  if Flags >= 0 then
    fpfcntl(H, F_SETFL, Flags or O_NONBLOCK);
end;

procedure OpenChannel;
var
  Exe, Name: string;
begin
  FreeAndNil(Player);
  if FileExists('/usr/bin/pw-play') then
    Exe := '/usr/bin/pw-play'
  else if FileExists('/usr/bin/pw-cat') then
    Exe := '/usr/bin/pw-cat'
  else if FileExists('/usr/bin/paplay') then
    Exe := '/usr/bin/paplay'
  else
    Exe := '/usr/bin/aplay';
  if not FileExists(Exe) then
  begin
    Writeln('no pw-play, paplay, or aplay');
    Flush(Output);
    ChannelRetry := Now + 30 / 86400;
    Exit;
  end;
  { One raw stream for the life of the program. Silence keeps the HDMI
    port awake; a shout is just more samples on that same stream. }
  Player := TProcess.Create(nil);
  Player.Executable := Exe;
  Name := ExtractFileName(Exe);
  if (Name = 'pw-play') or (Name = 'pw-cat') then
  begin
    if Name = 'pw-cat' then
      Player.Parameters.Add('--playback');
    Player.Parameters.Add('--raw');
    Player.Parameters.Add('--format=s16');
    Player.Parameters.Add('--rate=22050');
    Player.Parameters.Add('--channels=1');
    Player.Parameters.Add('-');
  end
  else if Name = 'paplay' then
  begin
    Player.Parameters.Add('--raw');
    Player.Parameters.Add('--format=s16le');
    Player.Parameters.Add('--rate=22050');
    Player.Parameters.Add('--channels=1');
  end
  else
  begin
    Player.Parameters.Add('-q');
    Player.Parameters.Add('-t');
    Player.Parameters.Add('raw');
    Player.Parameters.Add('-f');
    Player.Parameters.Add('S16_LE');
    Player.Parameters.Add('-r');
    Player.Parameters.Add('22050');
    Player.Parameters.Add('-c');
    Player.Parameters.Add('1');
  end;
  Player.Options := [poUsePipes];
  try
    Player.Execute;
  except
    FreeAndNil(Player);
    ChannelRetry := Now + 5 / 86400;
    Exit;
  end;
  if not Player.Running then
  begin
    Writeln('audio channel did not stay open');
    Flush(Output);
    FreeAndNil(Player);
    ChannelRetry := Now + 5 / 86400;
    Exit;
  end;
  Unblock(Player.Input.Handle);
  if Player.Output <> nil then
    Unblock(Player.Output.Handle);
  ChannelRetry := Now + 365;
  Writeln('audio channel open');
  Flush(Output);
  EnqueueSilence(22050);
  Pump;
end;

procedure FeedChannel;
begin
  if (Player <> nil) and not Player.Running then
  begin
    Writeln('audio channel closed');
    Flush(Output);
    FreeAndNil(Player);
    ChannelRetry := Now + 2 / 86400;
  end;
  if ((Player = nil) or not Player.Running) and (Now >= ChannelRetry) then
    OpenChannel;
  if (Player = nil) or not Player.Running then
    Exit;
  DrainPlayer;
  if Length(Pending) < 1470 * 6 then
    EnqueueSilence(1470);
  Pump;
end;

procedure AppendPcm(const Extra: TBytes);
var
  Old: Integer;
begin
  if Length(Extra) = 0 then
    Exit;
  Old := Length(Pending);
  SetLength(Pending, Old + Length(Extra));
  Move(Extra[0], Pending[Old], Length(Extra));
end;

procedure PlayKathy;
begin
  if Length(ShoutPcm) = 0 then
    Exit;
  if (Player = nil) or not Player.Running then
    OpenChannel;
  AppendPcm(ShoutPcm);
  KathyUntil := Now + (Length(ShoutPcm) / 44100 + 0.4) / 86400;
  Writeln('saying: No bugs! (Kathy)');
  Flush(Output);
  Pump;
end;

function SpeechIdle: Boolean;
begin
  Result := Now >= KathyUntil;
end;

procedure OnQuit(Widget: PGtkWidget; Data: gpointer); cdecl;
begin
  gtk_main_quit;
end;

procedure OnAbout(Widget: PGtkWidget; Data: gpointer); cdecl;
var
  Dlg: PGtkWidget;
begin
  Dlg := gtk_message_dialog_new(nil, GTK_DIALOG_MODAL, GTK_MESSAGE_INFO,
    GTK_BUTTONS_OK, PChar(AboutBlurb));
  gtk_window_set_title(PGtkWindow(Dlg), 'No Bugs');
  gtk_dialog_run(PGtkDialog(Dlg));
  gtk_widget_destroy(Dlg);
end;

procedure OnSay(Widget: PGtkWidget; Data: gpointer); cdecl;
begin
  if SpeechIdle then
    PlayKathy;
end;

procedure OnPause(Widget: PGtkWidget; Data: gpointer); cdecl;
begin
  if Parade <> nil then
    Parade.Paused := not Parade.Paused;
end;

function BuildBarMenu: PGtkWidget;
var
  Menu, Item: PGtkWidget;
begin
  Menu := gtk_menu_new;
  Item := gtk_menu_item_new_with_label('Say "No bugs!"');
  g_signal_connect(G_OBJECT(Item), 'activate', G_CALLBACK(@OnSay), nil);
  gtk_menu_shell_append(PGtkMenuShell(Menu), Item);
  Item := gtk_menu_item_new_with_label('Pause or resume');
  g_signal_connect(G_OBJECT(Item), 'activate', G_CALLBACK(@OnPause), nil);
  gtk_menu_shell_append(PGtkMenuShell(Menu), Item);
  Item := gtk_separator_menu_item_new;
  gtk_menu_shell_append(PGtkMenuShell(Menu), Item);
  Item := gtk_menu_item_new_with_label('About the signatures');
  g_signal_connect(G_OBJECT(Item), 'activate', G_CALLBACK(@OnAbout), nil);
  gtk_menu_shell_append(PGtkMenuShell(Menu), Item);
  Item := gtk_menu_item_new_with_label('Quit No Bugs');
  g_signal_connect(G_OBJECT(Item), 'activate', G_CALLBACK(@OnQuit), nil);
  gtk_menu_shell_append(PGtkMenuShell(Menu), Item);
  gtk_widget_show_all(Menu);
  Result := Menu;
end;

procedure OnStatusPopup(Icon: PGtkStatusIcon; Button: guint; ActivateTime: guint32;
  Data: gpointer); cdecl;
begin
  if BarMenu = nil then
    BarMenu := BuildBarMenu;
  gtk_menu_popup(PGtkMenu(BarMenu), nil, nil, nil, nil, Button, ActivateTime);
end;

procedure OnSig(sig: cint); cdecl;
begin
  WantQuit := True;
end;

procedure PushBarIcon;
begin
  if (StatusIcon <> nil) and (IconPix <> nil) then
    gtk_status_icon_set_from_pixbuf(StatusIcon, IconPix);
end;

function OnTick(Data: gpointer): gboolean; cdecl;
var
  Line: string;
begin
  if WantQuit then
  begin
    gtk_main_quit;
    Result := False;
    Exit;
  end;
  FeedChannel;
  PushBarIcon;
  RefreshStage;
  if Parade <> nil then
  begin
    Parade.Tick(1 / 30);
    if SpeechIdle then
    begin
      Line := Parade.ClaimAnnouncement;
      if Line <> '' then
        PlayKathy;
    end;
  end;
  Present;
  Result := True;
end;

function OnExpose(Widget: PGtkWidget; Event: PGdkEvent; Data: gpointer): gboolean; cdecl;
begin
  Result := True;
  if (Widget = nil) or (Widget^.window = nil) or (OverlayPix = nil) then
    Exit;
  if NeedShape then
    PresentShaped(Widget^.window)
  else
    gdk_draw_pixbuf(Widget^.window, nil, OverlayPix, 0, 0, 0, 0, -1, -1,
      GDK_RGB_DITHER_NONE, 0, 0);
  PunchInput(Widget^.window);
end;

procedure OnRealize(Widget: PGtkWidget; Data: gpointer); cdecl;
var
  Win: PGdkWindow;
begin
  Win := gtk_widget_get_window(Widget);
  if not NeedShape then
    gdk_window_set_back_pixmap(Win, nil, False);
  HideAll(Win);
  PunchInput(Win);
end;

function OnMap(Widget: PGtkWidget; Event: PGdkEvent; Data: gpointer): gboolean; cdecl;
var
  Win: PGdkWindow;
begin
  Win := gtk_widget_get_window(Widget);
  if Win <> nil then
    OverlayXid := gdk_x11_drawable_get_xid(Win);
  PunchInput(Win);
  Result := False;
end;

procedure FillBarPix;
var
  Bug: TBug;
  S: TSprite;
  Raw, P, Dst: PByte;
  X, Y, SX, SY, Stride: Integer;
  MinX, MinY, MaxX, MaxY, SW, SH, DW, DH, OX, OY, DX, DY: Integer;
  R, G, B: Byte;
begin
  if IconPix = nil then
    Exit;
  Raw := PByte(gdk_pixbuf_get_pixels(IconPix));
  if Raw = nil then
    Exit;
  Stride := gdk_pixbuf_get_rowstride(IconPix);
  { Every pixel is opaque. A transparent pixbuf is the blank gap in the
    panel: the slot is reserved, and the bar shows through it. }
  for Y := 0 to BarH - 1 do
  begin
    Dst := Raw + Y * Stride;
    for X := 0 to BarW - 1 do
    begin
      Dst[0] := 236;
      Dst[1] := 232;
      Dst[2] := 214;
      Dst[3] := 255;
      Inc(Dst, 4);
    end;
  end;
  FillChar(Bug, SizeOf(Bug), 0);
  Bug.Species := spLadybug;
  Bug.Dir := 1;
  Bug.Horizontal := True;
  Bug.Alive := True;
  S := SpriteFor(Bug);
  if (S.Pixels = nil) or (S.W < 1) or (S.H < 1) then
    Exit;
  MinX := S.W;
  MinY := S.H;
  MaxX := -1;
  MaxY := -1;
  for Y := 0 to S.H - 1 do
    for X := 0 to S.W - 1 do
    begin
      P := S.Pixels + (Y * S.W + X) * 4;
      if P[3] <= 40 then
        Continue;
      if X < MinX then
        MinX := X;
      if Y < MinY then
        MinY := Y;
      if X > MaxX then
        MaxX := X;
      if Y > MaxY then
        MaxY := Y;
    end;
  if MaxX < MinX then
    Exit;
  SW := MaxX - MinX + 1;
  SH := MaxY - MinY + 1;
  DW := BarW - 2;
  DH := BarH - 2;
  if SW * DH > SH * DW then
  begin
    DH := SH * DW div SW;
    if DH < 1 then
      DH := 1;
  end
  else
  begin
    DW := SW * DH div SH;
    if DW < 1 then
      DW := 1;
  end;
  OX := (BarW - DW) div 2;
  OY := (BarH - DH) div 2;
  for DY := 0 to DH - 1 do
    for DX := 0 to DW - 1 do
    begin
      SX := MinX + DX * SW div DW;
      SY := MinY + DY * SH div DH;
      if SX > MaxX then
        SX := MaxX;
      if SY > MaxY then
        SY := MaxY;
      P := S.Pixels + (SY * S.W + SX) * 4;
      if P[3] <= 40 then
        Continue;
      R := P[0];
      G := P[1];
      B := P[2];
      if P[3] < 255 then
      begin
        R := Byte((Integer(R) * P[3] + 236 * (255 - P[3])) div 255);
        G := Byte((Integer(G) * P[3] + 232 * (255 - P[3])) div 255);
        B := Byte((Integer(B) * P[3] + 214 * (255 - P[3])) div 255);
      end;
      Dst := Raw + (OY + DY) * Stride + (OX + DX) * 4;
      Dst[0] := R;
      Dst[1] := G;
      Dst[2] := B;
      Dst[3] := 255;
    end;
end;

procedure InstallIcon;
begin
  { The Grouch Tribute's panel picture: a 24 by 24 pixbuf on the status
    icon, and one menu kept for the life of the program. Right-click that. }
  IconPix := gdk_pixbuf_new(GDK_COLORSPACE_RGB, True, 8, BarW, BarH);
  FillBarPix;
  StatusIcon := gtk_status_icon_new;
  gtk_status_icon_set_tooltip(StatusIcon, 'No Bugs');
  g_signal_connect(G_OBJECT(StatusIcon), 'popup-menu', TGCallback(@OnStatusPopup), nil);
  PushBarIcon;
end;

procedure RunHost;
var
  Screen: PGdkScreen;
  ViewH: Integer;
begin
  gtk_init(@argc, @argv);
  BuildSprites;
  InstallKathy;
  OpenChannel;
  WantQuit := False;
  FpSignal(SIGINT, @OnSig);
  FpSignal(SIGTERM, @OnSig);

  Screen := gdk_screen_get_default;
  ScreenW := gdk_screen_get_width(Screen);
  ScreenH := gdk_screen_get_height(Screen);
  { An RGBA colormap on this Pi paints a white sheet. The bugs stay a 1-bit shape. }
  NeedShape := True;
  PanelTop := ReadPanelTop;
  ViewH := ScreenH - PanelTop;
  if ViewH < 1 then
    ViewH := ScreenH;

  InstallIcon;

  OverlayPix := gdk_pixbuf_new(GDK_COLORSPACE_RGB, True, 8, ScreenW, ViewH);
  Overlay := gtk_window_new(GTK_WINDOW_TOPLEVEL);
  gtk_window_set_title(PGtkWindow(Overlay), 'No Bugs');
  gtk_window_set_decorated(PGtkWindow(Overlay), False);
  gtk_window_set_keep_above(PGtkWindow(Overlay), True);
  gtk_window_set_skip_taskbar_hint(PGtkWindow(Overlay), True);
  gtk_window_set_skip_pager_hint(PGtkWindow(Overlay), True);
  gtk_window_set_accept_focus(PGtkWindow(Overlay), False);
  gtk_widget_set_app_paintable(Overlay, True);
  gtk_widget_set_double_buffered(Overlay, False);
  gtk_window_move(PGtkWindow(Overlay), 0, PanelTop);
  gtk_window_resize(PGtkWindow(Overlay), ScreenW, ViewH);
  g_signal_connect(G_OBJECT(Overlay), 'delete-event', G_CALLBACK(@OnQuit), nil);
  g_signal_connect(G_OBJECT(Overlay), 'realize', G_CALLBACK(@OnRealize), nil);
  g_signal_connect(G_OBJECT(Overlay), 'map-event', G_CALLBACK(@OnMap), nil);
  g_signal_connect(G_OBJECT(Overlay), 'expose-event', G_CALLBACK(@OnExpose), nil);

  gtk_widget_realize(Overlay);
  if gtk_widget_get_window(Overlay) <> nil then
  begin
    HideAll(gtk_widget_get_window(Overlay));
    PunchInput(gtk_widget_get_window(Overlay));
  end;
  RefreshStage;
  if Parade <> nil then
    Parade.FillRoster;
  Present;
  gtk_widget_show_all(Overlay);
  PunchInput(gtk_widget_get_window(Overlay));
  Writeln('No Bugs is walking the window ledges.');
  Writeln('The ladybird is in the panel. Right-click it, or press Ctrl-C.');
  g_timeout_add(33, TGSourceFunc(@OnTick), nil);
  PushBarIcon;
  gtk_main;
  FreeAndNil(Player);
  if Parade <> nil then
    FreeAndNil(Parade);
end;

{$ELSE}

procedure RunHost;
begin
end;

{$ENDIF}

end.
