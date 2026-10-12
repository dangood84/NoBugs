unit hostmacos;

{
  Above the Dock, below the menu bar. Level 21 is that sandwich:
  kCGDockWindowLevel is 20, kCGMainMenuWindowLevel is 24. The parade
  has to be visible standing on the Dock, and it has to stay out of
  the menu, because the menu is how you ask it to leave.

  Clicks go through. The Mac remains a Mac. Lazarus is not involved;
  these are the Cocoa bindings that ship with the Free Pascal compiler.
  src/launch.c has already put a pool under us.
}

{$mode objfpc}{$H+}
{$modeswitch objectivec1}

interface

procedure RunHost;

implementation

uses
  Math, SysUtils, BaseUnix, Classes, Process, CocoaAll,
  nbtypes, nbgeom, nbsprites, nbsim, nbsound;

{$linkframework CoreGraphics}
{$linkframework CoreFoundation}
{$link lib/launch.o}

const
  kCGWindowListOptionOnScreenOnly = 1;
  kCGWindowListExcludeDesktopElements = 16;
  { Between the Dock and the menu bar. See the note above. }
  ParadeLevel = 21;
  kCGImageAlphaPremultipliedLast = 1;
  kCGBitmapByteOrder32Big = 16384;
  kCGInterpolationNone = 1;

type
  TPane = record
    Frame: TBox;
    View: NSView;
  end;

  TCachedImage = record
    Pixels: Pointer;
    Image: Pointer;
  end;

  TBugView = objcclass(NSView)
  public
    procedure drawRect(dirtyRect: NSRect); override;
    function isOpaque: ObjCBOOL; override;
  end;

  TDirector = objcclass(NSObject)
  public
    procedure tick(sender: id); message 'tick:';
    procedure sayNow(sender: id); message 'sayNow:';
    procedure togglePause(sender: id); message 'togglePause:';
    procedure showAbout(sender: id); message 'showAbout:';
    procedure quitApp(sender: id); message 'quitApp:';
  end;

function CGWindowListCopyWindowInfo(option: UInt32; relativeToWindow: UInt32): Pointer;
  cdecl; external name 'CGWindowListCopyWindowInfo';
procedure CFRelease(cf: Pointer); cdecl; external name 'CFRelease';
function CFDataCreate(allocator: Pointer; bytes: Pointer; length: PtrInt): Pointer;
  cdecl; external name 'CFDataCreate';
function CGColorSpaceCreateDeviceRGB: Pointer; cdecl; external name 'CGColorSpaceCreateDeviceRGB';
procedure CGColorSpaceRelease(cs: Pointer); cdecl; external name 'CGColorSpaceRelease';
function CGDataProviderCreateWithCFData(data: Pointer): Pointer;
  cdecl; external name 'CGDataProviderCreateWithCFData';
procedure CGDataProviderRelease(p: Pointer); cdecl; external name 'CGDataProviderRelease';
function CGImageCreate(width, height, bitsPerComponent, bitsPerPixel, bytesPerRow: PtrUInt;
  space: Pointer; bitmapInfo: UInt32; provider: Pointer; decode: Pointer;
  shouldInterpolate: Byte; intent: Int32): Pointer; cdecl; external name 'CGImageCreate';
procedure CGImageRelease(image: Pointer); cdecl; external name 'CGImageRelease';
procedure CGContextDrawImage(c: Pointer; rect: NSRect; image: Pointer);
  cdecl; external name 'CGContextDrawImage';
procedure CGContextSetInterpolationQuality(c: Pointer; quality: Int32);
  cdecl; external name 'CGContextSetInterpolationQuality';

var
  Director: TDirector;
  Panes: array of TPane;
  Windows: array of NSWindow;
  VoiceName: string;
  PauseItem: NSMenuItem;
  StopPlease: LongInt;
  LastScan: TDateTime;
  RosterFilled: Boolean;
  SayJob: TProcess;
  SpeechPath: string;
  LineBusyUntil: TDateTime;
  ChimeSound: NSSound;
  LineSound: NSSound;
  DumpOnly: Boolean;
  Images: array of TCachedImage;
  PrimaryTop: Double;

procedure OnSignal(sig: cint); cdecl;
begin
  if sig = 0 then
    Exit;
  StopPlease := 1;
end;

function Num(dict: NSDictionary; const Key: string): Double;
var
  O: NSObject;
begin
  Result := 0;
  if dict = nil then
    Exit;
  O := dict.objectForKey(NSSTR(Key));
  if O = nil then
    Exit;
  Result := NSNumber(O).doubleValue;
end;

function StrOf(dict: NSDictionary; const Key: string): string;
var
  O: NSObject;
begin
  Result := '';
  if dict = nil then
    Exit;
  O := dict.objectForKey(NSSTR(Key));
  if O = nil then
    Exit;
  Result := string(NSString(O).UTF8String);
end;

function BoxOf(const R: NSRect): TBox;
begin
  Result.Left := R.origin.x;
  Result.Bottom := R.origin.y;
  Result.Right := R.origin.x + R.size.width;
  Result.Top := R.origin.y + R.size.height;
end;

function CGBox(X, Y, W, H: Double): TBox;
begin
  { Window-server space: origin at the top-left of the main display, Y down.
    AppKit space: origin at the bottom-left, Y up. One subtraction, forever. }
  Result.Left := X;
  Result.Right := X + W;
  Result.Top := PrimaryTop - Y;
  Result.Bottom := PrimaryTop - (Y + H);
end;

procedure ChooseVoice;
var
  Job: TProcess;
  Lines: TStringList;
  Ids: array of string;
  I, Sp: Integer;
  Line, Name: string;
begin
  VoiceName := '';
  Job := TProcess.Create(nil);
  Lines := TStringList.Create;
  try
    Job.Executable := '/usr/bin/say';
    Job.Parameters.Add('-v');
    Job.Parameters.Add('?');
    Job.Options := [poUsePipes, poNoConsole];
    try
      Job.Execute;
      { Read before waiting. A full pipe and poWaitOnExit is a deadlock. }
      Lines.LoadFromStream(Job.Output);
      Job.WaitOnExit;
    except
      Lines.Clear;
    end;
  finally
    Job.Free;
  end;
  SetLength(Ids, Lines.Count);
  for I := 0 to Lines.Count - 1 do
  begin
    Line := Trim(Lines[I]);
    Sp := Pos(' ', Line);
    if Sp > 1 then
      Name := Copy(Line, 1, Sp - 1)
    else
      Name := Line;
    Ids[I] := Name;
  end;
  Lines.Free;
  VoiceName := PickSillyVoice(Ids);
  if VoiceName = '' then
    VoiceName := 'Kathy';
  Writeln('voice: ', VoiceName, ', recorded at ', VoiceRecordHz,
    ' Hz, played at ', VoiceRecordHz * 2, ' Hz');
end;

function ImageFor(const S: TSprite): Pointer;
var
  I, N: Integer;
  CopyPx, Data, Provider, Space: Pointer;
begin
  Result := nil;
  if S.Pixels = nil then
    Exit;
  for I := 0 to High(Images) do
    if Images[I].Pixels = S.Pixels then
      Exit(Images[I].Image);
  N := S.W * S.H;
  CopyPx := GetMem(N * 4);
  Move(S.Pixels^, CopyPx^, N * 4);
  PremultiplyInPlace(PByte(CopyPx), N);
  Data := CFDataCreate(nil, CopyPx, N * 4);
  FreeMem(CopyPx);
  Provider := CGDataProviderCreateWithCFData(Data);
  CFRelease(Data);
  Space := CGColorSpaceCreateDeviceRGB;
  Result := CGImageCreate(S.W, S.H, 8, 32, PtrUInt(S.W * 4), Space,
    kCGImageAlphaPremultipliedLast or kCGBitmapByteOrder32Big, Provider, nil, 0, 0);
  CGDataProviderRelease(Provider);
  CGColorSpaceRelease(Space);
  SetLength(Images, Length(Images) + 1);
  Images[High(Images)].Pixels := S.Pixels;
  Images[High(Images)].Image := Result;
end;

procedure RefreshStage;
var
  Screens, Info: NSArray;
  I, N: Integer;
  SC: NSScreen;
  Dict, Bounds: NSDictionary;
  CF: Pointer;
  Owner: string;
  Layer: Integer;
  Alpha, BW, BH: Double;
  Box: TBox;
  Displays: array of TDisplay;
  Raw, Docks: array of TBox;
  BestDock: Integer;
  BestArea, Area: Double;
  Ledges: TLedgeList;
  Ours: Integer;
begin
  Ours := FpGetpid;
  Screens := NSScreen.screens;
  PrimaryTop := NSScreen.mainScreen.frame.origin.y + NSScreen.mainScreen.frame.size.height;
  SetLength(Displays, Integer(Screens.count));
  for I := 0 to High(Displays) do
  begin
    SC := NSScreen(Screens.objectAtIndex(NSUInteger(I)));
    Displays[I].Frame := BoxOf(SC.frame);
    Displays[I].Work := BoxOf(SC.visibleFrame);
    Displays[I].HasDock := False;
    if Displays[I].Work.Bottom - Displays[I].Frame.Bottom > 24 then
      Displays[I].DockEdge := deBottom
    else if Displays[I].Work.Left - Displays[I].Frame.Left > 24 then
      Displays[I].DockEdge := deLeft
    else if Displays[I].Frame.Right - Displays[I].Work.Right > 24 then
      Displays[I].DockEdge := deRight
    else
      Displays[I].DockEdge := deNone;
  end;

  SetLength(Raw, 0);
  SetLength(Docks, 0);
  CF := CGWindowListCopyWindowInfo(kCGWindowListOptionOnScreenOnly or kCGWindowListExcludeDesktopElements, 0);
  if CF <> nil then
  begin
    Info := NSArray(CF);
    for I := 0 to Integer(Info.count) - 1 do
    begin
      Dict := NSDictionary(Info.objectAtIndex(NSUInteger(I)));
      Owner := StrOf(Dict, 'kCGWindowOwnerName');
      Layer := Round(Num(Dict, 'kCGWindowLayer'));
      Alpha := Num(Dict, 'kCGWindowAlpha');
      if Round(Num(Dict, 'kCGWindowOwnerPID')) = Ours then
        Continue;
      if Alpha < 0.15 then
        Continue;
      Bounds := NSDictionary(Dict.objectForKey(NSSTR('kCGWindowBounds')));
      BW := Num(Bounds, 'Width');
      BH := Num(Bounds, 'Height');
      if (BW < 8) or (BH < 8) then
        Continue;
      Box := CGBox(Num(Bounds, 'X'), Num(Bounds, 'Y'), BW, BH);
      if LowerCase(Owner) = 'dock' then
      begin
        SetLength(Docks, Length(Docks) + 1);
        Docks[High(Docks)] := Box;
        Continue;
      end;
      if Layer <> 0 then
        Continue;
      if (BW < 80) or (BH < 48) then
        Continue;
      SetLength(Raw, Length(Raw) + 1);
      Raw[High(Raw)] := Box;
    end;
    CFRelease(CF);
  end;

  for N := 0 to High(Displays) do
  begin
    BestDock := -1;
    BestArea := 0;
    for I := 0 to High(Docks) do
    begin
      { The Dock process owns more than the Dock. The real one is the
        short strip sitting in the reserved margin, not a full-screen
        window that happens to share the name. }
      if Displays[N].DockEdge = deBottom then
      begin
        if (BoxHeight(Docks[I]) > 180) or (BoxWidth(Docks[I]) < 80) then
          Continue;
        if Docks[I].Top > Displays[N].Work.Bottom + 40 then
          Continue;
      end
      else if Displays[N].DockEdge = deLeft then
      begin
        if (BoxWidth(Docks[I]) > 180) or (Docks[I].Right > Displays[N].Work.Left + 40) then
          Continue;
      end
      else if Displays[N].DockEdge = deRight then
      begin
        if (BoxWidth(Docks[I]) > 180) or (Docks[I].Left < Displays[N].Work.Right - 40) then
          Continue;
      end
      else
        Continue;
      Area := BoxWidth(Docks[I]) * BoxHeight(Docks[I]);
      if Area > BestArea then
      begin
        BestArea := Area;
        BestDock := I;
      end;
    end;
    if BestDock >= 0 then
    begin
      Displays[N].HasDock := True;
      Displays[N].DockBox := Docks[BestDock];
    end;
  end;

  BuildLedges(Raw, Displays, Ledges);
  if Parade = nil then
    Parade := TWorld.Create;
  Parade.SetStage(Displays, Ledges);

  if DumpOnly then
  begin
    Writeln('displays=', Length(Displays), ' windows=', Length(Raw), ' dock-windows=', Length(Docks), ' ledges=', Length(Ledges));
    for I := 0 to High(Raw) do
      Writeln(Format('  window %.0f,%.0f .. %.0f,%.0f',
        [Raw[I].Left, Raw[I].Bottom, Raw[I].Right, Raw[I].Top]));
    for I := 0 to High(Docks) do
      Writeln(Format('  dock-win %.0f,%.0f .. %.0f,%.0f',
        [Docks[I].Left, Docks[I].Bottom, Docks[I].Right, Docks[I].Top]));
    for I := 0 to High(Displays) do
      Writeln(Format('  screen %.0f,%.0f %.0fx%.0f work-bottom %.0f dock-edge %d has-dock %s',
        [Displays[I].Frame.Left, Displays[I].Frame.Bottom,
        BoxWidth(Displays[I].Frame), BoxHeight(Displays[I].Frame),
        Displays[I].Work.Bottom, Ord(Displays[I].DockEdge),
        BoolToStr(Displays[I].HasDock, True)]));
    for I := 0 to Min(High(Ledges), 24) do
      Writeln(Format('  ledge %d kind=%d horiz=%s x %.0f..%.0f y %.0f',
        [I, Ord(Ledges[I].Kind), BoolToStr(Ledges[I].Horizontal, True),
        Ledges[I].X1, Ledges[I].X2, Ledges[I].Y1]));
  end;
end;

procedure PaintPane(Index: Integer);
var
  Ctx: Pointer;
  I: Integer;
  B: TBug;
  S: TSprite;
  Img: Pointer;
  Left, Bottom, W, H, DrawY: Double;
  R: NSRect;
  Pane: TBox;
begin
  if (Index < 0) or (Index > High(Panes)) or (Parade = nil) then
    Exit;
  Ctx := Pointer(NSGraphicsContext.currentContext.CGContext);
  if Ctx = nil then
    Exit;
  CGContextSetInterpolationQuality(Ctx, kCGInterpolationNone);
  Pane := Panes[Index].Frame;
  for I := 0 to High(Parade.Bugs) do
  begin
    B := Parade.Bugs[I];
    if not B.Alive then
      Continue;
    DrawY := B.Y;
    if (B.State = stWalk) or (B.State = stExit) then
      DrawY := DrawY + Sin(B.Phase * 1.6) * 0.85;
    S := SpriteFor(B);
    Img := ImageFor(S);
    if Img = nil then
      Continue;
    SpriteRect(S, B.X, DrawY, Left, Bottom, W, H);
    if (Left + W < Pane.Left) or (Left > Pane.Right) or
      (Bottom + H < Pane.Bottom) or (Bottom > Pane.Top) then
      Continue;
    R := NSMakeRect(Left - Pane.Left, Bottom - Pane.Bottom, W, H);
    CGContextDrawImage(Ctx, R, Img);
  end;
end;

function PaneIndex(View: NSView): Integer;
var
  I: Integer;
begin
  Result := -1;
  for I := 0 to High(Panes) do
    if Panes[I].View = View then
      Exit(I);
end;

procedure TBugView.drawRect(dirtyRect: NSRect);
begin
  if dirtyRect.size.width < 0 then
    Exit;
  PaintPane(PaneIndex(Self));
end;

function TBugView.isOpaque: ObjCBOOL;
begin
  Result := False;
end;

function SpeechBusy: Boolean;
begin
  Result := (SayJob <> nil) or (Now < LineBusyUntil);
end;

procedure PlayMemoryWav(const Wav: TBytes; var Slot: NSSound; Volume: Single);
var
  Data: NSData;
  Sound: NSSound;
begin
  if Length(Wav) = 0 then
    Exit;
  Data := NSData.dataWithBytes_length(@Wav[0], NSUInteger(Length(Wav)));
  Sound := NSSound.alloc.initWithData(Data);
  if Sound = nil then
    Exit;
  if Slot <> nil then
    Slot.release;
  Slot := Sound;
  Slot.setVolume(Volume);
  Slot.play;
end;

procedure PlayChime;
begin
  PlayMemoryWav(MakeChimeWav, ChimeSound, 0.9);
end;

procedure PumpSpeech;
var
  Raw, Fast: TBytes;
  Seconds: Double;
begin
  if SayJob = nil then
    Exit;
  if SayJob.Running then
    Exit;
  FreeAndNil(SayJob);
  if not ReadWavFile(SpeechPath, Raw) then
    Exit;
  { Twice the hertz the voice was hired for. The samples do not change. }
  Fast := SoundMasterWav(CheerWav(Raw), 2);
  Seconds := WavPlaybackSeconds(Fast);
  PlayMemoryWav(Fast, LineSound, 1);
  if LineSound = nil then
    Writeln('the recording was made, and the player refused it')
  else
    Writeln(Format('played at %d Hz (recorded at %d Hz, %.2f s)',
      [VoiceRecordHz * 2, VoiceRecordHz, Seconds]));
  Flush(Output);
  LineBusyUntil := Now + (Seconds + 0.12) / 86400;
end;

procedure StartAnnouncement(const Line: string);
begin
  if SpeechBusy then
    Exit;
  if Line = '' then
    Exit;
  if VoiceName = '' then
    VoiceName := 'Kathy';
  SpeechPath := GetTempDir + 'nobugs-line.wav';
  FreeAndNil(SayJob);
  SayJob := TProcess.Create(nil);
  SayJob.Executable := '/usr/bin/say';
  SayJob.Parameters.Add('-v');
  SayJob.Parameters.Add(VoiceName);
  SayJob.Parameters.Add('-o');
  SayJob.Parameters.Add(SpeechPath);
  SayJob.Parameters.Add('--file-format=WAVE');
  { Hired at the low rate. PumpSpeech will claim a higher one. }
  SayJob.Parameters.Add('--data-format=LEI16@' + IntToStr(VoiceRecordHz));
  { "No! Bugs!", said slowly. The double-speed playback is what makes it hurried. }
  SayJob.Parameters.Add(SayCheer(Line));
  SayJob.Options := [poNoConsole];
  try
    SayJob.Execute;
  except
    FreeAndNil(SayJob);
    Exit;
  end;
  Writeln('saying: ', Line);
  Flush(Output);
end;

procedure TDirector.sayNow(sender: id);
begin
  if sender = nil then ;
  if SpeechBusy then
    Exit;
  PlayChime;
  StartAnnouncement('No bugs!');
end;

procedure TDirector.togglePause(sender: id);
begin
  if sender = nil then ;
  if Parade = nil then
    Exit;
  Parade.Paused := not Parade.Paused;
  if PauseItem <> nil then
  begin
    if Parade.Paused then
      PauseItem.setTitle(NSSTR('Resume the parade'))
    else
      PauseItem.setTitle(NSSTR('Pause the parade'));
  end;
end;

procedure TDirector.showAbout(sender: id);
var
  Alert: NSAlert;
begin
  if sender = nil then ;
  Alert := NSAlert.alloc.init;
  Alert.setMessageText(NSSTR('No Bugs'));
  Alert.setInformativeText(NSSTR(AboutBlurb));
  Alert.addButtonWithTitle(NSSTR('Onward'));
  Alert.runModal;
end;

procedure TDirector.quitApp(sender: id);
begin
  if sender = nil then ;
  StopPlease := 1;
end;

procedure TDirector.tick(sender: id);
var
  I: Integer;
  Line: string;
begin
  if sender = nil then ;
  if StopPlease <> 0 then
  begin
    NSApplication.sharedApplication.terminate(nil);
    Halt(0);
  end;
  if (Now - LastScan) * 86400 > 0.45 then
  begin
    RefreshStage;
    LastScan := Now;
  end;
  if not RosterFilled then
  begin
    Parade.FillRoster;
    RosterFilled := True;
    Writeln('bugs=', Parade.AliveCount, ' ledges=', Length(Parade.Ledges));
    Flush(Output);
  end;
  Parade.Tick(1 / 30);
  if Verbose and (Trunc(Parade.Time * 2) <> Trunc((Parade.Time - 1 / 30) * 2)) then
    Writeln(Format('t=%.1f alive=%d', [Parade.Time, Parade.AliveCount]));
  PumpSpeech;
  if not SpeechBusy then
  begin
    Line := Parade.ClaimAnnouncement;
    if Line <> '' then
    begin
      PlayChime;
      StartAnnouncement(Line);
    end;
  end;
  for I := 0 to High(Panes) do
    if Panes[I].View <> nil then
      Panes[I].View.setNeedsDisplay_(True);
end;

procedure BuildMenu;
var
  Bar: NSStatusBar;
  Item: NSStatusItem;
  Menu: NSMenu;
  Entry: NSMenuItem;
  Button: NSStatusBarButton;
begin
  Bar := NSStatusBar.systemStatusBar;
  Item := Bar.statusItemWithLength(NSVariableStatusItemLength);
  Button := Item.button;
  if Button <> nil then
  begin
    Button.setTitle(NSSTR('No Bugs'));
    Button.setToolTip(NSSTR('There are no bugs.'));
  end;
  Menu := NSMenu.alloc.initWithTitle(NSSTR('No Bugs'));
  Entry := NSMenuItem.alloc.initWithTitle_action_keyEquivalent(
    NSSTR('No Bugs'), nil, NSSTR(''));
  Entry.setEnabled(False);
  Menu.addItem(Entry);
  Menu.addItem(NSMenuItem.separatorItem);
  Entry := NSMenuItem.alloc.initWithTitle_action_keyEquivalent(
    NSSTR('Say "No bugs!"'), objcselector('sayNow:'), NSSTR(''));
  Entry.setTarget(Director);
  Menu.addItem(Entry);
  PauseItem := NSMenuItem.alloc.initWithTitle_action_keyEquivalent(
    NSSTR('Pause the parade'), objcselector('togglePause:'), NSSTR(''));
  PauseItem.setTarget(Director);
  Menu.addItem(PauseItem);
  Entry := NSMenuItem.alloc.initWithTitle_action_keyEquivalent(
    NSSTR('About the signatures'), objcselector('showAbout:'), NSSTR(''));
  Entry.setTarget(Director);
  Menu.addItem(Entry);
  Menu.addItem(NSMenuItem.separatorItem);
  Entry := NSMenuItem.alloc.initWithTitle_action_keyEquivalent(
    NSSTR('Quit No Bugs'), objcselector('quitApp:'), NSSTR('q'));
  Entry.setTarget(Director);
  Menu.addItem(Entry);
  Item.setMenu(Menu);
end;

procedure BuildWindows;
var
  Screens: NSArray;
  I: Integer;
  SC: NSScreen;
  Win: NSWindow;
  View: TBugView;
  Frame: NSRect;
begin
  Screens := NSScreen.screens;
  SetLength(Panes, Integer(Screens.count));
  SetLength(Windows, Length(Panes));
  for I := 0 to High(Panes) do
  begin
    SC := NSScreen(Screens.objectAtIndex(NSUInteger(I)));
    Frame := SC.frame;
    Panes[I].Frame := BoxOf(Frame);
    Win := NSWindow.alloc.initWithContentRect_styleMask_backing_defer(
      Frame, NSBorderlessWindowMask, NSBackingStoreBuffered, False);
    Win.setOpaque(False);
    Win.setBackgroundColor(NSColor.clearColor);
    Win.setHasShadow(False);
    Win.setIgnoresMouseEvents(True);
    Win.setLevel(ParadeLevel);
    Win.setCollectionBehavior(
      NSWindowCollectionBehaviorCanJoinAllSpaces or
      NSWindowCollectionBehaviorStationary or
      NSWindowCollectionBehaviorFullScreenAuxiliary or
      NSWindowCollectionBehaviorIgnoresCycle);
    View := TBugView.alloc.initWithFrame(NSMakeRect(0, 0, Frame.size.width, Frame.size.height));
    Win.setContentView(View);
    Win.orderFrontRegardless;
    Panes[I].View := View;
    Windows[I] := Win;
  end;
end;

procedure RunHost;
var
  App: NSApplication;
  Pool: NSAutoreleasePool;
  Timer: NSTimer;
begin
  SetExceptionMask([exInvalidOp, exDenormalized, exZeroDivide, exOverflow, exUnderflow, exPrecision]);
  Pool := NSAutoreleasePool.alloc.init;
  App := NSApplication.sharedApplication;
  App.setActivationPolicy(NSApplicationActivationPolicyAccessory);
  ChooseVoice;
  Director := TDirector.alloc.init;
  if DumpOnly then
  begin
    RefreshStage;
    Halt(0);
  end;
  Writeln('No Bugs');
  Writeln('The parade is on your window ledges and the Dock.');
  Writeln('Every so often Kathy will shout, an octave up: No bugs!');
  Writeln('Quit from the No Bugs menu, or press Ctrl-C.');
  Flush(Output);
  BuildMenu;
  RefreshStage;
  LastScan := Now;
  BuildWindows;
  if Parade <> nil then
  begin
    Parade.FillRoster;
    RosterFilled := True;
    Writeln('bugs=', Parade.AliveCount, ' ledges=', Length(Parade.Ledges));
    Flush(Output);
  end;
  FpSignal(SIGINT, @OnSignal);
  FpSignal(SIGTERM, @OnSignal);
  Timer := NSTimer.timerWithTimeInterval_target_selector_userInfo_repeats(
    1 / 30, Director, objcselector('tick:'), nil, True);
  NSRunLoop.currentRunLoop.addTimer_forMode(Timer, NSRunLoopCommonModes);
  App.run;
  Pool.release;
end;

initialization
  DumpOnly := False;
  for StopPlease := 1 to ParamCount do
    if ParamStr(StopPlease) = '--dump' then
      DumpOnly := True;
  StopPlease := 0;

end.
