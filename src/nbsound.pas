unit nbsound;

{
  There is a story people half-remember from System 7.

  On System 7.5, if you typed "secret about box" into SimpleText and
  dragged those three words onto the desktop, a window appeared: a flag
  over the Cupertino campus, an iguana in the credits, and — if you
  waited — the team, with the names scrolling by. The original Macintosh
  cases had been signed on the inside of the mold. The machine was
  introducing its authors.

  It did not, at any point, say "No bugs!" That line is ours. The mood
  is theirs: a small proud denial. The delivery is a different old Mac
  trick. SoundMaster, Bruce Tomlin's sound desk, would play a sample
  at whatever hertz you typed into the header. A voice that had been
  recorded for a low rate, played back at a higher one, came out fast
  and squeaky, like a cartoon that had been wound too tight. We do
  that on purpose. An American woman shouts the line. The samples
  are left alone, and so is her pitch. Only the rate in the header
  is a lie: 11025 Hz, played at 22050.
}

{$mode objfpc}{$H+}

interface

uses
  SysUtils;

const
  AboutBlurb =
    'No Bugs is a small parade on the glass. Ants, ladybirds, beetles and caterpillars ' +
    'treat the tops of your windows, and the Dock, as a pavement. Now and then one of them ' +
    'walks off the screen, because the bezel was only ever a suggestion.' + LineEnding + LineEnding +
    'The voice is a private joke with System 7.5. Typing "secret about box" into SimpleText ' +
    'and dragging it onto the desktop opened a window: a flag over Cupertino, and if you waited, ' +
    'the team, names scrolling. The original Macintosh cases were signed inside the mold. ' +
    'Nobody recorded a sound that said "No bugs!" The freshly installed system was simply ' +
    'pleased with itself. This one says the quiet part out loud: an American woman ' +
    'shouting "No bugs!", recorded at 11025 Hz and played at 22050. Same pitches, ' +
    'one octave up, because the header is the only thing that changed — while the ' +
    'evidence strolls along the title bars.';
  { The utterance is rendered at this rate. Playback claims twice that. }
  VoiceRecordHz = 11025;

function PickPhrase: string;
{ Two blows, not a sentence. "No bugs!" goes in as "No! Bugs!". }
function ShoutedLine(const Line: string): string;
{ The same cheer, with Apple's "speak slower" mark. Only `say` understands it. }
function SayCheer(const Line: string): string;
function PickSillyVoice(const Ids: array of string): string;
function VoiceShort(const Id: string): string;
function MakeChimeWav: TBytes;
function WriteWavFile(const Path: string; const Bytes: TBytes): Boolean;
function ReadWavFile(const Path: string; out Bytes: TBytes): Boolean;
{ Same samples. The header's sample rate is multiplied by TimesFaster.
  Pitch and speed both go up, because nothing was resampled. }
function SoundMasterWav(const Src: TBytes; TimesFaster: Double): TBytes;
{ Cut the dying tail, lift the second blow, and say it loud.
  Playback is still the SoundMaster lie; this only fixes the performance. }
function CheerWav(const Src: TBytes): TBytes;
function WavPlaybackSeconds(const Wav: TBytes): Double;

implementation

uses
  Math, Classes;

function PickPhrase: string;
begin
  { One line. The Mac speaks it, and the stored wave is the same line. }
  Result := 'No bugs!';
end;

function ShoutedLine(const Line: string): string;
begin
  { Two blows, not a sentence. The exclamation mark is the gap a cheer
    needs, so "bugs" does not get swallowed by "no". The words stay
    "No bugs!" — nothing else is added. }
  if Line = 'No bugs!' then
    Result := 'No! Bugs!'
  else
    Result := Line;
end;

function SayCheer(const Line: string): string;
begin
  { Kathy already talks like SimpleText did in 1995. Do not slow her
    down and do not retune her. "No! Bugs!" is two blows. The octave
    is only the 11025-to-22050 header. }
  Result := ShoutedLine(Line);
end;

function PickSillyVoice(const Ids: array of string): string;
const
  { Kathy is the American woman from MacinTalk, the voice SimpleText
    used when System 7.5 talked. Samantha is the same idea, newer,
    if Kathy is not installed. Her pitch stays hers. }
  Want: array[0..1] of string = (
    'kathy', 'samantha'
  );
var
  I, J: Integer;
begin
  for I := 0 to High(Want) do
    for J := 0 to High(Ids) do
      if Pos(Want[I], LowerCase(Ids[J])) > 0 then
        Exit(Ids[J]);
  Result := '';
end;

function VoiceShort(const Id: string): string;
var
  P: Integer;
begin
  P := Length(Id);
  while (P > 0) and (Id[P] <> '.') do
    Dec(P);
  Result := Copy(Id, P + 1, MaxInt);
  if Result = '' then
    Result := Id;
end;

procedure WriteLE16(var B: TBytes; At: Integer; V: Word);
begin
  B[At] := Byte(V and $FF);
  B[At + 1] := Byte((V shr 8) and $FF);
end;

procedure WriteLE32(var B: TBytes; At: Integer; V: Cardinal);
begin
  B[At] := Byte(V and $FF);
  B[At + 1] := Byte((V shr 8) and $FF);
  B[At + 2] := Byte((V shr 16) and $FF);
  B[At + 3] := Byte((V shr 24) and $FF);
end;

function MakeChimeWav: TBytes;
const
  Rate = 22050;
  NoteHz: array[0..2] of Double = (523.25, 659.25, 783.99);
var
  Samples, I, N, Total, DataBytes, K: Integer;
  Env, Wave, Mixed: Double;
  S: SmallInt;
begin
  { Three mallet notes, C-E-G, the noise a proud little Mac might make
    before it clears its throat. Short on purpose. }
  Samples := (Rate * 110) div 1000;
  Total := 3 * Samples + 2 * (Rate * 30) div 1000;
  DataBytes := Total * 2;
  Result := nil;
  SetLength(Result, 44 + DataBytes);
  Result[0] := Ord('R');
  Result[1] := Ord('I');
  Result[2] := Ord('F');
  Result[3] := Ord('F');
  WriteLE32(Result, 4, Cardinal(36 + DataBytes));
  Result[8] := Ord('W');
  Result[9] := Ord('A');
  Result[10] := Ord('V');
  Result[11] := Ord('E');
  Result[12] := Ord('f');
  Result[13] := Ord('m');
  Result[14] := Ord('t');
  Result[15] := Ord(' ');
  WriteLE32(Result, 16, 16);
  WriteLE16(Result, 20, 1);
  WriteLE16(Result, 22, 1);
  WriteLE32(Result, 24, Rate);
  WriteLE32(Result, 28, Rate * 2);
  WriteLE16(Result, 32, 2);
  WriteLE16(Result, 34, 16);
  Result[36] := Ord('d');
  Result[37] := Ord('a');
  Result[38] := Ord('t');
  Result[39] := Ord('a');
  WriteLE32(Result, 40, Cardinal(DataBytes));

  I := 0;
  for N := 0 to 2 do
  begin
    for K := 0 to Samples - 1 do
    begin
      Env := Exp(-6.5 * (K / Samples));
      Wave := Sin(2 * Pi * NoteHz[N] * (K / Rate));
      Wave := Wave + 0.18 * Sin(4 * Pi * NoteHz[N] * (K / Rate));
      if K < 80 then
        Wave := Wave + (Random - 0.5) * (1 - K / 80) * 0.35;
      Mixed := Wave * Env * 0.55;
      if Mixed > 1 then
        Mixed := 1;
      if Mixed < -1 then
        Mixed := -1;
      S := Round(Mixed * 32000);
      Result[44 + I * 2] := Byte(Word(S) and $FF);
      Result[44 + I * 2 + 1] := Byte((Word(S) shr 8) and $FF);
      Inc(I);
    end;
    if N < 2 then
      Inc(I, (Rate * 30) div 1000);
  end;
end;

function WriteWavFile(const Path: string; const Bytes: TBytes): Boolean;
var
  F: TFileStream;
begin
  Result := False;
  if Length(Bytes) = 0 then
    Exit;
  try
    F := TFileStream.Create(Path, fmCreate);
    try
      F.WriteBuffer(Bytes[0], Length(Bytes));
      Result := True;
    finally
      F.Free;
    end;
  except
    Result := False;
  end;
end;

function ReadWavFile(const Path: string; out Bytes: TBytes): Boolean;
var
  F: TFileStream;
begin
  Result := False;
  Bytes := nil;
  if not FileExists(Path) then
    Exit;
  try
    F := TFileStream.Create(Path, fmOpenRead or fmShareDenyNone);
    try
      SetLength(Bytes, F.Size);
      if Length(Bytes) > 0 then
        F.ReadBuffer(Bytes[0], Length(Bytes));
      Result := Length(Bytes) > 44;
    finally
      F.Free;
    end;
  except
    Bytes := nil;
    Result := False;
  end;
end;

function ReadLE16(const B: TBytes; At: Integer): Word;
begin
  Result := Word(B[At]) or (Word(B[At + 1]) shl 8);
end;

function ReadLE32(const B: TBytes; At: Integer): Cardinal;
begin
  Result := Cardinal(B[At]) or (Cardinal(B[At + 1]) shl 8) or
    (Cardinal(B[At + 2]) shl 16) or (Cardinal(B[At + 3]) shl 24);
end;

function FourCC(const B: TBytes; At: Integer; const Name: string): Boolean;
begin
  Result := (At >= 0) and (At + 4 <= Length(B)) and
    (B[At] = Ord(Name[1])) and (B[At + 1] = Ord(Name[2])) and
    (B[At + 2] = Ord(Name[3])) and (B[At + 3] = Ord(Name[4]));
end;

function SoundMasterWav(const Src: TBytes; TimesFaster: Double): TBytes;
var
  P, FmtAt, Size: Integer;
  Channels, Bits: Word;
  Rate, Block: Cardinal;
begin
  { SoundMaster did not resample. It changed the number in the sound
    header and let the hardware play the bits faster. A sound that
    required 11 kHz, played at 22, jumped an octave and finished in
    half the time. That is the whole cartoon. }
  Result := nil;
  SetLength(Result, Length(Src));
  if Length(Src) = 0 then
    Exit;
  Move(Src[0], Result[0], Length(Src));
  if TimesFaster < 1.01 then
    Exit;
  if not FourCC(Result, 0, 'RIFF') or not FourCC(Result, 8, 'WAVE') then
    Exit;
  P := 12;
  FmtAt := -1;
  while P + 8 <= Length(Result) do
  begin
    Size := Integer(ReadLE32(Result, P + 4));
    if (Size < 0) or (P + 8 + Size > Length(Result)) then
      Break;
    if FourCC(Result, P, 'fmt ') then
      FmtAt := P;
    P := P + 8 + Size;
    if Odd(Size) then
      Inc(P);
  end;
  if (FmtAt < 0) or (FmtAt + 24 > Length(Result)) then
    Exit;
  if ReadLE16(Result, FmtAt + 8) <> 1 then
    Exit;
  Channels := ReadLE16(Result, FmtAt + 10);
  Rate := ReadLE32(Result, FmtAt + 12);
  Bits := ReadLE16(Result, FmtAt + 22);
  if (Channels = 0) or (Rate = 0) or (Bits < 8) then
    Exit;
  Rate := Cardinal(Round(Rate * TimesFaster));
  if Rate < 1 then
    Rate := 1;
  Block := Cardinal(Channels) * Cardinal(Bits div 8);
  if Block = 0 then
    Exit;
  WriteLE32(Result, FmtAt + 12, Rate);
  WriteLE32(Result, FmtAt + 16, Rate * Block);
end;

function WavPlaybackSeconds(const Wav: TBytes): Double;
var
  P, FmtAt, DataAt, Size: Integer;
  Rate, ByteRate: Cardinal;
  DataBytes: Integer;
begin
  Result := 0.6;
  if not FourCC(Wav, 0, 'RIFF') or not FourCC(Wav, 8, 'WAVE') then
    Exit;
  P := 12;
  FmtAt := -1;
  DataAt := -1;
  DataBytes := 0;
  while P + 8 <= Length(Wav) do
  begin
    Size := Integer(ReadLE32(Wav, P + 4));
    if (Size < 0) or (P + 8 + Size > Length(Wav)) then
      Break;
    if FourCC(Wav, P, 'fmt ') then
      FmtAt := P;
    if FourCC(Wav, P, 'data') then
    begin
      DataAt := P;
      DataBytes := Size;
    end;
    P := P + 8 + Size;
    if Odd(Size) then
      Inc(P);
  end;
  if (FmtAt < 0) or (DataAt < 0) or (FmtAt + 20 > Length(Wav)) then
    Exit;
  Rate := ReadLE32(Wav, FmtAt + 12);
  ByteRate := ReadLE32(Wav, FmtAt + 16);
  if ByteRate = 0 then
    Exit;
  if Rate = 0 then
    Exit;
  Result := DataBytes / ByteRate;
  if Result < 0.15 then
    Result := 0.15;
  if Result > 8 then
    Result := 8;
end;

type
  TSamples = array of SmallInt;
  TSpan = record
    A, B: Integer;
  end;

function LoadMono16(const Src: TBytes; out Rate: Integer; out Pcm: TSamples): Boolean;
var
  P, FmtAt, DataAt, Size, I, N: Integer;
  Channels, Bits: Word;
begin
  Result := False;
  Rate := 0;
  Pcm := nil;
  if not FourCC(Src, 0, 'RIFF') or not FourCC(Src, 8, 'WAVE') then
    Exit;
  P := 12;
  FmtAt := -1;
  DataAt := -1;
  N := 0;
  while P + 8 <= Length(Src) do
  begin
    Size := Integer(ReadLE32(Src, P + 4));
    if (Size < 0) or (P + 8 + Size > Length(Src)) then
      Break;
    if FourCC(Src, P, 'fmt ') then
      FmtAt := P;
    if FourCC(Src, P, 'data') then
    begin
      DataAt := P + 8;
      N := Size div 2;
    end;
    P := P + 8 + Size;
    if Odd(Size) then
      Inc(P);
  end;
  if (FmtAt < 0) or (DataAt < 0) or (N < 1) or (FmtAt + 24 > Length(Src)) then
    Exit;
  if ReadLE16(Src, FmtAt + 8) <> 1 then
    Exit;
  Channels := ReadLE16(Src, FmtAt + 10);
  Bits := ReadLE16(Src, FmtAt + 22);
  Rate := Integer(ReadLE32(Src, FmtAt + 12));
  if (Channels <> 1) or (Bits <> 16) or (Rate < 1000) then
    Exit;
  if DataAt + N * 2 > Length(Src) then
    Exit;
  SetLength(Pcm, N);
  for I := 0 to N - 1 do
    Pcm[I] := SmallInt(ReadLE16(Src, DataAt + I * 2));
  Result := True;
end;

function BuildMono16(Rate: Integer; const Pcm: TSamples): TBytes;
var
  DataBytes, I: Integer;
  V: SmallInt;
begin
  DataBytes := Length(Pcm) * 2;
  Result := nil;
  SetLength(Result, 44 + DataBytes);
  Result[0] := Ord('R');
  Result[1] := Ord('I');
  Result[2] := Ord('F');
  Result[3] := Ord('F');
  WriteLE32(Result, 4, Cardinal(36 + DataBytes));
  Result[8] := Ord('W');
  Result[9] := Ord('A');
  Result[10] := Ord('V');
  Result[11] := Ord('E');
  Result[12] := Ord('f');
  Result[13] := Ord('m');
  Result[14] := Ord('t');
  Result[15] := Ord(' ');
  WriteLE32(Result, 16, 16);
  WriteLE16(Result, 20, 1);
  WriteLE16(Result, 22, 1);
  WriteLE32(Result, 24, Cardinal(Rate));
  WriteLE32(Result, 28, Cardinal(Rate) * 2);
  WriteLE16(Result, 32, 2);
  WriteLE16(Result, 34, 16);
  Result[36] := Ord('d');
  Result[37] := Ord('a');
  Result[38] := Ord('t');
  Result[39] := Ord('a');
  WriteLE32(Result, 40, Cardinal(DataBytes));
  for I := 0 to High(Pcm) do
  begin
    V := Pcm[I];
    Result[44 + I * 2] := Byte(Word(V) and $FF);
    Result[44 + I * 2 + 1] := Byte((Word(V) shr 8) and $FF);
  end;
end;

function LevelAt(const Pcm: TSamples; At, Win: Integer): Double;
var
  I, N: Integer;
  Acc: Double;
begin
  Result := 0;
  if (Win < 1) or (At >= Length(Pcm)) then
    Exit;
  N := Win;
  if At + N > Length(Pcm) then
    N := Length(Pcm) - At;
  if N < 1 then
    Exit;
  Acc := 0;
  for I := 0 to N - 1 do
    Acc := Acc + Sqr(Pcm[At + I] / 32767);
  Result := Sqrt(Acc / N);
end;

function TrimWhimper(const Pcm: TSamples; Rate, S, E: Integer): TSamples;
var
  FromS, Keep, Win, Hop, I, PeakAt, Under, Fade, N: Integer;
  Peak, Level: Double;
begin
  Result := nil;
  FromS := S - (Rate div 50);
  if FromS < 0 then
    FromS := 0;
  if E > Length(Pcm) then
    E := Length(Pcm);
  if E - FromS < Rate div 20 then
    E := FromS + (Rate div 12);
  if E > Length(Pcm) then
    E := Length(Pcm);
  Win := Rate div 80;
  if Win < 8 then
    Win := 8;
  Hop := Win div 2;
  Peak := 0;
  PeakAt := 0;
  I := FromS;
  while I < E do
  begin
    Level := LevelAt(Pcm, I, Win);
    if Level > Peak then
    begin
      Peak := Level;
      PeakAt := I;
    end;
    Inc(I, Hop);
  end;
  Keep := E;
  Under := 0;
  I := PeakAt;
  while I < E do
  begin
    Level := LevelAt(Pcm, I, Win);
    if Level < Peak * 0.48 then
    begin
      Inc(Under, Hop);
      if Under >= Rate div 25 then
      begin
        Keep := I;
        Break;
      end;
    end
    else
      Under := 0;
    Inc(I, Hop);
  end;
  if Keep - FromS < (Rate * 18) div 100 then
    Keep := FromS + (Rate * 18) div 100;
  if Keep > E then
    Keep := E;
  if Keep > Length(Pcm) then
    Keep := Length(Pcm);
  N := Keep - FromS;
  if N < 1 then
    Exit;
  SetLength(Result, N);
  Move(Pcm[FromS], Result[0], N * SizeOf(SmallInt));
  Fade := (Rate * 12) div 1000;
  if Fade > N div 3 then
    Fade := N div 3;
  for I := 0 to Fade - 1 do
    Result[N - 1 - I] := SmallInt(Round(Result[N - 1 - I] * ((Fade - I) / (Fade + 1))));
end;

function CheerWav(const Src: TBytes): TBytes;
var
  Rate, Win, Hop, I, Gap, N, Base: Integer;
  Pcm, Blow, Joined: TSamples;
  Spans: array of TSpan;
  On: Boolean;
  Start, PeakSamp: Integer;
  Peak, Level, Scale, Shape, Y: Double;
begin
  Result := Src;
  if not LoadMono16(Src, Rate, Pcm) then
    Exit;
  if Length(Pcm) < Rate div 5 then
    Exit;
  Win := (Rate * 12) div 1000;
  if Win < 8 then
    Win := 8;
  Hop := Win div 2;
  Peak := 0;
  I := 0;
  while I < Length(Pcm) - Win do
  begin
    Level := LevelAt(Pcm, I, Win);
    if Level > Peak then
      Peak := Level;
    Inc(I, Hop);
  end;
  if Peak < 0.01 then
    Exit;
  SetLength(Spans, 0);
  On := False;
  Start := 0;
  I := 0;
  while I < Length(Pcm) - Win do
  begin
    Level := LevelAt(Pcm, I, Win);
    if (Level >= Peak * 0.12) and not On then
    begin
      On := True;
      Start := I;
    end
    else if (Level < Peak * 0.12) and On then
    begin
      On := False;
      if I - Start > Rate div 16 then
      begin
        SetLength(Spans, Length(Spans) + 1);
        Spans[High(Spans)].A := Start;
        Spans[High(Spans)].B := I;
      end;
    end;
    Inc(I, Hop);
  end;
  if On and (Length(Pcm) - Start > Rate div 16) then
  begin
    SetLength(Spans, Length(Spans) + 1);
    Spans[High(Spans)].A := Start;
    Spans[High(Spans)].B := Length(Pcm);
  end;
  { Glue the little gaps inside one word. Leave the cheer's own pause. }
  I := 1;
  while I < Length(Spans) do
  begin
    if Spans[I].A - Spans[I - 1].B < (Rate * 11) div 100 then
    begin
      Spans[I - 1].B := Spans[I].B;
      for N := I to High(Spans) - 1 do
        Spans[N] := Spans[N + 1];
      SetLength(Spans, Length(Spans) - 1);
    end
    else
      Inc(I);
  end;
  if Length(Spans) = 0 then
    Exit;
  Joined := nil;
  Gap := (Rate * 45) div 1000;
  for I := 0 to High(Spans) do
  begin
    { Her pitches, not a second tuning. The octave is the header's job. }
    Blow := TrimWhimper(Pcm, Rate, Spans[I].A, Spans[I].B);
    if Length(Blow) = 0 then
      Continue;
    if Length(Joined) > 0 then
    begin
      Base := Length(Joined);
      SetLength(Joined, Base + Gap);
      for N := 0 to Gap - 1 do
        Joined[Base + N] := 0;
    end;
    Base := Length(Joined);
    SetLength(Joined, Base + Length(Blow));
    Move(Blow[0], Joined[Base], Length(Blow) * SizeOf(SmallInt));
  end;
  if Length(Joined) < Rate div 12 then
    Exit;
  PeakSamp := 1;
  for I := 0 to High(Joined) do
    if Abs(Joined[I]) > PeakSamp then
      PeakSamp := Abs(Joined[I]);
  Scale := 30000 / PeakSamp;
  Shape := Tanh(1.35);
  for I := 0 to High(Joined) do
  begin
    Y := Tanh(1.35 * (Joined[I] * Scale / 32767)) / Shape;
    Y := Y * 31000;
    if Y > 32767 then
      Y := 32767;
    if Y < -32767 then
      Y := -32767;
    Joined[I] := SmallInt(Round(Y));
  end;
  Result := BuildMono16(Rate, Joined);
end;

end.
