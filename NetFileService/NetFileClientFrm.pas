unit NetFileClientFrm;

interface

uses
  Winapi.Windows, Winapi.Messages, System.SysUtils, System.Variants, System.Classes, Vcl.Graphics,
  Vcl.Controls, Vcl.Forms, Vcl.Dialogs, Vcl.StdCtrls, Vcl.ExtCtrls, Vcl.ComCtrls,

  System.IOUtils, Vcl.FileCtrl, System.DateUtils,

  CoreClasses,
  ListEngine, UnicodeMixedLib, DoStatusIO,
  DataFrameEngine, MemoryStream64, PascalStrings, CoreCipher, NotifyObjectBase, Cadencer,
  CommunicationFramework, PhysicsIO, CommunicationFrameworkDoubleTunnelIO_NoAuth;

type
  TNetFileClientForm = class(TForm, ICommunicationFrameworkClientInterface)
    GlobalCliPanel: TPanel;
    topPanel: TPanel;
    ListView: TListView;
    HostEdit: TLabeledEdit;
    PasswdEdit: TLabeledEdit;
    GoButton: TButton;
    progressTimer: TTimer;
    RefreshButton: TButton;
    FilterEdit: TLabeledEdit;
    DelayLabel: TLabel;
    DownloadButton: TButton;
    UploadButton: TButton;
    Memo: TMemo;
    Splitter: TSplitter;
    SaveDialog: TSaveDialog;
    StateTimer: TTimer;
    OpenDialog: TOpenDialog;
    DeleteButton: TButton;
    procedure progressTimerTimer(Sender: TObject);
    procedure StateTimerTimer(Sender: TObject);
    procedure GoButtonClick(Sender: TObject);
    procedure RefreshButtonClick(Sender: TObject);
    procedure UploadButtonClick(Sender: TObject);
    procedure DownloadButtonClick(Sender: TObject);
    procedure DeleteButtonClick(Sender: TObject);
    procedure DelayLabelClick(Sender: TObject);
    procedure ListViewColumnClick(Sender: TObject; Column: TListColumn);
    procedure ListViewKeyUp(Sender: TObject; var Key: Word; Shift: TShiftState);
  private
    // connection state
    procedure ClientConnected(Sender: TCommunicationFrameworkClient);
    procedure ClientDisconnect(Sender: TCommunicationFrameworkClient);

    // dostatus
    procedure DoStatus_Backcall(Text_: SystemString; const ID: Integer);
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    procedure RefreshFileList;
    procedure DownloadSelected(var DestDir: SystemString);
    procedure OpenDialogAndUpload();
    procedure DeleteSelected();
  end;

  TNetFileClient = class(TPhysicsClient)
  protected
    FRecv, FSend: TCommunicationFrameworkWithP2PVM_Client;
    FDoubleTunnel: TCommunicationFramework_DoubleTunnelClient_NoAuth;
  public
    constructor Create; override;
    destructor Destroy; override;
    procedure Progress; override;
  end;

  TRemoteFileData = record
    FileName: SystemString;
    Size: Int64;
    DateTime_: TDateTime;
  end;

  PRemoteFileData = ^TRemoteFileData;

var
  NetFileClientForm: TNetFileClientForm;
  NetFileClient: TNetFileClient;
  DownloadDirectory: SystemString;

implementation

{$R *.dfm}


uses ProgressBarFrm;

function CompInt(const A, b: Integer): Integer; inline;
begin
  if A = b then
      Result := 0
  else if A < b then
      Result := -1
  else
      Result := 1;
end;

function CompText(const t1, t2: TPascalString): Integer; inline;
  function WasWide(T: PPascalString): Byte; inline;
  var
    C: SystemChar;
  begin
    for C in T^.buff do
      if Ord(C) > 127 then
          Exit(1);
    Result := 0;
  end;

var
  d: Double;
  Same, Diff: Integer;
begin
  Result := CompInt(WasWide(@t1), WasWide(@t2));
  if Result = 0 then
    begin
      Result := CompInt(length(t1), length(t2));
      if Result = 0 then
          Result := CompareText(t1, t2);
    end;
end;

function LV_Sort1(lParam1, lParam2, lParamSort: LParam): Integer; stdcall;
var
  itm1, itm2: TListItem;
begin
  itm1 := TListItem(lParam1);
  itm2 := TListItem(lParam2);
  case lParamSort of
    0: Result := CompText(itm1.Caption, itm2.Caption);
    1: Result := CompInt(PRemoteFileData(itm1.Data)^.Size, PRemoteFileData(itm2.Data)^.Size);
    2: Result := CompareDateTime(PRemoteFileData(itm1.Data)^.DateTime_, PRemoteFileData(itm2.Data)^.DateTime_);
    3: Result := CompText(umlGetFileExt(PRemoteFileData(itm1.Data)^.FileName), umlGetFileExt(PRemoteFileData(itm2.Data)^.FileName));
  end;
end;

function LV_Sort2(lParam2, lParam1, lParamSort: LParam): Integer; stdcall;
var
  itm1, itm2: TListItem;
begin
  itm1 := TListItem(lParam1);
  itm2 := TListItem(lParam2);
  case lParamSort of
    0: Result := CompText(itm1.Caption, itm2.Caption);
    1: Result := CompInt(PRemoteFileData(itm1.Data)^.Size, PRemoteFileData(itm2.Data)^.Size);
    2: Result := CompareDateTime(PRemoteFileData(itm1.Data)^.DateTime_, PRemoteFileData(itm2.Data)^.DateTime_);
    3: Result := CompText(umlGetFileExt(PRemoteFileData(itm1.Data)^.FileName), umlGetFileExt(PRemoteFileData(itm2.Data)^.FileName));
  end;
end;

constructor TNetFileClient.Create;
begin
  inherited Create;
  FRecv := TCommunicationFrameworkWithP2PVM_Client.Create;
  FSend := TCommunicationFrameworkWithP2PVM_Client.Create;

  AutomatedP2PVMBindClient.AddClient(FRecv, '::', 2);
  AutomatedP2PVMBindClient.AddClient(FSend, '::', 1);
  AutomatedP2PVMClient := True;
  AutomatedP2PVMClientDelayBoot := 0;

  FRecv.SwitchMaxSecurity;
  FSend.SwitchMaxSecurity;
  FRecv.QuietMode := True;
  FSend.QuietMode := True;
  QuietMode := True;

  FDoubleTunnel := TCommunicationFramework_DoubleTunnelClient_NoAuth.Create(FRecv, FSend);
  FDoubleTunnel.RegisterCommand;
end;

destructor TNetFileClient.Destroy;
begin
  DisposeObject(FDoubleTunnel);
  DisposeObject(FRecv);
  DisposeObject(FSend);
  inherited Destroy;
end;

procedure TNetFileClient.Progress;
begin
  FDoubleTunnel.Progress;
  inherited Progress;
end;

procedure TNetFileClientForm.progressTimerTimer(Sender: TObject);
var
  Total, Complete: Int64;
begin
  NetFileClient.Progress;
  CheckThreadSynchronize;

  if NetFileClient.Connected and NetFileClient.FDoubleTunnel.LinkOk then
    begin
      if NetFileClient.FRecv.ClientIO.GetBigStreamReceiveState(Total, Complete) or NetFileClient.FSend.ClientIO.GetBigStreamSendingState(Total, Complete) then
        begin
          if not ProgressBarForm.Visible then
            begin
              ProgressBarForm.Show;
              ProgressBarForm.ProgressBar.Min := 0;
              ProgressBarForm.ProgressBar.Max := 100;
            end;
          ProgressBarForm.ProgressBar.Position := umlPercentageToInt64(Total, Complete);
          ProgressBarForm.InfoLabel.Caption := Format('complete: %s/%s', [umlSizeToStr(Complete).Text, umlSizeToStr(Total).Text]);
        end
      else
        begin
          ProgressBarForm.Close;
        end;
    end;
end;

procedure TNetFileClientForm.StateTimerTimer(Sender: TObject);
begin
  Caption := Format('Net File Client. P2PVM-Network(Received: %s Send: %s)',
    [umlSizeToStr(NetFileClient.Statistics[stReceiveSize]).Text, umlSizeToStr(NetFileClient.Statistics[stSendSize]).Text]);
end;

procedure TNetFileClientForm.GoButtonClick(Sender: TObject);
var
  host_: U_String;
  port_: Word;
begin
  if NetFileClient.Connected then
    begin
      NetFileClient.Disconnect;
      Exit;
    end;

  DelayLabel.Caption := '..';
  NetFileClient.AutomatedP2PVMAuthToken := PasswdEdit.Text;
  NetFileClient.OnAutomatedP2PVMClientConnectionDone_P := procedure(Sender: TCommunicationFramework; P_IO: TPeerIO)
    begin
      NetFileClient.FDoubleTunnel.TunnelLinkP(procedure(const State: Boolean)
        begin
          if State then
            begin
              DelayLabel.Caption := Format('ping %d MS', [round(NetFileClient.FDoubleTunnel.ServerDelay * 1000)]);
              RefreshFileList;
              GoButton.Caption := 'Close';
            end;
        end);
    end;

  port_ := 7456;
  host_ := HostEdit.Text;
  ExtractHostAddress(host_, port_);

  NetFileClient.AsyncConnectP(
    host_, port_, procedure(const State: Boolean)
    begin
    end);
end;

procedure TNetFileClientForm.RefreshButtonClick(Sender: TObject);
begin
  RefreshFileList;
end;

procedure TNetFileClientForm.UploadButtonClick(Sender: TObject);
begin
  OpenDialogAndUpload;
end;

procedure TNetFileClientForm.DownloadButtonClick(Sender: TObject);
begin
  DownloadSelected(DownloadDirectory);
end;

procedure TNetFileClientForm.DeleteButtonClick(Sender: TObject);
begin
  DeleteSelected;
end;

procedure TNetFileClientForm.DelayLabelClick(Sender: TObject);
begin
  if not NetFileClient.Connected then
      Exit;
  if not NetFileClient.FDoubleTunnel.LinkOk then
      Exit;

  DelayLabel.Caption := '..';
  NetFileClient.FDoubleTunnel.SyncCadencer;
  NetFileClient.FSend.WaitP(1000, procedure(const State: Boolean)
    begin
      DelayLabel.Caption := Format('ping %d MS', [round(NetFileClient.FDoubleTunnel.ServerDelay * 1000)]);
    end);
end;

procedure TNetFileClientForm.ListViewKeyUp(Sender: TObject; var Key: Word; Shift: TShiftState);
begin
  if ListView.IsEditing then
      Exit;
  case Key of
    VK_F5: RefreshButtonClick(RefreshButton);
    VK_DELETE: DeleteButtonClick(DeleteButton);
  end;
end;

procedure TNetFileClientForm.ClientConnected(Sender: TCommunicationFrameworkClient);
begin
end;

procedure TNetFileClientForm.ClientDisconnect(Sender: TCommunicationFrameworkClient);
begin
  NetFileClient.FDoubleTunnel.Disconnect;
  ListView.Items.BeginUpdate;
  ListView.Items.Clear;
  ListView.Items.EndUpdate;
  DelayLabel.Caption := '..';
  GoButton.Caption := 'GO';
end;

procedure TNetFileClientForm.DoStatus_Backcall(Text_: SystemString; const ID: Integer);
begin
  if Memo.Lines.Count > 5000 then
      Memo.Lines.Clear;
  Memo.Lines.Add(Text_);
end;

constructor TNetFileClientForm.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  AddDoStatusHook(self, DoStatus_Backcall);
  NetFileClient := TNetFileClient.Create;
  NetFileClient.OnInterface := self;
  DownloadDirectory := TPath.GetLibraryPath;
end;

destructor TNetFileClientForm.Destroy;
begin
  DeleteDoStatusHook(self);
  NetFileClient.FDoubleTunnel.Disconnect;
  NetFileClient.Disconnect;

  DisposeObject(NetFileClient);
  inherited Destroy;
end;

procedure TNetFileClientForm.RefreshFileList;
var
  d: TDFE;
begin
  if not NetFileClient.Connected then
      Exit;
  if not NetFileClient.FDoubleTunnel.LinkOk then
      Exit;

  d := TDFE.Create;
  d.WriteString(FilterEdit.Text);
  NetFileClient.FSend.SendStreamCmdP('GetFileList', d, procedure(Sender: TPeerIO; ResultData: TDataFrameEngine)
    var
      i: Integer;
      tmp: TDFE;
      p: PRemoteFileData;
    begin
      ListView.Items.BeginUpdate;
      for i := 0 to ListView.Items.Count - 1 do
          dispose(PRemoteFileData(ListView.Items[i].Data));
      ListView.Items.Clear;
      while ResultData.Reader.NotEnd do
        begin
          tmp := TDFE.Create;
          ResultData.Reader.ReadDataFrame(tmp);
          new(p);
          p^.FileName := tmp.Reader.ReadString;
          p^.Size := tmp.Reader.ReadInt64;
          p^.DateTime_ := tmp.Reader.ReadDouble;
          with ListView.Items.Add do
            begin
              Caption := p^.FileName;
              SubItems.Add(umlSizeToStr(p^.Size));
              SubItems.Add(umlDateTimeToStr(p^.DateTime_));
              SubItems.Add(umlGetFileExt(p^.FileName));
              Data := p;
              ImageIndex := -1;
              StateIndex := -1;
            end;
          DisposeObject(tmp);
        end;
      ListView.Items.EndUpdate;
      ListView.Width := ListView.Width - 1;
    end);
  DisposeObject(d);
end;

procedure TNetFileClientForm.DownloadSelected(var DestDir: SystemString);
var
  i: Integer;
  rn, ln: U_String;
begin
  if ListView.SelCount > 1 then
    begin
      if not SelectDirectory('download directory.', '', DestDir, [sdNewFolder, sdNewUI, sdValidateDir]) then
          Exit;
      for i := 0 to ListView.Items.Count - 1 do
        if ListView.Items[i].Selected then
          begin
            rn := ListView.Items[i].Caption;
            ln := umlCombineFileName(DestDir, rn);
            NetFileClient.FDoubleTunnel.AutomatedDownloadFileP(rn, ln,
              procedure(const UserData: Pointer; const UserObject: TCoreClassObject; stream: TCoreClassStream; const FileName: SystemString)
              begin
                DoStatus('done download %s', [FileName]);
              end);
          end;
    end
  else if ListView.SelCount = 1 then
    begin
      rn := ListView.Selected.Caption;

      SaveDialog.InitialDir := DestDir;
      SaveDialog.FileName := umlCombineFileName(DestDir, rn);
      if not SaveDialog.Execute then
          Exit;
      ln := SaveDialog.FileName;
      DestDir := umlGetFilePath(ln);
      NetFileClient.FDoubleTunnel.AutomatedDownloadFileP(rn, ln,
        procedure(const UserData: Pointer; const UserObject: TCoreClassObject; stream: TCoreClassStream; const FileName: SystemString)
        begin
          DoStatus('done download %s', [FileName]);
        end);
    end;
end;

procedure TNetFileClientForm.OpenDialogAndUpload;
var
  i: Integer;
begin
  if not OpenDialog.Execute then
      Exit;
  for i := 0 to OpenDialog.Files.Count - 1 do
      NetFileClient.FDoubleTunnel.AutomatedUploadFile(OpenDialog.Files[i]);
end;

procedure TNetFileClientForm.DeleteSelected;
var
  i: Integer;
  rn: U_String;
begin
  if MessageDlg('delete?', mtWarning, [mbYes, mbNo], 0) <> mrYes then
      Exit;
  for i := 0 to ListView.Items.Count - 1 do
    if ListView.Items[i].Selected then
      begin
        rn := ListView.Items[i].Caption;
        NetFileClient.FSend.SendDirectConsoleCmd('DeleteFile', rn);
      end;
  RefreshFileList;
end;

procedure TNetFileClientForm.ListViewColumnClick(Sender: TObject; Column: TListColumn);
var
  i: Integer;
begin
  // reset other sort column
  for i := 0 to ListView.columns.Count - 1 do
    if ListView.columns[i] <> Column then
        ListView.columns[i].Tag := 0;

  // imp sort
  if Column.Tag = 0 then
    begin
      ListView.CustomSort(@LV_Sort1, Column.Index);
      Column.Tag := 1;
    end
  else
    begin
      ListView.CustomSort(@LV_Sort2, Column.Index);
      Column.Tag := 0;
    end;
end;

end.
