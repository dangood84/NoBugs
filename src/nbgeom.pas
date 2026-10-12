unit nbgeom;

{
  Window tops are a level. The Dock is a level. Anything buried behind
  a nearer window is not a floor — a bug standing there would be
  hovering in front of somebody else's title bar, which is a different
  kind of lie from the one the voice tells.
}

{$mode objfpc}{$H+}

interface

uses
  nbtypes;

const
  MinLedge = 48;

procedure BuildLedges(const Windows: array of TBox; const Displays: array of TDisplay;
  out Ledges: TLedgeList);

implementation

uses
  Math;

type
  TSeg = record
    A, B: Double;
  end;
  TSegList = array of TSeg;

procedure PushSeg(var Segs: TSegList; A, B: Double);
begin
  if B - A < MinLedge then
    Exit;
  SetLength(Segs, Length(Segs) + 1);
  Segs[High(Segs)].A := A;
  Segs[High(Segs)].B := B;
end;

function SubtractSegs(const Segs: TSegList; CutA, CutB: Double): TSegList;
var
  I: Integer;
  S: TSeg;
begin
  Result := nil;
  SetLength(Result, 0);
  if CutB < CutA then
  begin
    Result := Segs;
    Exit;
  end;
  for I := 0 to High(Segs) do
  begin
    S := Segs[I];
    if (CutB <= S.A) or (CutA >= S.B) then
      PushSeg(Result, S.A, S.B)
    else
    begin
      if CutA > S.A then
        PushSeg(Result, S.A, CutA);
      if CutB < S.B then
        PushSeg(Result, CutB, S.B);
    end;
  end;
end;

procedure AddLedge(var Ledges: TLedgeList; Kind: TLedgeKind; Horizontal: Boolean;
  X1, X2, Y1, Y2: Double);
var
  L: TLedge;
begin
  if Length(Ledges) >= 80 then
    Exit;
  if Horizontal then
  begin
    if X2 - X1 < MinLedge then
      Exit;
    if X2 < X1 then
    begin
      L.X1 := X2;
      L.X2 := X1;
    end
    else
    begin
      L.X1 := X1;
      L.X2 := X2;
    end;
    L.Y1 := Y1;
    L.Y2 := Y1;
  end
  else
  begin
    if Y2 - Y1 < MinLedge then
      Exit;
    L.X1 := X1;
    L.X2 := X1;
    if Y2 < Y1 then
    begin
      L.Y1 := Y2;
      L.Y2 := Y1;
    end
    else
    begin
      L.Y1 := Y1;
      L.Y2 := Y2;
    end;
  end;
  L.Kind := Kind;
  L.Horizontal := Horizontal;
  SetLength(Ledges, Length(Ledges) + 1);
  Ledges[High(Ledges)] := L;
end;

function CoversY(const W: TBox; Y: Double): Boolean;
begin
  Result := (Y >= W.Bottom - 1) and (Y <= W.Top + 1);
end;

function OnDisplay(const D: TDisplay; Y, X1, X2: Double): Boolean;
begin
  Result := (Y >= D.Frame.Bottom - 2) and (Y <= D.Frame.Top + 2) and
    (X2 > D.Frame.Left + 4) and (X1 < D.Frame.Right - 4);
end;

procedure AddDock(var Ledges: TLedgeList; const D: TDisplay);
var
  X, Y1, Y2: Double;
begin
  case D.DockEdge of
    deBottom:
      begin
        if D.HasDock then
        begin
          AddLedge(Ledges, lkDock, True, D.DockBox.Left, D.DockBox.Right, D.DockBox.Top, D.DockBox.Top);
          if D.DockBox.Left - D.Frame.Left > MinLedge then
            AddLedge(Ledges, lkFloor, True, D.Frame.Left, D.DockBox.Left, D.Frame.Bottom, D.Frame.Bottom);
          if D.Frame.Right - D.DockBox.Right > MinLedge then
            AddLedge(Ledges, lkFloor, True, D.DockBox.Right, D.Frame.Right, D.Frame.Bottom, D.Frame.Bottom);
        end
        else
          AddLedge(Ledges, lkDock, True, D.Frame.Left, D.Frame.Right, D.Work.Bottom, D.Work.Bottom);
      end;
    deLeft:
      begin
        if D.HasDock then
          X := D.DockBox.Right
        else
          X := D.Work.Left;
        Y1 := D.Frame.Bottom;
        Y2 := D.Work.Top;
        if D.HasDock then
        begin
          Y1 := D.DockBox.Bottom;
          Y2 := D.DockBox.Top;
        end;
        AddLedge(Ledges, lkWall, False, X, X, Y1, Y2);
        AddLedge(Ledges, lkFloor, True, X, D.Frame.Right, D.Frame.Bottom, D.Frame.Bottom);
      end;
    deRight:
      begin
        if D.HasDock then
          X := D.DockBox.Left
        else
          X := D.Work.Right;
        Y1 := D.Frame.Bottom;
        Y2 := D.Work.Top;
        if D.HasDock then
        begin
          Y1 := D.DockBox.Bottom;
          Y2 := D.DockBox.Top;
        end;
        AddLedge(Ledges, lkWall, False, X, X, Y1, Y2);
        AddLedge(Ledges, lkFloor, True, D.Frame.Left, X, D.Frame.Bottom, D.Frame.Bottom);
      end;
  else
    AddLedge(Ledges, lkFloor, True, D.Frame.Left, D.Frame.Right, D.Frame.Bottom, D.Frame.Bottom);
  end;
end;

procedure BuildLedges(const Windows: array of TBox; const Displays: array of TDisplay;
  out Ledges: TLedgeList);
var
  D, I, J, S: Integer;
  TopY, A, B: Double;
  Segs: TSegList;
  W: TBox;
begin
  SetLength(Ledges, 0);
  for D := 0 to High(Displays) do
    AddDock(Ledges, Displays[D]);

  for I := 0 to High(Windows) do
  begin
    W := Windows[I];
    TopY := W.Top;
    if W.Right - W.Left < MinLedge then
      Continue;
    for D := 0 to High(Displays) do
    begin
      if not OnDisplay(Displays[D], TopY, W.Left, W.Right) then
        Continue;
      { Only the menu bar itself is off limits. A maximised window's top
        sits on Work.Top, flush with that bar, so a bug standing there
        would be wearing the clock as a hat. Leave a body-height of air. }
      if TopY > Displays[D].Work.Top + 1 then
        Continue;
      if Displays[D].Work.Top - TopY < 28 then
        Continue;
      if TopY < Displays[D].Work.Bottom + 8 then
        Continue;
      A := Max(W.Left, Displays[D].Frame.Left);
      B := Min(W.Right, Displays[D].Frame.Right);
      SetLength(Segs, 0);
      PushSeg(Segs, A, B);
      for J := 0 to I - 1 do
      begin
        if CoversY(Windows[J], TopY) then
          Segs := SubtractSegs(Segs, Windows[J].Left, Windows[J].Right);
      end;
      for S := 0 to High(Segs) do
        AddLedge(Ledges, lkWindow, True, Segs[S].A, Segs[S].B, TopY, TopY);
    end;
  end;
end;

end.
