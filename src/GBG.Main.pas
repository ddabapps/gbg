unit GBG.Main;

interface

uses
  System.SysUtils,
  System.Classes,
  GBG.Types,
  GBG.Params;

type

  TExitCode = record
  public
    const
      None = 0;
      Execuction = 1;
      Usage = 2;
      Cancellation = 3;
      FileExists = 4;
      LargeFile = 5;
      Unknown = 9;
  end;

  TBufferCallback = reference to procedure (const BytesRemaining: UInt64;
    out Buffer: TBytes);

  TMain = class
  strict private
    const
      MaxUnchallengedFileSize = 500 * TMemUnits.OneMB;      // 500,000,000 bytes
      {$IFDEF Win64}
      MaxSupportedFileSize = 20 * TMemUnits.OneGiB;      // 21,474,836,480 bytes
      {$ELSE}
      MaxSupportedFileSize = 1 * TMemUnits.OneGiB;        // 1,073,741,824 bytes
      {$ENDIF}
    class var
      fParams: TParams;
    class function GetConfirmation(const Question: string;
      const TrueResponse: Char): Boolean;
    class procedure CheckUserPermissions;
    class procedure HandleProgramException(const E: Exception);
    class procedure HandleExecutionException(const E: Exception);
    class function FreeSpaceOnFileDrive: UInt64;
    class procedure Usage;
    class procedure Version;
    class procedure Initialise;
    class procedure Execute;
  public
    class procedure Run;
    class destructor Destroy;
  end;

implementation

uses
  System.IOUtils,
  System.Math,
  System.Character,
  GBG.AppInfo,
  GBG.DataWriter,
  GBG.Exceptions,
  GBG.Generator.Base,
  GBG.NumberFmt;

{ TMain }

class procedure TMain.CheckUserPermissions;
begin
  if fParams.FileSize > MaxUnchallengedFileSize  then
  begin
    case fParams.LargeFileAction of
      TLargeFileAction.Prompt:
        if not GetConfirmation(
          Format(
            'Requested size is greater than %s bytes. Continue? [y/N]',
            [TNumberFmt.Create(MaxUnchallengedFileSize).ToString]
          ),
          'Y'
        ) then
          raise ECancellation.Create('Operation cancelled');
      TLargeFileAction.Error:
        raise EFileTooBig.CreateFmt(
          'Output file is greater than %s bytes. Use -L option to allow.',
          [TNumberFmt.Create(MaxUnchallengedFileSize).ToString]
        );
      TLargeFileAction.Allow:
        ; // do nothing - allow large file to be createed
    end;
  end;
  if TFile.Exists(fParams.FileName) then
  begin
    case fParams.ExistingFileAction of
      TExistingFileAction.Prompt:
        if not GetConfirmation(
          'Output file already exists. Overwrite? [y/N]', 'Y'
        ) then
          raise ECancellation.Create('Operation cancelled');
      TExistingFileAction.Error:
        raise EFileExists.Create(
          'Output file already exists. Use -O option to overwrite.'
        );
      TExistingFileAction.Overwrite:
        ; // do nothing - permit file to be overwritten
    end;
  end;
end;

class destructor TMain.Destroy;
begin
  fParams.Free;
end;

class procedure TMain.Execute;
begin
  try
    // Create output file
    var FS := TFileStream.Create(fParams.FileName, fmCreate);
    try
      if fParams.FileSize = 0 then
        Exit;   // file size is 0 => close empty file
      // Create generator of required type
      var Generator := TGeneratorFactory.CreateInstance(fParams.GeneratorType);
      try
        // Create data writer that output the random data
        var Writer := TDataWriter.Create(FS, Generator);
        try
          if fParams.RandomDataChunkSize > 0 then
            // We want 1 or more chunks of the same random data
            Writer.WriteDuplicatedChunks(
              fParams.FileSize, fParams.RandomDataChunkSize
            )
          else
            // We want all data in the file to be random
            Writer.WriteUniqueData(
              fParams.FileSize, fParams.DefRandomDataChunkSize
            );
        finally
          Writer.Free;
        end;
      finally
        Generator.Free;
      end;
    finally
      FS.Free;
    end;
  except
    on E: Exception do
      HandleExecutionException(E);
  end;
end;

class function TMain.FreeSpaceOnFileDrive: UInt64;
begin
  var FreeAvailable, Total, FreeTotal: Int64;
  var Drive := TDirectory.GetDirectoryRoot(fParams.FileName);
  if not GetDiskFreeSpaceEx(PChar(Drive), FreeAvailable, Total, @FreeTotal) then
    raise EExecutionError.Create('Drive ' + Drive + ' not found');
  Result := UInt64(FreeAvailable)
end;

class function TMain.GetConfirmation(const Question: string;
  const TrueResponse: Char): Boolean;
begin
  Write(Question);
  var Response: Char;
  Readln(Response);
  Result := Response.ToUpper = TrueResponse;
end;

class procedure TMain.HandleExecutionException(const E: Exception);
begin
  try
    if TFile.Exists(fParams.FileName) then
      TFile.Delete(fParams.FileName);
  except
    // swallow exception: not relevant to main program operation
  end;

  ExitCode := 1;
  if E is EFCreateError then
    raise EExecutionError.Create('Can''t create file')
  else if E is EWriteError then
    raise EExecutionError.Create('Failure while writing file')
  else
    raise E;
end;

class procedure TMain.HandleProgramException(const E: Exception);
begin
  ExitCode := TExitCode.None;;
  if E is EUsageError then
  begin
    Writeln('Usage Error: ' + E.Message);
    Writeln;
    Writeln('Enter gbg with no parameters for help');
    ExitCode := TExitCode.Usage;
  end
  else if E is ECancellation then
  begin
    Writeln(E.Message);
    ExitCode := TExitCode.Cancellation;
  end
  else if E is EExecutionError then
  begin
    Writeln('Error: ' + E.Message);
    ExitCode := TExitCode.Execuction;
  end
  else if E is EFileExists then
  begin
    Writeln('Error: ' + E.Message);
    ExitCode := TExitCode.FileExists;
  end
  else if E is EFileTooBig then
  begin
    Writeln('Error: ' + E.Message);
    ExitCode := TExitCode.LargeFile;
  end
  else if E is ESilent then
  begin
    Usage;
    ExitCode := TExitCode.None;
  end
  else
  begin
    // Unexpected exception: re-raise
    ExitCode := TExitCode.Unknown;
    raise E;
  end;
end;

class procedure TMain.Initialise;
begin

  CheckUserPermissions; // raises exceptions if user denies permissions

  if fParams.FileSize > FreeSpaceOnFileDrive then
    raise EExecutionError.Create(
      'Requested file size is larger than free space on drive '
      + TDirectory.GetDirectoryRoot(fParams.FileName)
    );
end;

class procedure TMain.Run;
begin
  try
    fParams := TParams.Create(MaxSupportedFileSize);
    if fParams.ShowVersion then
      Version
    else
    begin
      Initialise;
      Execute;
    end;
    ExitCode := TExitCode.None;
  except
    on E: Exception do
      HandleProgramException(E);
  end;
end;

class procedure TMain.Usage;
const
  HelpText = '''
  Usage:

    gbg <filename> <size> [<options>]
    gbg -V
    gbg

  Where:
    <filename> = Name of file to create.
    <size> = Size of file to create.
      * Maximum file size is %0:s bytes.
    <options> = zero or more of:
      -a -> Generate printable ASCII characters (code 32..126).
      -A -> Generate all ASCII characters (code 0..127).
      -l -> Stop with error if requested file size > 500Mb.
      -L -> Silently create file of any size, ignoring 500Mb limit.
      -o -> Stop with error if output file already exists.
      -O -> Silently overwrite any existing output file with same name.
      -r:<number> -> Set the number of bytes of random data written before the
         data repeats.
         * Maximum value is %1:s bytes.
         * Default value is %2:s bytes.
      -r:all -> Random data does not repeat.

    -V -> Display version information and halt.

    no parameters ->   Display this information and halt.

  A forward slash can be used instead of a dash in options.

  A number of bytes is specified as a decimal number, with or without thousands
  separators. The number can be expressed in Kb, KiB, MB, MiB, GB or GiB by
  appending the appropriate symbol to the end of the number.
  ''';
begin
  Writeln(
    Format(
      HelpText,
      [
        TNumberFmt.Create(MaxSupportedFileSize).ToString,
        TNumberFmt.Create(TParams.MaxRandomDataChunkSize).ToString,
        TNumberFmt.Create(TParams.DefRandomDataChunkSize).ToString
      ]
    )
  );
//  Writeln('Usage:');
//  Writeln;
//  Writeln('  gbg filename size [options]');
//  Writeln('  gbg -V');
//  Writeln('  gbg');
//  Writeln;
//  Writeln('  Where:');
//  Writeln('    filename = name of file to create');
//  Writeln(
//    Format(
//      '    size = size of file to create (0..%s)',
//      [TNumberFmt.Create(MaxSupportedFileSize).ToString]
//    )
//  );
//  WriteLn('    options = zero or more of:');
//  WriteLn('      -a -> generate printable ASCII characters (code 32..126)');
//  WriteLn('      -A -> generate all ASCII characters (code 0..127)');
//  WriteLn('      -l -> stop with error if requested file size > 500Mb');
//  WriteLn('      -L -> silently create file of any size, ignoring 500Mb limit');
//  WriteLn('      -o -> stop with error if output file already exists');
//  WriteLn('      -O -> silently overwrite existing output file with same name');
//  WriteLn('      -r:<number> -> set the size random data written before the');
//  WriteLn('         data repeats (
//  WriteLn;
//  WriteLn('    -V = display version information and halt');
//  WriteLn;
//  WriteLn('    no parameters = display this information and halt');
//  WriteLn;
//  WriteLn('  Note: /x is equivalent to -x');
end;

class procedure TMain.Version;
begin
  WriteLn(
    Format('%s %s ', [TAppInfo.ProgramVersion, TAppInfo.ProgramExeDate])
  );
end;

end.

