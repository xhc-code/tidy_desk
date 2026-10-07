; Inno Setup 脚本 - 桌面收纳盒 (Tidy Desk) Windows 安装程序
; 使用 Inno Setup 6 (https://jrsoftware.org/isdl.php) 编译

#define MyAppName "桌面收纳盒"
#define MyAppEnglishName "Tidy Desk"
#define MyAppVersion "1.0.0"
#define MyAppPublisher "Tidy Desk Community"
#define MyAppURL "https://github.com/xhc-code/tidy_desk"
#define MyAppExeName "tidy_desk.exe"
#define SourceDir "..\..\build\windows\x64\runner\Release"

[Setup]
; 基础应用信息
AppId={{E6F780A1-3C42-4D95-949B-5A8E58742B28}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
AppPublisherURL={#MyAppURL}
AppSupportURL={#MyAppURL}
AppUpdatesURL={#MyAppURL}
DefaultDirName={autopf}\{#MyAppName}
DisableProgramGroupPage=yes

; 权限与安装模式：支持为所有用户或当前用户安装
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog

; 进程管理：安装与卸载时如果程序正在运行，自动优雅提示关闭
CloseApplications=yes
RestartApplications=no

; 图标与输出设置
SetupIconFile=..\runner\resources\app_icon.ico
OutputDir=..\..\dist
OutputBaseFilename=桌面收纳盒_Setup_v{#MyAppVersion}
Compression=lzma2/ultra64
SolidCompression=yes
WizardStyle=modern
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
UninstallDisplayIcon={app}\{#MyAppExeName}

[Languages]
; 当前阶段锁定为纯中文版（未来扩展国际化时可在此追加其他语言）
Name: "chinesesimplified"; MessagesFile: "compiler:Languages\ChineseSimplified.isl"

[Tasks]
Name: "desktopicon"; Description: "创建桌面快捷方式"; GroupDescription: "附加快捷方式:"
Name: "autostart"; Description: "开机自动启动桌面收纳盒"; GroupDescription: "开机设置:"; Flags: unchecked

[Files]
; 打包 Release 产物目录下的所有文件及子目录 (包含 flutter_windows.dll, data/ 等)
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Registry]
; 开机自启动注册表项 (用户勾选 autostart 任务时自动写入，卸载时自动清理)
Root: HKCU; Subkey: "Software\Microsoft\Windows\CurrentVersion\Run"; ValueType: string; ValueName: "{#MyAppName}"; ValueData: """{app}\{#MyAppExeName}"""; Flags: uninsdeletevalue; Tasks: autostart

[UninstallDelete]
; 卸载时默认彻底清空程序安装目录下的所有临时文件
Type: filesandordirs; Name: "{app}"

[Run]
; 安装完成后启动程序 (使用 runasoriginaluser 避免以管理员提权身份运行导致 UIPI 拖拽失效)
Description: "{cm:LaunchProgram,{#StringChange(MyAppName, '&', '&&')}}"; Filename: "{app}\{#MyAppExeName}"; Flags: nowait postinstall skipifsilent runasoriginaluser

[Code]
// 卸载完成前的交互式用户数据清空询问（保护用户配置与更新平滑性）
procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
begin
  if CurUninstallStep = usPostUninstall then
  begin
    if MsgBox('是否同时清空用户配置文件（包括自定义分类规则、常用加权排序、窗口偏好与运行日志）？' + #13#10 + #13#10 +
              '• 点击【是】：彻底清空所有个人配置，不留任何残留；' + #13#10 +
              '• 点击【否】：保留个人配置（推荐），方便下次重装或更新后继续使用。',
              mbConfirmation, MB_YESNO or MB_DEFBUTTON2) = IDYES then
    begin
      // 深度清空 AppData 中的用户数据
      DelTree(ExpandConstant('{userappdata}\tidy_desk'), True, True, True);
      DelTree(ExpandConstant('{localappdata}\tidy_desk'), True, True, True);
    end;
  end;
end;







