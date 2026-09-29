unit GBG.NumberFmt;

interface

uses
  System.SysUtils,
  System.Generics.Collections;

type

  TMemSizeSymbols = record
    var
      fValue: UInt64;
    class var
      fSymbolMap: TDictionary<string,UInt64>;
  public
    class constructor Create;
    class destructor Destroy;
    ///  <summary>Attempts to convert a memory size symbol to the number of
    ///  bytes it represents.</summary>
    ///  <param name="APrefix">[in] Prefix to convert.</param>
    ///  <param name="ABytes">[in] Number of bytes represented by symbol. If
    ///  <c>APrefix</c> is not recognised then the conversion fails and
    ///  <c>ABytes</c> is undefined.</param>
    ///  <returns><c>Boolean</c>. <c>True</c> if the conversion succeeded or
    ///  <c>False</c> if it failed.</returns>
    class function TryPrefixToBytes(const APrefix: string; out ABytes: UInt64):
      Boolean; static;
  end;

  TNumberFmt = record
  strict private
    class function TryCleanIntStr(const ANumStr: string;
      out ACleanedNumStr: string): Boolean; static;
  public
    class function FormatNumber(const AValue: UInt64): string; static;
    class function TryParse(ANumStr: string; out AValue: UInt64): Boolean;
      overload; static;
    class function TryParseUInt(const ANumStr: string; out AValue: UInt64):
      Boolean; static;
  end;

  ENumberFmt = class(Exception);

implementation

uses
  System.Character,
  System.Hash,
  System.Generics.Defaults,
  GBG.Types;

{ TNumberFmt }

class function TNumberFmt.FormatNumber(const AValue: UInt64): string;
begin
  Result := Format('%.0n', [Extended(AValue)], TFormatSettings.Create);
end;

class function TNumberFmt.TryCleanIntStr(const ANumStr: string;
  out ACleanedNumStr: string): Boolean;
begin
  ACleanedNumStr := ANumStr.Trim;

  // Empty string is not a valid number
  if ACleanedNumStr.IsEmpty then
    Exit(False);

  // Check for empty "thousands" group, using correct separator for locale
  // empty group within string (e.g. 99,99,,99)
  var Separator := TFormatSettings.Create.ThousandSeparator;
  var DoubleSeparator := Separator + Separator;
  if ACleanedNumStr.Contains(DoubleSeparator) then
    Exit(False);
  // leading and trailing empty groups (e.g. ,999,)
  if ACleanedNumStr.StartsWith(Separator)
    or ACleanedNumStr.EndsWith(Separator) then
    Exit(False);

  // Remove thousands separator: we don't assume size of grouping since this
  // varies across locales
  ACleanedNumStr := ACleanedNumStr.Replace(
    Separator, '', [TReplaceFlag.rfReplaceAll]
  );
  Result := True;
end;

class function TNumberFmt.TryParse(ANumStr: string;
  out AValue: UInt64): Boolean;
begin
 var NumStr := ANumStr.Trim;

  // Split number from any memory symbol suffix
  var Idx := ANumStr.Length;
  while (Idx >= 1) and ANumStr[Idx].IsLetter do
    Dec(Idx);
  var MemSymbol := ANumStr.Substring(Idx);
  var Number := ANumStr.Substring(0, ANumStr.Length - MemSymbol.Length);

  // Parse number part
  var ParsedNumber: UInt64;
  if not TryParseUInt(Number, ParsedNumber) then
    Exit(False);

  // Convert the memory symbol to its related a multiplier
  var Multiplier: UInt64;
  if MemSymbol.IsEmpty then
    Multiplier := 1
  else
  begin
    if not TMemSizeSymbols.TryPrefixToBytes(MemSymbol, Multiplier) then
      Exit(False);
  end;

  // Calculate number of bytes by applying multiplier to entered number
  if High(UInt64) div Multiplier < ParsedNumber then
    Exit(False);  // Multiplier * ParsedNumber to big for UInt64!
  AValue := Multiplier * ParsedNumber;

  Result := True;
 end;

class function TNumberFmt.TryParseUInt(const ANumStr: string;
  out AValue: UInt64): Boolean;
begin
  var CleanedNumStr: string;

  // Validate string format & remove thousands separator
  if not TryCleanIntStr(ANumStr, CleanedNumStr) then
    Exit(False);

  // Convert to number
  Result := TryStrToUInt64(CleanedNumStr, AValue)
end;

{ TMemSizeSymbols }

class constructor TMemSizeSymbols.Create;
begin
  fSymbolMap := TDictionary<string,UInt64>.Create(
    TDelegatedEqualityComparer<string>.Create(
      function (const Left, Right: string): Boolean
      begin
        Result := string.Compare(Left, Right, True) = 0;
      end,
      function (const Value: string): Integer
      begin
        Result := THashBobJenkins.GetHashValue(
          string.UpperCase(Value, TLocaleOptions.loUserLocale)
        );
      end
    )
  );
  // Only the following subset of IEC and SI memory size symbols are supported
  // See https://help.creoline.com/en/doc/memory-sizes-zjTUhueSK6
  // IEC symbols
  fSymbolMap.Add('KiB', TMemUnits.OneKiB);    // kibibyte
  fSymbolMap.Add('MiB', TMemUnits.OneMiB);    // mebibyte
  fSymbolMap.Add('GiB', TMemUnits.OneGiB);    // gibibyte
  // SI symbols
  fSymbolMap.Add('Kb',  TMemUnits.OneKB);     // kilobyte
  fSymbolMap.Add('MB',  TMemUnits.OneMB);	    // megabyte
  fSymbolMap.Add('GB',  TMemUnits.OneGB);     // gigabyte
end;

class destructor TMemSizeSymbols.Destroy;
begin
  fSymbolMap.Free;
end;

class function TMemSizeSymbols.TryPrefixToBytes(const APrefix: string;
  out ABytes: UInt64): Boolean;
begin
  Result := True;
  var Prefix := APrefix.Trim;
  if Prefix.IsEmpty then
    ABytes := 1
  else if not fSymbolMap.TryGetValue(Prefix, ABytes) then
    Exit(False);
end;

end.

