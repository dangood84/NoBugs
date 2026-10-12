unit nbsim;

{
  A lemming walks because the level said the ground continued.
  These ones walk because a title bar is a kerb and the Dock is a
  promenade. When the kerb stops at the edge of the glass, some of
  them treat that as a reason to turn around. The rest remember
  their training and keep going.
}

{$mode objfpc}{$H+}

interface

uses
  nbtypes;

type
  TWorld = class
  public
    Bugs: array of TBug;
    Ledges: TLedgeList;
    Displays: array of TDisplay;
    Paused: Boolean;
    Time: Double;
    NextAnnounce: Double;
    Target: Integer;
    RespawnIn: Double;
    ForcedAnnounce: Boolean;
    constructor Create;
    procedure SetStage(const ADisplays: array of TDisplay; const ALedges: TLedgeList);
    procedure FillRoster;
    procedure Tick(Dt: Double);
    function ClaimAnnouncement: string;
    procedure ForceAnnouncement;
    function AliveCount: Integer;
  private
    function LowestBottom: Double;
    function FullyOff(const B: TBug): Boolean;
    function NearScreenEdge(const B: TBug): Boolean;
    function FindHorizontal(X, Y: Double; MaxDy: Double; out Index: Integer): Boolean;
    function FindWall(X, Y: Double; out Index: Integer): Boolean;
    function FindLip(const B: TBug; out Index: Integer): Boolean;
    procedure ApplyLip(var B: TBug; Action: TLipAction);
    procedure SpawnOne;
    procedure Land(var B: TBug; OldY: Double);
    procedure StepBug(var B: TBug; Dt: Double);
  end;

function ChooseLipAction(Kind: TLedgeKind; NearEdge: Boolean): TLipAction;
function SpeedOf(S: TSpecies): Double;

var
  Parade: TWorld;
  AllowLoaf: Boolean;

implementation

uses
  Math, nbsprites, nbsound;

constructor TWorld.Create;
begin
  inherited Create;
  Target := 9;
  NextAnnounce := 6.5;
  RespawnIn := 0;
  Paused := False;
end;

procedure TWorld.SetStage(const ADisplays: array of TDisplay; const ALedges: TLedgeList);
var
  I: Integer;
begin
  SetLength(Displays, Length(ADisplays));
  for I := 0 to High(ADisplays) do
    Displays[I] := ADisplays[I];
  SetLength(Ledges, Length(ALedges));
  for I := 0 to High(ALedges) do
    Ledges[I] := ALedges[I];
end;

function SpeedOf(S: TSpecies): Double;
begin
  case S of
    spAnt: Result := 54;
    spLadybug: Result := 38;
    spBeetle: Result := 30;
    spCaterpillar: Result := 22;
  else
    Result := 40;
  end;
end;

function ChooseLipAction(Kind: TLedgeKind; NearEdge: Boolean): TLipAction;
var
  R: Double;
begin
  R := Random;
  if NearEdge and (Kind in [lkDock, lkFloor, lkWall]) then
  begin
    if R < 0.74 then
      Exit(laExit)
    else
      Exit(laTurn);
  end;
  if NearEdge then
  begin
    if R < 0.58 then
      Exit(laExit)
    else if R < 0.78 then
      Exit(laTurn)
    else if R < 0.92 then
      Exit(laFall)
    else
      Exit(laHop);
  end;
  if R < 0.34 then
    Exit(laTurn)
  else if R < 0.62 then
    Exit(laFall)
  else if R < 0.84 then
    Exit(laHop)
  else
    Exit(laTurn);
end;

function TWorld.AliveCount: Integer;
var
  I: Integer;
begin
  Result := 0;
  for I := 0 to High(Bugs) do
    if Bugs[I].Alive then
      Inc(Result);
end;

function TWorld.LowestBottom: Double;
var
  I: Integer;
begin
  Result := 0;
  if Length(Displays) = 0 then
    Exit;
  Result := Displays[0].Frame.Bottom;
  for I := 1 to High(Displays) do
    if Displays[I].Frame.Bottom < Result then
      Result := Displays[I].Frame.Bottom;
end;

function TWorld.FullyOff(const B: TBug): Boolean;
var
  I: Integer;
  L, R, Bot, Top: Double;
  D: TDisplay;
begin
  Result := True;
  L := B.X - BugHalfWidth;
  R := B.X + BugHalfWidth;
  Bot := B.Y - 8;
  Top := B.Y + 32;
  for I := 0 to High(Displays) do
  begin
    D := Displays[I];
    if (R > D.Frame.Left) and (L < D.Frame.Right) and
      (Top > D.Frame.Bottom) and (Bot < D.Frame.Top) then
      Exit(False);
  end;
end;

function TWorld.NearScreenEdge(const B: TBug): Boolean;
var
  I: Integer;
begin
  Result := False;
  for I := 0 to High(Displays) do
  begin
    if (B.Dir < 0) and (Abs(B.X - Displays[I].Frame.Left) < 36) then
      Exit(True);
    if (B.Dir > 0) and (Abs(B.X - Displays[I].Frame.Right) < 36) then
      Exit(True);
    if not B.Horizontal then
    begin
      if (B.Dir > 0) and (Abs(B.Y - Displays[I].Frame.Top) < 36) then
        Exit(True);
      if (B.Dir < 0) and (Abs(B.Y - Displays[I].Frame.Bottom) < 36) then
        Exit(True);
    end;
  end;
end;

function TWorld.FindHorizontal(X, Y: Double; MaxDy: Double; out Index: Integer): Boolean;
var
  I: Integer;
  Best, Dy: Double;
  L: TLedge;
begin
  Result := False;
  Index := -1;
  Best := MaxDy;
  for I := 0 to High(Ledges) do
  begin
    L := Ledges[I];
    if not L.Horizontal then
      Continue;
    if (X < L.X1 - 2) or (X > L.X2 + 2) then
      Continue;
    Dy := Abs(Y - L.Y1);
    if Dy < Best then
    begin
      Best := Dy;
      Index := I;
      Result := True;
    end;
  end;
end;

function TWorld.FindWall(X, Y: Double; out Index: Integer): Boolean;
var
  I: Integer;
  L: TLedge;
  Best, Dx: Double;
begin
  Result := False;
  Index := -1;
  Best := 10;
  for I := 0 to High(Ledges) do
  begin
    L := Ledges[I];
    if L.Horizontal then
      Continue;
    if (Y < L.Y1 - 2) or (Y > L.Y2 + 2) then
      Continue;
    Dx := Abs(X - L.X1);
    if Dx < Best then
    begin
      Best := Dx;
      Index := I;
      Result := True;
    end;
  end;
end;

function TWorld.FindLip(const B: TBug; out Index: Integer): Boolean;
var
  I: Integer;
  L: TLedge;
  Best, D: Double;
begin
  Result := False;
  Index := -1;
  Best := 16;
  for I := 0 to High(Ledges) do
  begin
    L := Ledges[I];
    if B.Horizontal and L.Horizontal then
    begin
      if Abs(B.Y - L.Y1) > 22 then
        Continue;
      if B.Dir > 0 then
        D := Abs(B.X - L.X2)
      else
        D := Abs(B.X - L.X1);
    end
    else if (not B.Horizontal) and (not L.Horizontal) then
    begin
      if Abs(B.X - L.X1) > 14 then
        Continue;
      if B.Dir > 0 then
        D := Abs(B.Y - L.Y2)
      else
        D := Abs(B.Y - L.Y1);
    end
    else
      Continue;
    if D < Best then
    begin
      Best := D;
      Index := I;
      Result := True;
    end;
  end;
end;

procedure TWorld.ApplyLip(var B: TBug; Action: TLipAction);
begin
  case Action of
    laTurn:
      begin
        B.Dir := -B.Dir;
        if B.Horizontal then
          B.X := B.X + B.Dir * 5
        else
          B.Y := B.Y + B.Dir * 5;
        B.State := stWalk;
        B.VX := 0;
        B.VY := 0;
      end;
    laFall:
      begin
        B.State := stFall;
        B.VY := -30;
        B.VX := B.Dir * SpeedOf(B.Species) * 0.45;
        B.Horizontal := True;
      end;
    laHop:
      begin
        B.State := stFall;
        B.VY := 470;
        B.VX := B.Dir * SpeedOf(B.Species);
        B.Horizontal := True;
      end;
    laExit:
      begin
        { The glass ends. The walk does not. They leave still stepping,
          the way a lemming leaves a cliff that was drawn a tile short. }
        B.State := stExit;
        B.Horizontal := True;
        B.VX := 0;
        B.VY := 0;
      end;
  end;
end;

procedure TWorld.SpawnOne;
var
  L: TLedge;
  B: TBug;
  Span: Double;
begin
  if Length(Ledges) = 0 then
    Exit;
  FillChar(B, SizeOf(B), 0);
  L := Ledges[Random(Length(Ledges))];
  B.Species := TSpecies(Random(4));
  B.Dir := 1;
  if Random < 0.5 then
    B.Dir := -1;
  B.Frame := Random(4);
  B.Phase := Random * 4;
  B.State := stWalk;
  B.Alive := True;
  B.Horizontal := L.Horizontal;
  if L.Horizontal then
  begin
    Span := L.X2 - L.X1;
    if Span < 24 then
      B.X := (L.X1 + L.X2) / 2
    else if Random < 0.28 then
    begin
      if Random < 0.5 then
      begin
        B.X := L.X1 + 10;
        B.Dir := -1;
      end
      else
      begin
        B.X := L.X2 - 10;
        B.Dir := 1;
      end;
    end
    else
      B.X := L.X1 + 12 + Random * (Span - 24);
    B.Y := L.Y1;
    B.FeetOnLeft := True;
  end
  else
  begin
    Span := L.Y2 - L.Y1;
    B.X := L.X1;
    if Span < 24 then
      B.Y := (L.Y1 + L.Y2) / 2
    else
      B.Y := L.Y1 + 12 + Random * (Span - 24);
    B.FeetOnLeft := True;
    if Length(Displays) > 0 then
      B.FeetOnLeft := B.X < (Displays[0].Frame.Left + Displays[0].Frame.Right) / 2;
  end;
  SetLength(Bugs, Length(Bugs) + 1);
  Bugs[High(Bugs)] := B;
end;

procedure TWorld.FillRoster;
var
  Guard: Integer;
begin
  Guard := 0;
  while (AliveCount < Target) and (Guard < Target + 2) do
  begin
    SpawnOne;
    Inc(Guard);
  end;
end;

procedure TWorld.Land(var B: TBug; OldY: Double);
var
  I, Best: Integer;
  L: TLedge;
  BestY: Double;
begin
  if B.VY >= 0 then
    Exit;
  Best := -1;
  BestY := -1e9;
  for I := 0 to High(Ledges) do
  begin
    L := Ledges[I];
    if not L.Horizontal then
      Continue;
    if (B.X < L.X1) or (B.X > L.X2) then
      Continue;
    if (OldY + 1 >= L.Y1) and (B.Y <= L.Y1) and (L.Y1 >= BestY) then
    begin
      BestY := L.Y1;
      Best := I;
    end;
  end;
  if Best < 0 then
    Exit;
  B.Y := Ledges[Best].Y1;
  B.State := stWalk;
  B.Horizontal := True;
  B.VY := 0;
  if Abs(B.VX) > 8 then
  begin
    if B.VX < 0 then
      B.Dir := -1
    else
      B.Dir := 1;
  end;
  B.VX := 0;
end;

procedure TWorld.StepBug(var B: TBug; Dt: Double);
var
  Speed, OldY: Double;
  Index: Integer;
  Action: TLipAction;
begin
  if not B.Alive then
    Exit;
  Speed := SpeedOf(B.Species);
  if B.Species = spCaterpillar then
    Speed := Speed * (0.65 + 0.35 * Abs(Sin(B.Phase)));

  case B.State of
    stPause:
      begin
        B.PauseLeft := B.PauseLeft - Dt;
        if B.PauseLeft <= 0 then
          B.State := stWalk;
      end;
    stExit:
      begin
        B.X := B.X + B.Dir * Speed * Dt;
        B.Phase := B.Phase + Speed * Dt * 0.16;
        B.Frame := Trunc(B.Phase) mod 4;
        if FullyOff(B) then
          B.Alive := False;
      end;
    stFall:
      begin
        OldY := B.Y;
        B.VY := B.VY - 1500 * Dt;
        B.Y := B.Y + B.VY * Dt;
        B.X := B.X + B.VX * Dt;
        B.Phase := B.Phase + Dt * 8;
        B.Frame := Trunc(B.Phase) mod 4;
        Land(B, OldY);
        if B.Y < LowestBottom - 48 then
          B.Alive := False
        else if FullyOff(B) then
          B.Alive := False;
      end;
    stWalk:
      begin
        if AllowLoaf and (Random < 0.10 * Dt) then
        begin
          B.State := stPause;
          B.PauseLeft := 0.28 + Random * 0.85;
          Exit;
        end;
        if B.Horizontal then
          B.X := B.X + B.Dir * Speed * Dt
        else
          B.Y := B.Y + B.Dir * Speed * Dt;
        B.Phase := B.Phase + Speed * Dt * 0.16;
        B.Frame := Trunc(B.Phase) mod 4;
        if B.Horizontal then
        begin
          if FindHorizontal(B.X, B.Y, 42, Index) then
            B.Y := Ledges[Index].Y1
          else if FindLip(B, Index) then
          begin
            Action := ChooseLipAction(Ledges[Index].Kind, NearScreenEdge(B));
            ApplyLip(B, Action);
          end
          else
            ApplyLip(B, laFall);
        end
        else if FindWall(B.X, B.Y, Index) then
          B.X := Ledges[Index].X1
        else if FindLip(B, Index) then
        begin
          Action := ChooseLipAction(Ledges[Index].Kind, NearScreenEdge(B));
          ApplyLip(B, Action);
        end
        else
          ApplyLip(B, laFall);
      end;
  end;
end;

procedure TWorld.Tick(Dt: Double);
var
  I, N: Integer;
begin
  if Dt > 0.05 then
    Dt := 0.05;
  if Dt < 0 then
    Dt := 0;
  Time := Time + Dt;
  if Paused then
    Exit;
  for I := 0 to High(Bugs) do
    StepBug(Bugs[I], Dt);
  N := 0;
  for I := 0 to High(Bugs) do
    if Bugs[I].Alive then
    begin
      Bugs[N] := Bugs[I];
      Inc(N);
    end;
  SetLength(Bugs, N);
  if AliveCount < Target then
  begin
    RespawnIn := RespawnIn - Dt;
    if RespawnIn <= 0 then
    begin
      SpawnOne;
      RespawnIn := 0.45;
    end;
  end;
end;

function TWorld.ClaimAnnouncement: string;
begin
  Result := '';
  if Paused and not ForcedAnnounce then
    Exit;
  if not ForcedAnnounce and (Time < NextAnnounce) then
    Exit;
  Result := PickPhrase;
  ForcedAnnounce := False;
  NextAnnounce := Time + 38 + Random * 52;
end;

procedure TWorld.ForceAnnouncement;
begin
  ForcedAnnounce := True;
end;

initialization
  AllowLoaf := True;

end.
