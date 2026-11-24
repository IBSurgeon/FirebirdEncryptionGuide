object MainForm: TMainForm
  Left = 0
  Top = 0
  Caption = 'Firebird encryption: FireDAC and fbcrypt'
  ClientHeight = 562
  ClientWidth = 780
  Color = clBtnFace
  Font.Charset = DEFAULT_CHARSET
  Font.Color = clWindowText
  Font.Height = -12
  Font.Name = 'Segoe UI'
  Font.Style = []
  Position = poScreenCenter
  OnCreate = FormCreate
  OnDestroy = FormDestroy
  TextHeight = 15
  object ConnectionBox: TGroupBox
    Left = 8
    Top = 8
    Width = 764
    Height = 161
    Caption = 'Connection'
    TabOrder = 0
    object Label1: TLabel
      Left = 16
      Top = 27
      Caption = 'Client folder:'
    end
    object ClientDirEdit: TEdit
      Left = 112
      Top = 24
      Width = 572
      TabOrder = 0
      TextHint = 'Folder with fbclient.dll, fbcrypt.dll and libcrypto'
    end
    object BrowseClientButton: TButton
      Left = 692
      Top = 22
      Width = 60
      Height = 25
      Caption = '...'
      TabOrder = 1
      OnClick = BrowseClientButtonClick
    end
    object Label2: TLabel
      Left = 16
      Top = 59
      Caption = 'Server:'
    end
    object ServerEdit: TEdit
      Left = 112
      Top = 56
      Width = 120
      TabOrder = 2
      Text = 'localhost'
    end
    object Label3: TLabel
      Left = 252
      Top = 59
      Caption = 'Port:'
    end
    object PortEdit: TEdit
      Left = 288
      Top = 56
      Width = 60
      TabOrder = 3
      Text = '3070'
    end
    object Label5: TLabel
      Left = 424
      Top = 59
      Caption = 'User:'
    end
    object UserEdit: TEdit
      Left = 480
      Top = 56
      Width = 120
      TabOrder = 4
      Text = 'SYSDBA'
    end
    object Label4: TLabel
      Left = 16
      Top = 91
      Caption = 'Database:'
    end
    object DatabaseEdit: TEdit
      Left = 112
      Top = 88
      Width = 236
      TabOrder = 5
      Text = 'crypt_red'
    end
    object Label6: TLabel
      Left = 424
      Top = 91
      Caption = 'Password:'
    end
    object PasswordEdit: TEdit
      Left = 480
      Top = 88
      Width = 272
      TabOrder = 6
      Text = 'masterkey'
      PasswordChar = '*'
    end
    object Label9: TLabel
      Left = 16
      Top = 123
      Caption = 'SQL:'
    end
    object SqlEdit: TEdit
      Left = 112
      Top = 120
      Width = 640
      TabOrder = 7
      Text = 'select * from demo'
    end
  end
  object KeyBox: TGroupBox
    Left = 8
    Top = 175
    Width = 764
    Height = 82
    Caption = 'Key'
    TabOrder = 1
    object Label7: TLabel
      Left = 16
      Top = 28
      Caption = 'Name:'
    end
    object KeyNameEdit: TEdit
      Left = 112
      Top = 24
      Width = 120
      TabOrder = 0
      Text = 'Red'
    end
    object Label8: TLabel
      Left = 252
      Top = 28
      Caption = 'Value:'
    end
    object KeyValueEdit: TEdit
      Left = 288
      Top = 24
      Width = 352
      TabOrder = 1
      PasswordChar = '*'
      TextHint = '0x..,0x..,'
    end
    object ShowKeyCheckBox: TCheckBox
      Left = 652
      Top = 26
      Width = 100
      Caption = 'Show'
      TabOrder = 2
      OnClick = ShowKeyCheckBoxClick
    end
    object UseKeyCheckBox: TCheckBox
      Left = 16
      Top = 56
      Width = 340
      Caption = 'The program sends this key (fbcrypt)'
      Checked = True
      State = cbChecked
      TabOrder = 3
    end
    object LoadKeyButton: TButton
      Left = 380
      Top = 50
      Width = 160
      Height = 25
      Caption = 'Load key file...'
      TabOrder = 4
      OnClick = LoadKeyButtonClick
    end
    object SaveKeyButton: TButton
      Left = 552
      Top = 50
      Width = 200
      Height = 25
      Caption = 'Save as DPAPI protected file...'
      TabOrder = 5
      OnClick = SaveKeyButtonClick
    end
  end
  object ConnectButton: TButton
    Left = 8
    Top = 268
    Width = 100
    Height = 25
    Caption = 'Connect'
    TabOrder = 2
    OnClick = ConnectButtonClick
  end
  object DisconnectButton: TButton
    Left = 116
    Top = 268
    Width = 100
    Height = 25
    Caption = 'Disconnect'
    Enabled = False
    TabOrder = 3
    OnClick = DisconnectButtonClick
  end
  object EncryptButton: TButton
    Left = 260
    Top = 268
    Width = 90
    Height = 25
    Caption = 'Encrypt'
    Enabled = False
    TabOrder = 4
    OnClick = EncryptButtonClick
  end
  object DecryptButton: TButton
    Left = 356
    Top = 268
    Width = 90
    Height = 25
    Caption = 'Decrypt'
    Enabled = False
    TabOrder = 5
    OnClick = DecryptButtonClick
  end
  object ChangeKeyButton: TButton
    Left = 452
    Top = 268
    Width = 100
    Height = 25
    Caption = 'Change key...'
    Enabled = False
    TabOrder = 6
    OnClick = ChangeKeyButtonClick
  end
  object StateLabel: TLabel
    Left = 570
    Top = 272
    Width = 200
    Height = 17
    AutoSize = False
    Caption = 'Not connected'
  end
  object ProgressBar1: TProgressBar
    Left = 8
    Top = 302
    Width = 764
    Height = 17
    TabOrder = 7
  end
  object LogMemo: TMemo
    Left = 8
    Top = 328
    Width = 400
    Height = 226
    ReadOnly = True
    ScrollBars = ssVertical
    TabOrder = 8
  end
  object DemoGrid: TDBGrid
    Left = 420
    Top = 328
    Width = 352
    Height = 226
    DataSource = DataSource1
    TabOrder = 9
  end
  object DataSource1: TDataSource
    Left = 440
    Top = 344
  end
end
