unit nbtest;

{$mode objfpc}{$H+}

interface

function RunSelfTests: Boolean;

implementation

uses
  SysUtils, nbtypes, nbgeom, nbsim, nbsound, nbsprites;

var
  Fails: Integer;

procedure Expect(Ok: Boolean; const Msg: string);
begin
  if Ok then
    Exit;
  Inc(Fails);
  Writeln('FAIL: ', Msg);
end;

procedure TestOcclusion;
var
  Windows: array[0..1] of TBox;
  Displays: array[0..0] of TDisplay;
  Ledges: TLedgeList;
  I, WindowLedges: Integer;
  SawLeft, SawRight: Boolean;
begin
  FillChar(Displays[0], SizeOf(Displays[0]), 0);
  Displays[0].Frame.Left := 0;
  Displays[0].Frame.Bottom := 0;
  Displays[0].Frame.Right := 1000;
  Displays[0].Frame.Top := 800;
  Displays[0].Work := Displays[0].Frame;
  Displays[0].Work.Top := 778;
  Displays[0].Work.Bottom := 70;
  Displays[0].DockEdge := deBottom;
  Displays[0].HasDock := True;
  Displays[0].DockBox.Left := 300;
  Displays[0].DockBox.Right := 700;
  Displays[0].DockBox.Bottom := 0;
  Displays[0].DockBox.Top := 70;

  { Front window covers the middle of the rear window's top edge. }
  Windows[0].Left := 100;
  Windows[0].Right := 180;
  Windows[0].Bottom := 100;
  Windows[0].Top := 220;
  Windows[1].Left := 40;
  Windows[1].Right := 260;
  Windows[1].Bottom := 80;
  Windows[1].Top := 180;

  BuildLedges(Windows, Displays, Ledges);
  SawLeft := False;
  SawRight := False;
  WindowLedges := 0;
  for I := 0 to High(Ledges) do
  begin
    if Ledges[I].Kind <> lkWindow then
      Continue;
    Inc(WindowLedges);
    if (Abs(Ledges[I].Y1 - 180) < 0.1) and (Abs(Ledges[I].X1 - 40) < 0.1) and
      (Abs(Ledges[I].X2 - 100) < 0.1) then
      SawLeft := True;
    if (Abs(Ledges[I].Y1 - 180) < 0.1) and (Abs(Ledges[I].X1 - 180) < 0.1) and
      (Abs(Ledges[I].X2 - 260) < 0.1) then
      SawRight := True;
  end;
  Expect(SawLeft, 'rear ledge keeps the uncovered left span');
  Expect(SawRight, 'rear ledge keeps the uncovered right span');
  Expect(WindowLedges = 3, 'the front window keeps its own top, and the rear one is split');
end;

procedure TestDock;
var
  Displays: array[0..0] of TDisplay;
  Ledges: TLedgeList;
  None: array of TBox;
  I: Integer;
  Dock, LeftFloor, RightFloor: Boolean;
begin
  SetLength(None, 0);
  FillChar(Displays[0], SizeOf(Displays[0]), 0);
  Displays[0].Frame.Right := 1000;
  Displays[0].Frame.Top := 800;
  Displays[0].Work := Displays[0].Frame;
  Displays[0].Work.Top := 778;
  Displays[0].Work.Bottom := 70;
  Displays[0].DockEdge := deBottom;
  Displays[0].HasDock := True;
  Displays[0].DockBox.Left := 300;
  Displays[0].DockBox.Right := 700;
  Displays[0].DockBox.Top := 70;
  BuildLedges(None, Displays, Ledges);
  Dock := False;
  LeftFloor := False;
  RightFloor := False;
  for I := 0 to High(Ledges) do
  begin
    if (Ledges[I].Kind = lkDock) and (Abs(Ledges[I].Y1 - 70) < 0.1) and
      (Abs(Ledges[I].X1 - 300) < 0.1) and (Abs(Ledges[I].X2 - 700) < 0.1) then
      Dock := True;
    if (Ledges[I].Kind = lkFloor) and (Abs(Ledges[I].X1) < 0.1) and
      (Abs(Ledges[I].X2 - 300) < 0.1) then
      LeftFloor := True;
    if (Ledges[I].Kind = lkFloor) and (Abs(Ledges[I].X1 - 700) < 0.1) and
      (Abs(Ledges[I].X2 - 1000) < 0.1) then
      RightFloor := True;
  end;
  Expect(Dock, 'the Dock itself is a ledge');
  Expect(LeftFloor, 'wallpaper beside the Dock, left');
  Expect(RightFloor, 'wallpaper beside the Dock, right');
end;

procedure TestWalkAndExit;
var
  W: TWorld;
  D: array[0..0] of TDisplay;
  L: TLedgeList;
  B: TBug;
  I: Integer;
begin
  AllowLoaf := False;
  W := TWorld.Create;
  try
    FillChar(D[0], SizeOf(D[0]), 0);
    D[0].Frame.Right := 1000;
    D[0].Frame.Top := 800;
    D[0].Work := D[0].Frame;
    D[0].DockEdge := deNone;
    SetLength(L, 1);
    L[0].Kind := lkFloor;
    L[0].Horizontal := True;
    L[0].X1 := 0;
    L[0].X2 := 1000;
    L[0].Y1 := 0;
    L[0].Y2 := 0;
    W.Target := 0;
    W.SetStage(D, L);
    FillChar(B, SizeOf(B), 0);
    B.X := 100;
    B.Y := 0;
    B.Dir := 1;
    B.Species := spAnt;
    B.State := stWalk;
    B.Horizontal := True;
    B.Alive := True;
    SetLength(W.Bugs, 1);
    W.Bugs[0] := B;
    for I := 1 to 30 do
      W.Tick(1 / 30);
    Expect(W.Bugs[0].Alive, 'a bug on a long floor stays in the world');
    Expect(W.Bugs[0].Y = 0, 'feet stay on the floor');
    Expect(W.Bugs[0].X > 120, 'the ant actually walks');

    W.Bugs[0].State := stExit;
    W.Bugs[0].X := 990;
    W.Bugs[0].Dir := 1;
    W.Bugs[0].Alive := True;
    for I := 1 to 90 do
    begin
      if Length(W.Bugs) = 0 then
        Break;
      W.Tick(1 / 30);
    end;
    Expect(W.AliveCount = 0, 'walking off the glass removes the bug');
  finally
    W.Free;
  end;
  AllowLoaf := True;
end;

procedure TestFallLands;
var
  W: TWorld;
  D: array[0..0] of TDisplay;
  L: TLedgeList;
  B: TBug;
  I: Integer;
  Landed: Boolean;
begin
  AllowLoaf := False;
  W := TWorld.Create;
  try
    FillChar(D[0], SizeOf(D[0]), 0);
    D[0].Frame.Right := 800;
    D[0].Frame.Top := 600;
    D[0].Work := D[0].Frame;
    D[0].DockEdge := deNone;
    SetLength(L, 1);
    L[0].Kind := lkWindow;
    L[0].Horizontal := True;
    L[0].X1 := 0;
    L[0].X2 := 500;
    L[0].Y1 := 100;
    L[0].Y2 := 100;
    W.Target := 0;
    W.SetStage(D, L);
    FillChar(B, SizeOf(B), 0);
    B.X := 200;
    B.Y := 180;
    B.VY := -10;
    B.Dir := 1;
    B.Species := spBeetle;
    B.State := stFall;
    B.Horizontal := True;
    B.Alive := True;
    SetLength(W.Bugs, 1);
    W.Bugs[0] := B;
    Landed := False;
    for I := 1 to 60 do
    begin
      W.Tick(1 / 30);
      if (Length(W.Bugs) > 0) and (W.Bugs[0].State = stWalk) and (Abs(W.Bugs[0].Y - 100) < 0.1) then
        Landed := True;
    end;
    Expect(Landed, 'a falling beetle lands on the title bar');
  finally
    W.Free;
  end;
  AllowLoaf := True;
end;

procedure TestVoiceAndChime;
var
  Ids: array[0..3] of string;
  Wav, Fast, Padded: TBytes;
  Chosen: string;
  Exits, I: Integer;
  Rate: Cardinal;
begin
  Ids[0] := 'com.apple.speech.synthesis.voice.Daniel';
  Ids[1] := 'com.apple.speech.synthesis.voice.Kathy';
  Ids[2] := 'com.apple.voice.compact.en-US.Samantha';
  Ids[3] := 'com.apple.speech.synthesis.voice.Tingting';
  Chosen := PickSillyVoice(Ids);
  Expect(Pos('Kathy', Chosen) > 0, 'Kathy is the System 7 American woman');
  Expect(Pos('Daniel', Chosen) = 0, 'Daniel does not get the line');
  Expect(SayCheer('No bugs!') = 'No! Bugs!', 'two shouts, in her own tempo');
  Expect(Pos('anzai', LowerCase(SayCheer('No bugs!'))) = 0, 'the cheer does not add another word');
  Wav := MakeChimeWav;
  Expect(Length(Wav) > 44, 'the chime has a body');
  Expect((Wav[0] = Ord('R')) and (Wav[1] = Ord('I')) and (Wav[2] = Ord('F')) and (Wav[3] = Ord('F')),
    'the chime is a WAV');
  Fast := SoundMasterWav(Wav, 2);
  Expect(Length(Fast) = Length(Wav), 'SoundMaster does not resample');
  Rate := Cardinal(Fast[24]) or (Cardinal(Fast[25]) shl 8) or
    (Cardinal(Fast[26]) shl 16) or (Cardinal(Fast[27]) shl 24);
  Expect(Rate = 44100, 'a 22050 Hz chime played at twice the hertz');
  { say inserts a filler chunk before the samples. The rate lie has to
    find fmt wherever it sits, not assume it starts at byte 12. }
  SetLength(Padded, 12 + 8 + 4 + 8 + 16 + 8 + 4);
  Padded[0] := Ord('R');
  Padded[1] := Ord('I');
  Padded[2] := Ord('F');
  Padded[3] := Ord('F');
  Padded[8] := Ord('W');
  Padded[9] := Ord('A');
  Padded[10] := Ord('V');
  Padded[11] := Ord('E');
  Padded[12] := Ord('J');
  Padded[13] := Ord('U');
  Padded[14] := Ord('N');
  Padded[15] := Ord('K');
  Padded[16] := 4;
  Padded[20] := Ord('x');
  Padded[24] := Ord('f');
  Padded[25] := Ord('m');
  Padded[26] := Ord('t');
  Padded[27] := Ord(' ');
  Padded[28] := 16;
  Padded[32] := 1;
  Padded[34] := 1;
  Padded[36] := Byte(11025 and $FF);
  Padded[37] := Byte((11025 shr 8) and $FF);
  Padded[40] := Padded[36];
  Padded[41] := Padded[37];
  Padded[44] := 1;
  Padded[46] := 8;
  Padded[48] := Ord('d');
  Padded[49] := Ord('a');
  Padded[50] := Ord('t');
  Padded[51] := Ord('a');
  Padded[52] := 4;
  Padded[56] := 9;
  Padded[57] := 8;
  Padded[58] := 7;
  Padded[59] := 6;
  Fast := SoundMasterWav(Padded, 2);
  Rate := Cardinal(Fast[36]) or (Cardinal(Fast[37]) shl 8) or
    (Cardinal(Fast[38]) shl 16) or (Cardinal(Fast[39]) shl 24);
  Expect(Rate = 22050, 'the rate lie finds fmt after a filler chunk');
  Expect(Fast[56] = 9, 'the samples themselves stay put');
  Expect(WavPlaybackSeconds(Fast) > 0, 'a lied header still has a duration');
  RandSeed := 7;
  Exits := 0;
  for I := 1 to 80 do
    if ChooseLipAction(lkDock, True) = laExit then
      Inc(Exits);
  Expect(Exits > 40, 'at the edge of the Dock, most of them leave');
end;

procedure TestSpriteInk;
var
  B: TBug;
  S: TSprite;
  I, Opaque: Integer;
begin
  BuildSprites;
  FillChar(B, SizeOf(B), 0);
  B.Species := spAnt;
  B.Dir := 1;
  B.Horizontal := True;
  B.Alive := True;
  S := SpriteFor(B);
  Opaque := 0;
  for I := 0 to S.W * S.H - 1 do
    if S.Pixels[I * 4 + 3] > 0 then
      Inc(Opaque);
  Expect(Opaque > 40, 'the ant is not an empty sprite');
end;

function RunSelfTests: Boolean;
begin
  Fails := 0;
  RandSeed := 424242;
  TestOcclusion;
  TestDock;
  TestWalkAndExit;
  TestFallLands;
  TestVoiceAndChime;
  TestSpriteInk;
  if Fails = 0 then
    Writeln('self-test: ok')
  else
    Writeln('self-test: ', Fails, ' failed');
  Result := Fails = 0;
end;

end.
