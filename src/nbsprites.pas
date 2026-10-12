unit nbsprites;

{
  Drawn one blob at a time, in the spirit of a System 7 icon that grew
  too many legs. The antennae are the only part of the program that
  seems to be listening for a correction.
}

{$mode objfpc}{$H+}

interface

uses
  nbtypes;

const
  PixelScale = 2;
  ArtW = 48;
  ArtH = 34;
  BugHalfWidth = 24;

type
  TSprite = record
    W, H: Integer;
    FootX, FootY: Integer;
    Pixels: PByte;
  end;

procedure BuildSprites;
function SpritesReady: Boolean;
function SpriteFor(const Bug: TBug): TSprite;
procedure SpriteRect(const S: TSprite; FootWorldX, FootWorldY: Double;
  out Left, Bottom, Width, Height: Double);
procedure BlitSprite(const S: TSprite; FootWorldX, FootWorldY, RegionLeft, RegionTop: Double;
  Dest: PByte; DestW, DestH: Integer);
procedure PremultiplyInPlace(P: PByte; Count: Integer);
procedure SavePreview(const Path: string);

implementation

uses
  SysUtils, Classes, Math;

type
  TRaster = class
    W, H: Integer;
    Pix: PByte;
    constructor Create(AW, AH: Integer);
    destructor Destroy; override;
    procedure Clear;
    procedure Plot(X, Y: Integer; const C: TPixel);
    procedure Oval(CX, CY, RX, RY: Double; const C: TPixel);
    procedure Stick(X1, Y1, X2, Y2, Thick: Double; const C: TPixel);
  end;

var
  Ready: Boolean;
  RightS, LeftS: array[TSpecies, 0..3] of TSprite;
  UpLeft, UpRight, DownLeft, DownRight: array[TSpecies, 0..3] of TSprite;

function SpritesReady: Boolean;
begin
  Result := Ready;
end;

constructor TRaster.Create(AW, AH: Integer);
begin
  inherited Create;
  W := AW;
  H := AH;
  Pix := GetMem(W * H * 4);
  Clear;
end;

destructor TRaster.Destroy;
begin
  if Pix <> nil then
    FreeMem(Pix);
  inherited Destroy;
end;

procedure TRaster.Clear;
begin
  FillChar(Pix^, W * H * 4, 0);
end;

procedure TRaster.Plot(X, Y: Integer; const C: TPixel);
var
  Dst: PByte;
  Inv, DA, OA, SR, SG, SB: Integer;
begin
  if (X < 0) or (Y < 0) or (X >= W) or (Y >= H) or (C.A = 0) then
    Exit;
  Dst := Pix + (Y * W + X) * 4;
  if C.A = 255 then
  begin
    Dst[0] := C.R;
    Dst[1] := C.G;
    Dst[2] := C.B;
    Dst[3] := 255;
    Exit;
  end;
  DA := Dst[3];
  Inv := 255 - C.A;
  OA := C.A + DA * Inv div 255;
  if OA <= 0 then
    Exit;
  SR := C.R;
  SG := C.G;
  SB := C.B;
  Dst[0] := Byte((SR * C.A + Integer(Dst[0]) * DA * Inv div 255) div OA);
  Dst[1] := Byte((SG * C.A + Integer(Dst[1]) * DA * Inv div 255) div OA);
  Dst[2] := Byte((SB * C.A + Integer(Dst[2]) * DA * Inv div 255) div OA);
  Dst[3] := Byte(OA);
end;

procedure TRaster.Oval(CX, CY, RX, RY: Double; const C: TPixel);
var
  X0, Y0, X1, Y1, X, Y: Integer;
  DX, DY, PX, PY: Double;
begin
  if (RX <= 0) or (RY <= 0) then
    Exit;
  X0 := Floor((CX - RX) * PixelScale) - 1;
  X1 := Ceil((CX + RX) * PixelScale) + 1;
  Y0 := Floor((CY - RY) * PixelScale) - 1;
  Y1 := Ceil((CY + RY) * PixelScale) + 1;
  for Y := Y0 to Y1 do
    for X := X0 to X1 do
    begin
      PX := (X + 0.5) / PixelScale;
      PY := (Y + 0.5) / PixelScale;
      DX := (PX - CX) / RX;
      DY := (PY - CY) / RY;
      if DX * DX + DY * DY <= 1 then
        Plot(X, H - 1 - Y, C);
    end;
end;

procedure TRaster.Stick(X1, Y1, X2, Y2, Thick: Double; const C: TPixel);
var
  Len, T, X, Y: Double;
  Steps, I: Integer;
begin
  Len := Hypot(X2 - X1, Y2 - Y1);
  Steps := Max(1, Round(Len / 0.45));
  for I := 0 to Steps do
  begin
    T := I / Steps;
    X := X1 + (X2 - X1) * T;
    Y := Y1 + (Y2 - Y1) * T;
    Oval(X, Y, Thick, Thick, C);
  end;
end;

procedure Keep(var Dest: TSprite; R: TRaster; FootPtX, FootPtY: Double);
begin
  Dest.W := R.W;
  Dest.H := R.H;
  Dest.FootX := Round(FootPtX * PixelScale);
  Dest.FootY := R.H - 1 - Round(FootPtY * PixelScale);
  Dest.Pixels := GetMem(R.W * R.H * 4);
  Move(R.Pix^, Dest.Pixels^, R.W * R.H * 4);
end;

procedure MirrorSprite(const Src: TSprite; var Dest: TSprite);
var
  X, Y: Integer;
  S, D: PByte;
begin
  Dest.W := Src.W;
  Dest.H := Src.H;
  Dest.FootX := Src.W - 1 - Src.FootX;
  Dest.FootY := Src.FootY;
  Dest.Pixels := GetMem(Src.W * Src.H * 4);
  for Y := 0 to Src.H - 1 do
    for X := 0 to Src.W - 1 do
    begin
      S := Src.Pixels + (Y * Src.W + X) * 4;
      D := Dest.Pixels + (Y * Src.W + (Src.W - 1 - X)) * 4;
      Move(S^, D^, 4);
    end;
end;

procedure RotateCCW(const Src: TSprite; var Dest: TSprite);
var
  X, Y, NX, NY: Integer;
  S, D: PByte;
begin
  { Head was on the right and feet were on the bottom. After this they
    point up and to the left, which is what you want on a left-hand Dock. }
  Dest.W := Src.H;
  Dest.H := Src.W;
  Dest.Pixels := GetMem(Dest.W * Dest.H * 4);
  FillChar(Dest.Pixels^, Dest.W * Dest.H * 4, 0);
  for Y := 0 to Src.H - 1 do
    for X := 0 to Src.W - 1 do
    begin
      NX := Src.H - 1 - Y;
      NY := Src.W - 1 - X;
      S := Src.Pixels + (Y * Src.W + X) * 4;
      D := Dest.Pixels + (NY * Dest.W + NX) * 4;
      Move(S^, D^, 4);
    end;
  Dest.FootX := Src.H - 1 - Src.FootY;
  Dest.FootY := Src.W - 1 - Src.FootX;
end;

procedure RotateCW(const Src: TSprite; var Dest: TSprite);
var
  X, Y, NX, NY: Integer;
  S, D: PByte;
begin
  Dest.W := Src.H;
  Dest.H := Src.W;
  Dest.Pixels := GetMem(Dest.W * Dest.H * 4);
  FillChar(Dest.Pixels^, Dest.W * Dest.H * 4, 0);
  for Y := 0 to Src.H - 1 do
    for X := 0 to Src.W - 1 do
    begin
      NX := Y;
      NY := X;
      S := Src.Pixels + (Y * Src.W + X) * 4;
      D := Dest.Pixels + (NY * Dest.W + NX) * 4;
      Move(S^, D^, 4);
    end;
  Dest.FootX := Src.FootY;
  Dest.FootY := Src.FootX;
end;

procedure DrawAnt(R: TRaster; Frame: Integer);
var
  Sway: Double;
  Feet: array[0..2] of Double;
  Outline, Body, Hi, Leg, Far: TPixel;
begin
  Outline := Pix(22, 12, 8, 255);
  Body := Pix(74, 48, 28, 255);
  Hi := Pix(140, 98, 60, 230);
  Leg := Pix(32, 18, 10, 255);
  Far := Pix(58, 36, 20, 255);
  R.Oval(24, 1.3, 11, 1.5, Pix(0, 0, 0, 55));
  R.Oval(14, 16, 9.0, 6.2, Outline);
  R.Oval(14, 16, 7.4, 4.8, Body);
  R.Oval(12, 18.2, 3.0, 1.5, Hi);
  R.Oval(25.5, 15.6, 5.0, 4.0, Outline);
  R.Oval(25.5, 15.6, 3.7, 2.9, Body);
  R.Oval(34.2, 16.6, 4.2, 3.6, Outline);
  R.Oval(34.2, 16.6, 3.2, 2.7, Body);
  R.Oval(36.0, 17.6, 1.15, 1.15, Pix(248, 246, 236, 255));
  R.Oval(36.3, 17.5, 0.55, 0.55, Pix(18, 12, 8, 255));
  Sway := (Frame - 1.5) * 1.3;
  R.Stick(32.6, 19.4, 27.2, 27.0 + Sway, 0.55, Leg);
  R.Stick(35.2, 19.6, 40.2, 27.6 - Sway, 0.55, Leg);
  R.Oval(27.2, 27.0 + Sway, 0.7, 0.7, Leg);
  R.Oval(40.2, 27.6 - Sway, 0.7, 0.7, Leg);
  case Frame of
    0:
      begin
        Feet[0] := -6;
        Feet[1] := 1;
        Feet[2] := 6;
      end;
    1:
      begin
        Feet[0] := -2;
        Feet[1] := 5;
        Feet[2] := -3;
      end;
    2:
      begin
        Feet[0] := 6;
        Feet[1] := -1;
        Feet[2] := -6;
      end;
  else
    begin
      Feet[0] := 2;
      Feet[1] := -5;
      Feet[2] := 4;
    end;
  end;
  R.Stick(21.5, 12.4, 21.5 + Feet[0], 2.0, 0.85, Leg);
  R.Stick(25.5, 12.0, 25.5 + Feet[1], 2.0, 0.85, Leg);
  R.Stick(29.5, 12.4, 29.5 + Feet[2], 2.0, 0.85, Leg);
  R.Stick(22.5, 14.6, 22.5 + Feet[2] * 0.55, 8.0, 0.55, Far);
  R.Stick(27.0, 14.6, 27.0 + Feet[0] * 0.55, 8.4, 0.55, Far);
end;

procedure DrawLadybug(R: TRaster; Frame: Integer);
var
  Kick: Double;
  Shell, Dark, Leg: TPixel;
begin
  Dark := Pix(18, 14, 16, 255);
  Shell := Pix(196, 36, 40, 255);
  Leg := Pix(16, 12, 14, 255);
  Kick := (Frame mod 2) * 3 - 1.5;
  R.Oval(22, 1.4, 12, 1.6, Pix(0, 0, 0, 50));
  R.Oval(20, 16, 12.2, 8.2, Dark);
  R.Oval(20, 16.4, 10.6, 6.8, Shell);
  R.Oval(16, 18.5, 3.2, 1.4, Pix(240, 120, 120, 180));
  R.Stick(14, 16, 26, 16, 0.45, Dark);
  R.Oval(14, 19, 1.7, 1.5, Dark);
  R.Oval(22, 20, 1.8, 1.6, Dark);
  R.Oval(18, 14, 1.5, 1.3, Dark);
  R.Oval(26, 15.5, 1.6, 1.4, Dark);
  R.Oval(33.5, 16.2, 4.6, 4.2, Dark);
  R.Oval(35.2, 17.6, 1.05, 1.05, Pix(250, 250, 245, 255));
  R.Oval(35.5, 17.5, 0.5, 0.5, Dark);
  R.Stick(12, 11, 8 + Kick, 2.2, 0.8, Leg);
  R.Stick(18, 10, 16 - Kick, 2.0, 0.8, Leg);
  R.Stick(24, 10.5, 26 + Kick, 2.1, 0.8, Leg);
  R.Stick(10, 14, 6, 9 + Kick, 0.55, Leg);
  R.Stick(30, 13, 34, 8 - Kick, 0.55, Leg);
end;

procedure DrawBeetle(R: TRaster; Frame: Integer);
var
  Step: Double;
  Dark, Body, Hi, Leg: TPixel;
begin
  Dark := Pix(10, 32, 24, 255);
  Body := Pix(28, 110, 72, 255);
  Hi := Pix(120, 210, 150, 200);
  Leg := Pix(12, 28, 20, 255);
  Step := (Frame - 1.5) * 2.2;
  R.Oval(24, 1.3, 12, 1.5, Pix(0, 0, 0, 55));
  R.Oval(16, 15, 10, 6.4, Dark);
  R.Oval(16, 15.2, 8.4, 5.0, Body);
  R.Oval(13, 17.4, 3.4, 1.6, Hi);
  R.Oval(28, 15.2, 5.2, 4.2, Dark);
  R.Oval(28, 15.2, 4.0, 3.1, Body);
  R.Oval(35.5, 16.4, 3.6, 3.2, Dark);
  R.Oval(35.5, 16.4, 2.6, 2.3, Pix(20, 70, 48, 255));
  R.Stick(37.5, 18.6, 43.5, 22.5 + Step * 0.3, 0.7, Dark);
  R.Oval(36.6, 17.4, 0.9, 0.9, Pix(230, 245, 220, 255));
  R.Oval(36.8, 17.3, 0.4, 0.4, Dark);
  R.Stick(22, 11, 18 + Step, 2.0, 0.9, Leg);
  R.Stick(27, 10.6, 29 - Step, 2.0, 0.9, Leg);
  R.Stick(32, 11.2, 35 + Step * 0.6, 2.2, 0.8, Leg);
  R.Stick(20, 13.5, 16 - Step * 0.4, 7.5, 0.55, Pix(16, 48, 34, 255));
  R.Stick(30, 13.2, 33 + Step * 0.4, 7.2, 0.55, Pix(16, 48, 34, 255));
end;

procedure DrawCaterpillar(R: TRaster; Frame: Integer);
var
  I: Integer;
  X, Y, Bob: Double;
  Green, Dark, Belly: TPixel;
begin
  Green := Pix(116, 168, 46, 255);
  Dark := Pix(62, 100, 24, 255);
  Belly := Pix(186, 210, 90, 255);
  R.Oval(24, 1.5, 14, 1.4, Pix(0, 0, 0, 45));
  for I := 0 to 5 do
  begin
    Bob := Sin((I + Frame) * 1.15) * 1.6;
    X := 8 + I * 6.2;
    Y := 10 + Bob;
    R.Oval(X, Y, 3.8, 3.3, Dark);
    R.Oval(X, Y + 0.4, 3.0, 2.5, Green);
    R.Oval(X, Y - 0.8, 2.2, 1.2, Belly);
    R.Stick(X - 1.2, Y - 2.4, X - 2.4, 2.0, 0.45, Dark);
    R.Stick(X + 1.2, Y - 2.4, X + 2.2, 2.0, 0.45, Dark);
  end;
  X := 8 + 5 * 6.2;
  Y := 10 + Sin((5 + Frame) * 1.15) * 1.6;
  R.Oval(X + 1.2, Y + 1.3, 1.0, 1.0, Pix(250, 250, 240, 255));
  R.Oval(X + 1.5, Y + 1.2, 0.45, 0.45, Dark);
  R.Stick(X + 2.4, Y + 2.6, X + 5.5, Y + 5.2, 0.4, Dark);
  R.Stick(X + 0.4, Y + 2.8, X - 1.5, Y + 5.4, 0.4, Dark);
end;

procedure DrawSpecies(R: TRaster; S: TSpecies; Frame: Integer);
begin
  case S of
    spAnt: DrawAnt(R, Frame);
    spLadybug: DrawLadybug(R, Frame);
    spBeetle: DrawBeetle(R, Frame);
    spCaterpillar: DrawCaterpillar(R, Frame);
  end;
end;

procedure BuildSprites;
var
  S: TSpecies;
  F: Integer;
  R: TRaster;
begin
  if Ready then
    Exit;
  R := TRaster.Create(ArtW * PixelScale, ArtH * PixelScale);
  try
    for S := Low(TSpecies) to High(TSpecies) do
      for F := 0 to 3 do
      begin
        R.Clear;
        DrawSpecies(R, S, F);
        Keep(RightS[S, F], R, 24, 2);
        MirrorSprite(RightS[S, F], LeftS[S, F]);
        RotateCCW(RightS[S, F], UpLeft[S, F]);
        MirrorSprite(UpLeft[S, F], UpRight[S, F]);
        RotateCW(RightS[S, F], DownRight[S, F]);
        MirrorSprite(DownRight[S, F], DownLeft[S, F]);
      end;
  finally
    R.Free;
  end;
  Ready := True;
end;

function SpriteFor(const Bug: TBug): TSprite;
var
  F: Integer;
begin
  if not Ready then
    BuildSprites;
  F := Bug.Frame mod 4;
  if F < 0 then
    F := 0;
  if Bug.Horizontal then
  begin
    if Bug.Dir < 0 then
      Result := LeftS[Bug.Species, F]
    else
      Result := RightS[Bug.Species, F];
  end
  else if Bug.Dir >= 0 then
  begin
    if Bug.FeetOnLeft then
      Result := UpLeft[Bug.Species, F]
    else
      Result := UpRight[Bug.Species, F];
  end
  else if Bug.FeetOnLeft then
    Result := DownLeft[Bug.Species, F]
  else
    Result := DownRight[Bug.Species, F];
end;

procedure SpriteRect(const S: TSprite; FootWorldX, FootWorldY: Double;
  out Left, Bottom, Width, Height: Double);
begin
  Width := S.W / PixelScale;
  Height := S.H / PixelScale;
  Left := FootWorldX - S.FootX / PixelScale;
  Bottom := FootWorldY - (S.H - S.FootY) / PixelScale;
end;

procedure BlitSprite(const S: TSprite; FootWorldX, FootWorldY, RegionLeft, RegionTop: Double;
  Dest: PByte; DestW, DestH: Integer);
var
  Left, Bottom, Width, Height: Double;
  OX, OY, DX, DY, SX, SY, BX, BY: Integer;
  Src, Dst: PByte;
  SA, DA, Inv, OA: Integer;
  DW, DH: Integer;
begin
  if (S.Pixels = nil) or (Dest = nil) then
    Exit;
  SpriteRect(S, FootWorldX, FootWorldY, Left, Bottom, Width, Height);
  DW := Trunc(Width);
  DH := Trunc(Height);
  if DW < 1 then
    DW := 1;
  if DH < 1 then
    DH := 1;
  OX := Trunc(Left - RegionLeft);
  OY := Trunc(RegionTop - (Bottom + Height));
  for DY := 0 to DH - 1 do
    for DX := 0 to DW - 1 do
    begin
      BX := OX + DX;
      BY := OY + DY;
      if (BX < 0) or (BY < 0) or (BX >= DestW) or (BY >= DestH) then
        Continue;
      SX := DX * PixelScale + PixelScale div 2;
      SY := DY * PixelScale + PixelScale div 2;
      if SX >= S.W then
        SX := S.W - 1;
      if SY >= S.H then
        SY := S.H - 1;
      Src := S.Pixels + (SY * S.W + SX) * 4;
      SA := Src[3];
      if SA = 0 then
        Continue;
      Dst := Dest + (BY * DestW + BX) * 4;
      if SA = 255 then
      begin
        Move(Src^, Dst^, 4);
        Continue;
      end;
      DA := Dst[3];
      Inv := 255 - SA;
      OA := SA + DA * Inv div 255;
      if OA <= 0 then
        Continue;
      Dst[0] := Byte((Integer(Src[0]) * SA + Integer(Dst[0]) * DA * Inv div 255) div OA);
      Dst[1] := Byte((Integer(Src[1]) * SA + Integer(Dst[1]) * DA * Inv div 255) div OA);
      Dst[2] := Byte((Integer(Src[2]) * SA + Integer(Dst[2]) * DA * Inv div 255) div OA);
      Dst[3] := Byte(OA);
    end;
end;

procedure PremultiplyInPlace(P: PByte; Count: Integer);
var
  I, A: Integer;
begin
  for I := 0 to Count - 1 do
  begin
    A := P[3];
    if A = 0 then
    begin
      P[0] := 0;
      P[1] := 0;
      P[2] := 0;
    end
    else if A < 255 then
    begin
      P[0] := Byte(Integer(P[0]) * A div 255);
      P[1] := Byte(Integer(P[1]) * A div 255);
      P[2] := Byte(Integer(P[2]) * A div 255);
    end;
    Inc(P, 4);
  end;
end;

procedure SavePreview(const Path: string);
var
  BmpW, BmpH, X, Y, Row, Col, Stride, Pad, FileSize: Integer;
  Buf: PByte;
  F: TFileStream;
  Header: array[0..53] of Byte;
  B: TBug;
  S: TSprite;
  Pix: PByte;
  RegionTop: Double;
begin
  BuildSprites;
  BmpW := 640;
  BmpH := 420;
  Buf := GetMem(BmpW * BmpH * 4);
  try
    FillChar(Buf^, BmpW * BmpH * 4, 0);
    for Y := 0 to BmpH - 1 do
      for X := 0 to BmpW - 1 do
      begin
        Pix := Buf + (Y * BmpW + X) * 4;
        Pix[0] := 236;
        Pix[1] := 232;
        Pix[2] := 214;
        Pix[3] := 255;
      end;
    RegionTop := BmpH;
    for Row := 0 to BmpH - 1 do
    begin
      Y := Row;
      if Abs((RegionTop - Y) - 80) < 1.2 then
        for X := 20 to BmpW - 20 do
        begin
          Pix := Buf + (Y * BmpW + X) * 4;
          Pix[0] := 40;
          Pix[1] := 32;
          Pix[2] := 24;
          Pix[3] := 255;
        end;
    end;
    for Row := 0 to 3 do
      for Col := 0 to 3 do
      begin
        FillChar(B, SizeOf(B), 0);
        B.Species := TSpecies(Row);
        B.Frame := Col;
        B.Dir := 1;
        B.Horizontal := True;
        B.Alive := True;
        S := SpriteFor(B);
        BlitSprite(S, 70 + Col * 140, 80 + (3 - Row) * 90, 0, RegionTop, Buf, BmpW, BmpH);
      end;
    FillChar(B, SizeOf(B), 0);
    B.Species := spAnt;
    B.Frame := 1;
    B.Dir := -1;
    B.Horizontal := True;
    B.Alive := True;
    BlitSprite(SpriteFor(B), 560, 80, 0, RegionTop, Buf, BmpW, BmpH);

    Pad := (4 - (BmpW * 3) mod 4) mod 4;
    Stride := BmpW * 3 + Pad;
    FileSize := 54 + Stride * BmpH;
    FillChar(Header, SizeOf(Header), 0);
    Header[0] := Ord('B');
    Header[1] := Ord('M');
    Header[2] := Byte(FileSize and $FF);
    Header[3] := Byte((FileSize shr 8) and $FF);
    Header[4] := Byte((FileSize shr 16) and $FF);
    Header[5] := Byte((FileSize shr 24) and $FF);
    Header[10] := 54;
    Header[14] := 40;
    Header[18] := Byte(BmpW and $FF);
    Header[19] := Byte((BmpW shr 8) and $FF);
    Header[22] := Byte(BmpH and $FF);
    Header[23] := Byte((BmpH shr 8) and $FF);
    Header[26] := 1;
    Header[28] := 24;
    F := TFileStream.Create(Path, fmCreate);
    try
      F.WriteBuffer(Header, 54);
      for Y := BmpH - 1 downto 0 do
      begin
        for X := 0 to BmpW - 1 do
        begin
          Pix := Buf + (Y * BmpW + X) * 4;
          F.WriteBuffer(Pix[2], 1);
          F.WriteBuffer(Pix[1], 1);
          F.WriteBuffer(Pix[0], 1);
        end;
        if Pad > 0 then
        begin
          Header[30] := 0;
          Header[31] := 0;
          Header[32] := 0;
          F.WriteBuffer(Header[30], Pad);
        end;
      end;
    finally
      F.Free;
    end;
  finally
    FreeMem(Buf);
  end;
end;

end.
