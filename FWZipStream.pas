﻿////////////////////////////////////////////////////////////////////////////////
//
//  ****************************************************************************
//  * Project   : FWZip
//  * Unit Name : FWZipStream
//  * Purpose   : Вспомогательные стримы для поддержки шифрования на лету,
//  *           : и усеченного заголовка ZLib,
//  *           : для поддержки разбитых на тома архивов и прочее утилитарные
//  *           : стримы для проверки целостности архива
//  * Author    : Александр (Rouse_) Багель
//  * Copyright : © Fangorn Wizards Lab 1998 - 2020.
//  * Version   : 1.1.0
//  * Home Page : http://rouse.drkb.ru
//  * Home Blog : http://alexander-bagel.blogspot.ru
//  ****************************************************************************
//  * Stable Release : http://rouse.drkb.ru/components.php#fwzip
//  * Latest Source  : https://github.com/AlexanderBagel/FWZip
//  ****************************************************************************
//
//  Используемые источники:
//  ftp://ftp.info-zip.org/pub/infozip/doc/appnote-iz-latest.zip
//  http://zlib.net/zlib-1.2.5.tar.gz
//  http://www.base2ti.com/
//
//
//  Описание идеи TFWZipItemStream:
//  При помещении в архив сжатого блока данных методом Deflate у него
//  отрезается двухбайтный заголовок в котором указаны параметры сжатия.
//  Т.е. в архив помещаются сами данные в чистом виде.
//  Для распаковки необходимо данный заголовок восстановить.
//  TFWZipItemStream позволяет добавить данный заголовок "на лету"
//  абсолютно прозрачно для внешнего кода.
//  Сам заголовок генерируется в конструкторе и подставляется в методе Read.
//  Так-же класс, выступая посредником между двумя стримами,
//  позволяет производить шифрование и дешифровку передаваемых данных.
//  Шифрование производится в методе Write, в этот момент класс является
//  посредником между TCompressionStream и результирующим стримом.
//  Дешифрование осуществляется в методе Read, в этот момент класс является
//  посредником между стримом со сжатыми и
//  пошифрованными данными и TDecompressionStream.
//

unit FWZipStream;

interface

{$I fwzip.inc}

uses
  Windows,
  Classes,
  SysUtils,
  Math,
  FWZipConsts,
  FWZipCrypt,
  FWZipCrc32,
  FWZipZLib;

const
  NO_STREAM = -1;

type
  TFWZipItemStream = class(TStream)
  private
    FOwner: TStream;
    FCryptor: TFWZipCryptor;
    FDecryptor: TFWZipDecryptor;
    FSize, FStart, FPosition: Int64;
    {$IFDEF USE_AUTOGENERATED_ZLIB_HEADER}
    FHeader: Word;
    {$ENDIF}
  protected
    function GetSize: Int64; override;
  public
    constructor Create(AOwner: TStream; Cryptor: TFWZipCryptor;
      Decryptor: TFWZipDecryptor; CompressLevel: Byte; ASize: Int64);
    function Seek(Offset: Longint; Origin: Word): Longint; overload; override;
    function Seek(const Offset: Int64; Origin: TSeekOrigin): Int64; overload; override;
    function Read(var Buffer; Count: Longint): Longint; override;
    function Write(const Buffer; Count: Longint): Longint; override;
  end;

  EFWZipItemItemUnpackedStreamException = class(Exception);

  // Виртуальный стрим данных.
  // Используется для более привычной работы с незапакованным блоком данных,
  // расположенного в архиве
  TFWZipItemItemUnpackedStream = class(TStream)
  private
    FOwnerStream: TStream;
    FOffset: Int64;
    FSize, FPosition: Integer;
  protected
    function GetSize: Int64; override;
    procedure SetSize(NewSize: Longint); override;
  public
    constructor Create; overload;
    constructor Create(Owner: TStream; Offset: Int64; Size: Integer); overload;
    function Read(var Buffer; Count: Longint): Longint; override;
    function Write(const Buffer; Count: Longint): Longint; override;
    function Seek(Offset: Longint; Origin: Word): Longint; override;
  end;

  //  TFakeStream предназначен для проверки архива на целостность
  TFakeStream = class(TStream)
  private
    FSize: Int64;
    FPosition: Int64;
  protected
    procedure SetSize(const NewSize: Int64); override;
  public
    function Seek(const Offset: Int64; Origin: TSeekOrigin): Int64; overload; override;
    function Write(const Buffer; Count: Longint): Longint; override;
    function Read(var Buffer; Count: Longint): Longint; override;
  end;

  TFWMultiStreamMode = (msmRead, msmWrite);

  EFWMultiStreamException = class(Exception)
  public
    constructor Create(ADiskNumber: Integer); overload;
    constructor Create(const AMessage: string); overload;
  end;

  TFWMultiStreamClass = class of TFWAbstractMultiStream;

  TFWLastVolumesType = (lvtLastPart, lvtCentralDirectory);

  // Данный стрим используется при работе с архивом разбитым на тома
  TFWAbstractMultiStream = class(TStream)
  private
    FMode: TFWMultiStreamMode;
    FCurrentDiskData: TStream;
    FPosition: Int64;
    procedure CheckMode(AMode: TFWMultiStreamMode);
    function CurrentDiskNumber: Integer;
    function CalcOffset(DiskNumber: Integer): Int64;
    function UpdateCurrentDiskData: Integer;
  protected
    function GetNextWriteVolume: TStream; virtual; abstract;
    procedure GetStream(DiskNumber: Integer; var DiskData: TStream); virtual; abstract;
    function GetTotalSize: Int64; virtual; abstract;
    function GetVolumeSizeByIndex(Index: Integer): Int64; virtual; abstract;
    procedure TrimFromDiskNumber(Index: Integer); virtual; abstract;
    property VolumeSize[Index: Integer]: Int64 read GetVolumeSizeByIndex;
    procedure UpdateVolumeSize; virtual; abstract;
    /// <summary>
    ///  Метод должен вызываться только для режима msmWrite после окончания
    ///  записи архива. Применяется для закрытия последнего дома и его переименования.
    /// </summary>
    procedure FinallyWrite; virtual;
  protected
    procedure SetSize(const NewSize: Int64); override;
  public
    constructor Create(AMode: TFWMultiStreamMode); reintroduce;
    procedure GetRelativeInfo(var DiskNumber: Integer; var RealtiveOffset: Int64);
    function GetDiskCount: Integer; virtual; abstract;
    function GetWriteVolumeSize: Int64; virtual; abstract;
    function Read(var Buffer; Count: Longint): Longint; override;
    function Write(const Buffer; Count: Longint): Longint; override;
    function Seek(const Offset: Int64; Origin: TSeekOrigin): Int64; overload; override;
    function Seek(DiskNumber: Integer; Offset: Int64): Int64; overload;
    /// <summary>
    ///  Начинает новый том архива даже если предыдущий был заполнен не до конца
    ///  Работает только в режиме msmWrite
    /// </summary>
    procedure StartNewVolume;
    property Mode: TFWMultiStreamMode read FMode;
  end;

  EFWFileMultiStreamException = class(Exception);

  TReadSizeMode = (rsmQuick, rsmFull);

  // Используется для работы с томами архива доступным из файловой системы
  TFWFileMultiStream = class(TFWAbstractMultiStream)
  private const
    MinPartSize = {$IFDEF UNIT_TEST}100{$ELSE}$10000{$ENDIF};
  private
    FCurrentStreamNumber: Integer;
    FCurrentStream: TFileStream;
    FFilePath: string;
    FVolumesPath: TStringList;
    FTotalSize, FVolumeSize: Int64;
    FReadVolumesSize, FWriteVolumesSize: array of Int64;
    function AddNewVolume: TStream;
    procedure FillFilesList(const FilePath: string;
      ReadSizeMode: TReadSizeMode);
    procedure FillFilesSize(ReadSizeMode: TReadSizeMode);
  protected
    constructor Create(const FilePath: string;
      AMode: TFWMultiStreamMode; ReadSizeMode: TReadSizeMode;
      PartSize: Int64);
    function GetNextWriteVolume: TStream; override;
    procedure GetStream(DiskNumber: Integer; var DiskData: TStream); override;
    function GetTotalSize: Int64; override;
    function GetVolumeSizeByIndex(Index: Integer): Int64; override;
    procedure TrimFromDiskNumber(Index: Integer); override;
    procedure UpdateVolumeSize; override;
    procedure FinallyWrite; override;
  protected
    function GetVolumeExt(Index: Integer): string; virtual; // если имена файлов не .zХХ то перекрываем эту процедуру в наследнике
  public
    constructor CreateRead(const FilePath: string; ReadSizeMode: TReadSizeMode = rsmFull);
    constructor CreateWrite(const FilePath: string; PartSize: Int64 = MinPartSize);
    destructor Destroy; override;
    function GetDiskCount: Integer; override;
    function GetWriteVolumeSize: Int64; override;
  end;

implementation

const
  E_READONLY = 'TFWZipItemItemUnpackedStream работает только в режиме ReadOnly';

{ TFWZipItemStream }

constructor TFWZipItemStream.Create(AOwner: TStream; Cryptor: TFWZipCryptor;
  Decryptor: TFWZipDecryptor; CompressLevel: Byte; ASize: Int64);
begin
  inherited Create;
  FOwner := AOwner;
  FCryptor := Cryptor;
  FDecryptor := Decryptor;

  FSize := ASize;
  FStart := AOwner.Position;
  FPosition := 0;

  // Rouse_ 30.10.2013
  // Устаревший код
  {$IFDEF USE_AUTOGENERATED_ZLIB_HEADER}

  // Rouse_ 17.03.2011
  // Размерчик все-же нужно править увеличикая на размер заголовка
  Inc(FSize, 2);
  // Восстанавливаем пропущенный заголовок ZLib стрима
  // см. deflate.c - int ZEXPORT deflate (strm, flush)

  // uInt header = (Z_DEFLATED + ((s->w_bits-8)<<4)) << 8;
  FHeader := (Z_DEFLATED + (7 {32k Window size} shl 4)) shl 8;

  // if (s->strategy >= Z_HUFFMAN_ONLY || s->level < 2)
  //     level_flags = 0;
  // else if (s->level < 6)
  //     level_flags = 1;
  // else if (s->level == 6)
  //     level_flags = 2;
  // else
  //     level_flags = 3;
  //
  // сам CompressLevel (level_flags)
  // берется из уже заполненного GeneralPurposeBitFlag
  // здесь мы из битовой маски восстанавливаем оригинальные значения

  case CompressLevel of
    PBF_COMPRESS_SUPERFAST:
      CompressLevel := 0;
    PBF_COMPRESS_FAST:
      CompressLevel := 1;
    PBF_COMPRESS_NORMAL:
      CompressLevel := 2;
    PBF_COMPRESS_MAXIMUM:
      CompressLevel := 3;
  end;

  // header |= (level_flags << 6);
  FHeader := FHeader or (CompressLevel shl 6);

  // if (s->strstart != 0) header |= PRESET_DICT;
  // словарь не используется - оставляем без изменений

  // header += 31 - (header % 31);
  Inc(FHeader, 31 - (FHeader mod 31));

  // putShortMSB(s, header);
  FHeader := (FHeader shr 8) + (FHeader and $FF) shl 8;
  {$ENDIF}
end;

function TFWZipItemStream.GetSize: Int64;
begin
  Result := FSize;
end;

function TFWZipItemStream.Read(var Buffer; Count: Integer): Longint;
var
  P: PByte;
  DecryptBuff: Pointer;
begin
  // Rouse_ 30.10.2013
  // Устаревший код
  {$IFDEF USE_AUTOGENERATED_ZLIB_HEADER}
  if FPosition = 0 then
  begin
    // если зачитываются данные с самого начала
    // необходимо перед ними разместить заголовок ZLib
    P := @FHeader;
    Move(P^, Buffer, 2);
    FOwner.Position := FStart;
    P := @Buffer;
    Inc(P, 2);
    if Count > Size then
      Count := Size;
    FOwner.Position := FStart;
    if FDecryptor <> nil then
    begin
      // в случае если файл зашифрован, производим расшифровку блока
      GetMem(DecryptBuff, Count - 2);
      try
        Result := FOwner.Read(DecryptBuff^, Count - 2);
        FDecryptor.DecryptBuffer(DecryptBuff, Result);
        Move(DecryptBuff^, P^, Result);
      finally
        FreeMem(DecryptBuff);
      end;
    end
    else
      Result := FOwner.Read(P^, Count - 2);
    Inc(Result, 2);
    Inc(FPosition, Result);
  end
  else
  begin
    FOwner.Position := FStart + Position - 2;
  {$ELSE}
  begin
    FOwner.Position := FStart + Position;
  {$ENDIF}
    if Count > Size - Position then
      Count := Size - Position;
    if FDecryptor <> nil then
    begin
      // в случае если файл зашифрован, производим расшифровку блока
      GetMem(DecryptBuff, Count);
      try
        Result := FOwner.Read(DecryptBuff^, Count);
        FDecryptor.DecryptBuffer(DecryptBuff, Result);
        P := @Buffer;
        Move(DecryptBuff^, P^, Result);
      finally
        FreeMem(DecryptBuff);
      end;
    end
    else
      Result := FOwner.Read(Buffer, Count);
    Inc(FPosition, Result);
  end;
end;

function TFWZipItemStream.Seek(Offset: Integer; Origin: Word): Longint;
begin
  Result := Seek(Int64(Offset), TSeekOrigin(Origin));
end;

function TFWZipItemStream.Seek(const Offset: Int64; Origin: TSeekOrigin): Int64;
begin
  case Origin of
    soBeginning: FPosition := Offset;
    soCurrent: Inc(FPosition, Offset);
    soEnd: FPosition := Size + Offset;
  end;
  Result := FPosition;
end;

function TFWZipItemStream.Write(const Buffer; Count: Integer): Longint;
var
  EncryptBuffer: PByte;
begin
  if FCryptor = nil then
    Result := FOwner.Write(Buffer, Count)
  else
  begin
    // криптуем буфер
    GetMem(EncryptBuffer, Count);
    try
      Move(Buffer, EncryptBuffer^, Count);

      // Rouse_ 31.10.2013
      // Устаревший код
      {$IFDEF USE_AUTOGENERATED_ZLIB_HEADER}
      // Шифровать блок нужно пропустив двубайтный заголовок ZLib
      if FPosition = 0 then
      begin
        Inc(EncryptBuffer, 2);
        FCryptor.EncryptBuffer(EncryptBuffer, Count - 2);
        Dec(EncryptBuffer, 2);
      end
      else
      {$ENDIF}
        FCryptor.EncryptBuffer(EncryptBuffer, Count);
      Result := FOwner.Write(EncryptBuffer^, Count);
    finally
      FreeMem(EncryptBuffer);
    end;
  end;
  Inc(FPosition, Result);
end;

{ TFWZipItemItemUnpackedStream }

constructor TFWZipItemItemUnpackedStream.Create;
begin
  raise EFWZipItemItemUnpackedStreamException.Create(
    'Неверный вызов конструктора');
end;

constructor TFWZipItemItemUnpackedStream.Create(Owner: TStream; Offset: Int64;
  Size: Integer);
begin
  FOwnerStream := Owner;
  FOffset := Offset;
  FSize := Size;
end;

function TFWZipItemItemUnpackedStream.GetSize: Int64;
begin
  Result := FSize;
end;

function TFWZipItemItemUnpackedStream.Read(var Buffer; Count: Longint): Longint;
begin
  if FPosition + Count > FSize then
     Count := FSize - FPosition;
  FOwnerStream.Position := FOffset + FPosition;
  Result := FOwnerStream.Read(Buffer, Count);
  Inc(FPosition, Result);
end;

function TFWZipItemItemUnpackedStream.Seek(Offset: Longint;
  Origin: Word): Longint;
begin
  case Origin of
    soFromBeginning: FPosition := Offset;
    soFromCurrent: Inc(FPosition, Offset);
    soFromEnd: FPosition := Size + Offset;
  end;
  if FPosition < 0 then
    FPosition := 0;
  if FPosition > FSize then
    FPosition := FSize;
  Result := FPosition;
end;

procedure TFWZipItemItemUnpackedStream.SetSize(NewSize: Longint);
begin
  raise EFWZipItemItemUnpackedStreamException.Create(E_READONLY);
end;

function TFWZipItemItemUnpackedStream.Write(const Buffer;
  Count: Longint): Longint;
begin
  raise EFWZipItemItemUnpackedStreamException.Create(E_READONLY);
end;

{ TFakeStream }

function TFakeStream.Read(var Buffer; Count: Longint): Longint;
begin
  raise Exception.Create('TFakeStream.Read');
end;

function TFakeStream.Write(const Buffer; Count: Longint): Longint;
begin
  FSize := FSize + Count;
  Result := Count;
end;

function TFakeStream.Seek(const Offset: Int64; Origin: TSeekOrigin): Int64;
begin
  case Origin of
    soBeginning: FPosition := Offset;
    soCurrent: Inc(FPosition, Offset);
    soEnd: FPosition := FSize + Offset;
  end;
  Result := FPosition;
end;

procedure TFakeStream.SetSize(const NewSize: Int64);
begin
  FSize := NewSize;
end;

{ EFWMultiStreamException }

constructor EFWMultiStreamException.Create(ADiskNumber: Integer);
begin
  inherited CreateFmt('Can not find disk image №%d', [ADiskNumber]);
end;

constructor EFWMultiStreamException.Create(const AMessage: string);
begin
  inherited Create(AMessage);
end;

{ TFWAbstractMultiStream }

function TFWAbstractMultiStream.CalcOffset(DiskNumber: Integer): Int64;
begin
  Result := FPosition - VolumeSize[DiskNumber];
end;

procedure TFWAbstractMultiStream.CheckMode(AMode: TFWMultiStreamMode);
begin
  if FMode <> AMode then
    if FMode = msmRead then
      raise EFWMultiStreamException.Create('Can`t write data on read.')
    else
      raise EFWMultiStreamException.Create('Can`t read data on write.');
end;

constructor TFWAbstractMultiStream.Create(AMode: TFWMultiStreamMode);
begin
  FMode := AMode;
end;

function TFWAbstractMultiStream.CurrentDiskNumber: Integer;
var
  I: Integer;
begin
  Result := 0;
  for I := GetDiskCount - 1 downto 0 do
  begin
    if VolumeSize[I] <= FPosition then
    begin
      Result := I;
      Break;
    end;
  end;
end;

procedure TFWAbstractMultiStream.FinallyWrite;
begin
  CheckMode(msmWrite);
end;

procedure TFWAbstractMultiStream.GetRelativeInfo(var DiskNumber: Integer;
  var RealtiveOffset: Int64);
begin
  DiskNumber := CurrentDiskNumber;
  RealtiveOffset := CalcOffset(DiskNumber);
end;

function TFWAbstractMultiStream.Read(var Buffer; Count: Longint): Longint;
var
  PartialRead: Longint;
  P: PByte;
begin
  CheckMode(msmRead);
  Result := 0;
  while Result < Count do
  begin
    P := PByte(@Buffer);
    Inc(P, Result);
    PartialRead := FCurrentDiskData.Read(P^, Count - Result);

    if PartialRead = 0 then
      raise EFWMultiStreamException.Create('Ошибка чтения данных.');

    Inc(Result, PartialRead);
    Inc(FPosition, PartialRead);
    if FCurrentDiskData.Position = FCurrentDiskData.Size then
    begin
      GetStream(CurrentDiskNumber, FCurrentDiskData);
      if FCurrentDiskData = nil then
        Break;
    end;
  end;
end;

function TFWAbstractMultiStream.Seek(const Offset: Int64; Origin: TSeekOrigin): Int64;
var
  DiskNumber: Integer;
begin
  case TSeekOrigin(Origin) of
    soBeginning: FPosition := Offset;
    soCurrent: Inc(FPosition, Offset);
    soEnd: FPosition := GetTotalSize + Offset;
  end;

  if FPosition < 0 then
    FPosition := 0;
  if FPosition > GetTotalSize then
    FPosition := GetTotalSize;

  DiskNumber := UpdateCurrentDiskData;
  FCurrentDiskData.Seek(CalcOffset(DiskNumber), soBeginning);
  Result := FPosition;
end;

function TFWAbstractMultiStream.Seek(DiskNumber: Integer; Offset: Int64): Int64;
begin
  if (DiskNumber < 0) or (DiskNumber >= GetDiskCount) then
    raise EFWMultiStreamException.Create(DiskNumber);
  Offset := VolumeSize[DiskNumber] + Offset;
  Result := Seek(Offset, soBeginning);
end;

procedure TFWAbstractMultiStream.SetSize(const NewSize: Int64);
var
  TotalRemain, MaxVolumeSize, TotalSize: Int64;
begin
  CheckMode(msmWrite);
  TotalSize := GetTotalSize;

  // Если изменения размера нет, то и нечего делать
  if TotalSize = NewSize then Exit;

  // Размер стрима уменьшается
  if TotalSize > NewSize then
  begin
    Position := NewSize;
    FCurrentDiskData.Size := CalcOffset(CurrentDiskNumber);
    TrimFromDiskNumber(CurrentDiskNumber);
    Exit;
  end;

  // В противном случае увеличивать будем с самого последнего тома
  GetStream(GetDiskCount - 1, FCurrentDiskData);

  // Которого может и не быть
  if FCurrentDiskData = nil then
    FCurrentDiskData := GetNextWriteVolume;

  TotalRemain := NewSize - TotalSize;
  MaxVolumeSize := GetWriteVolumeSize;

  while TotalRemain > 0 do
  begin
    if FCurrentDiskData.Size + TotalRemain <= MaxVolumeSize then
    begin
      FCurrentDiskData.Size := FCurrentDiskData.Size + TotalRemain;
      UpdateVolumeSize;
      Exit;
    end;
    Dec(TotalRemain, MaxVolumeSize - FCurrentDiskData.Size);
    FCurrentDiskData.Size := MaxVolumeSize;
    UpdateVolumeSize;
    FCurrentDiskData := GetNextWriteVolume;
  end;
end;

procedure TFWAbstractMultiStream.StartNewVolume;
begin
  CheckMode(msmWrite);
  if Position <> Size then
    raise EFWMultiStreamException.Create('Нельзя завершать текущий том находясь в середине архива.');
  if FCurrentDiskData <> nil then
    if FCurrentDiskData.Size > 0 then
      GetNextWriteVolume;
end;

function TFWAbstractMultiStream.UpdateCurrentDiskData: Integer;
begin
  Result := CurrentDiskNumber;
  GetStream(Result, FCurrentDiskData);
  if FCurrentDiskData = nil then
    raise EFWMultiStreamException.Create(Result);
end;

function TFWAbstractMultiStream.Write(const Buffer; Count: Longint): Longint;
var
  PartialWrite: LongInt;
  WriteSize: Int64;
  P: PByte;
begin
  CheckMode(msmWrite);
  Result := 0;
  WriteSize := GetWriteVolumeSize;

  if FCurrentDiskData = nil then
    FCurrentDiskData := GetNextWriteVolume;

  while Result < Count do
  begin
    PartialWrite := Min(Count - Result, WriteSize - FCurrentDiskData.Position);
    P := PByte(@Buffer);
    Inc(P, Result);
    if FCurrentDiskData.Write(P^, PartialWrite) <> PartialWrite then
      raise EFWMultiStreamException.Create('Ошибка записи данных.');
    Inc(Result, PartialWrite);
    Inc(FPosition, PartialWrite);
    UpdateVolumeSize;
    if FCurrentDiskData.Position = WriteSize then
      FCurrentDiskData := GetNextWriteVolume;
  end;
end;

{ TFWFileMultiStream }

function TFWFileMultiStream.AddNewVolume: TStream;
var
  NewVolumePath: string;
begin
  FCurrentStreamNumber := FVolumesPath.Count;
  NewVolumePath :=
    ChangeFileExt(FFilePath, GetVolumeExt(FCurrentStreamNumber + 1));
  FVolumesPath.Add(NewVolumePath);
  SetLength(FReadVolumesSize, FVolumesPath.Count);
  SetLength(FWriteVolumesSize, FVolumesPath.Count);
  FreeAndNil(FCurrentStream);
  FCurrentStream :=
    TFileStream.Create(NewVolumePath, fmCreate or fmShareDenyWrite);
  UpdateVolumeSize;
  Result := FCurrentStream;
end;

constructor TFWFileMultiStream.Create(const FilePath: string;
  AMode: TFWMultiStreamMode; ReadSizeMode: TReadSizeMode; PartSize: Int64);
begin
  FCurrentStreamNumber := NO_STREAM;
  FFilePath := FilePath;
  FVolumesPath := TStringList.Create;
  if AMode = msmRead then
    FillFilesList(FilePath, ReadSizeMode)
  else
  begin
    if PartSize < MinPartSize then
      raise EFWFileMultiStreamException.CreateFmt(
        'Указан слишком маленький размер тома (%d), минимальный размер = %d', [PartSize, MinPartSize]);
    FVolumeSize := PartSize;
  end;
  inherited Create(AMode);
end;

constructor TFWFileMultiStream.CreateRead(const FilePath: string;
  ReadSizeMode: TReadSizeMode);
begin
  Create(FilePath, msmRead, ReadSizeMode, 0);
end;

constructor TFWFileMultiStream.CreateWrite(const FilePath: string;
  PartSize: Int64);
begin
  Create(FilePath, msmWrite, rsmQuick, PartSize);
end;

destructor TFWFileMultiStream.Destroy;
begin
  if Mode = msmWrite then
    FinallyWrite
  else
    FreeAndNil(FCurrentStream);
  FVolumesPath.Free;
  inherited;
end;

procedure TFWFileMultiStream.FillFilesList(
  const FilePath: string; ReadSizeMode: TReadSizeMode);
var
  I: Integer;
  SplitFilePath: string;
begin
  FVolumesPath.Clear;
  if not FileExists(FilePath) then
    raise EFWFileMultiStreamException.CreateFmt('File not found: "%s"', [FilePath]);
  I := 1;
  SplitFilePath := ChangeFileExt(FilePath, GetVolumeExt(I));
  while FileExists(SplitFilePath) do
  begin
    FVolumesPath.Add(SplitFilePath);
    Inc(I);
    SplitFilePath := ChangeFileExt(FilePath, GetVolumeExt(I));
  end;
  FVolumesPath.Add(FilePath);
  FillFilesSize(ReadSizeMode);
end;

procedure TFWFileMultiStream.FillFilesSize(ReadSizeMode: TReadSizeMode);
var
  F: TFileStream;
  I, FirstVolumeSize, Tmp: Integer;
begin
  FTotalSize := 0;

  SetLength(FReadVolumesSize, FVolumesPath.Count);

  if ReadSizeMode = rsmFull then
  begin
    for I := 0 to FVolumesPath.Count - 1 do
    begin
      F := TFileStream.Create(FVolumesPath[I], fmShareDenyWrite);
      try
        // Каждая запись содержит размер с которого она начинается в плоском массиве
        FReadVolumesSize[I] := FTotalSize;
        Inc(FTotalSize, F.Size);
      finally
        F.Free;
      end;
    end;
    Exit;
  end;

  F := TFileStream.Create(FVolumesPath[0], fmShareDenyWrite);
  try
    FirstVolumeSize := F.Size;
  finally
    F.Free;
  end;

  I := FVolumesPath.Count;
  repeat
    Dec(I);
    F := TFileStream.Create(FVolumesPath[I], fmShareDenyWrite);
    try
      FReadVolumesSize[I] := F.Size;
    finally
      F.Free;
    end;
  until FReadVolumesSize[I] = FirstVolumeSize;

  for I := 0 to FVolumesPath.Count - 1 do
  begin
    Tmp := FReadVolumesSize[I];
    FReadVolumesSize[I] := FTotalSize;
    if Tmp = 0 then
      Inc(FTotalSize, FirstVolumeSize)
    else
      Inc(FTotalSize, Tmp);
  end;
end;

procedure TFWFileMultiStream.FinallyWrite;
var
  LastDiskIndex: Integer;
begin
  inherited;
  FreeAndNil(FCurrentStream);
  FCurrentStreamNumber := NO_STREAM;
  LastDiskIndex := GetDiskCount - 1;
  while LastDiskIndex >= 0 do
  begin
    if FWriteVolumesSize[LastDiskIndex] = 0 then
    begin
      DeleteFile(FVolumesPath[LastDiskIndex]);
      Dec(LastDiskIndex);
    end
    else
      Break;
  end;
  if LastDiskIndex >= 0 then
    RenameFile(FVolumesPath[LastDiskIndex], FFilePath);
  SetLength(FReadVolumesSize, 0);
  SetLength(FWriteVolumesSize, 0);
  FVolumesPath.Clear;
end;

function TFWFileMultiStream.GetDiskCount: Integer;
begin
  Result := FVolumesPath.Count;
end;

function TFWFileMultiStream.GetNextWriteVolume: TStream;
begin
  if (FCurrentStreamNumber < 0) or (FCurrentStreamNumber >= FVolumesPath.Count - 1) then
    Result := AddNewVolume
  else
    GetStream(FCurrentStreamNumber + 1, Result);
end;

procedure TFWFileMultiStream.GetStream(DiskNumber: Integer; var DiskData: TStream);
const
  OpenMode: array [TFWMultiStreamMode] of Word =
    (fmShareDenyWrite, fmOpenReadWrite or fmShareExclusive);
begin
  if FCurrentStreamNumber = DiskNumber then
  begin
    DiskData := FCurrentStream;
    Exit;
  end;

  FCurrentStreamNumber := DiskNumber;
  FreeAndNil(FCurrentStream);
  DiskData := nil;

  if (DiskNumber < 0) or (DiskNumber >= FVolumesPath.Count) then
  begin
    if FMode = msmRead then Exit;
    if DiskNumber > FVolumesPath.Count then Exit;
    DiskData := AddNewVolume;
    Exit;
  end;

  if FileExists(FVolumesPath[DiskNumber]) then
  begin
    FCurrentStream :=
      TFileStream.Create(FVolumesPath[DiskNumber], OpenMode[FMode]);
    DiskData := FCurrentStream;
  end;
end;

function TFWFileMultiStream.GetTotalSize: Int64;
begin
  Result := FTotalSize;
end;

function TFWFileMultiStream.GetVolumeExt(Index: Integer): string;
var
  Tmp, CharCount: Integer;
begin
  if Index < 100 then
    Result := Format('.z%.2d', [Index])
  else
  begin
    Tmp := Index div 100;
    CharCount := 2;
    while Tmp > 0 do
    begin
      Inc(CharCount);
      Tmp := Tmp div 10;
    end;
    Result := Format('.z%.' + IntToStr(CharCount) + 'd', [Index]);
  end;
end;

function TFWFileMultiStream.GetVolumeSizeByIndex(Index: Integer): Int64;
begin
  Result := FReadVolumesSize[Index];
end;

function TFWFileMultiStream.GetWriteVolumeSize: Int64;
begin
  Result := FVolumeSize;
end;

procedure TFWFileMultiStream.TrimFromDiskNumber(Index: Integer);
var
  I: Integer;
begin
  Inc(Index);
  SetLength(FReadVolumesSize, Index);
  SetLength(FWriteVolumesSize, Index);
  for I := FVolumesPath.Count - 1 downto Index do
  begin
    DeleteFile(PChar(FVolumesPath[I]));
    FVolumesPath.Delete(I);
  end;
  UpdateVolumeSize;
end;

procedure TFWFileMultiStream.UpdateVolumeSize;
var
  I: Integer;
begin
  if FCurrentStream = nil then Exit;
  if FCurrentStreamNumber < 0 then Exit;
  FWriteVolumesSize[FCurrentStreamNumber] := FCurrentStream.Size;
  FTotalSize := 0;
  for I := 0 to Length(FReadVolumesSize) - 1 do
  begin
    FReadVolumesSize[I] := FTotalSize;
    Inc(FTotalSize, FWriteVolumesSize[I]);
  end;
end;

end.
