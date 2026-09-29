unit GBG.Params;

interface

uses
  GBG.Types;

type

  TParams = class
  strict private
    const
      OptionStartChars = ['-', '/'];
    var
      fFileName: string;
      fFileSize: UInt64;
      fGeneratorType: TGeneratorType;
      fExistingFileAction: TExistingFileAction;
      fLargeFileAction: TLargeFileAction;
      fShowVersion: Boolean;
      fIsFileSizeSet: Boolean;
      fMaxFileSize: UInt64;
      fRandomDataChunkSize: UInt64;
    function IsOption(const S: string): Boolean;
    procedure ParseCommandLine;
    procedure ParseRandomDataChunkSizeCommand(const ACmd: string);
  public
    const
      ///  <summary>Default random data chunk size.</summary>
      DefRandomDataChunkSize = 10 * TMemUnits.OneMiB;
      // Maximum random data chunk size
      // For 64 bit version, this is calculated as the maximum dynamic array
      // size according to answers to the Stack Overflow question at
      // https://tinyurl.com/mr3dehxb
      // For 32 bit version, this is limited to 1Gb.
      {$IFDEF Win64}
      MaxRandomDataChunkSize = MaxInt - 2 * Sizeof(Longint); // 2 GiB - 9 bytes
      {$ELSE}
      MaxRandomDataChunkSize = 1 * TMemUnits.OneGiB;
      {$ENDIF}
  public
    constructor Create(const AMaxFileSize: UInt64);
    property FileName: string read fFileName;
    property FileSize: UInt64 read fFileSize;
    property GeneratorType: TGeneratorType read fGeneratorType;
    property ExistingFileAction: TExistingFileAction read fExistingFileAction;
    property LargeFileAction: TLargeFileAction read fLargeFileAction;
    property ShowVersion: Boolean read fShowVersion;
    property RandomDataChunkSize: UInt64 read fRandomDataChunkSize;
  end;

implementation

uses
  System.SysUtils,
  System.Character,
  System.Math,

  GBG.Exceptions,
  GBG.NumberFmt;

{ TParams }

constructor TParams.Create(const AMaxFileSize: UInt64);
begin
  inherited Create;
  fMaxFileSize := AMaxFileSize;
  fFileName := '';
  fFileSize := 0;
  fGeneratorType := TGeneratorType.Binary;
  fExistingFileAction := TExistingFileAction.Prompt;
  fLargeFileAction := TLargeFileAction.Prompt;
  fShowVersion := False;
  fIsFileSizeSet := False;
  fRandomDataChunkSize := DefRandomDataChunkSize;
  ParseCommandLine;
end;

function TParams.IsOption(const S: string): Boolean;
begin
  Result := (S.Length >= 2) and CharInSet(S[1], OptionStartChars);
end;

procedure TParams.ParseCommandLine;
begin
  if ParamCount = 0 then
    raise ESilent.Create('');
  for var I := 1 to ParamCount do
  begin
    var Cmd := ParamStr(I);
    if IsOption(Cmd) then
    begin
      if (Length(Cmd) = 2) and (Cmd[2] = 'a') then
      begin
        fGeneratorType := TGeneratorType.PrintableASCII;
      end
      else if (Length(Cmd) = 2) and (Cmd[2] = 'A') then
      begin
        fGeneratorType := TGeneratorType.ASCII;
      end
      else if (Length(Cmd) = 2) and (Cmd[2] = 'o') then
      begin
        fExistingFileAction := TExistingFileAction.Error;
      end
      else if (Length(Cmd) = 2) and (Cmd[2] = 'O') then
      begin
        fExistingFileAction := TExistingFileAction.Overwrite;
      end
      else if (Length(Cmd) = 2) and (Cmd[2] = 'l') then
      begin
        fLargeFileAction := TLargeFileAction.Error;
      end
      else if (Length(Cmd) = 2) and (Cmd[2] = 'L') then
      begin
        fLargeFileAction := TLargeFileAction.Allow;
      end
      else if (Length(Cmd) >= 2) and (Cmd[2] = 'r') then
      begin
        ParseRandomDataChunkSizeCommand(Cmd);
      end
      else if (Length(Cmd) = 2) and (Cmd[2] = 'V') then
        fShowVersion := True
      else
        raise EUsageError.CreateFmt('Option not valid: "%s"', [Cmd]);
    end
    else
    begin
      if fFileName = '' then
        fFileName := Cmd
      else if not fIsFileSizeSet then
      begin
        if not TNumberFmt.TryParse(Cmd, fFileSize) then
          raise EUsageError.CreateFmt(
            'Invalid file size. Malformed number: "%s"', [Cmd]
          );
        if not InRange(fFileSize, 0, fMaxFileSize) then
          raise EUsageError.CreateFmt(
            'Invalid file size. Must be a whole number in range 0 to %s',
            [TNumberFmt.FormatNumber(fMaxFileSize)]
          );
        fIsFileSizeSet := True;
      end
      else
        raise EUsageError.Create('Too many parameters');
    end;
  end;
  if fShowVersion then
  begin
    if ParamCount <> 1 then
      raise EUsageError.Create('-V must be the only parameter');
  end
  else if (fFileName = '') or not fIsFileSizeSet then
    raise EUsageError.Create('A file name and a file size are required');
end;

procedure TParams.ParseRandomDataChunkSizeCommand(const ACmd: string);

  procedure Error(const AMsg: string);
  begin
    raise EUsageError.CreateFmt('Malformed -r option: %s', [AMsg]);
  end;

begin
  // Format of this command is "-r:" <size> where <size> is a number that
  // may contain thousand separators and end with an IEC symbol
  // Alternatively, the whole file can be specified using "-r:all"
  Assert((ACmd.Length >= 2) and (ACmd[2] = 'r'), 'Invalid ACmd: ' + ACmd);
  if (ACmd.Length < 3) or (ACmd[3] <> ':') then
    Error('missing colon after -r');
  if (ACmd.Length < 4) then
    Error('no size specified after -r:');
  var SizeStr: string := ACmd.Substring(3);  // zero based index
  if SizeStr = 'all' then
    fRandomDataChunkSize := 0   // special value meaning "whole file"
  else if not TNumberFmt.TryParse(SizeStr, fRandomDataChunkSize) then
    Error(Format('invalid size "%s"', [SizeStr]));
  if fRandomDataChunkSize > MaxRandomDataChunkSize then
    Error('random data chunk size is too large');
end;

end.
