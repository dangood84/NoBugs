unit hostlinux;

{
  X11 host. A 32-bit window, override-redirect, parked above everything,
  with an empty input shape so clicks fall through to whatever the bugs
  are standing on. Wayland compositors that still speak XWayland can
  show it; a pure Wayland session cannot, and the program says so.
}

{$mode objfpc}{$H+}

interface

procedure RunHost;

implementation

uses
  BaseUnix, SysUtils, Classes, Process, Math, ctypes,
  xlib, x, xutil,
  nbtypes, nbgeom, nbsprites, nbsim, nbsound;

const
  ShapeInput = 2;
  ShapeSet = 0;

function XDisplayWidth(dpy: PDisplay; screen: cint): cint; cdecl; external;
function XDisplayHeight(dpy: PDisplay; screen: cint): cint; cdecl; external;
function XShapeCombineRectangles(dpy: PDisplay; win: TWindow; destKind, xOff, yOff: cint;
  rects: Pointer; n, op, ordering: cint): cint; cdecl; external 'Xext';

var
  Disp: PDisplay;
  RootWin: TWindow;
  Overlay: TWindow;
  GC: TGC;
  Img: PXImage;
  ScreenH: Integer;
  Quit: Boolean;
  Talker: TProcess;
  SpeechPath, PlayPath: string;
  { 0 idle, 1 espeak is writing the file, 2 a player is speaking the cartoon. }
  SpeechPhase: Integer;

procedure OnSignal(sig: cint); cdecl;
begin
  if sig >= 0 then
    Quit := True;
end;

function Atom(const Name: string): TAtom;
begin
  Result := XInternAtom(Disp, PChar(Name), 0);
end;

function ReadWorkArea(out Work: TBox): Boolean;
var
  Actual: TAtom;
  Format: cint;
  Count, Bytes: culong;
  Data: PByte;
  V: PLongint;
begin
  Result := False;
  Data := nil;
  if XGetWindowProperty(Disp, RootWin, Atom('_NET_WORKAREA'), 0, 4, 0,
    AnyPropertyType, @Actual, @Format, @Count, @Bytes, @Data) <> 0 then
    Exit;
  try
    if (Data = nil) or (Count < 4) then
      Exit;
    V := PLongint(Data);
    Work.Left := V[0];
    Work.Right := V[0] + V[2];
    Work.Top := ScreenH - V[1];
    Work.Bottom := ScreenH - (V[1] + V[3]);
    Result := True;
  finally
    if Data <> nil then
      XFree(Data);
  end;
end;

procedure RefreshStage;
var
  Actual: TAtom;
  Format: cint;
  Count, Bytes: culong;
  Data: PByte;
  Ids: PLongint;
  I, N: Integer;
  Attrs: TXWindowAttributes;
  Boxes: array of TBox;
  Displays: array[0..0] of TDisplay;
  Ledges: TLedgeList;
  Work: TBox;
begin
  SetLength(Boxes, 0);
  Data := nil;
  if XGetWindowProperty(Disp, RootWin, Atom('_NET_CLIENT_LIST'), 0, 1024, 0,
    AnyPropertyType, @Actual, @Format, @Count, @Bytes, @Data) = 0 then
  begin
    Ids := PLongint(Data);
    N := Count;
    for I := 0 to N - 1 do
    begin
      if XGetWindowAttributes(Disp, Ids[I], @Attrs) = 0 then
        Continue;
      if (Attrs.width < 80) or (Attrs.height < 48) then
        Continue;
      if Attrs.map_state <> IsViewable then
        Continue;
      SetLength(Boxes, Length(Boxes) + 1);
      Boxes[High(Boxes)].Left := Attrs.x;
      Boxes[High(Boxes)].Right := Attrs.x + Attrs.width;
      Boxes[High(Boxes)].Top := ScreenH - Attrs.y;
      Boxes[High(Boxes)].Bottom := ScreenH - (Attrs.y + Attrs.height);
    end;
    if Data <> nil then
      XFree(Data);
  end;

  FillChar(Displays[0], SizeOf(Displays[0]), 0);
  Displays[0].Frame.Right := XDisplayWidth(Disp, XDefaultScreen(Disp));
  Displays[0].Frame.Top := ScreenH;
  Displays[0].Work := Displays[0].Frame;
  Displays[0].DockEdge := deNone;
  if ReadWorkArea(Work) then
  begin
    Displays[0].Work := Work;
    if Work.Bottom - Displays[0].Frame.Bottom > 24 then
      Displays[0].DockEdge := deBottom
    else if Work.Left - Displays[0].Frame.Left > 24 then
      Displays[0].DockEdge := deLeft
    else if Displays[0].Frame.Right - Work.Right > 24 then
      Displays[0].DockEdge := deRight;
  end;
  BuildLedges(Boxes, Displays, Ledges);
  if Parade = nil then
    Parade := TWorld.Create;
  Parade.SetStage(Displays, Ledges);
end;

procedure Present;
var
  I: Integer;
  B: TBug;
  YDraw: Double;
begin
  if (Img = nil) or (Img^.data = nil) then
    Exit;
  FillChar(Img^.data^, Img^.width * Img^.height * 4, 0);
  if Parade <> nil then
    for I := 0 to High(Parade.Bugs) do
    begin
      B := Parade.Bugs[I];
      if not B.Alive then
        Continue;
      YDraw := B.Y;
      if (B.State = stWalk) or (B.State = stExit) then
        YDraw := YDraw + Sin(B.Phase * 1.6) * 0.85;
      BlitSprite(SpriteFor(B), B.X, YDraw, 0, ScreenH, PByte(Img^.data), Img^.width, Img^.height);
    end;
  PremultiplyInPlace(PByte(Img^.data), Img^.width * Img^.height);
  XPutImage(Disp, Overlay, GC, Img, 0, 0, 0, 0, Img^.width, Img^.height);
  XFlush(Disp);
end;

function FindOnPath(const Names: array of string): string;
var
  I: Integer;
  Candidate: string;
begin
  Result := '';
  for I := 0 to High(Names) do
  begin
    Candidate := '/usr/bin/' + Names[I];
    if FileExists(Candidate) then
      Exit(Candidate);
    Candidate := '/usr/local/bin/' + Names[I];
    if FileExists(Candidate) then
      Exit(Candidate);
  end;
end;

procedure RunJob(const Exe: string; const Args: array of string);
var
  I: Integer;
begin
  FreeAndNil(Talker);
  Talker := TProcess.Create(nil);
  Talker.Executable := Exe;
  for I := 0 to High(Args) do
    Talker.Parameters.Add(Args[I]);
  Talker.Options := [poNoWait, poDetached];
  try
    Talker.Execute;
  except
    FreeAndNil(Talker);
  end;
end;

procedure StartRender(const Line: string);
var
  Exe: string;
begin
  Exe := FindOnPath(['espeak-ng', 'espeak']);
  if Exe = '' then
  begin
    Writeln('saying (no espeak installed): ', Line);
    Exit;
  end;
  { An American woman, at her own pace. The octave is the wav header. }
  RunJob(Exe, ['-v', 'en-us+f3', '-q', '-w', SpeechPath, ShoutedLine(Line)]);
  if Talker = nil then
    SpeechPhase := 0
  else
    SpeechPhase := 1;
  Writeln('saying: ', Line);
end;

procedure PollSpeech;
var
  Raw, Fast: TBytes;
  Player: string;
begin
  if Talker = nil then
  begin
    if SpeechPhase <> 0 then
      SpeechPhase := 0;
    Exit;
  end;
  if Talker.Running then
    Exit;
  FreeAndNil(Talker);
  if SpeechPhase = 1 then
  begin
    SpeechPhase := 0;
    if not ReadWavFile(SpeechPath, Raw) then
      Exit;
    Fast := SoundMasterWav(CheerWav(Raw), 2);
    if not WriteWavFile(PlayPath, Fast) then
      Exit;
    Player := FindOnPath(['aplay', 'paplay', 'afplay']);
    if Player = '' then
    begin
      Writeln('the cartoon wav is ready, and nothing on this machine will play it');
      Exit;
    end;
    if ExtractFileName(Player) = 'aplay' then
      RunJob(Player, ['-q', PlayPath])
    else
      RunJob(Player, [PlayPath]);
    if Talker <> nil then
      SpeechPhase := 2;
  end
  else
    SpeechPhase := 0;
end;

function SpeechIdle: Boolean;
begin
  Result := (SpeechPhase = 0) and (Talker = nil);
end;

procedure RunHost;
var
  Scr: cint;
  Vis: TXVisualInfo;
  Attr: TXSetWindowAttributes;
  W, H: cuint;
  Ev: TXEvent;
  Req: TTimeSpec;
  Line: string;
begin
  Disp := XOpenDisplay(nil);
  if Disp = nil then
  begin
    Writeln('No Bugs could not open an X11 display.');
    Writeln('A pure Wayland session needs XWayland for this host.');
    Halt(1);
  end;
  Scr := XDefaultScreen(Disp);
  RootWin := XRootWindow(Disp, Scr);
  ScreenH := XDisplayHeight(Disp, Scr);
  W := XDisplayWidth(Disp, Scr);
  H := ScreenH;
  if XMatchVisualInfo(Disp, Scr, 32, TrueColor, @Vis) = 0 then
  begin
    Writeln('No Bugs needs a 32-bit TrueColor visual, and this display has none.');
    Halt(1);
  end;

  FillChar(Attr, SizeOf(Attr), 0);
  Attr.override_redirect := 1;
  Attr.colormap := XCreateColormap(Disp, RootWin, Vis.visual, AllocNone);
  Attr.border_pixel := 0;
  Attr.background_pixel := 0;
  Overlay := XCreateWindow(Disp, RootWin, 0, 0, W, H, 0, 32, InputOutput, Vis.visual,
    CWOverrideRedirect or CWColormap or CWBorderPixel or CWBackPixel, @Attr);
  XChangeProperty(Disp, Overlay, Atom('_NET_WM_STATE'), XA_ATOM, 32, PropModeReplace,
    @Atom('_NET_WM_STATE_ABOVE'), 1);
  XStoreName(Disp, Overlay, 'No Bugs');
  { An empty input shape: the window is visible and unclickable. }
  XShapeCombineRectangles(Disp, Overlay, ShapeInput, 0, 0, nil, 0, ShapeSet, 0);
  XMapWindow(Disp, Overlay);
  GC := XCreateGC(Disp, Overlay, 0, nil);
  Img := XCreateImage(Disp, Vis.visual, 32, ZPixmap, 0, nil, W, H, 32, 0);
  if Img <> nil then
    Img^.data := GetMem(W * H * 4);

  BuildSprites;
  SpeechPath := GetTempDir + 'nobugs-line.wav';
  PlayPath := GetTempDir + 'nobugs-fast.wav';
  fpSignal(SIGINT, @OnSignal);
  fpSignal(SIGTERM, @OnSignal);
  RefreshStage;
  if Parade <> nil then
    Parade.FillRoster;
  Writeln('No Bugs is walking the window ledges.');
  Writeln('Press Ctrl-C to send them home.');

  Quit := False;
  while not Quit do
  begin
    while XPending(Disp) <> 0 do
    begin
      XNextEvent(Disp, @Ev);
      if Ev._type = ClientMessage then
        Quit := True;
    end;
    RefreshStage;
    if Parade <> nil then
    begin
      Parade.Tick(1 / 30);
      PollSpeech;
      if SpeechIdle then
      begin
        Line := Parade.ClaimAnnouncement;
        if Line <> '' then
          StartRender(Line);
      end;
    end;
    Present;
    Req.tv_sec := 0;
    Req.tv_nsec := 33000000;
    fpNanoSleep(@Req, nil);
  end;

  FreeAndNil(Talker);
  if Img <> nil then
  begin
    if Img^.data <> nil then
      FreeMem(Img^.data);
    Img^.data := nil;
    XDestroyImage(Img);
  end;
  XFreeGC(Disp, GC);
  XDestroyWindow(Disp, Overlay);
  XCloseDisplay(Disp);
end;

end.
