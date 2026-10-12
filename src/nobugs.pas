program nobugs;

{
  No Bugs. A parade for the title bars.
  Build this with the Free Pascal compiler. Lazarus is not required,
  and not used: the Mac host talks to Cocoa directly, after src/launch.c
  has opened the door.
}

{$mode objfpc}{$H+}

uses
  SysUtils, nbtypes, nbtest, nbsprites
  {$IFDEF DARWIN}, hostmacos{$ENDIF}
  {$IFDEF MSWINDOWS}, hostwindows{$ENDIF}
  {$IFDEF LINUX}, hostlinux{$ENDIF}
  ;

var
  I: Integer;
  PreviewPath: string;
  WantTest, WantPreview: Boolean;

begin
  PreviewPath := 'bin/preview.bmp';
  for I := 1 to ParamCount do
  begin
    if ParamStr(I) = '--self-test' then
      WantTest := True
    else if ParamStr(I) = '--preview' then
      WantPreview := True
    else if ParamStr(I) = '--verbose' then
      Verbose := True
    else if (I > 1) and (ParamStr(I - 1) = '--preview') then
      PreviewPath := ParamStr(I);
  end;

  if WantTest then
  begin
    if not RunSelfTests then
      Halt(1);
    Halt(0);
  end;

  if WantPreview then
  begin
    SavePreview(PreviewPath);
    Writeln('preview: ', PreviewPath);
    Halt(0);
  end;

  {$IF defined(DARWIN) or defined(MSWINDOWS) or defined(LINUX)}
  RunHost;
  {$ELSE}
  Writeln('No Bugs has no host for this operating system.');
  Halt(1);
  {$ENDIF}
end.
