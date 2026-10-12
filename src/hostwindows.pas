unit hostwindows;

{
  The same parade, on the other side of the glass.
  Window tops and the taskbar are ledges. The overlay is a layered,
  click-through window, so the desktop keeps working underneath it.
  The line is an American woman when Windows has one, recorded and
  then played at twice the hertz.
}

{$mode objfpc}{$H+}

interface

procedure RunHost;

implementation

uses
  Windows, MMSystem, SysUtils, Classes, Process, Math,
  nbtypes, nbgeom, nbsprites, nbsim, nbsound;

const
  TrayMsg = WM_USER + 24;
  MenuSay = 1001;
  MenuPause = 1002;
  MenuQuit = 1003;

var
  Overlay: HWND;
  MemDC: HDC;
  Dib: HBITMAP;
  Bits: Pointer;
  BufW, BufH: Integer;
  PrimaryH: Integer;
  RegionLeft, RegionTop: Double;
  Quit: Boolean;
  Talker: TProcess;
  ChimePath, SpeechPath, PlayPath: string;
  { 0 idle, 1 the voice is still writing the file, 2 the cartoon is playing. }
  SpeechPhase: Integer;
  LineBusyUntil: TDateTime;

type
  TBoxList = array of TBox;

function EnumWindowsProc(Wnd: HWND; lp: LPARAM): WINBOOL; stdcall;
var
  R: TRect;
  Ex: LONG;
  Boxes: ^TBoxList;
  Box: TBox;
begin
  Result := True;
  Boxes := Pointer(lp);
  if (Boxes = nil) or (Wnd = Overlay) or not IsWindowVisible(Wnd) then
    Exit;
  Ex := GetWindowLong(Wnd, GWL_EXSTYLE);
  if (Ex and WS_EX_TOOLWINDOW) <> 0 then
    Exit;
  if not GetWindowRect(Wnd, R) then
    Exit;
  if (R.Right - R.Left < 80) or (R.Bottom - R.Top < 48) then
    Exit;
  Box.Left := R.Left;
  Box.Right := R.Right;
  Box.Top := PrimaryH - R.Top;
  Box.Bottom := PrimaryH - R.Bottom;
  SetLength(Boxes^, Length(Boxes^) + 1);
  Boxes^[High(Boxes^)] := Box;
end;

procedure CollectWindows(out Boxes: TBoxList);
begin
  SetLength(Boxes, 0);
  EnumWindows(@EnumWindowsProc, LPARAM(@Boxes));
end;

function TaskbarBox(out Box: TBox; out Edge: TDockEdge): Boolean;
var
  W: HWND;
  R: TRect;
begin
  Result := False;
  Edge := deNone;
  W := FindWindow('Shell_TrayWnd', nil);
  if W = 0 then
    Exit;
  if not GetWindowRect(W, R) then
    Exit;
  Box.Left := R.Left;
  Box.Right := R.Right;
  Box.Top := PrimaryH - R.Top;
  Box.Bottom := PrimaryH - R.Bottom;
  Result := True;
  if BoxHeight(Box) < BoxWidth(Box) then
  begin
    if Box.Bottom <= 4 then
      Edge := deBottom
    else
      Edge := deNone;
  end
  else if Box.Left <= 4 then
    Edge := deLeft
  else
    Edge := deRight;
end;

procedure RefreshStage;
var
  Boxes: TBoxList;
  Displays: array[0..0] of TDisplay;
  Ledges: TLedgeList;
  Bar: TBox;
  Edge: TDockEdge;
begin
  PrimaryH := GetSystemMetrics(SM_CYSCREEN);
  FillChar(Displays[0], SizeOf(Displays[0]), 0);
  Displays[0].Frame.Left := 0;
  Displays[0].Frame.Bottom := 0;
  Displays[0].Frame.Right := GetSystemMetrics(SM_CXSCREEN);
  Displays[0].Frame.Top := PrimaryH;
  Displays[0].Work := Displays[0].Frame;
  if TaskbarBox(Bar, Edge) then
  begin
    Displays[0].DockEdge := Edge;
    Displays[0].HasDock := True;
    Displays[0].DockBox := Bar;
    if Edge = deBottom then
      Displays[0].Work.Bottom := Bar.Top
    else if Edge = deLeft then
      Displays[0].Work.Left := Bar.Right
    else if Edge = deRight then
      Displays[0].Work.Right := Bar.Left;
  end;
  CollectWindows(Boxes);
  BuildLedges(Boxes, Displays, Ledges);
  if Parade = nil then
    Parade := TWorld.Create;
  Parade.SetStage(Displays, Ledges);
end;

procedure SwapRedBlue(P: PByte; Count: Integer);
var
  I: Integer;
  T: Byte;
begin
  { The sprites are RGBA. A Windows DIB is BGRA. }
  for I := 0 to Count - 1 do
  begin
    T := P[0];
    P[0] := P[2];
    P[2] := T;
    Inc(P, 4);
  end;
end;

function BugTrayIcon: HICON;
const
  N = 32;
var
  Info: BITMAPINFO;
  Bits: Pointer;
  DC: HDC;
  Color, Mask: HBITMAP;
  IconInfo: TIconInfo;
  Rgba: array of Byte;
  P: PByte;
begin
  Result := 0;
  SetLength(Rgba, N * N * 4);
  PaintLadybugIcon(@Rgba[0], N, N);
  P := @Rgba[0];
  SwapRedBlue(P, N * N);
  FillChar(Info, SizeOf(Info), 0);
  Info.bmiHeader.biSize := SizeOf(BITMAPINFOHEADER);
  Info.bmiHeader.biWidth := N;
  Info.bmiHeader.biHeight := -N;
  Info.bmiHeader.biPlanes := 1;
  Info.bmiHeader.biBitCount := 32;
  Info.bmiHeader.biCompression := BI_RGB;
  DC := GetDC(0);
  Bits := nil;
  Color := CreateDIBSection(DC, Info, DIB_RGB_COLORS, Bits, 0, 0);
  if (Color <> 0) and (Bits <> nil) then
    Move(Rgba[0], Bits^, Length(Rgba));
  Mask := CreateBitmap(N, N, 1, 1, nil);
  FillChar(IconInfo, SizeOf(IconInfo), 0);
  IconInfo.fIcon := True;
  IconInfo.hbmMask := Mask;
  IconInfo.hbmColor := Color;
  Result := CreateIconIndirect(IconInfo);
  if Color <> 0 then
    DeleteObject(Color);
  if Mask <> 0 then
    DeleteObject(Mask);
  ReleaseDC(0, DC);
end;

procedure Present;
var
  I: Integer;
  B: TBug;
  YDraw: Double;
  Pt: TPoint;
  Sz: TSize;
  Src: TPoint;
  Blend: BLENDFUNCTION;
begin
  if Bits = nil then
    Exit;
  FillChar(Bits^, BufW * BufH * 4, 0);
  if Parade <> nil then
    for I := 0 to High(Parade.Bugs) do
    begin
      B := Parade.Bugs[I];
      if not B.Alive then
        Continue;
      YDraw := B.Y;
      if (B.State = stWalk) or (B.State = stExit) then
        YDraw := YDraw + Sin(B.Phase * 1.6) * 0.85;
      BlitSprite(SpriteFor(B), B.X, YDraw, RegionLeft, RegionTop, PByte(Bits), BufW, BufH);
    end;
  SwapRedBlue(PByte(Bits), BufW * BufH);
  PremultiplyInPlace(PByte(Bits), BufW * BufH);
  Pt.X := GetSystemMetrics(SM_XVIRTUALSCREEN);
  Pt.Y := GetSystemMetrics(SM_YVIRTUALSCREEN);
  Sz.cx := BufW;
  Sz.cy := BufH;
  Src.X := 0;
  Src.Y := 0;
  Blend.BlendOp := AC_SRC_OVER;
  Blend.BlendFlags := 0;
  Blend.SourceConstantAlpha := 255;
  Blend.AlphaFormat := AC_SRC_ALPHA;
  UpdateLayeredWindow(Overlay, 0, @Pt, @Sz, MemDC, @Src, 0, @Blend, ULW_ALPHA);
end;

procedure StartRender(const Line: string);
var
  Safe, Heard: string;
begin
  if (Talker <> nil) and Talker.Running then
    Exit;
  FreeAndNil(Talker);
  Safe := StringReplace(ShoutedLine(Line), '''', '''''', [rfReplaceAll]);
  Heard := StringReplace(SpeechPath, '''', '''''', [rfReplaceAll]);
  Talker := TProcess.Create(nil);
  Talker.Executable := 'powershell.exe';
  Talker.Parameters.Add('-NoProfile');
  Talker.Parameters.Add('-WindowStyle');
  Talker.Parameters.Add('Hidden');
  Talker.Parameters.Add('-Command');
  { Write a wav in an American woman's voice. Playback is a separate lie. }
  Talker.Parameters.Add(
    'Add-Type -AssemblyName System.Speech; ' +
    '$s = New-Object System.Speech.Synthesis.SpeechSynthesizer; ' +
    'foreach ($v in $s.GetInstalledVoices()) { ' +
    '$i = $v.VoiceInfo; ' +
    'if (($i.Culture.Name -like ''en-US*'') -and ($i.Gender -eq ''Female'')) { $s.SelectVoice($i.Name); break } }; ' +
    '$s.Rate = -4; ' +
    '$s.SetOutputToWaveFile(''' + Heard + '''); ' +
    '$s.Speak(''' + Safe + ''')');
  Talker.Options := [poNoWait, poDetached];
  try
    Talker.Execute;
    SpeechPhase := 1;
  except
    FreeAndNil(Talker);
    SpeechPhase := 0;
  end;
end;

procedure PollSpeech;
var
  Raw, Fast: TBytes;
begin
  if SpeechPhase = 1 then
  begin
    if (Talker <> nil) and Talker.Running then
      Exit;
    FreeAndNil(Talker);
    SpeechPhase := 2;
    LineBusyUntil := Now + 0.4 / 86400;
    if not ReadWavFile(SpeechPath, Raw) then
      Exit;
    Fast := SoundMasterWav(CheerWav(Raw), 2);
    if WriteWavFile(PlayPath, Fast) then
      PlaySound(PChar(PlayPath), 0, SND_FILENAME or SND_ASYNC or SND_NODEFAULT);
    LineBusyUntil := Now + (WavPlaybackSeconds(Fast) + 0.15) / 86400;
  end
  else if (SpeechPhase = 2) and (Now >= LineBusyUntil) then
    SpeechPhase := 0;
end;

function SpeechIdle: Boolean;
begin
  Result := SpeechPhase = 0;
end;

procedure PlayChime;
var
  Wav: TBytes;
begin
  Wav := MakeChimeWav;
  if not WriteWavFile(ChimePath, Wav) then
    Exit;
  PlaySound(PChar(ChimePath), 0, SND_FILENAME or SND_ASYNC or SND_NODEFAULT);
end;

procedure Announce(const Line: string);
begin
  if not SpeechIdle then
    Exit;
  PlayChime;
  StartRender(Line);
  Writeln('saying: ', Line);
end;

function WindowProc(Wnd: HWND; Msg: UINT; WParam: WPARAM; LParam: LPARAM): LRESULT; stdcall;
var
  Menu: HMENU;
  Cmd: Integer;
  Line: string;
begin
  Result := 0;
  case Msg of
    WM_TIMER:
      begin
        RefreshStage;
        if (Parade <> nil) and (Parade.AliveCount < Parade.Target) and (Length(Parade.Bugs) = 0) then
          Parade.FillRoster;
        if Parade <> nil then
        begin
          Parade.Tick(1 / 30);
          PollSpeech;
          if SpeechIdle then
          begin
            Line := Parade.ClaimAnnouncement;
            if Line <> '' then
              Announce(Line);
          end;
        end;
        Present;
      end;
    TrayMsg:
      if (LParam = WM_RBUTTONUP) or (LParam = WM_LBUTTONUP) then
      begin
        Menu := CreatePopupMenu;
        AppendMenu(Menu, MF_STRING, MenuSay, 'Say "No bugs!"');
        if (Parade <> nil) and Parade.Paused then
          AppendMenu(Menu, MF_STRING, MenuPause, 'Resume the parade')
        else
          AppendMenu(Menu, MF_STRING, MenuPause, 'Pause the parade');
        AppendMenu(Menu, MF_STRING, MenuQuit, 'Quit No Bugs');
        SetForegroundWindow(Wnd);
        Cmd := Integer(TrackPopupMenu(Menu, TPM_RETURNCMD or TPM_RIGHTBUTTON,
          LoWord(GetMessagePos), HiWord(GetMessagePos), 0, Wnd, nil));
        DestroyMenu(Menu);
        case Cmd of
          MenuSay: Announce('No bugs!');
          MenuPause:
            if Parade <> nil then
              Parade.Paused := not Parade.Paused;
          MenuQuit: Quit := True;
        end;
      end;
    WM_DESTROY:
      Quit := True;
  else
    Result := DefWindowProc(Wnd, Msg, WParam, LParam);
  end;
end;

procedure RunHost;
var
  Cls: WNDCLASS;
  Msg: TMsg;
  ScreenDC: HDC;
  Info: BITMAPINFO;
  Notify: TNotifyIconDataA;
  Vx, Vy: Integer;
begin
  BuildSprites;
  PrimaryH := GetSystemMetrics(SM_CYSCREEN);
  Vx := GetSystemMetrics(SM_XVIRTUALSCREEN);
  Vy := GetSystemMetrics(SM_YVIRTUALSCREEN);
  BufW := GetSystemMetrics(SM_CXVIRTUALSCREEN);
  BufH := GetSystemMetrics(SM_CYVIRTUALSCREEN);
  if BufW < 1 then
    BufW := GetSystemMetrics(SM_CXSCREEN);
  if BufH < 1 then
    BufH := PrimaryH;
  RegionLeft := Vx;
  RegionTop := PrimaryH - Vy;
  ChimePath := GetTempDir + 'nobugs-chime.wav';
  SpeechPath := GetTempDir + 'nobugs-line.wav';
  PlayPath := GetTempDir + 'nobugs-fast.wav';

  FillChar(Cls, SizeOf(Cls), 0);
  Cls.lpfnWndProc := @WindowProc;
  Cls.hInstance := HInstance;
  Cls.lpszClassName := 'NoBugsParade';
  Cls.hCursor := LoadCursor(0, IDC_ARROW);
  RegisterClass(Cls);

  Overlay := CreateWindowEx(
    WS_EX_LAYERED or WS_EX_TRANSPARENT or WS_EX_TOPMOST or WS_EX_TOOLWINDOW or WS_EX_NOACTIVATE,
    'NoBugsParade', 'No Bugs', WS_POPUP,
    Vx, Vy, BufW, BufH, 0, 0, HInstance, nil);
  if Overlay = 0 then
  begin
    Writeln('No Bugs could not open an overlay window.');
    Halt(1);
  end;

  ScreenDC := GetDC(0);
  MemDC := CreateCompatibleDC(ScreenDC);
  FillChar(Info, SizeOf(Info), 0);
  Info.bmiHeader.biSize := SizeOf(BITMAPINFOHEADER);
  Info.bmiHeader.biWidth := BufW;
  Info.bmiHeader.biHeight := -BufH;
  Info.bmiHeader.biPlanes := 1;
  Info.bmiHeader.biBitCount := 32;
  Info.bmiHeader.biCompression := BI_RGB;
  Dib := CreateDIBSection(ScreenDC, Info, DIB_RGB_COLORS, Bits, 0, 0);
  SelectObject(MemDC, Dib);
  ReleaseDC(0, ScreenDC);

  FillChar(Notify, SizeOf(Notify), 0);
  Notify.cbSize := SizeOf(Notify);
  Notify.hWnd := Overlay;
  Notify.uID := 1;
  Notify.uFlags := NIF_MESSAGE or NIF_ICON or NIF_TIP;
  Notify.uCallbackMessage := TrayMsg;
  Notify.hIcon := BugTrayIcon;
  lstrcpynA(@Notify.szTip[0], 'No Bugs', 128);
  Shell_NotifyIconA(NIM_ADD, @Notify);

  ShowWindow(Overlay, SW_SHOWNOACTIVATE);
  RefreshStage;
  if Parade <> nil then
    Parade.FillRoster;
  Writeln('No Bugs is on the taskbar and the window ledges.');
  Writeln('Right-click the tray icon to quit.');
  SetTimer(Overlay, 1, 33, nil);

  Quit := False;
  while not Quit and GetMessage(Msg, 0, 0, 0) do
  begin
    TranslateMessage(Msg);
    DispatchMessage(Msg);
  end;

  KillTimer(Overlay, 1);
  Shell_NotifyIconA(NIM_DELETE, @Notify);
  if Notify.hIcon <> 0 then
    DestroyIcon(Notify.hIcon);
  FreeAndNil(Talker);
  if Dib <> 0 then
    DeleteObject(Dib);
  if MemDC <> 0 then
    DeleteDC(MemDC);
  if Overlay <> 0 then
    DestroyWindow(Overlay);
end;

end.
