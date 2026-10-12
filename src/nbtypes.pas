unit nbtypes;

{
  Shared shapes for the parade. Every host — Cocoa, Win32, X11 —
  speaks in this coordinate system:

    X grows to the right.
    Y grows up.
    The origin is the bottom-left of the primary display.

  macOS window-server rectangles do not. They arrive with Y growing
  down from the top-left of that same display. The host flips them
  once, at the door, and the rest of the program never hears about it.
}

{$mode objfpc}{$H+}

interface

type
  TSpecies = (spAnt, spLadybug, spBeetle, spCaterpillar);
  TBugState = (stWalk, stPause, stFall, stExit);
  TLedgeKind = (lkWindow, lkDock, lkFloor, lkWall);
  TDockEdge = (deNone, deBottom, deLeft, deRight);
  TLipAction = (laTurn, laFall, laHop, laExit);

  TPixel = record
    R, G, B, A: Byte;
  end;

  TBox = record
    Left, Bottom, Right, Top: Double;
  end;

  TLedge = record
    Kind: TLedgeKind;
    Horizontal: Boolean;
    X1, X2, Y1, Y2: Double;
  end;

  TDisplay = record
    Frame: TBox;
    Work: TBox;
    DockEdge: TDockEdge;
    HasDock: Boolean;
    DockBox: TBox;
  end;

  TBug = record
    X, Y: Double;
    VX, VY: Double;
    Dir: Integer;
    Species: TSpecies;
    Frame: Integer;
    Phase: Double;
    State: TBugState;
    PauseLeft: Double;
    Horizontal: Boolean;
    FeetOnLeft: Boolean;
    Alive: Boolean;
  end;

  TLedgeList = array of TLedge;

function Pix(R, G, B, A: Byte): TPixel;
function BoxWidth(const B: TBox): Double;
function BoxHeight(const B: TBox): Double;
function SpeciesName(S: TSpecies): string;

var
  Verbose: Boolean;

implementation

function Pix(R, G, B, A: Byte): TPixel;
begin
  Result.R := R;
  Result.G := G;
  Result.B := B;
  Result.A := A;
end;

function BoxWidth(const B: TBox): Double;
begin
  Result := B.Right - B.Left;
end;

function BoxHeight(const B: TBox): Double;
begin
  Result := B.Top - B.Bottom;
end;

function SpeciesName(S: TSpecies): string;
begin
  case S of
    spAnt: Result := 'ant';
    spLadybug: Result := 'ladybug';
    spBeetle: Result := 'beetle';
    spCaterpillar: Result := 'caterpillar';
  else
    Result := 'bug';
  end;
end;

end.
