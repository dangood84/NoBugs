unit hostlinux;

{
  Raspberry Pi and other Linux desktops. GTK 2, not a raw X window.

  Lemmings Overlay taught the expensive lessons, and this host keeps them:

  An override-redirect window sits on top of the panel menus and the
  desktop stops redrawing. This one is an ordinary undecorated window.

  An RGBA colormap with no compositor is painted as a white sheet.
  The colormap is used only when _NET_WM_CM_S0 actually has an owner.
  Otherwise the bugs are a 1-bit shape, and the first frame is an empty
  shape so the desktop is never covered in white while we wake up.

  shape_combine_mask clears the input shape. Clicks are punched through
  again after every reshape, or the parade would steal the panel.

  A guessed panel height of 36 pixels leaves a white strip over the
  tray. The height comes from the work area and the strut, and anything
  under 56 is lifted to 56, which is what cleared that strip.

  FPC's gtk2 unit does not declare the status-icon calls. They are
  cdecl externals, the same way Eyes reaches the panel. That icon is
  the one that shows up. Ctrl-C still works if a panel ignores it.

  Window ids come from libX11.so.6. The x and xlib Pascal units are
  not in this unit; their record layouts do not match the library.
}

{$mode objfpc}{$H+}

interface

procedure RunHost;

implementation

{$IFDEF LINUX}

uses
  SysUtils, Classes, Math, BaseUnix, Unix, ctypes,
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
procedure gtk_status_icon_set_tooltip_text(icon: PGtkStatusIcon; text: Pgchar); cdecl; external;
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
  IconN = 32;

var
  Overlay: PGtkWidget;
  OverlayPix: PGdkPixbuf;
  IconPix: PGdkPixbuf;
  StatusIcon: PGtkStatusIcon;
  OverlayPm: PGdkPixmap;
  OverlayPmW, OverlayPmH: Integer;
  ScreenW, ScreenH, PanelTop: Integer;
  OverlayXid: TXWindow;
  NeedShape: Boolean;
  WantQuit: Boolean;
  KathyPath: string;
  KathyUntil: TDateTime;

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

procedure InstallKathy;
var
  Wav: TBytes;
  F: File;
begin
  Wav := KathyShout;
  KathyPath := IncludeTrailingPathDelimiter(GetTempDir) + 'nobugs-kathy.wav';
  AssignFile(F, KathyPath);
  Rewrite(F, 1);
  if Length(Wav) > 0 then
    BlockWrite(F, Wav[0], Length(Wav));
  CloseFile(F);
  KathyUntil := 0;
end;

procedure PlayKathy;
var
  Cmd: string;
begin
  { The same two-step Lemmings uses. paplay hits the desktop mixer.
    aplay is only there if paplay is missing. No device name: naming
    the HDMI sink was what left the television quiet. }
  if KathyPath = '' then
    Exit;
  Cmd := '(paplay ''' + KathyPath + ''' || aplay -q ''' + KathyPath +
    ''') >/dev/null 2>&1 &';
  fpSystem(Cmd);
  KathyUntil := Now + (WavPlaybackSeconds(KathyShout) + 0.2) / 86400;
  Writeln('saying: No bugs! (Kathy)');
  Flush(Output);
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

procedure Popup(Button: guint; When: guint32);
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
  gtk_menu_popup(PGtkMenu(Menu), nil, nil, nil, nil, Button, When);
end;

procedure OnStatusPopup(Icon: PGtkStatusIcon; Button: guint; ActivateTime: guint32;
  Data: gpointer); cdecl;
begin
  Popup(Button, ActivateTime);
end;

procedure OnSig(sig: cint); cdecl;
begin
  WantQuit := True;
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

procedure InstallIcon;
var
  Pixels: array of Byte;
  Raw: PByte;
  Y, Stride: Integer;
begin
  SetLength(Pixels, IconN * IconN * 4);
  PaintLadybugIcon(@Pixels[0], IconN, IconN);
  IconPix := gdk_pixbuf_new(GDK_COLORSPACE_RGB, True, 8, IconN, IconN);
  Raw := PByte(gdk_pixbuf_get_pixels(IconPix));
  if Raw <> nil then
  begin
    { Rowstride can be wider than the pixels. A single Move shears the bug. }
    Stride := gdk_pixbuf_get_rowstride(IconPix);
    for Y := 0 to IconN - 1 do
      Move(Pixels[Y * IconN * 4], (Raw + Y * Stride)^, IconN * 4);
  end;
  StatusIcon := gtk_status_icon_new;
  gtk_status_icon_set_from_pixbuf(StatusIcon, IconPix);
  gtk_status_icon_set_tooltip_text(StatusIcon, 'No Bugs');
  gtk_status_icon_set_visible(StatusIcon, True);
  g_signal_connect(G_OBJECT(StatusIcon), 'popup-menu', G_CALLBACK(@OnStatusPopup), nil);
end;

procedure RunHost;
var
  Screen: PGdkScreen;
  Map: PGdkColormap;
  ViewH: Integer;
begin
  gtk_init(@argc, @argv);
  BuildSprites;
  InstallKathy;
  WantQuit := False;
  FpSignal(SIGINT, @OnSig);
  FpSignal(SIGTERM, @OnSig);

  Screen := gdk_screen_get_default;
  ScreenW := gdk_screen_get_width(Screen);
  ScreenH := gdk_screen_get_height(Screen);
  NeedShape := not CompositorRunning;
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
  if not NeedShape then
  begin
    Map := gdk_screen_get_rgba_colormap(Screen);
    if Map <> nil then
      gtk_widget_set_colormap(Overlay, Map);
  end;
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
  gtk_main;
  FreeAndNil(Talker);
  if Parade <> nil then
    FreeAndNil(Parade);
end;

{$ELSE}

procedure RunHost;
begin
end;

{$ENDIF}

end.
