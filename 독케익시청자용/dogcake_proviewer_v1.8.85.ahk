#Requires AutoHotkey v2.0
#SingleInstance Force

; ============================================================
; 치지직 방송 감시 + 타임라인
;
; Ctrl + Alt + C : 종료 예약 취소
; Ctrl + Alt + P : 방송 감시 종료
; Ctrl + Alt + M : 모니터 끄기
; Ctrl + Alt + L : 설정
; Ctrl + Alt + K : 타임라인 메모
; Ctrl + Alt + O : 타임라인 뷰어
; Ctrl + Alt + [ : LoL 조회
;
; ============================================================


; dogcake proviewer v1.8.85
; CSV 자동 백업 + GitHub 자동 업데이트
; ============================================================
; 단축키
; ============================================================

; 단축키는 settings.ini의 사용자 설정에 따라 시작 시 등록한다.


; ============================================================
; 트레이 아이콘
; ============================================================

try
{
    TraySetIcon(
        A_ScriptDir "\dogicon.ico"
    )
}

; 업데이트 메뉴
try
{
    A_TrayMenu.Add("업데이트 확인", CheckForUpdates)
    A_TrayMenu.Add("LoL 조회", ShowLolRankGui)
}
catch
{
}


; ============================================================
; 업데이트 설정
; ============================================================

CurrentVersion := "1.8.85"
UpdateRepo := "midubu/dogcake-proviewer"
UpdateApiUrl := "https://api.github.com/repos/" . UpdateRepo . "/releases/latest"
UpdateUserAgent := "dogcake-proviewer/" . CurrentVersion


; ============================================================
; 사용자 설정
; ============================================================

ChannelID :=
    "b68af124ae2f1743a1dcbf5e2ab41e0b"

; Cloudflare Worker 배포 후 URL을 입력한다. Riot API Key는 이 파일에 저장하지 않는다.
LolWorkerBaseUrl := ""
LolRankSettingsFile := A_ScriptDir "\data\lol_rank.ini"
LolRankCooldownSeconds := 10
LolRankLastRequestTick := 0
LolRankHttp := 0
LolRankRequestStartedTick := 0
LolRankGuiObj := 0
LolRankRiotIdEdit := 0
LolRankStatusText := 0
LolRankNameText := 0
LolRankRankText := 0
LolRankRecordText := 0
LolRankRateText := 0
LolGameStatusText := 0
LolGameNotifyCheckbox := 0
LolMatchPushPID := 0
LolMatchPushRestartTick := 0

DataDir :=
    A_ScriptDir "\data"

LolMatchEventDirectory :=
    DataDir "\lol_match_events"

SettingsFile :=
    DataDir "\settings.ini"

ProtectedAppsFile :=
    DataDir "\protected_apps.ini"

DefaultShutdownEnabled := 1
DefaultShutdownMinutes := 5
DefaultNightStart := "22:30"
DefaultNightEnd := "04:00"
DefaultYoutubeEnabled := 0
DefaultYoutubeTrigger := "똥! ㅋㅋ"
DefaultYoutubeCooldown := 60
DefaultHotkeys := Map(
    "CancelShutdown", "^!c",
    "StopMonitor", "^!p",
    "MonitorOff", "^!m",
    "Settings", "^!l",
    "TimelineMemo", "^!k",
    "TimelineViewer", "^!o",
    "LolRank", "^!SC01A"
)
HotkeyLabels := Map(
    "CancelShutdown", "종료 예약 취소",
    "StopMonitor", "방송 감시 종료",
    "MonitorOff", "모니터 끄기",
    "Settings", "설정 열기",
    "TimelineMemo", "타임라인 메모",
    "TimelineViewer", "타임라인 뷰어",
    "LolRank", "LoL 조회"
)
HotkeyBindings := Map()
ActiveHotkeyInputHook := 0

ShutdownEnabled :=
    DefaultShutdownEnabled

ShutdownMinutes :=
    DefaultShutdownMinutes

NightStart :=
    DefaultNightStart

NightEnd :=
    DefaultNightEnd

YoutubeEnabled :=
    DefaultYoutubeEnabled

YoutubeTrigger :=
    DefaultYoutubeTrigger

YoutubeCooldownMinutes :=
    DefaultYoutubeCooldown

ShutdownDelay :=
    ShutdownMinutes * 60

CheckInterval := 30000
LiveApiRetryDelay := 5000
LiveApiRetryMaxDelay := 60000


; ============================================================
; API 주소
; ============================================================

API_URL :=
    "https://api.chzzk.naver.com/polling/v2/channels/"
    . ChannelID
    . "/live-status"

CHZZK_URL :=
    "https://chzzk.naver.com/live/"
    . ChannelID

; 현재 채널의 VOD만 검색
VIDEO_LIST_BASE_URL :=
    "https://api.chzzk.naver.com/service/v1/channels/"
    . ChannelID
    . "/videos"


; ============================================================
; 타임라인 설정
; ============================================================

TimelineFile :=
    DataDir "\timeline.csv"

CategoryHistoryFile :=
    DataDir "\category_history.csv"

; CSV 백업 폴더
TimelineBackupDir :=
    DataDir "\timeline_backup"

; 같은 자동 처리 과정에서 너무 많은 백업이 생기는 것을 방지
LastTimelineBackupAt := 0
TimelineBackupMaxCount := 100

VodPageSize := 30
VodMaxPages := 20

; VOD 자동 재연결 간격: 10분
VodReconnectInterval := 600000

; 방송 시작시간과 VOD liveOpenDate의 허용 오차
VodTimeTolerance := 180

; 같은 방송의 VOD가 여러 개로 분할될 수 있으므로
; 각 VOD의 duration을 이용해 방송 전체 경과시간을 VOD 내부 시간으로 변환한다.

BroadcastStart := ""
LastBroadcastStart := ""
LastBroadcastEnd := ""
LastStatus := ""
LastLiveStatusCheckTick := 0

ActiveCategorySession := ""
ActiveCategoryId := ""
ActiveCategoryName := ""
ActiveCategoryStart := ""

TimelineViewerLinks :=
    Map()

TimelineViewerRows :=
    Map()

TimelineViewerHoverInfo :=
    Map()

TimelineViewerStatusColors :=
    Map()

SquareCheckboxControls :=
    Map()

TimelineCalendarState :=
    {
        Viewer: 0,
        Month: "",
        SelectedDate: "",
        MonthText: 0,
        DayControls: Map(),
        WeekControls: [],
        CalendarSlots: [],
        SelectionFrame: [],
        List: 0,
        StatusImageList: 0,
        SummaryText: 0,
        SearchEdit: 0,
        HoverRow: -2
    }


; ============================================================
; 보호 앱
; ============================================================

ProtectedApps := []


; ============================================================
; 상태 변수
; ============================================================

PreviousState := ""

ChromeOpened := false

ShutdownScheduled := false
ShutdownTargetTime := 0

YoutubeCooldownUntil := 0

ChatHelperPID := 0

ChatQueueFile :=
    DataDir "\chzzk_chat_queue.txt"

ChatDebugLogFile :=
    DataDir "\youtube_trigger_debug.log"

ChatTriggerConfigFile :=
    DataDir "\chzzk_chat_trigger.txt"

ChatHelperScript :=
    A_ScriptDir "\chzzk_chat.ps1"

ChatStatus := "OFF"


; ============================================================
; Edit subclass 전역 변수
; ============================================================

EditSubclassOldProc := Map()
EditSubclassCallback := 0


; ============================================================
PrepareDataDirectory()
{
    global DataDir

    if !DirExist(DataDir)
        DirCreate(DataDir)

    legacyFiles := [
        "settings.ini",
        "protected_apps.ini",
        "timeline.csv",
        "category_history.csv",
        "chzzk_chat_debug.log",
        "chzzk_chat_trigger.txt",
        "youtube_trigger_debug.log"
    ]

    for fileName in legacyFiles
    {
        oldPath := A_ScriptDir "\" fileName
        newPath := DataDir "\" fileName
        if FileExist(oldPath) && !FileExist(newPath)
        {
            try FileMove(oldPath, newPath, false)
            catch
            {
                try FileCopy(oldPath, newPath, false)
                catch
                {
                }
            }
        }

        ; If both copies exist, keep the active data copy and archive the
        ; root-level legacy copy inside data instead of leaving it beside AHK.
        if FileExist(oldPath) && FileExist(newPath)
        {
            legacyDir := DataDir "\legacy_migration"
            if !DirExist(legacyDir)
                try DirCreate(legacyDir)

            if DirExist(legacyDir)
            {
                archivePath := legacyDir "\" fileName ".legacy_" A_Now
                try FileMove(oldPath, archivePath, false)
                if FileExist(oldPath) && !FileExist(archivePath)
                {
                    try FileCopy(oldPath, archivePath, false)
                    if FileExist(archivePath)
                        try FileDelete(oldPath)
                }
            }
        }
    }

    oldBackupDir := A_ScriptDir "\timeline_backup"
    newBackupDir := DataDir "\timeline_backup"
    if DirExist(oldBackupDir)
    {
        if !DirExist(newBackupDir)
        {
            try DirMove(oldBackupDir, newBackupDir)
            catch
            {
                DirCreate(newBackupDir)
            }
        }

        if DirExist(newBackupDir)
        {
            Loop Files, oldBackupDir "\*.csv", "F"
            {
                target := newBackupDir "\" A_LoopFileName
                if !FileExist(target)
                {
                    try FileCopy(A_LoopFileFullPath, target, false)
                    catch
                    {
                    }
                }
            }
        }
    }
}
; 초기화
; ============================================================

PrepareDataDirectory()
LoadSettings()
RegisterUserHotkeys()
LoadProtectedApps()

StartChatMonitor()
OnExit(StopChatMonitor)
OnExit(StopLolMatchPush)
OnExit(FinalizeBroadcastCategory)

SetTimer(
    PollChatTrigger,
    500
)

A_IconTip :=
    "치지직 방송 감시 | 시작 중..."

SetTimer(
    CheckLiveStatus,
    CheckInterval
)

SetTimer(
    CheckPendingVodMatches,
    VodReconnectInterval
)

CheckLiveStatus()
CheckPendingVodMatches()

; A single Worker-side poll finds completed matches and pushes them over the
; WebSocket. This timer only reads local event files; it makes no network calls.
SetTimer(PollLolMatchPushEvents, 500)
SetTimer(EnsureLolMatchPushConnection, 5000)
RefreshLolGamePollingState()

; 프로그램 시작 후 잠시 기다린 다음 업데이트를 확인한다.
; 네트워크 확인 때문에 프로그램 시작이 지연되지 않도록 비동기로 실행한다.
SetTimer(AutoCheckForUpdates, -5000)


; ============================================================
; GitHub 업데이트
; ============================================================

CheckForUpdates(*)
{
    CheckForUpdatesCore(true)
}


AutoCheckForUpdates(*)
{
    CheckForUpdatesCore(false)
}


CheckForUpdatesCore(ManualCheck := false)
{
    global CurrentVersion
    global UpdateApiUrl
    global UpdateUserAgent

    try
    {
        Http := ComObject("WinHttp.WinHttpRequest.5.1")
        Http.Open("GET", UpdateApiUrl, false)
        Http.SetRequestHeader("User-Agent", UpdateUserAgent)
        Http.SetRequestHeader("Accept", "application/vnd.github+json")
        Http.SetTimeouts(3000, 3000, 5000, 5000)
        Http.Send()

        if (Http.Status != 200)
        {
            if ManualCheck
                MsgBox("GitHub 업데이트 정보를 가져오지 못했습니다.`nHTTP 상태: " . Http.Status, "업데이트 확인", "Icon!")
            return false
        }

        Response := Http.ResponseText
    }
    catch as Err
    {
        ; 시작 시 자동 확인은 조용히 실패한다.
        ; 사용자가 메뉴에서 직접 확인한 경우에만 오류를 표시한다.
        if ManualCheck
            MsgBox("업데이트 확인에 실패했습니다.`n`n" . Err.Message, "업데이트 확인", "Icon!")
        return false
    }

    if !RegExMatch(Response, '"tag_name"\s*:\s*"([^"\\]+)"', &TagMatch)
    {
        if ManualCheck
            MsgBox("GitHub Release 버전을 확인하지 못했습니다.", "업데이트 확인", "Icon!")
        return false
    }

    LatestVersion := TagMatch[1]
    if (SubStr(LatestVersion, 1, 1) = "v")
        LatestVersion := SubStr(LatestVersion, 2)

    if !(VerCompare(LatestVersion, CurrentVersion) > 0)
    {
        if (VerCompare(LatestVersion, CurrentVersion) = 0)
            RefreshChatHelper(LatestVersion, Response, ManualCheck)

        if ManualCheck
            MsgBox("현재 최신 버전입니다.`n`n현재 버전: v" . CurrentVersion, "업데이트 확인", "Iconi")
        return true
    }

    ; Release Asset은 이름/업로드 상태에 따라 404가 날 수 있으므로
    ; 우선 Asset URL을 찾고, 실제 다운로드 단계에서 실패하면
    ; 해당 태그의 raw 파일 URL로 자동 재시도한다.
    DownloadUrl := ""
    HelperDownloadUrl := ""
    if RegExMatch(Response, '"browser_download_url"\s*:\s*"([^"]+\.ahk)"', &AssetMatch)
        DownloadUrl := AssetMatch[1]
    if RegExMatch(Response, '"browser_download_url"\s*:\s*"([^"]+\.ps1)"', &HelperAssetMatch)
        HelperDownloadUrl := HelperAssetMatch[1]

    Result := MsgBox(
        "새 버전이 있습니다.`n`n"
        . "현재 버전: v" . CurrentVersion . "`n"
        . "최신 버전: v" . LatestVersion . "`n`n"
        . "지금 업데이트할까요?",
        "dogcake proviewer 업데이트",
        "YesNo Iconi"
    )

    if (Result != "Yes")
        return true

    return StartSelfUpdate(DownloadUrl, HelperDownloadUrl, LatestVersion)
}


StartSelfUpdate(DownloadUrl, HelperDownloadUrl, LatestVersion)
{
    global CurrentVersion

    TempBase := A_Temp "\\dogcake_proviewer_update_" A_TickCount
    TempFile := TempBase ".ahk"
    TempHelperFile := TempBase ".ps1"
    HelperTargetFile := A_ScriptDir . "\chzzk_chat.ps1"
    UpdaterFile := TempBase "_updater.ahk"

    RawUrl := "https://raw.githubusercontent.com/midubu/dogcake-proviewer/v"
        . LatestVersion
        . "/dogcake_proviewer_v"
        . LatestVersion
        . ".ahk"

    HelperRawUrl := "https://raw.githubusercontent.com/midubu/dogcake-proviewer/v"
        . LatestVersion
        . "/chzzk_chat.ps1"

    Downloaded := false
    FirstError := ""

    ; 1차: GitHub Release Asset
    if (DownloadUrl != "")
    {
        try
        {
            DownloadFileFromUrl(DownloadUrl, TempFile)
            Downloaded := ValidateDownloadedAhk(TempFile, LatestVersion)
            if !Downloaded
                try FileDelete(TempFile)
        }
        catch as Err
        {
            FirstError := Err.Message
            try FileDelete(TempFile)
        }
    }

    ; 2차: 해당 Release tag의 raw 파일
    if !Downloaded
    {
        try
        {
            DownloadFileFromUrl(RawUrl, TempFile)
            Downloaded := ValidateDownloadedAhk(TempFile, LatestVersion)
            if !Downloaded
                try FileDelete(TempFile)
        }
        catch as Err
        {
            SecondError := Err.Message
            try FileDelete(TempFile)
        }
    }

    if !Downloaded
    {
        Detail := "업데이트 파일을 다운로드하지 못했습니다."
        if (FirstError != "")
            Detail .= Chr(10) . Chr(10) . "Release Asset: " . FirstError
        if IsSet(SecondError) && (SecondError != "")
            Detail .= Chr(10) . "Raw 파일: " . SecondError

        MsgBox(Detail, "업데이트 실패", "Icon!")
        return false
    }

    ; The .ps1 release asset is optional. Keep an installed helper unless the release includes one.
    HelperDownloaded := false
    NeedCreateHelper := !FileExist(HelperTargetFile)
    UpdateHelper := (HelperDownloadUrl != "" || NeedCreateHelper)
    if (HelperDownloadUrl != "")
    {
        try
        {
            DownloadFileFromUrl(HelperDownloadUrl, TempHelperFile)
            HelperDownloaded := ValidateDownloadedPs1(TempHelperFile)
            if !HelperDownloaded
                try FileDelete(TempHelperFile)
        }
        catch as Err
        {
            HelperDownloadError := Err.Message
            try FileDelete(TempHelperFile)
        }
        if !HelperDownloaded
        {
            Detail := "릴리스에 포함된 채팅 helper를 확인하지 못해 업데이트를 중단했습니다."
            if IsSet(HelperDownloadError) && (HelperDownloadError != "")
                Detail .= Chr(10) . Chr(10) . HelperDownloadError
            try FileDelete(TempFile)
            MsgBox(Detail, "업데이트 실패", "Icon!")
            return false
        }
    }
    if (!HelperDownloaded && NeedCreateHelper)
    {
        try
        {
            DownloadFileFromUrl(HelperRawUrl, TempHelperFile)
            HelperDownloaded := ValidateDownloadedPs1(TempHelperFile)
            if !HelperDownloaded
                try FileDelete(TempHelperFile)
        }
        catch as Err
        {
            HelperDownloadError := Err.Message
            try FileDelete(TempHelperFile)
        }
    }

    if (UpdateHelper && !HelperDownloaded)
    {
        Detail := "필요한 채팅 helper를 다운로드하지 못해 업데이트를 중단했습니다."
        if IsSet(HelperDownloadError) && (HelperDownloadError != "")
            Detail .= Chr(10) . Chr(10) . HelperDownloadError
        try FileDelete(TempFile)
        MsgBox(Detail, "업데이트 실패", "Icon!")
        return false
    }

    if !FileExist(TempFile)
    {
        MsgBox("업데이트 파일을 다운로드하지 못했습니다.", "업데이트 실패", "Icon!")
        return false
    }

    try
    {
        FileSize := FileGetSize(TempFile)
        if (FileSize < 10000)
        {
            FileDelete(TempFile)
            MsgBox("다운로드한 업데이트 파일의 크기가 비정상적입니다.", "업데이트 실패", "Icon!")
            return false
        }
    }
    catch as Err
    {
        try FileDelete(TempFile)
        MsgBox("다운로드한 업데이트 파일을 확인하지 못했습니다.`n`n" . Err.Message, "업데이트 실패", "Icon!")
        return false
    }

    OldTargetFile := A_ScriptFullPath
    NewTargetFile := A_ScriptDir . "\dogcake_proviewer_v" . LatestVersion . ".ahk"
    HelperBackupFile := TempBase . ".ps1.bak"
    AppDir := A_ScriptDir
    AHKExe := A_ScriptDir . "\AutoHotkey64.exe"
    if !FileExist(AHKExe)
        AHKExe := A_AhkPath
    CurrentPID := DllCall("GetCurrentProcessId")
    StartupDir := A_Startup
    ShortcutFile := StartupDir . "\독케익시청자용.lnk"
    IconFile := AppDir . "\\dogicon.ico"

    QTemp := UpdaterQuote(TempFile)
    QHelperTemp := UpdaterQuote(TempHelperFile)
    QHelperTarget := UpdaterQuote(HelperTargetFile)
    QHelperBackup := UpdaterQuote(HelperBackupFile)
    QOld := UpdaterQuote(OldTargetFile)
    QNew := UpdaterQuote(NewTargetFile)
    QApp := UpdaterQuote(AppDir)
    QExe := UpdaterQuote(AHKExe)
    QStartup := UpdaterQuote(StartupDir)
    QShortcut := UpdaterQuote(ShortcutFile)
    QIcon := UpdaterQuote(IconFile)
    QSelf := UpdaterQuote(UpdaterFile)

    UpdaterScript :=
        '#Requires AutoHotkey v2.0`r`n'
        . '#SingleInstance Force`r`n`r`n'
        . 'source := ' . QTemp . '`r`n'
        . 'updateHelper := ' . (UpdateHelper ? 'true' : 'false') . '`r`n'
        . 'helperSource := ' . QHelperTemp . '`r`n'
        . 'helperTarget := ' . QHelperTarget . '`r`n'
        . 'helperBackup := ' . QHelperBackup . '`r`n'
        . 'oldTarget := ' . QOld . '`r`n'
        . 'newTarget := ' . QNew . '`r`n'
        . 'appDir := ' . QApp . '`r`n'
        . 'ahkExe := ' . QExe . '`r`n'
        . 'startupDir := ' . QStartup . '`r`n'
        . 'shortcutFile := ' . QShortcut . '`r`n'
        . 'iconFile := ' . QIcon . '`r`n'
        . 'selfFile := ' . QSelf . '`r`n'
        . 'processId := ' . CurrentPID . '`r`n`r`n'
        . 'UpdaterQuote(Text)`r`n'
        . '{`r`n'
        . '    return Chr(34) . StrReplace(Text, Chr(34), Chr(34) . Chr(34)) . Chr(34)`r`n'
        . '}`r`n`r`n'
        . 'try`r`n'
        . '{`r`n'
        . '    Loop 120`r`n'
        . '    {`r`n'
        . '        if !ProcessExist(processId)`r`n'
        . '            break`r`n'
        . '        Sleep(500)`r`n'
        . '    }`r`n`r`n'
        . '    if ProcessExist(processId)`r`n'
        . '        throw Error("기존 프로그램이 종료되지 않았습니다.")`r`n`r`n'
        . '    if !DirExist(appDir)`r`n'
        . '        throw Error("프로그램 폴더를 찾을 수 없습니다. " . appDir)`r`n`r`n'
        . '    hadHelper := false`r`n'
        . '    if updateHelper`r`n'
        . '    {`r`n'
        . '        if !FileExist(helperSource)`r`n'
        . '            throw Error("새 채팅 helper 파일을 찾을 수 없습니다.")`r`n'
        . '        hadHelper := FileExist(helperTarget)`r`n'
        . '        if hadHelper`r`n'
        . '            FileCopy(helperTarget, helperBackup, true)`r`n'
        . '        FileMove(helperSource, helperTarget, true)`r`n'
        . '        if !FileExist(helperTarget)`r`n'
        . '            throw Error("새 채팅 helper 설치에 실패했습니다.")`r`n'
        . '    }`r`n`r`n'
        . '    if FileExist(newTarget)`r`n'
        . '        FileDelete(newTarget)`r`n`r`n'
        . '    try`r`n'
        . '        FileMove(source, newTarget, true)`r`n'
        . '    catch as installErr`r`n'
        . '    {`r`n'
        . '        if updateHelper && hadHelper && FileExist(helperBackup)`r`n'
        . '            FileCopy(helperBackup, helperTarget, true)`r`n'
        . '        throw installErr`r`n'
        . '    }`r`n`r`n'
        . '    if !FileExist(newTarget)`r`n'
        . '        throw Error("새 버전 파일 생성에 실패했습니다.")`r`n`r`n'
        . '    if !DirExist(startupDir)`r`n'
        . '        DirCreate(startupDir)`r`n`r`n'
        . '    if FileExist(shortcutFile)`r`n'
        . '        try FileDelete(shortcutFile)`r`n`r`n'
        . '    Loop Files, startupDir . "\독케익시청자용v*.lnk", "F"`r`n'
        . '    {`r`n'
        . '        try FileDelete(A_LoopFileFullPath)`r`n'
        . '    }`r`n`r`n'
        . '    if !FileExist(ahkExe)`r`n'
        . '        throw Error("AutoHotkey64.exe를 찾을 수 없습니다. " . ahkExe)`r`n`r`n'
        . '    shell := ComObject("WScript.Shell")`r`n'
        . '    link := shell.CreateShortcut(shortcutFile)`r`n'
        . '    link.TargetPath := ahkExe`r`n'
        . '    link.Arguments := Chr(34) . newTarget . Chr(34)`r`n'
        . '    link.WorkingDirectory := appDir`r`n'
        . '    if FileExist(iconFile)`r`n'
        . '        link.IconLocation := iconFile`r`n'
        . '    else`r`n'
        . '        link.IconLocation := ahkExe`r`n'
        . '    link.Save()`r`n`r`n'
        . '    if !FileExist(shortcutFile)`r`n'
        . '        throw Error("시작프로그램 바로가기 생성에 실패했습니다.")`r`n`r`n'
        . '    if (oldTarget != newTarget) && FileExist(oldTarget)`r`n'
        . '        try FileDelete(oldTarget)`r`n`r`n'
        . '    if updateHelper && FileExist(helperBackup)`r`n'
        . '        try FileDelete(helperBackup)`r`n`r`n'
        . '    Run(UpdaterQuote(ahkExe) . " " . UpdaterQuote(newTarget), appDir)`r`n'
        . '    Sleep(1000)`r`n'
        . '    try FileDelete(selfFile)`r`n'
        . '    ExitApp()`r`n'
        . '}`r`n'
        . 'catch as Err`r`n'
        . '{`r`n'
        . '    if updateHelper && FileExist(helperBackup)`r`n'
        . '        try FileCopy(helperBackup, helperTarget, true)`r`n`r`n'
        . '    MsgBox("업데이트에 실패했습니다." . Chr(10) . Chr(10) . Err.Message . Chr(10) . Chr(10) . "업데이트 도우미: " . selfFile, "dogcake proviewer 업데이트 실패", "Icon!")`r`n'
        . '    ExitApp(1)`r`n'
        . '}`r`n'

    try
    {
        FileAppend(UpdaterScript, UpdaterFile, "UTF-8")

        if !FileExist(UpdaterFile)
            throw Error("업데이트 도우미 파일을 만들지 못했습니다.")

        Run(UpdaterQuote(AHKExe) . " " . UpdaterQuote(UpdaterFile), AppDir)

        ToolTip(
            "🔄 v" . LatestVersion . " 업데이트를 준비했습니다.`n"
            . "프로그램을 종료한 후 자동으로 교체·재실행합니다."
        )
        SetTimer(ClearTimelineToolTip, -3000)

        Sleep(500)
        ExitApp()
    }
    catch as Err
    {
        try FileDelete(TempFile)
        try FileDelete(TempHelperFile)
        try FileDelete(UpdaterFile)

        MsgBox(
            "업데이트를 시작하지 못했습니다.`n`n"
            . Err.Message,
            "업데이트 실패",
            "Icon!"
        )
        return false
    }
}



RefreshChatHelper(LatestVersion, ReleaseResponse, ManualCheck := false)
{
    global ChatHelperScript

    HelperUrl := ""
    if RegExMatch(ReleaseResponse, '"browser_download_url"\s*:\s*"([^"]+\.ps1)"', &HelperAssetMatch)
        HelperUrl := HelperAssetMatch[1]

    RawUrl := "https://raw.githubusercontent.com/midubu/dogcake-proviewer/v"
        . LatestVersion
        . "/chzzk_chat.ps1"
    TempHelper := A_Temp . "\dogcake_helper_refresh_" . A_TickCount . ".ps1"
    Downloaded := false
    NeedCreateHelper := !FileExist(ChatHelperScript)

    if (HelperUrl = "" && !NeedCreateHelper)
        return true

    if (HelperUrl != "")
    {
        try
        {
            DownloadFileFromUrl(HelperUrl, TempHelper)
            Downloaded := ValidateDownloadedPs1(TempHelper)
            if !Downloaded
                try FileDelete(TempHelper)
        }
        catch
        {
            try FileDelete(TempHelper)
        }
    }

    if (!Downloaded && (HelperUrl != "" || NeedCreateHelper))
    {
        try
        {
            DownloadFileFromUrl(RawUrl, TempHelper)
            Downloaded := ValidateDownloadedPs1(TempHelper)
            if !Downloaded
                try FileDelete(TempHelper)
        }
        catch
        {
            try FileDelete(TempHelper)
        }
    }

    if !Downloaded
        return false

    BackupHelper := TempHelper . ".bak"
    HadHelper := FileExist(ChatHelperScript)
    try
    {
        if FileExist(ChatHelperScript)
        {
            ExistingContent := FileRead(ChatHelperScript, "UTF-8")
            DownloadedContent := FileRead(TempHelper, "UTF-8")
            if (ExistingContent = DownloadedContent)
            {
                FileDelete(TempHelper)
                return true
            }
        }

        if HadHelper
            FileCopy(ChatHelperScript, BackupHelper, true)

        StopChatMonitor()
        StopLolMatchPush()
        FileMove(TempHelper, ChatHelperScript, true)
        if !FileExist(ChatHelperScript)
            throw Error("채팅 helper 파일 교체에 실패했습니다.")

        StartChatMonitor()
        RefreshLolGamePollingState()
        if FileExist(BackupHelper)
            FileDelete(BackupHelper)

        if ManualCheck
            TrayTip("보조 파일 업데이트", "채팅 helper를 최신 버전으로 교체했습니다.", 2)
        return true
    }
    catch as Err
    {
        if FileExist(BackupHelper)
            try FileCopy(BackupHelper, ChatHelperScript, true)
        if HadHelper
        {
            StartChatMonitor()
            RefreshLolGamePollingState()
        }
        try FileDelete(TempHelper)
        try FileDelete(BackupHelper)
        if ManualCheck
            MsgBox("채팅 helper 갱신에 실패했습니다.`n`n" . Err.Message, "업데이트 오류", "Icon!")
        return false
    }
}


UpdaterQuote(Text)
{
    return '"' . StrReplace(Text, '"', '""') . '"'
}


ValidateDownloadedAhk(FilePath, LatestVersion)
{
    if !FileExist(FilePath)
        return false

    try
    {
        Content := FileRead(FilePath, "UTF-8")
    }
    catch
    {
        try Content := FileRead(FilePath, "CP949")
        catch
            return false
    }

    if !InStr(Content, "#Requires AutoHotkey v2.0")
        return false

    VersionNeedle := "CurrentVersion := " . Chr(34) . LatestVersion . Chr(34)
    if !InStr(Content, VersionNeedle)
        return false

    return true
}


ValidateDownloadedPs1(FilePath)
{
    if !FileExist(FilePath)
        return false

    try
    {
        if (FileGetSize(FilePath) < 1000)
            return false

        Content := FileRead(FilePath, "UTF-8")
    }
    catch
    {
        return false
    }

    return (
        InStr(Content, "[string]$ChannelId")
        && InStr(Content, "[string]$TriggerFile")
        && InStr(Content, "[string]$TriggerConfigFile")
        && InStr(Content, "function Write-Trace")
    )
}

DownloadFileFromUrl(Url, FilePath)
{
    Http := ComObject("WinHttp.WinHttpRequest.5.1")
    Http.Open("GET", Url, false)
    Http.SetRequestHeader("User-Agent", "dogcake-proviewer-updater")
    Http.SetRequestHeader("Accept", "application/octet-stream")
    Http.SetTimeouts(5000, 5000, 15000, 15000)
    Http.Send()

    if (Http.Status != 200)
        throw Error("HTTP 상태 코드 " . Http.Status)

    Stream := ComObject("ADODB.Stream")
    Stream.Type := 1
    Stream.Open()
    Stream.Write(Http.ResponseBody)
    Stream.SaveToFile(FilePath, 2)
    Stream.Close()
}


PowerShellQuote(Text)
{
    return "'" . StrReplace(Text, "'", "''") . "'"
}


; ============================================================
; 야간 보호 시간 확인
; ============================================================

IsNightTime()
{
    global NightStart
    global NightEnd

    start :=
        TimeToMinutes(
            NightStart
        )

    end :=
        TimeToMinutes(
            NightEnd
        )

    current :=
        A_Hour * 60
        + A_Min

    if (start = end)
        return false

    if (start < end)
    {
        return (
            current >= start
            && current < end
        )
    }

    return (
        current >= start
        || current < end
    )
}


; ============================================================
; 시간 → 분
; ============================================================

TimeToMinutes(timeText)
{
    parts :=
        StrSplit(
            Trim(timeText),
            ":"
        )

    if (parts.Length != 2)
        return 0

    hour :=
        parts[1] + 0

    minute :=
        parts[2] + 0

    if (
        hour < 0
        || hour > 23
        || minute < 0
        || minute > 59
    )
        return 0

    return (
        hour * 60
        + minute
    )
}


; ============================================================
; 시 유효성
; ============================================================

IsValidHour(value)
{
    try
        n := Integer(value)
    catch
        return false

    return (
        n >= 0
        && n <= 23
    )
}


; ============================================================
; 분 유효성
; ============================================================

IsValidMinute(value)
{
    try
        n := Integer(value)
    catch
        return false

    return (
        n >= 0
        && n <= 59
    )
}


; ============================================================
; 시간 형식 확인
; ============================================================

IsValidTime(timeText)
{
    parts :=
        StrSplit(
            Trim(timeText),
            ":"
        )

    if (parts.Length != 2)
        return false

    hour :=
        parts[1] + 0

    minute :=
        parts[2] + 0

    return (
        hour >= 0
        && hour <= 23
        && minute >= 0
        && minute <= 59
    )
}


; ============================================================
; 방송 상태 확인
;
; 방송 감시 + 타임라인 방송 시작시간 기록
; ============================================================

CheckLiveStatus()
{
    global API_URL
    global CHZZK_URL

    global PreviousState
    global ChromeOpened

    global ShutdownEnabled

    global ShutdownScheduled
    global ShutdownTargetTime
    global ShutdownDelay
    global ShutdownMinutes

    global BroadcastStart
    global LastStatus
    global LastLiveStatusCheckTick

    global A_IconTip


    ; ========================================================
    ; 야간 보호 중이면 종료 예약 취소
    ; ========================================================

    if IsNightTime() && ShutdownScheduled
    {
        CancelShutdownReservation(false)

        TrayTip(
            "야간 종료 보호",
            "야간 보호 시간에 들어가 컴퓨터 종료 예약을 취소했습니다.",
            1
        )
    }


    ; ========================================================
    ; 보호 앱이 실행 중이면 종료 예약 취소
    ; ========================================================

    if (
        ShutdownScheduled
        && IsAnyProtectedAppRunning()
    )
    {
        CancelShutdownReservation(false)

        TrayTip(
            "종료 보호",
            "보호 앱이 실행 중이라 컴퓨터 종료 예약을 취소했습니다.",
            1
        )
    }


    ; ========================================================
    ; API 요청
    ; ========================================================

    try
    {
        http :=
            ComObject(
                "WinHttp.WinHttpRequest.5.1"
            )

        http.Open(
            "GET",
            API_URL,
            false
        )

        http.SetRequestHeader(
            "User-Agent",
            "Mozilla/5.0"
        )

        http.SetRequestHeader(
            "Accept",
            "application/json"
        )

        http.SetTimeouts(3000, 3000, 5000, 5000)
        http.Send()

        if (http.Status != 200)
        {
            A_IconTip :=
                "치지직 방송 감시 | API 오류 (자동 재시도 중)"

            ScheduleLiveApiRetry()
            return
        }

        response :=
            http.ResponseText


        ; ====================================================
        ; 방송 상태
        ; ====================================================

        if InStr(
            response,
            '"status":"OPEN"'
        )
        {
            CurrentState := "OPEN"
        }
        else if InStr(
            response,
            '"status":"CLOSE"'
        )
        {
            CurrentState := "CLOSE"
        }
        else
        {
            A_IconTip :=
                "치지직 방송 감시 | 상태 확인 실패 (자동 재시도 중)"

            ScheduleLiveApiRetry()
            return
        }

        ResetLiveApiRetry()
        LastLiveStatusCheckTick := A_TickCount
        RefreshLolGamePollingState(CurrentState)

        CategoryId := GetJsonStringField(response, "liveCategory")
        CategoryName := GetJsonStringField(response, "liveCategoryValue")

        ; ====================================================
        ; 방송 시작시간 추출
        ; ====================================================

        OpenDate := ""

        if RegExMatch(
            response,
            '"openDate"\s*:\s*"([^"]+)"',
            &OpenMatch
        )
        {
            OpenDate :=
                OpenMatch[1]
        }

        ParsedDate := ""

        if (OpenDate != "")
        {
            ParsedDate :=
                ParseChzzkDate(
                    OpenDate
                )
        }


        ; ====================================================
        ; 최초 실행
        ; ====================================================

        if (PreviousState = "")
        {
            PreviousState :=
                CurrentState

            if (CurrentState = "OPEN")
            {
                if (ParsedDate != "")
                {
                    BroadcastStart :=
                        ParsedDate

                    LastBroadcastStart :=
                        ParsedDate
                }

                LastStatus :=
                    "OPEN"

                TrackBroadcastCategory(
                    "OPEN",
                    BroadcastStart != "" ? BroadcastStart : ParsedDate,
                    CategoryId,
                    CategoryName
                )

                Run(
                    CHZZK_URL
                )

                ChromeOpened := true
            }
            else
            {
                BroadcastStart := ""
                LastStatus := "CLOSE"
            }

            UpdateTrayStatus(
                CurrentState
            )

            return
        }


        ; ====================================================
        ; CLOSE → OPEN
        ; 방송 재개
        ; ========================================================

        if (
            PreviousState = "CLOSE"
            && CurrentState = "OPEN"
        )
        {
            ; ==================================================
            ; 2시간 이내 재방송 판정
            ;
            ; OFF → ON 사이가 2시간 이내라면
            ; 새로운 방송으로 만들지 않고 기존 방송의
            ; 최초 시작시간을 그대로 유지한다.
            ;
            ; 2시간을 초과하면 현재 VOD/live 상태의
            ; 시작시간을 새로운 방송 시작시간으로 사용한다.
            ; ==================================================

            ReconnectGapSeconds := -1

            if (
                LastBroadcastEnd != ""
                && ParsedDate != ""
            )
            {
                try
                {
                    ReconnectGapSeconds :=
                        DateDiff(
                            LastBroadcastEnd,
                            ParsedDate,
                            "Seconds"
                        )
                }
                catch
                {
                    ReconnectGapSeconds := -1
                }
            }

            if (
                ReconnectGapSeconds >= 0
                && ReconnectGapSeconds <= 7200
                && LastBroadcastStart != ""
            )
            {
                ; 2시간 이내 재방송 → 기존 방송일 유지
                BroadcastStart :=
                    LastBroadcastStart
            }
            else if (ParsedDate != "")
            {
                ; 2시간 초과 → 현재 방송을 새로운 세션으로 시작
                BroadcastStart :=
                    ParsedDate

                LastBroadcastStart :=
                    ParsedDate
            }
            else
            {
                BroadcastStart :=
                    ""
            }

            LastStatus :=
                "OPEN"


            ; ==================================================
            ; 종료 예약 취소
            ; ==================================================

            if ShutdownScheduled
            {
                CancelShutdownReservation(false)

                TrayTip(
                    "치지직 방송 재개",
                    "방송이 다시 시작되어 컴퓨터 종료 예약을 취소했습니다.",
                    1
                )
            }


            ; ==================================================
            ; 치지직 방송 열기
            ; ==================================================

            if !ChromeOpened
            {
                Run(
                    CHZZK_URL
                )

                ChromeOpened := true

                TrayTip(
                    "치지직 방송 시작",
                    "방송이 시작되었습니다. 기본 브라우저를 열었습니다.",
                    1
                )
            }

            UpdateTrayStatus(
                CurrentState
            )
        }


        ; ========================================================
        ; 방송 중 계속 OPEN
        ; ========================================================

        if (CurrentState = "OPEN")
        {
            if (BroadcastStart = "")
            {
                if (ParsedDate != "")
                    BroadcastStart :=
                        ParsedDate
            }

            LastStatus :=
                "OPEN"
        }


        ; ========================================================
        ; OPEN → CLOSE
        ; 방송 종료
        ; ========================================================

        if (
            PreviousState = "OPEN"
            && CurrentState = "CLOSE"
        )
        {
            ChromeOpened := false

            ; 재방송 판정을 위해 마지막 방송 세션의
            ; 시작시간과 종료 감지시간을 보존한다.
            if (BroadcastStart != "")
                LastBroadcastStart :=
                    BroadcastStart

            LastBroadcastEnd :=
                A_Now

            TrackBroadcastCategory(
                "CLOSE",
                BroadcastStart,
                "",
                ""
            )

            BroadcastStart := ""
            LastStatus := "CLOSE"


            ; ==================================================
            ; 야간 보호
            ; ==================================================

            if IsNightTime()
            {
                TrayTip(
                    "치지직 방송 종료",
                    "방송이 종료되었습니다. 야간 보호 시간이라 컴퓨터를 종료하지 않습니다.",
                    1
                )

                PreviousState :=
                    CurrentState

                UpdateTrayStatus(
                    CurrentState
                )

                return
            }


            ; ==================================================
            ; 보호 앱
            ; ==================================================

            if IsAnyProtectedAppRunning()
            {
                TrayTip(
                    "치지직 방송 종료",
                    "방송이 종료되었습니다. 보호 앱이 실행 중이라 컴퓨터를 종료하지 않습니다.",
                    1
                )

                PreviousState :=
                    CurrentState

                UpdateTrayStatus(
                    CurrentState
                )

                return
            }


            ; ==================================================
            ; 방송 종료 기능 OFF
            ; ==================================================

            if !ShutdownEnabled
            {
                if ShutdownScheduled
                    CancelShutdownReservation(false)

                TrayTip(
                    "치지직 방송 종료",
                    "방송이 종료되었지만 방송 종료 기능이 꺼져 있어 컴퓨터를 종료하지 않습니다.",
                    1
                )

                PreviousState :=
                    CurrentState

                UpdateTrayStatus(
                    CurrentState
                )

                return
            }


            ; ==================================================
            ; 종료 예약
            ; ==================================================

            ShutdownTargetTime :=
                A_TickCount
                + (
                    ShutdownDelay
                    * 1000
                )

            ShutdownScheduled := true


            TrayTip(
                "치지직 방송 종료",
                "방송 종료가 감지되었습니다.`n"
                . ShutdownMinutes
                . "분 후 컴퓨터가 종료됩니다.",
                1
            )


            ; ==================================================
            ; 정확히 종료 60초 전에 알림
            ; ==================================================

            WarningDelay :=
                (
                    ShutdownTargetTime
                    - A_TickCount
                )
                - 60000

            if (WarningDelay <= 0)
            {
                SetTimer(
                    ShutdownWarning,
                    -1
                )
            }
            else
            {
                SetTimer(
                    ShutdownWarning,
                    -WarningDelay
                )
            }


            ; ==================================================
            ; 실제 종료 예약
            ; ==================================================

            SetTimer(
                ShutdownPC,
                -(
                    ShutdownDelay
                    * 1000
                )
            )

            UpdateTrayStatus(
                CurrentState
            )
        }


        if (CurrentState = "OPEN")
        {
            TrackBroadcastCategory(
                "OPEN",
                BroadcastStart != "" ? BroadcastStart : ParsedDate,
                CategoryId,
                CategoryName
            )
        }

        PreviousState :=
            CurrentState

        UpdateTrayStatus(
            CurrentState
        )
    }
    catch
    {
        A_IconTip :=
            "치지직 방송 감시 | API 연결 오류 (자동 재시도 중)"

        ScheduleLiveApiRetry()
        return
    }
}


ScheduleLiveApiRetry()
{
    global LiveApiRetryDelay
    global LiveApiRetryMaxDelay

    SetTimer(CheckLiveStatus, -LiveApiRetryDelay)
    LiveApiRetryDelay := Min(LiveApiRetryDelay * 2, LiveApiRetryMaxDelay)
}


ResetLiveApiRetry()
{
    global LiveApiRetryDelay
    global CheckInterval

    LiveApiRetryDelay := 5000
    SetTimer(CheckLiveStatus, CheckInterval)
}


GetJsonStringField(Response, FieldName)
{
    Pattern :=
        '"' . FieldName . '"\s*:\s*"((?:\\.|[^"\\])*)"'

    if !RegExMatch(Response, Pattern, &Match)
        return ""

    Value := Match[1]
    Value := StrReplace(Value, Chr(92) . Chr(92), Chr(92))
    Value := StrReplace(Value, Chr(92) . Chr(34), Chr(34))
    Value := StrReplace(Value, Chr(92) . "n", " ")
    Value := StrReplace(Value, Chr(92) . "r", " ")
    Value := StrReplace(Value, Chr(92) . "t", " ")

    return Value
}


TrackBroadcastCategory(State, SessionStart, CategoryId, CategoryName)
{
    global ActiveCategorySession
    global ActiveCategoryId
    global ActiveCategoryName
    global ActiveCategoryStart

    if (State = "CLOSE")
    {
        FinalizeBroadcastCategory()
        return
    }

    if (CategoryName = "")
        CategoryName := "카테고리 미설정"

    if (SessionStart = "")
        SessionStart := A_Now

    Now := A_Now

    if (ActiveCategoryStart = "")
    {
        ActiveCategorySession := SessionStart
        ActiveCategoryId := CategoryId
        ActiveCategoryName := CategoryName
        ActiveCategoryStart := Now

        RecordCategoryTransition(
            SessionStart,
            Now,
            "",
            "",
            CategoryId,
            CategoryName,
            ""
        )
        return
    }

    if (ActiveCategorySession != SessionStart)
        FinalizeBroadcastCategory()

    if (ActiveCategoryStart = "")
    {
        ActiveCategorySession := SessionStart
        ActiveCategoryId := CategoryId
        ActiveCategoryName := CategoryName
        ActiveCategoryStart := Now

        RecordCategoryTransition(
            SessionStart,
            Now,
            "",
            "",
            CategoryId,
            CategoryName,
            ""
        )
        return
    }

    if (
        ActiveCategoryId = CategoryId
        && ActiveCategoryName = CategoryName
    )
        return

    try
    {
        DurationSeconds := DateDiff(
            Now,
            ActiveCategoryStart,
            "Seconds"
        )
    }
    catch
    {
        DurationSeconds := 0
    }

    RecordCategoryTransition(
        ActiveCategorySession,
        Now,
        ActiveCategoryId,
        ActiveCategoryName,
        CategoryId,
        CategoryName,
        DurationSeconds
    )

    ActiveCategorySession := SessionStart
    ActiveCategoryId := CategoryId
    ActiveCategoryName := CategoryName
    ActiveCategoryStart := Now
}


FinalizeBroadcastCategory(ExitReason := "", ExitCode := 0)
{
    global ActiveCategorySession
    global ActiveCategoryId
    global ActiveCategoryName
    global ActiveCategoryStart

    if (ActiveCategoryStart = "")
        return

    Now := A_Now

    try
    {
        DurationSeconds := DateDiff(
            Now,
            ActiveCategoryStart,
            "Seconds"
        )
    }
    catch
    {
        DurationSeconds := 0
    }

    RecordCategoryTransition(
        ActiveCategorySession,
        Now,
        ActiveCategoryId,
        ActiveCategoryName,
        "",
        "",
        DurationSeconds
    )

    ActiveCategorySession := ""
    ActiveCategoryId := ""
    ActiveCategoryName := ""
    ActiveCategoryStart := ""
}


RecordCategoryTransition(
    SessionStart,
    ChangeTime,
    PreviousCategoryId,
    PreviousCategoryName,
    NewCategoryId,
    NewCategoryName,
    DurationSeconds
)
{
    global CategoryHistoryFile

    try
    {
        if !FileExist(CategoryHistoryFile)
        {
            FileAppend(
                "방송시작,변경확인시각,이전카테고리ID,이전카테고리,새카테고리ID,새카테고리,이전카테고리시간(초),이전카테고리시간`r`n",
                CategoryHistoryFile,
                "UTF-8"
            )
        }

        DurationText :=
            DurationSeconds = ""
            ? ""
            : FormatElapsed(DurationSeconds)

        Fields := [
            FormatSessionDate(SessionStart),
            FormatSessionDate(ChangeTime),
            PreviousCategoryId,
            PreviousCategoryName,
            NewCategoryId,
            NewCategoryName,
            DurationSeconds,
            DurationText
        ]

        FileAppend(
            BuildCsvLine(Fields) . "`r`n",
            CategoryHistoryFile,
            "UTF-8"
        )
    }
    catch
    {
    }
}


; ============================================================
; 트레이 상태 갱신
; ============================================================

UpdateTrayStatus(CurrentState)
{
    global A_IconTip
    global ShutdownEnabled
    global ShutdownScheduled
    global ShutdownMinutes

    if !ShutdownEnabled
    {
        if (CurrentState = "OPEN")
            A_IconTip := "치지직 방송 감시 | 방송 ON | 종료 기능 OFF"
        else
            A_IconTip := "치지직 방송 감시 | 방송 OFF | 종료 기능 OFF"
        return
    }

    if IsNightTime()
    {
        if (CurrentState = "OPEN")
        {
            A_IconTip :=
                "치지직 방송 감시 | 방송 ON | 야간 종료 보호중"
        }
        else
        {
            A_IconTip :=
                "치지직 방송 감시 | 방송 OFF | 야간 종료 보호중"
        }

        return
    }

    if IsAnyProtectedAppRunning()
    {
        if (CurrentState = "OPEN")
        {
            A_IconTip :=
                "치지직 방송 감시 | 방송 ON | 종료 보호중"
        }
        else
        {
            A_IconTip :=
                "치지직 방송 감시 | 방송 OFF | 종료 보호중"
        }

        return
    }

    if (CurrentState = "OPEN")
    {
        A_IconTip :=
            "치지직 방송 감시 | 방송 ON"

        return
    }

    if ShutdownScheduled
    {
        A_IconTip :=
            "치지직 방송 감시 | 방송 OFF | "
            . ShutdownMinutes
            . "분 후 종료"

        return
    }

    A_IconTip :=
        "치지직 방송 감시 | 방송 OFF"
}


; ============================================================
; 보호 앱 실행 여부
; ============================================================

IsAnyProtectedAppRunning()
{
    global ProtectedApps

    if (ProtectedApps.Length = 0)
        return false

    CurrentPID :=
        DllCall(
            "GetCurrentProcessId"
        )

    for hwnd in WinGetList()
    {
        try
        {
            pid :=
                WinGetPID(
                    "ahk_id " hwnd
                )

            if (pid = CurrentPID)
                continue

            exeName :=
                WinGetProcessName(
                    "ahk_id " hwnd
                )

            if (exeName = "")
                continue

            exeName :=
                StrLower(
                    Trim(exeName)
                )

            for protectedExe in ProtectedApps
            {
                if (
                    exeName
                    =
                    StrLower(
                        Trim(protectedExe)
                    )
                )
                    return true
            }
        }
        catch
        {
            continue
        }
    }

    return false
}


; ============================================================
; 커스텀 체크박스
; ============================================================

CreateStyledCheckbox(
    GuiObj,
    x,
    y,
    label,
    initialValue,
    labelWidth := 360
)
{
    State := {
        Value: initialValue ? 1 : 0
    }

    Frame :=
        GuiObj.Add(
            "Text",
            "x" x
            . " y" y
            . " w20 h20"
            . " Background009B70",
            ""
        )

    Box :=
        GuiObj.Add(
            "Text",
            "x" (x + 2)
            . " y" (y + 2)
            . " w16 h16"
            . " Background202733"
            . " c8B949E"
            . " Center 0x200",
            ""
        )

    SquareCheckboxControls[Frame.Hwnd] := true
    SquareCheckboxControls[Box.Hwnd] := true

    static CleanupHandlerRegistered := false
    if !CleanupHandlerRegistered
    {
        OnMessage(0x82, ForgetSquareCheckboxControl)
        CleanupHandlerRegistered := true
    }

    LabelControl :=
        GuiObj.Add(
            "Text",
            "x" (x + 28)
            . " y" (y - 1)
            . " w" labelWidth " h22"
            . " cD6DCE5",
            label
        )

    Check := {
        Box: Box,
        Frame: Frame,
        Label: LabelControl,
        State: State,
        ExeName: label
    }

    Box.OnEvent(
        "Click",
        ToggleStyledCheckbox.Bind(Check)
    )

    Frame.OnEvent(
        "Click",
        ToggleStyledCheckbox.Bind(Check)
    )

    LabelControl.OnEvent(
        "Click",
        ToggleStyledCheckbox.Bind(Check)
    )

    UpdateStyledCheckbox(
        Check
    )

    return Check
}


ForgetSquareCheckboxControl(wParam, lParam, msg, hwnd)
{
    global SquareCheckboxControls
    if SquareCheckboxControls.Has(hwnd)
        SquareCheckboxControls.Delete(hwnd)
}


ToggleStyledCheckbox(Check, *)
{
    Check.State.Value :=
        !Check.State.Value

    UpdateStyledCheckbox(
        Check
    )

}


UpdateStyledCheckbox(Check)
{
    if Check.State.Value
    {
        Check.Box.Opt(
            "Background00D68F c11151C"
        )

        Check.Box.Text := "✓"
    }
    else
    {
        Check.Box.Opt(
            "Background202733 c8B949E"
        )

        Check.Box.Text := ""
    }
}


; ============================================================
; 통합 설정 GUI
; ============================================================

RegisterUserHotkeys()
{
    global HotkeyBindings
    global DefaultHotkeys
    global SettingsFile

    desiredBindings := Map()
    for action, binding in DefaultHotkeys
    {
        desiredBindings[action] := IniRead(
            SettingsFile, "Hotkeys", action, binding
        )
    }

    ; HotkeyBindings에는 실제 등록된 조합만 보관한다.
    ; 설정 파일에서 읽은 값을 먼저 넣으면 아직 등록되지 않은 조합에
    ; Off를 호출하게 되어 첫 실행 때 오류 복구 알림이 뜬다.
    HotkeyBindings := Map()

    try
    {
        ApplyUserHotkeys(desiredBindings)
    }
    catch
    {
        HotkeyBindings := Map()
        ApplyUserHotkeys(DefaultHotkeys)
        SaveSettings()
        TrayTip("단축키 복구", "저장된 단축키에 오류가 있어 기본값으로 복구했습니다.", 1)
    }
}


ApplyUserHotkeys(bindings)
{
    actions := Map(
        "CancelShutdown", CancelShutdownHotkey,
        "StopMonitor", StopMonitorHotkey,
        "MonitorOff", MonitorOffHotkey,
        "Settings", SettingsHotkey,
        "TimelineMemo", TimelineMemoHotkey,
        "TimelineViewer", TimelineViewerHotkey,
        "LolRank", LolRankHotkey
    )
    seen := Map()
    for action, binding in bindings
    {
        if (
            binding = ""
            || RegExMatch(binding, "^[#\^!+<>$~*]+$")
            || seen.Has(StrLower(binding))
        )
            throw Error("비어 있거나 중복된 단축키입니다.")
        seen[StrLower(binding)] := true
    }

    global HotkeyBindings
    previous := HotkeyBindings.Clone()
    try
    {
        for action, binding in previous
            Hotkey(binding, "Off")
        for action, binding in bindings
            Hotkey(binding, actions[action], "On")
        HotkeyBindings := bindings.Clone()
    }
    catch as err
    {
        for action, binding in bindings
        {
            try Hotkey(binding, "Off")
        }
        for action, binding in previous
        {
            try Hotkey(binding, actions[action], "On")
        }
        throw Error("단축키를 등록하지 못했습니다. 다른 프로그램과 충돌하는지 확인해주세요.",, err.Message)
    }
}


SetUserHotkeysEnabled(enabled)
{
    global HotkeyBindings

    for action, binding in HotkeyBindings
    {
        try
            Hotkey(binding, enabled ? "On" : "Off")
    }
}


CancelShutdownHotkey(*) => CancelShutdownReservation(true)

StopMonitorHotkey(*)
{
    result := MsgBox("치지직 방송 감시를 종료할까요?", "방송 감시 종료", "YesNo Icon?")
    if (result = "Yes")
        ExitApp
}

MonitorOffHotkey(*)
{
    Sleep(2000)
    SendMessage(0x112, 0xF170, 2, , "Program Manager")
}

SettingsHotkey(*) => ShowSettingsGui()
TimelineMemoHotkey(*) => ShowTimelineMemo()
TimelineViewerHotkey(*) => ShowTimelineViewer()
LolRankHotkey(*) => ShowLolRankGui()


ApplyAccentOutline(GuiObj, Control)
{
    Control.GetPos(&X, &Y, &Width, &Height)
    Control.Opt("Background202733 c00D68F")
    Control.SetFont("s9 Bold", "맑은 고딕")

    AddRoundedOutlineControls(GuiObj, X, Y, Width, Height, "00D68F", 1, 6)
}


AddRoundedOutlineControls(GuiObj, X, Y, Width, Height, Color, Thickness := 1, Radius := 6)
{
    Controls := []
    for Geometry in RoundedOutlineGeometry(X, Y, Width, Height, Thickness, Radius)
    {
        Controls.Push(GuiObj.Add(
            "Text",
            "x" Geometry[1] " y" Geometry[2]
            . " w" Geometry[3] " h" Geometry[4]
            . " Background" Color,
            ""
        ))
    }
    return Controls
}


RoundedOutlineGeometry(X, Y, Width, Height, Thickness := 1, Radius := 6)
{
    Radius := Min(Radius, Floor(Min(Width, Height) / 2))
    CurveLength := Max(1, Radius - 2)
    return [
        [X + Radius, Y, Width - (Radius * 2), Thickness],
        [X + Radius, Y + Height - Thickness, Width - (Radius * 2), Thickness],
        [X, Y + Radius, Thickness, Height - (Radius * 2)],
        [X + Width - Thickness, Y + Radius, Thickness, Height - (Radius * 2)],
        [X + 2, Y + 1, CurveLength, Thickness],
        [X + 1, Y + 2, Thickness, CurveLength],
        [X + Width - Radius, Y + 1, CurveLength, Thickness],
        [X + Width - 1 - Thickness, Y + 2, Thickness, CurveLength],
        [X + 2, Y + Height - 1 - Thickness, CurveLength, Thickness],
        [X + 1, Y + Height - Radius, Thickness, CurveLength],
        [X + Width - Radius, Y + Height - 1 - Thickness, CurveLength, Thickness],
        [X + Width - 1 - Thickness, Y + Height - Radius, Thickness, CurveLength]
    ]
}


MoveRoundedOutlineControls(Controls, X, Y, Width, Height, Thickness := 1, Radius := 6)
{
    for Index, Geometry in RoundedOutlineGeometry(X, Y, Width, Height, Thickness, Radius)
        Controls[Index].Move(Geometry[1], Geometry[2], Geometry[3], Geometry[4])
}


EnableRoundedGui(GuiObj, SkipCalendarDates := false)
{
    global TimelineCalendarState
    global SquareCheckboxControls

    try
    {
        Preference := Buffer(4, 0)
        NumPut("Int", 2, Preference, 0) ; DWMWCP_ROUND
        DllCall(
            "dwmapi\DwmSetWindowAttribute",
            "Ptr", GuiObj.Hwnd,
            "UInt", 33, ; DWMWA_WINDOW_CORNER_PREFERENCE
            "Ptr", Preference.Ptr,
            "UInt", 4
        )
    }

    try
    {
        ExcludedControls := Map()
        for ControlHwnd in SquareCheckboxControls
            ExcludedControls[ControlHwnd] := true
        if (
            SkipCalendarDates
            && IsObject(TimelineCalendarState)
            && GuiObj.Hwnd = TimelineCalendarState.Viewer.Hwnd
        )
        {
            for _, CalendarCell in TimelineCalendarState.CalendarSlots
                ExcludedControls[CalendarCell.Hwnd] := true
        }

        for ControlHwnd in WinGetControlsHwnd("ahk_id " . GuiObj.Hwnd)
        {
            if ExcludedControls.Has(ControlHwnd)
            {
                ; 이전에 적용된 둥근 영역도 제거해 날짜 칸을 항상 사각형으로 둔다.
                DllCall("SetWindowRgn", "Ptr", ControlHwnd, "Ptr", 0, "Int", true)
                continue
            }

            ClassNameBuffer := Buffer(512, 0)
            if !DllCall(
                "GetClassNameW",
                "Ptr", ControlHwnd,
                "Ptr", ClassNameBuffer.Ptr,
                "Int", 256
            )
                continue

            ClassName := StrGet(ClassNameBuffer, "UTF-16")
            if (ClassName != "Static" && ClassName != "Edit")
                continue

            Rect := Buffer(16, 0)
            if !DllCall("GetWindowRect", "Ptr", ControlHwnd, "Ptr", Rect.Ptr)
                continue

            Width := NumGet(Rect, 8, "Int") - NumGet(Rect, 0, "Int")
            Height := NumGet(Rect, 12, "Int") - NumGet(Rect, 4, "Int")
            if (Width < 6 || Height < 6)
                continue

            CornerDiameter := Min(18, Width, Height)
            Region := DllCall(
                "CreateRoundRectRgn",
                "Int", 0, "Int", 0,
                "Int", Width + 1, "Int", Height + 1,
                "Int", CornerDiameter, "Int", CornerDiameter,
                "Ptr"
            )

            if !DllCall("SetWindowRgn", "Ptr", ControlHwnd, "Ptr", Region, "Int", true)
                DllCall("DeleteObject", "Ptr", Region)
        }
    }
}


ShowHotkeySettingsGui(*)
{
    global HotkeyBindings
    global HotkeyLabels

    ; 입력한 조합이 이 프로그램의 기존 전역 단축키를 실행하지 않도록 잠시 비활성화
    SetUserHotkeysEnabled(false)

    HotkeyGui := Gui("+AlwaysOnTop", "단축키 설정")
    HotkeyGui.BackColor := "11151C"
    HotkeyGui.SetFont("s9", "맑은 고딕")
    HotkeyGui.Add("Text", "x20 y16 w300 h30 cFFFFFF", "단축키 설정")
    HotkeyGui.SetFont("s9", "맑은 고딕")
    HotkeyGui.Add("Text", "x22 y48 w400 h24 c8B949E", "각 항목을 선택한 뒤 원하는 키 조합을 눌러주세요.")

    edits := Map()
    winChecks := Map()
    editBindings := Map()
    y := 91
    for action, label in HotkeyLabels
    {
        HotkeyGui.Add("Text", "x25 y" y " w150 h26 cD6DCE5 0x200", label)
        winChecks[action] := CreateStyledCheckbox(
            HotkeyGui,
            175,
            y + 3,
            "Win",
            InStr(HotkeyBindings[action], "#"),
            38
        )
        baseBinding := StrReplace(HotkeyBindings[action], "#")
        edits[action] := HotkeyGui.Add(
            "Edit",
            "x245 y" y " w190 h27 ReadOnly -Border Background202733 cFFFFFF",
            FormatHotkeyForDisplay(baseBinding)
        )
        RemoveEditBorder(edits[action].Hwnd)
        editBindings[action] := baseBinding
        edits[action].OnEvent("Focus", BeginHotkeyCapture.Bind(action, edits, winChecks, editBindings))
        y += 48
    }
    HotkeyGui.Add("Text", "x25 y" y " w410 h36 c8B949E", "Win 체크 후 키 조합을 누르면 Windows 키 조합으로 등록됩니다.")
    y += 48
    save := HotkeyGui.Add("Text", "x25 y" y " w195 h35 Background00D68F c11151C Center 0x200", "저장")
    cancel := HotkeyGui.Add("Text", "x230 y" y " w205 h35 Background202733 cD6DCE5 Center 0x200", "취소")
    save.OnEvent("Click", (*) => SaveHotkeySettings(HotkeyGui, edits, winChecks, editBindings))
    cancel.OnEvent("Click", (*) => CloseHotkeySettingsGui(HotkeyGui))
    HotkeyGui.OnEvent("Close", (*) => CloseHotkeySettingsGui(HotkeyGui))
    winChecks["CancelShutdown"].Box.Focus()
    HotkeyGui.Show("w460 h" (y + 58))
    EnableRoundedGui(HotkeyGui)
}


FormatHotkeyForDisplay(binding)
{
    if (binding = "")
        return "클릭하여 입력"

    display := ""
    if InStr(binding, "^")
        display .= "Ctrl + "
    if InStr(binding, "!")
        display .= "Alt + "
    if InStr(binding, "+")
        display .= "Shift + "

    keyName := RegExReplace(binding, "^[#\^!+]+")
    if (StrUpper(keyName) = "SC01A")
        keyName := "["
    if (StrLen(keyName) = 1)
        keyName := StrUpper(keyName)
    return display . keyName
}


BeginHotkeyCapture(action, edits, winChecks, editBindings, *)
{
    global ActiveHotkeyInputHook

    if IsObject(ActiveHotkeyInputHook)
        ActiveHotkeyInputHook.Stop()

    edits[action].Value := "키 입력 대기 중… (Esc 취소)"
    hook := InputHook("L0")
    hook.KeyOpt("{All}", "SN")
    hook.OnKeyDown := CaptureUserHotkey.Bind(action, edits, winChecks, editBindings)
    ActiveHotkeyInputHook := hook
    hook.Start()
}


CaptureUserHotkey(action, edits, winChecks, editBindings, hook, vk, sc)
{
    global ActiveHotkeyInputHook

    ; modifier 키만 눌린 동안은 계속 기다린다.
    if (vk = 0x11 || vk = 0xA2 || vk = 0xA3
        || vk = 0x10 || vk = 0xA0 || vk = 0xA1
        || vk = 0x12 || vk = 0xA4 || vk = 0xA5
        || vk = 0x5B || vk = 0x5C)
        return

    hook.Stop()
    ActiveHotkeyInputHook := 0

    if (vk = 0x1B)
    {
        edits[action].Value := FormatHotkeyForDisplay(editBindings[action])
        winChecks[action].Box.Focus()
        return
    }

    keyName := GetKeyName(Format("vk{:02X}sc{:03X}", vk, sc))
    if (keyName = "")
    {
        edits[action].Value := FormatHotkeyForDisplay(editBindings[action])
        winChecks[action].Box.Focus()
        return
    }

    binding := ""
    if GetKeyState("Ctrl", "P")
        binding .= "^"
    if GetKeyState("Alt", "P")
        binding .= "!"
    if GetKeyState("Shift", "P")
        binding .= "+"
    binding .= keyName

    editBindings[action] := binding
    if (GetKeyState("LWin", "P") || GetKeyState("RWin", "P"))
    {
        winChecks[action].State.Value := 1
        UpdateStyledCheckbox(winChecks[action])
    }
    edits[action].Value := FormatHotkeyForDisplay(binding)
    winChecks[action].Box.Focus()
}


CloseHotkeySettingsGui(guiObj)
{
    global ActiveHotkeyInputHook
    if IsObject(ActiveHotkeyInputHook)
    {
        ActiveHotkeyInputHook.Stop()
        ActiveHotkeyInputHook := 0
    }
    SetUserHotkeysEnabled(true)
    try guiObj.Destroy()
}


SaveHotkeySettings(gui, edits, winChecks, editBindings)
{
    global ActiveHotkeyInputHook
    global HotkeyBindings
    global SettingsFile

    if IsObject(ActiveHotkeyInputHook)
    {
        ActiveHotkeyInputHook.Stop()
        ActiveHotkeyInputHook := 0
    }

    updated := Map()
    for action, control in edits
    {
        binding := editBindings[action]
        updated[action] := (winChecks[action].State.Value ? "#" : "") . binding
    }
    try
    {
        ApplyUserHotkeys(updated)
        SetUserHotkeysEnabled(false)
        for action, binding in updated
            IniWrite(binding, SettingsFile, "Hotkeys", action)
        gui.Destroy()
        SetUserHotkeysEnabled(true)
        TrayTip("단축키 저장 완료", "새 단축키를 적용했습니다.", 1)
    }
    catch as err
    {
        SetUserHotkeysEnabled(true)
        MsgBox(err.Message, "단축키 설정 오류", "Icon!")
    }
}

ShowSettingsGui()
{
    global ShutdownEnabled
    global ShutdownMinutes
    global NightStart
    global NightEnd
    global YoutubeEnabled
    global YoutubeTrigger
    global YoutubeCooldownMinutes
    global ProtectedApps

    GuiObj :=
        Gui(
            "+AlwaysOnTop",
            "치지직 방송 감시"
        )

    GuiObj.BackColor :=
        "11151C"

    GuiObj.SetFont(
        "s9",
        "맑은 고딕"
    )

    GuiObj.SetFont(
        "s15 Bold",
        "맑은 고딕"
    )

    GuiObj.Add(
        "Text",
        "x20 y16 w300 h30 cFFFFFF",
        "치지직 방송 감시"
    )

    GuiObj.SetFont(
        "s9",
        "맑은 고딕"
    )

    GuiObj.Add(
        "Text",
        "x22 y47 w280 h22 c8B949E",
        "방송 종료 및 자동 실행 설정"
    )

    GuiObj.Add(
        "Text",
        "x375 y22 w80 h24 Center c00D68F",
        "● 실행 중"
    )

    HotkeySettingsButton := GuiObj.Add(
        "Text", "x315 y47 w130 h27 Background202733 cD6DCE5 Center 0x200", "단축키 설정"
    )
    ApplyAccentOutline(GuiObj, HotkeySettingsButton)
    HotkeySettingsButton.OnEvent("Click", ShowHotkeySettingsGui)

    GuiObj.SetFont(
        "s11 Bold",
        "맑은 고딕"
    )

    GuiObj.Add(
        "Text",
        "x22 y82 w400 h25 cFFFFFF",
        "방송 종료 설정"
    )

    GuiObj.SetFont(
        "s9",
        "맑은 고딕"
    )

    GuiObj.Add(
        "Text",
        "x15 y108 w440 h100 Background2A313B",
        ""
    )

    GuiObj.Add(
        "Text",
        "x16 y109 w438 h98 Background11151C",
        ""
    )

    ShutdownCheck :=
        CreateStyledCheckbox(
            GuiObj,
            30,
            120,
            "방송 종료 후 컴퓨터 자동 종료",
            ShutdownEnabled
        )

    GuiObj.Add(
        "Text",
        "x30 y153 w150 h22 cD6DCE5",
        "종료 대기 시간"
    )

    ShutdownEdit :=
        GuiObj.Add(
            "Edit",
            "x330 y149 w65 h27 Background202733 cFFFFFF",
            ShutdownMinutes
        )

    RemoveEditBorder(
        ShutdownEdit.Hwnd
    )

    GuiObj.Add(
        "Text",
        "x402 y153 w35 h22 c8B949E",
        "분"
    )

    GuiObj.Add(
        "Text",
        "x30 y177 w395 h20 c8B949E",
        "방송 종료 후 설정한 시간이 지나면 컴퓨터를 종료합니다."
    )


    ; ========================================================
    ; 야간 보호
    ; ========================================================

    GuiObj.SetFont(
        "s11 Bold",
        "맑은 고딕"
    )

    GuiObj.Add(
        "Text",
        "x22 y228 w400 h25 cFFFFFF",
        "야간 종료 보호"
    )

    GuiObj.SetFont(
        "s9",
        "맑은 고딕"
    )

    startParts :=
        StrSplit(
            NightStart,
            ":"
        )

    endParts :=
        StrSplit(
            NightEnd,
            ":"
        )

    startHour :=
        (
            startParts.Length >= 1
            ? startParts[1]
            : "22"
        )

    startMin :=
        (
            startParts.Length >= 2
            ? startParts[2]
            : "30"
        )

    endHour :=
        (
            endParts.Length >= 1
            ? endParts[1]
            : "04"
        )

    endMin :=
        (
            endParts.Length >= 2
            ? endParts[2]
            : "00"
        )

    GuiObj.Add(
        "Text",
        "x15 y254 w440 h92 Background2A313B",
        ""
    )

    GuiObj.Add(
        "Text",
        "x16 y255 w438 h90 Background11151C",
        ""
    )

    GuiObj.Add(
        "Text",
        "x30 y277 w70 h22 cD6DCE5",
        "보호 시간"
    )

    NightStartHourEdit :=
        GuiObj.Add(
            "Edit",
            "x110 y273 w42 h27 -Border Background202733 cFFFFFF",
            startHour
        )

    RemoveEditBorder(
        NightStartHourEdit.Hwnd
    )

    GuiObj.Add(
        "Text",
        "x155 y277 w20 h22 c8B949E",
        "시"
    )

    NightStartMinEdit :=
        GuiObj.Add(
            "Edit",
            "x178 y273 w42 h27 -Border Background202733 cFFFFFF",
            startMin
        )

    RemoveEditBorder(
        NightStartMinEdit.Hwnd
    )

    GuiObj.Add(
        "Text",
        "x223 y277 w20 h22 c8B949E",
        "분"
    )

    GuiObj.Add(
        "Text",
        "x247 y277 w25 h22 Center c8B949E",
        "~"
    )

    NightEndHourEdit :=
        GuiObj.Add(
            "Edit",
            "x277 y273 w42 h27 -Border Background202733 cFFFFFF",
            endHour
        )

    RemoveEditBorder(
        NightEndHourEdit.Hwnd
    )

    GuiObj.Add(
        "Text",
        "x322 y277 w20 h22 c8B949E",
        "시"
    )

    NightEndMinEdit :=
        GuiObj.Add(
            "Edit",
            "x345 y273 w42 h27 -Border Background202733 cFFFFFF",
            endMin
        )

    RemoveEditBorder(
        NightEndMinEdit.Hwnd
    )

    GuiObj.Add(
        "Text",
        "x390 y277 w25 h22 c8B949E",
        "분"
    )

    GuiObj.Add(
        "Text",
        "x30 y312 w390 h22 c8B949E",
        "이 시간에는 방송 종료에 따른 컴퓨터 종료를 보호합니다."
    )


    ; ========================================================
    ; 보호 프로그램
    ; ========================================================

    GuiObj.SetFont(
        "s11 Bold",
        "맑은 고딕"
    )

    GuiObj.Add(
        "Text",
        "x22 y365 w400 h25 cFFFFFF",
        "종료 보호 프로그램"
    )

    GuiObj.SetFont(
        "s9",
        "맑은 고딕"
    )

    GuiObj.Add(
        "Text",
        "x15 y391 w440 h72 Background2A313B",
        ""
    )

    GuiObj.Add(
        "Text",
        "x16 y392 w438 h70 Background11151C",
        ""
    )

    ProtectedCountText :=
        GuiObj.Add(
            "Text",
            "x30 y414 w205 h24 cD6DCE5",
            ProtectedApps.Length
            . "개 프로그램 선택됨"
        )

    ProtectedButton :=
        GuiObj.Add(
            "Text",
            "x245 y407 w105 h30 Background202733 cD6DCE5 Center 0x200",
            "프로그램 선택"
        )

    ApplyAccentOutline(GuiObj, ProtectedButton)

    ClearButton :=
        GuiObj.Add(
            "Text",
            "x358 y407 w80 h30 Background202733 cD6DCE5 Center 0x200",
            "전체 해제"
        )


    ; ========================================================
    ; YouTube
    ; ========================================================

    GuiObj.SetFont(
        "s11 Bold",
        "맑은 고딕"
    )

    GuiObj.Add(
        "Text",
        "x22 y482 w400 h25 cFFFFFF",
        "YouTube 자동 실행"
    )

    GuiObj.SetFont(
        "s9",
        "맑은 고딕"
    )

    GuiObj.Add(
        "Text",
        "x15 y508 w440 h112 Background2A313B",
        ""
    )

    GuiObj.Add(
        "Text",
        "x16 y509 w438 h110 Background11151C",
        ""
    )

    YoutubeCheck :=
        CreateStyledCheckbox(
            GuiObj,
            30,
            528,
            "채팅에 지정 문구가 올라오면 YouTube 실행",
            YoutubeEnabled
        )

    GuiObj.Add(
        "Text",
        "x30 y563 w65 h22 cD6DCE5",
        "감지 문구"
    )

    TriggerEdit :=
        GuiObj.Add(
            "Edit",
            "x98 y559 w125 h27 -Border Background202733 cFFFFFF",
            YoutubeTrigger
        )

    RemoveEditBorder(
        TriggerEdit.Hwnd
    )

    GuiObj.Add(
        "Text",
        "x240 y563 w50 h22 cD6DCE5",
        "쿨타임"
    )

    CooldownEdit :=
        GuiObj.Add(
            "Edit",
            "x293 y559 w65 h27 -Border Background202733 cFFFFFF",
            YoutubeCooldownMinutes
        )

    RemoveEditBorder(
        CooldownEdit.Hwnd
    )

    GuiObj.Add(
        "Text",
        "x365 y563 w35 h22 c8B949E",
        "분"
    )

    GuiObj.Add(
        "Text",
        "x30 y592 w390 h22 c8B949E",
        "설정한 문구와 정확히 일치할 때 실행합니다."
    )


    ; ========================================================
    ; 하단 버튼
    ; ========================================================

    ResetButton :=
        GuiObj.Add(
            "Text",
            "x15 y640 w100 h35 Background202733 cD6DCE5 Center 0x200",
            "초기화"
        )

    SaveButton :=
        GuiObj.Add(
            "Text",
            "x125 y640 w220 h35 Background00D68F c11151C Center 0x200",
            "설정 저장"
        )

    CancelButton :=
        GuiObj.Add(
            "Text",
            "x355 y640 w100 h35 Background202733 cD6DCE5 Center 0x200",
            "취소"
        )


    ProtectedButton.OnEvent(
        "Click",
        (*) => ShowProtectedAppsGui(
            ProtectedCountText
        )
    )

    ClearButton.OnEvent(
        "Click",
        (*) => ClearAllProtectedApps(
            ProtectedCountText
        )
    )

    ResetButton.OnEvent(
        "Click",
        (*) => ResetAllSettings(
            GuiObj,
            ShutdownCheck,
            ShutdownEdit,
            NightStartHourEdit,
            NightStartMinEdit,
            NightEndHourEdit,
            NightEndMinEdit,
            YoutubeCheck,
            TriggerEdit,
            CooldownEdit,
            ProtectedCountText
        )
    )

    SaveButton.OnEvent(
        "Click",
        SaveSettingsFromGui.Bind(
            GuiObj,
            ShutdownCheck,
            ShutdownEdit,
            NightStartHourEdit,
            NightStartMinEdit,
            NightEndHourEdit,
            NightEndMinEdit,
            YoutubeCheck,
            TriggerEdit,
            CooldownEdit
        )
    )

    CancelButton.OnEvent(
        "Click",
        (*) => GuiObj.Destroy()
    )

    GuiObj.OnEvent(
        "Close",
        (*) => GuiObj.Destroy()
    )

    GuiObj.Show(
        "w470 h695"
    )
    EnableRoundedGui(GuiObj)
}


; ============================================================
; 보호 프로그램 선택창
; ============================================================

ShowProtectedAppsGui(
    CountText := 0
)
{
    global ProtectedApps

    AppMap := Map()
    AppList := []

    CurrentPID :=
        DllCall(
            "GetCurrentProcessId"
        )

    WindowList :=
        WinGetList()

    for hwnd in WindowList
    {
        try
        {
            pid :=
                WinGetPID(
                    "ahk_id " hwnd
                )

            if (pid = CurrentPID)
                continue

            if (!pid)
                continue

            exeName :=
                WinGetProcessName(
                    "ahk_id " hwnd
                )

            if (exeName = "")
                continue

            exeName :=
                Trim(exeName)

            if (exeName = "")
                continue

            lowerName :=
                StrLower(
                    exeName
                )

            if AppMap.Has(lowerName)
                continue

            AppMap[lowerName] :=
                exeName

            AppList.Push(
                exeName
            )
        }
        catch
        {
            continue
        }
    }


    for protectedExe in ProtectedApps
    {
        protectedExe :=
            Trim(protectedExe)

        if (protectedExe = "")
            continue

        lowerName :=
            StrLower(
                protectedExe
            )

        if !AppMap.Has(lowerName)
        {
            AppMap[lowerName] :=
                protectedExe

            AppList.Push(
                protectedExe
            )
        }
    }


    SortAppList(
        AppList
    )


    GuiObj :=
        Gui(
            "+AlwaysOnTop",
            "종료 보호 프로그램 선택"
        )

    GuiObj.BackColor :=
        "11151C"

    GuiObj.SetFont(
        "s9",
        "맑은 고딕"
    )

    GuiObj.SetFont(
        "s14 Bold",
        "맑은 고딕"
    )

    GuiObj.Add(
        "Text",
        "x20 y15 w400 h30 cFFFFFF",
        "종료 보호 프로그램"
    )

    GuiObj.SetFont(
        "s9",
        "맑은 고딕"
    )

    GuiObj.Add(
        "Text",
        "x22 y47 w420 h22 c8B949E",
        "방송 종료 후에도 실행 중이면 컴퓨터 종료를 막습니다."
    )

    GuiObj.SetFont(
        "s11 Bold",
        "맑은 고딕"
    )

    GuiObj.Add(
        "Text",
        "x22 y82 w400 h25 cFFFFFF",
        "실행 중인 프로그램"
    )

    GuiObj.SetFont(
        "s9",
        "맑은 고딕"
    )

    GuiObj.Add(
        "Text",
        "x15 y108 w440 h407 Background2A313B",
        ""
    )

    GuiObj.Add(
        "Text",
        "x16 y109 w438 h405 Background11151C",
        ""
    )

    GuiObj.Add(
        "Text",
        "x30 y122 w400 h22 c8B949E",
        "종료를 보호할 프로그램을 체크하세요."
    )

    ProtectedChecks := []

    StartY := 153
    RowHeight := 32

    if (AppList.Length = 0)
    {
        GuiObj.Add(
            "Text",
            "x40 y285 w390 h30 Center c8B949E",
            "현재 표시할 프로그램이 없습니다."
        )
    }
    else
    {
        for index, exeName in AppList
        {
            y :=
                StartY
                + (
                    (index - 1)
                    * RowHeight
                )

            initialValue :=
                IsProtectedExe(
                    exeName
                )

            Check :=
                CreateStyledCheckbox(
                    GuiObj,
                    30,
                    y,
                    exeName,
                    initialValue
                )

            ProtectedChecks.Push(
                Check
            )
        }
    }


    RefreshButton :=
        GuiObj.Add(
            "Text",
            "x15 y530 w125 h35 Background202733 cD6DCE5 Center 0x200",
            "목록 새로고침"
        )

    ClearButton :=
        GuiObj.Add(
            "Text",
            "x150 y530 w100 h35 Background202733 cD6DCE5 Center 0x200",
            "전체 해제"
        )

    ApplyButton :=
        GuiObj.Add(
            "Text",
            "x260 y530 w95 h35 Background00D68F c11151C Center 0x200",
            "적용"
        )

    CancelButton :=
        GuiObj.Add(
            "Text",
            "x360 y530 w95 h35 Background202733 cD6DCE5 Center 0x200",
            "취소"
        )


    RefreshButton.OnEvent(
        "Click",
        (*) => RefreshProtectedAppsGui(
            GuiObj,
            CountText
        )
    )

    ClearButton.OnEvent(
        "Click",
        (*) => ClearCustomProtectedChecks(
            ProtectedChecks
        )
    )

    ApplyButton.OnEvent(
        "Click",
        (*) => ApplyCustomProtectedApps(
            GuiObj,
            ProtectedChecks,
            CountText
        )
    )

    CancelButton.OnEvent(
        "Click",
        (*) => GuiObj.Destroy()
    )

    GuiObj.OnEvent(
        "Close",
        (*) => GuiObj.Destroy()
    )

    GuiObj.Show(
        "w470 h585"
    )
    EnableRoundedGui(GuiObj)
}


; ============================================================
; 보호 프로그램 목록 새로고침
; ============================================================

RefreshProtectedAppsGui(
    GuiObj,
    CountText
)
{
    GuiObj.Destroy()

    ShowProtectedAppsGui(
        CountText
    )
}


; ============================================================
; 프로그램 목록 정렬
; ============================================================

SortAppList(
    AppList
)
{
    Loop AppList.Length
    {
        i := A_Index

        Loop AppList.Length - i
        {
            j := A_Index

            if (
                StrCompare(
                    StrLower(
                        AppList[j]
                    ),
                    StrLower(
                        AppList[j + 1]
                    )
                ) > 0
            )
            {
                temp :=
                    AppList[j]

                AppList[j] :=
                    AppList[j + 1]

                AppList[j + 1] :=
                    temp
            }
        }
    }
}


; ============================================================
; 보호 프로그램 체크 전체 해제
; ============================================================

ClearCustomProtectedChecks(
    ProtectedChecks
)
{
    for Check in ProtectedChecks
    {
        Check.State.Value := 0

        UpdateStyledCheckbox(
            Check
        )
    }
}


; ============================================================
; 보호 프로그램 적용
; ============================================================

ApplyCustomProtectedApps(
    GuiObj,
    ProtectedChecks,
    CountText
)
{
    global ProtectedApps
    global ShutdownScheduled

    NewProtectedApps := []

    for Check in ProtectedChecks
    {
        if Check.State.Value
        {
            ExeName :=
                Check.ExeName

            if (ExeName != "")
                NewProtectedApps.Push(
                    ExeName
                )
        }
    }

    ProtectedApps :=
        NewProtectedApps

    if !SaveProtectedApps()
    {
        MsgBox(
            "보호 앱 목록을 저장하지 못했습니다.`n`n"
            . "파일 권한이나 디스크 상태를 확인해주세요.",
            "저장 오류",
            "Icon!"
        )

        return
    }

    if IsObject(CountText)
    {
        CountText.Text :=
            ProtectedApps.Length
            . "개 프로그램 선택됨"
    }

    if (
        ShutdownScheduled
        && IsAnyProtectedAppRunning()
    )
    {
        CancelShutdownReservation(false)

        TrayTip(
            "종료 보호",
            "보호 앱이 실행 중이라 컴퓨터 종료 예약을 취소했습니다.",
            1
        )
    }

    GuiObj.Destroy()

    TrayTip(
        "보호 앱 설정",
        ProtectedApps.Length
        . "개의 프로그램을 종료 보호 대상으로 저장했습니다.",
        1
    )
}


; ============================================================
; 기존 ListView 방식 호환 함수
; ============================================================

ApplyProtectedAppsFromList(
    GuiObj,
    LV,
    CountText
)
{
    global ProtectedApps
    global ShutdownScheduled

    NewProtectedApps := []

    row := 0

    while row :=
        LV.GetNext(
            row,
            "Checked"
        )
    {
        exeName :=
            LV.GetText(
                row,
                1
            )

        if (exeName != "")
        {
            if (
                exeName
                !=
                "현재 표시할 프로그램이 없습니다."
            )
            {
                NewProtectedApps.Push(
                    exeName
                )
            }
        }
    }

    ProtectedApps :=
        NewProtectedApps

    if !SaveProtectedApps()
    {
        MsgBox(
            "보호 앱 목록을 저장하지 못했습니다.`n`n"
            . "파일 권한이나 디스크 상태를 확인해주세요.",
            "저장 오류",
            "Icon!"
        )

        return
    }

    if IsObject(CountText)
    {
        CountText.Text :=
            ProtectedApps.Length
            . "개 프로그램 선택됨"
    }

    if (
        ShutdownScheduled
        && IsAnyProtectedAppRunning()
    )
    {
        CancelShutdownReservation(false)

        TrayTip(
            "종료 보호",
            "보호 앱이 실행 중이라 컴퓨터 종료 예약을 취소했습니다.",
            1
        )
    }

    GuiObj.Destroy()

    TrayTip(
        "보호 앱 설정",
        ProtectedApps.Length
        . "개의 프로그램을 종료 보호 대상으로 저장했습니다.",
        1
    )
}


; ============================================================
; 보호 프로그램 전체 해제
; ============================================================

ClearAllProtectedApps(
    CountText
)
{
    global ProtectedApps

    ProtectedApps := []

    if !SaveProtectedApps()
    {
        MsgBox(
            "보호 앱 목록을 저장하지 못했습니다.`n`n"
            . "파일 권한이나 디스크 상태를 확인해주세요.",
            "저장 오류",
            "Icon!"
        )

        return
    }

    if IsObject(CountText)
        CountText.Text :=
            "0개 프로그램 선택됨"

    TrayTip(
        "보호 앱 설정",
        "보호 앱을 모두 해제했습니다.",
        1
    )
}


; ============================================================
; 모든 설정 초기화
; ============================================================

ResetAllSettings(
    GuiObj,
    ShutdownCheck,
    ShutdownEdit,
    NightStartHourEdit,
    NightStartMinEdit,
    NightEndHourEdit,
    NightEndMinEdit,
    YoutubeCheck,
    TriggerEdit,
    CooldownEdit,
    ProtectedCountText
)
{
    global DefaultShutdownEnabled
    global DefaultShutdownMinutes
    global DefaultNightStart
    global DefaultNightEnd
    global DefaultYoutubeEnabled
    global DefaultYoutubeTrigger
    global DefaultYoutubeCooldown

    global ShutdownEnabled
    global ShutdownMinutes
    global ShutdownDelay
    global NightStart
    global NightEnd

    global YoutubeEnabled
    global YoutubeTrigger
    global YoutubeCooldownMinutes
    global YoutubeCooldownUntil

    global ProtectedApps
    global ShutdownScheduled
    global PreviousState

    answer :=
        MsgBox(
            "모든 설정을 기본값으로 초기화할까요?`n`n"
            . "• 방송 종료 자동 종료: 켬`n"
            . "• 종료 대기 시간: 5분`n"
            . "• 야간 보호: 22시 30분 ~ 04시 00분`n"
            . "• YouTube 자동 실행: 끔`n"
            . "• 감지 문구: 똥! ㅋㅋ`n"
            . "• YouTube 쿨타임: 60분`n"
            . "• 보호 프로그램: 전부 해제`n`n"
            . "저장된 설정 파일도 기본값으로 덮어씁니다.",
            "설정 초기화",
            "YesNo Icon? 4096"
        )

    if (answer != "Yes")
        return

    ShutdownEnabled :=
        DefaultShutdownEnabled

    ShutdownMinutes :=
        DefaultShutdownMinutes

    ShutdownDelay :=
        DefaultShutdownMinutes
        * 60

    NightStart :=
        DefaultNightStart

    NightEnd :=
        DefaultNightEnd

    YoutubeEnabled :=
        DefaultYoutubeEnabled

    YoutubeTrigger :=
        DefaultYoutubeTrigger

    YoutubeCooldownMinutes :=
        DefaultYoutubeCooldown

    YoutubeCooldownUntil := 0

    ProtectedApps := []

    if ShutdownScheduled
        CancelShutdownReservation(false)

    settingsSaved :=
        SaveSettings()

    appsSaved :=
        SaveProtectedApps()

    if (
        !settingsSaved
        || !appsSaved
    )
    {
        MsgBox(
            "설정을 기본값으로 변경했지만 파일 저장에 실패했습니다.`n`n"
            . "파일 권한이나 디스크 상태를 확인해주세요.",
            "초기화 저장 오류",
            "Icon!"
        )

        return
    }

    ShutdownCheck.State.Value :=
        DefaultShutdownEnabled

    UpdateStyledCheckbox(
        ShutdownCheck
    )

    ShutdownEdit.Value :=
        DefaultShutdownMinutes

    NightStartHourEdit.Value :=
        "22"

    NightStartMinEdit.Value :=
        "30"

    NightEndHourEdit.Value :=
        "04"

    NightEndMinEdit.Value :=
        "00"

    YoutubeCheck.State.Value :=
        DefaultYoutubeEnabled

    UpdateStyledCheckbox(
        YoutubeCheck
    )

    TriggerEdit.Value :=
        DefaultYoutubeTrigger

    CooldownEdit.Value :=
        DefaultYoutubeCooldown

    ProtectedCountText.Text :=
        "0개 프로그램 선택됨"

    StartChatMonitor()

    if (PreviousState != "")
    {
        UpdateTrayStatus(
            PreviousState
        )
    }

    TrayTip(
        "설정 초기화 완료",
        "모든 설정을 기본값으로 되돌렸습니다.",
        1
    )
}


; ============================================================
; GUI 설정 저장
; ============================================================

SaveSettingsFromGui(
    GuiObj,
    ShutdownCheck,
    ShutdownEdit,
    NightStartHourEdit,
    NightStartMinEdit,
    NightEndHourEdit,
    NightEndMinEdit,
    YoutubeCheck,
    TriggerEdit,
    CooldownEdit,
    *
)
{
    global ShutdownEnabled
    global ShutdownMinutes
    global ShutdownDelay
    global NightStart
    global NightEnd

    global YoutubeEnabled
    global YoutubeTrigger
    global YoutubeCooldownMinutes

    global PreviousState

    try
    {
        shutdownMinutes :=
            Integer(
                ShutdownEdit.Value
            )

        cooldownMinutes :=
            Integer(
                CooldownEdit.Value
            )

        nightStartHour :=
            Integer(
                NightStartHourEdit.Value
            )

        nightStartMin :=
            Integer(
                NightStartMinEdit.Value
            )

        nightEndHour :=
            Integer(
                NightEndHourEdit.Value
            )

        nightEndMin :=
            Integer(
                NightEndMinEdit.Value
            )

        if (
            shutdownMinutes < 1
            || shutdownMinutes > 1440
        )
        {
            MsgBox(
                "종료 대기 시간은 1~1440분 사이여야 합니다.",
                "설정 오류",
                "Icon!"
            )

            return
        }

        if (
            cooldownMinutes < 1
            || cooldownMinutes > 1440
        )
        {
            MsgBox(
                "YouTube 쿨타임은 1~1440분 사이여야 합니다.",
                "설정 오류",
                "Icon!"
            )

            return
        }

        if !IsValidHour(
            nightStartHour
        )
        {
            MsgBox(
                "야간 보호 시작 시간의 시 값이 올바르지 않습니다.",
                "설정 오류",
                "Icon!"
            )

            return
        }

        if !IsValidMinute(
            nightStartMin
        )
        {
            MsgBox(
                "야간 보호 시작 시간의 분 값이 올바르지 않습니다.",
                "설정 오류",
                "Icon!"
            )

            return
        }

        if !IsValidHour(
            nightEndHour
        )
        {
            MsgBox(
                "야간 보호 종료 시간의 시 값이 올바르지 않습니다.",
                "설정 오류",
                "Icon!"
            )

            return
        }

        if !IsValidMinute(
            nightEndMin
        )
        {
            MsgBox(
                "야간 보호 종료 시간의 분 값이 올바르지 않습니다.",
                "설정 오류",
                "Icon!"
            )

            return
        }

        nightStart :=
            Format(
                "{:02}:{:02}",
                nightStartHour,
                nightStartMin
            )

        nightEnd :=
            Format(
                "{:02}:{:02}",
                nightEndHour,
                nightEndMin
            )

        trigger :=
            TriggerEdit.Value

        if (trigger = "")
        {
            MsgBox(
                "YouTube 감지 문구를 입력해주세요.",
                "설정 오류",
                "Icon!"
            )

            return
        }

        ShutdownEnabled :=
            ShutdownCheck.State.Value

        ShutdownMinutes :=
            shutdownMinutes

        ShutdownDelay :=
            ShutdownMinutes
            * 60

        NightStart :=
            nightStart

        NightEnd :=
            nightEnd

        if !ShutdownEnabled && ShutdownScheduled
            CancelShutdownReservation(false)

        YoutubeEnabled :=
            YoutubeCheck.State.Value

        YoutubeTrigger :=
            trigger

        YoutubeCooldownMinutes :=
            cooldownMinutes

        if !SaveSettings()
        {
            MsgBox(
                "설정 파일을 저장하지 못했습니다.`n`n"
                . "파일 권한이나 디스크 상태를 확인해주세요.",
                "저장 오류",
                "Icon!"
            )

            return
        }

        StartChatMonitor()

        GuiObj.Destroy()

        if (PreviousState != "")
        {
            UpdateTrayStatus(
                PreviousState
            )
        }

        TrayTip(
            "설정 저장 완료",
            "설정을 저장했습니다.",
            1
        )
    }
    catch
    {
        MsgBox(
            "설정값을 확인해주세요.",
            "설정 오류",
            "Icon!"
        )
    }
}


; ============================================================
; 설정 불러오기
; ============================================================

LoadSettings()
{
    global SettingsFile

    global ShutdownEnabled
    global ShutdownMinutes
    global ShutdownDelay
    global NightStart
    global NightEnd

    global YoutubeEnabled
    global YoutubeTrigger
    global YoutubeCooldownMinutes

    needsRepair :=
        !FileExist(
            SettingsFile
        )

    try
    {
        ShutdownEnabled :=
            IniRead(
                SettingsFile,
                "Settings",
                "ShutdownEnabled",
                1
            ) + 0

        ShutdownMinutes :=
            IniRead(
                SettingsFile,
                "Settings",
                "ShutdownMinutes",
                5
            ) + 0

        NightStart :=
            IniRead(
                SettingsFile,
                "Settings",
                "NightStart",
                "22:30"
            )

        NightEnd :=
            IniRead(
                SettingsFile,
                "Settings",
                "NightEnd",
                "04:00"
            )

        YoutubeEnabled :=
            IniRead(
                SettingsFile,
                "Settings",
                "YoutubeEnabled",
                0
            ) + 0

        YoutubeTrigger :=
            IniRead(
                SettingsFile,
                "Settings",
                "YoutubeTrigger",
                "똥! ㅋㅋ"
            )

        YoutubeCooldownMinutes :=
            IniRead(
                SettingsFile,
                "Settings",
                "YoutubeCooldownMinutes",
                60
            ) + 0

        if (
            ShutdownEnabled != 0
            && ShutdownEnabled != 1
        )
        {
            ShutdownEnabled := 1
            needsRepair := true
        }

        if (
            ShutdownMinutes < 1
            || ShutdownMinutes > 1440
        )
        {
            ShutdownMinutes := 5
            needsRepair := true
        }

        if !IsValidTime(
            NightStart
        )
        {
            NightStart := "22:30"
            needsRepair := true
        }

        if !IsValidTime(
            NightEnd
        )
        {
            NightEnd := "04:00"
            needsRepair := true
        }

        if (
            YoutubeEnabled != 0
            && YoutubeEnabled != 1
        )
        {
            YoutubeEnabled := 0
            needsRepair := true
        }

        if (YoutubeTrigger = "")
        {
            YoutubeTrigger :=
                "똥! ㅋㅋ"

            needsRepair := true
        }

        if (
            YoutubeCooldownMinutes < 1
            || YoutubeCooldownMinutes > 1440
        )
        {
            YoutubeCooldownMinutes := 60
            needsRepair := true
        }
    }
    catch
    {
        ShutdownEnabled := 1
        ShutdownMinutes := 5
        NightStart := "22:30"
        NightEnd := "04:00"

        YoutubeEnabled := 0
        YoutubeTrigger := "똥! ㅋㅋ"
        YoutubeCooldownMinutes := 60

        needsRepair := true
    }

    ShutdownDelay :=
        ShutdownMinutes
        * 60

    if needsRepair
        SaveSettings()
}


; ============================================================
; 설정 저장
; ============================================================

SaveSettings()
{
    global SettingsFile
    global DefaultHotkeys
    global HotkeyBindings

    global ShutdownEnabled
    global ShutdownMinutes
    global NightStart
    global NightEnd

    global YoutubeEnabled
    global YoutubeTrigger
    global YoutubeCooldownMinutes

    try
    {
        if FileExist(SettingsFile)
            FileDelete(
                SettingsFile
            )

        IniWrite(
            ShutdownEnabled,
            SettingsFile,
            "Settings",
            "ShutdownEnabled"
        )

        IniWrite(
            ShutdownMinutes,
            SettingsFile,
            "Settings",
            "ShutdownMinutes"
        )

        IniWrite(
            NightStart,
            SettingsFile,
            "Settings",
            "NightStart"
        )

        IniWrite(
            NightEnd,
            SettingsFile,
            "Settings",
            "NightEnd"
        )

        IniWrite(
            YoutubeEnabled,
            SettingsFile,
            "Settings",
            "YoutubeEnabled"
        )

        IniWrite(
            YoutubeTrigger,
            SettingsFile,
            "Settings",
            "YoutubeTrigger"
        )

        IniWrite(
            YoutubeCooldownMinutes,
            SettingsFile,
            "Settings",
            "YoutubeCooldownMinutes"
        )

        for action, defaultBinding in DefaultHotkeys
        {
            binding := HotkeyBindings.Has(action)
                ? HotkeyBindings[action]
                : defaultBinding
            IniWrite(binding, SettingsFile, "Hotkeys", action)
        }

        return true
    }
    catch
    {
        return false
    }
}


; ============================================================
; 보호 앱인지 확인
; ============================================================

IsProtectedExe(
    exeName
)
{
    global ProtectedApps

    target :=
        StrLower(
            exeName
        )

    for protectedExe in ProtectedApps
    {
        if (
            target
            =
            StrLower(
                protectedExe
            )
        )
            return true
    }

    return false
}


; ============================================================
; 보호 앱 목록 불러오기
; ============================================================

LoadProtectedApps()
{
    global ProtectedApps
    global ProtectedAppsFile

    ProtectedApps := []

    needsRepair :=
        !FileExist(
            ProtectedAppsFile
        )

    try
    {
        CountText :=
            IniRead(
                ProtectedAppsFile,
                "ProtectedApps",
                "Count",
                ""
            )

        if (CountText = "")
        {
            Count := 0
            needsRepair := true
        }
        else
        {
            Count :=
                CountText + 0
        }

        if (
            Count < 0
            || Count > 1000
        )
        {
            Count := 0
            needsRepair := true
        }

        Loop Count
        {
            ExeName :=
                IniRead(
                    ProtectedAppsFile,
                    "ProtectedApps",
                    "App" A_Index,
                    ""
                )

            if (ExeName != "")
            {
                ProtectedApps.Push(
                    ExeName
                )
            }
            else
            {
                needsRepair := true
            }
        }

        if (
            ProtectedApps.Length = 0
            && Count != 0
        )
        {
            ProtectedApps := []
            needsRepair := true
        }
    }
    catch
    {
        ProtectedApps := []
        needsRepair := true
    }

    if needsRepair
        SaveProtectedApps()
}


; ============================================================
; 보호 앱 목록 저장
; ============================================================

SaveProtectedApps()
{
    global ProtectedApps
    global ProtectedAppsFile

    try
    {
        if FileExist(
            ProtectedAppsFile
        )
        {
            FileDelete(
                ProtectedAppsFile
            )
        }

        IniWrite(
            ProtectedApps.Length,
            ProtectedAppsFile,
            "ProtectedApps",
            "Count"
        )

        for Index, ExeName in ProtectedApps
        {
            if (
                Trim(ExeName) = ""
            )
                continue

            IniWrite(
                ExeName,
                ProtectedAppsFile,
                "ProtectedApps",
                "App" Index
            )
        }

        return true
    }
    catch as Err
    {
        MsgBox(
            "보호 앱 목록 저장 실패`n`n"
            . "파일: "
            . ProtectedAppsFile
            . "`n"
            . "오류: "
            . Err.Message,
            "저장 오류",
            "Icon!"
        )

        return false
    }
}


; ============================================================
; 실시간 치지직 채팅 감시 시작
; ============================================================

StartChatMonitor()
{
    global YoutubeEnabled
    global YoutubeTrigger

    global ChatHelperPID
    global ChatQueueFile
    global ChatTriggerConfigFile
    global ChatDebugLogFile
    global ChatHelperScript

    global ChannelID

    StopChatMonitor()

    if !YoutubeEnabled
        return

    if !FileExist(
        ChatHelperScript
    )
    {
        TrayTip(
            "채팅 감시 오류",
            "chzzk_chat.ps1 파일을 찾을 수 없습니다.",
            2
        )

        return
    }

    try
    {
        if FileExist(
            ChatQueueFile
        )
        {
            FileDelete(
                ChatQueueFile
            )
        }

        if FileExist(
            ChatTriggerConfigFile
        )
        {
            FileDelete(
                ChatTriggerConfigFile
            )
        }

        FileAppend(
            YoutubeTrigger,
            ChatTriggerConfigFile,
            "UTF-8"
        )

        PowerShellPath :=
            A_WinDir
            . "\System32\WindowsPowerShell\v1.0\powershell.exe"

        if !FileExist(
            PowerShellPath
        )
        {
            TrayTip(
                "채팅 감시 오류",
                "PowerShell을 찾을 수 없습니다.",
                2
            )

            return
        }

        command :=
            '"' PowerShellPath '"'
            . ' -NoProfile'
            . ' -ExecutionPolicy Bypass'
            . ' -File "' ChatHelperScript '"'
            . ' -ChannelId "' ChannelID '"'
            . ' -TriggerFile "' ChatQueueFile '"'
            . ' -TriggerConfigFile "' ChatTriggerConfigFile '"'
            . ' -LogFile "' ChatDebugLogFile '"'

        ChatHelperPID := 0

        Run(
            command,
            A_ScriptDir,
            "Hide",
            &ChatHelperPID
        )

        if !ChatHelperPID
        {
            TrayTip(
                "채팅 감시 오류",
                "채팅 helper를 실행하지 못했습니다.",
                2
            )
        }
    }
    catch
    {
        ChatHelperPID := 0

        TrayTip(
            "채팅 감시 오류",
            "채팅 helper 실행 중 오류가 발생했습니다.",
            2
        )
    }
}


; ============================================================
; 실시간 치지직 채팅 감시 종료
; ============================================================

StopChatMonitor(*)
{
    global ChatHelperPID

    if ChatHelperPID
    {
        try
        {
            ProcessClose(
                ChatHelperPID
            )
        }
        catch
        {
        }

        ChatHelperPID := 0
    }
}


; ============================================================
; 채팅 트리거 큐 확인
; ============================================================

PollChatTrigger()
{
    global ChatQueueFile

    if !FileExist(ChatQueueFile)
        return

    try
    {
        content := FileRead(ChatQueueFile, "UTF-8")
        FileDelete(ChatQueueFile)
        lines := StrSplit(content, "`n", "`r")
        LogYoutubeTrigger("QUEUE_READ lines=" . lines.Length)

        for line in lines
        {
            line := Trim(line)
            if (line = "")
                continue
            HandleChatMessage(line)
        }
    }
    catch as err
    {
        LogYoutubeTrigger("QUEUE_ERROR " . err.Message)
    }
}

LogYoutubeTrigger(message)
{
    global ChatDebugLogFile
    try FileAppend("[" . FormatTime(, "yyyy-MM-dd HH:mm:ss") . "] " . message . "`n", ChatDebugLogFile, "UTF-8")
}
; ============================================================
; YouTube 채팅 트리거
; ============================================================

HandleChatMessage(
    message
)
{
    global YoutubeEnabled
    global YoutubeTrigger
    global YoutubeCooldownMinutes
    global YoutubeCooldownUntil

    if !YoutubeEnabled
    {
        LogYoutubeTrigger("SKIP disabled")
        return
    }

    if !InStr(message, YoutubeTrigger)
    {
        LogYoutubeTrigger("SKIP no_match length=" . StrLen(message))
        return
    }

    if (A_TickCount < YoutubeCooldownUntil)
    {
        LogYoutubeTrigger("SKIP cooldown")
        return
    }

    try
    {
        Run("https://www.youtube.com/")
        LogYoutubeTrigger("RUN_OK triggerLength=" . StrLen(YoutubeTrigger))
    }
    catch as err
    {
        LogYoutubeTrigger("RUN_ERROR " . err.Message)
        return
    }

    YoutubeCooldownUntil :=
        A_TickCount
        + (
            YoutubeCooldownMinutes
            * 60000
        )

    TrayTip(
        "YouTube 실행",
        "채팅에 ["
        . YoutubeTrigger
        . "]이 감지되어 YouTube를 열었습니다.`n"
        . YoutubeCooldownMinutes
        . "분 동안 다시 실행하지 않습니다.",
        1
    )
}


; ============================================================
; 종료 예약 취소
; ============================================================

CancelShutdownReservation(
    ShowMessage := true
)
{
    global ShutdownScheduled
    global ShutdownTargetTime
    global A_IconTip

    RunWait(
        "shutdown.exe /a",
        ,
        "Hide"
    )

    SetTimer(
        ShutdownPC,
        0
    )

    SetTimer(
        ShutdownWarning,
        0
    )

    ShutdownScheduled := false
    ShutdownTargetTime := 0

    if ShowMessage
    {
        TrayTip(
            "종료 취소",
            "컴퓨터 종료 예약을 취소했습니다.",
            1
        )
    }

    A_IconTip :=
        "치지직 방송 감시 | 종료 예약 없음"
}


; ============================================================
; 종료 60초 전 알림
; ============================================================

ShutdownWarning()
{
    global ShutdownScheduled
    global A_IconTip

    if ShutdownScheduled
    {
        TrayTip(
            "컴퓨터 종료 예정",
            "컴퓨터 종료까지 60초 남았습니다.`n"
            . "방송이 다시 시작되면 자동으로 취소됩니다.`n"
            . "수동 취소: Ctrl + Alt + C",
            1
        )

        A_IconTip :=
            "치지직 방송 감시 | 종료까지 60초"
    }

    SetTimer(
        ShutdownWarning,
        0
    )
}


; ============================================================
; PC 종료
; ============================================================

ShutdownPC()
{
    global ShutdownScheduled
    global ShutdownTargetTime
    global A_IconTip

    if !ShutdownScheduled
        return

    if IsNightTime()
    {
        CancelShutdownReservation(false)

        TrayTip(
            "종료 보호",
            "야간 보호 시간이 시작되어 컴퓨터 종료를 취소했습니다.",
            1
        )

        return
    }

    if IsAnyProtectedAppRunning()
    {
        CancelShutdownReservation(false)

        TrayTip(
            "종료 보호",
            "보호 앱이 실행 중이라 컴퓨터 종료를 취소했습니다.",
            1
        )

        return
    }

    ShutdownScheduled := false
    ShutdownTargetTime := 0

    A_IconTip :=
        "치지직 방송 감시 | 컴퓨터 종료 중..."

    Run(
        "shutdown.exe /s /f /t 0",
        ,
        "Hide"
    )
}


; ============================================================
; ============================================================
; 타임라인
; ============================================================
; ============================================================


; ============================================================
; 10분마다 대기 중인 VOD 자동 재연결
;
; 새 구조:
;
; CSV
; ↓
; 방송시작 + 방송시간 읽기
; ↓
; 해당 채널 VOD 검색
; ↓
; VOD liveOpenDate와 방송 시작시간 비교
; ↓
; 일치 VOD 찾기
; ↓
; 방송 경과시간을 currentTime으로 적용
; ============================================================

CheckPendingVodMatches(ForceRun := false)
{
    global TimelineFile
    global VodReconnectInterval

    if !FileExist(TimelineFile)
    {
        SetTimer(CheckPendingVodMatches, 0)
        if ForceRun
        {
            ToolTip("⚠ 타임라인 CSV를 찾을 수 없습니다.")
            SetTimer(ClearTimelineToolTip, -3000)
        }
        return
    }

    ; 자동/수동 모두 아직 VOD가 연결되지 않은 행만 검사한다.
    ; 이미 연결된 VOD 링크는 절대 다시 검색하지 않는다.
    Rows := GetPendingTimelineRows(false)

    if (Rows.Length = 0)
    {
        if !ForceRun
        {
            SetTimer(CheckPendingVodMatches, 0)
            return
        }

        ToolTip("✓ 다시 연결할 타임라인이 없습니다.")
        SetTimer(ClearTimelineToolTip, -2000)
        return
    }

    if ForceRun
        ToolTip("🔄 VOD 재연결 확인 중...`n" . Rows.Length . "개 타임라인 검사")

    ConnectedCount := 0
    FailedCount := 0

    ; 같은 방송 세션의 여러 타임라인은 VOD 목록을 공유한다.
    ; 세션별 VOD 후보 목록을 한 번만 조회한다.
    VodCache := Map()
    SessionWindows := Map()

    ; 각 세션에서 가장 늦은 타임라인까지 후보 검색 구간으로 사용한다.
    for _, Row in Rows
    {
        SessionKey := NormalizeSessionDate(Row.SessionStart)
        if (SessionKey = "")
            continue

        if (
            !SessionWindows.Has(SessionKey)
            || Row.ElapsedSeconds > SessionWindows[SessionKey]
        )
            SessionWindows[SessionKey] := Row.ElapsedSeconds
    }

    for _, Row in Rows
    {
        SessionStart := Row.SessionStart
        ElapsedSeconds := Row.ElapsedSeconds
        TimeText := Row.TimeText
        SessionKey := NormalizeSessionDate(SessionStart)

        ; 같은 세션이면 VOD API 검색 결과를 공유한다.
        ; 수동 실행이어도 미연결 행만 대상으로 한다.
        Match := FindMatchingVod(
            SessionStart,
            ElapsedSeconds,
            VodCache,
            false,
            SessionWindows.Has(SessionKey) ? SessionWindows[SessionKey] : ElapsedSeconds
        )

        if !IsObject(Match)
        {
            FailedCount += 1
            continue
        }

        VideoNo := Match.VideoNo
        CurrentTime := Match.CurrentTime

        if (VideoNo = "" || CurrentTime < 0)
        {
            FailedCount += 1
            continue
        }

        ; 반드시 선택된 VOD의 "내부 시간"을 사용한다.
        VodUrl :=
            "https://chzzk.naver.com/video/"
            . VideoNo
            . "?currentTime="
            . Floor(CurrentTime)

        if UpdateTimelineVodLink(
            SessionStart,
            TimeText,
            VodUrl,
            false,
            Match.VideoTitle
        )
        {
            ConnectedCount += 1
        }
        else
        {
            FailedCount += 1
        }
    }

    ; 목록/달력이 열려 있으면 CSV 변경을 즉시 반영한다.
    try
    {
        if IsObject(TimelineCalendarState)
        {
            LoadTimelineViewerList()
            RenderTimelineCalendar()
        }
    }
    catch
    {
    }

    RemainingRows := GetPendingTimelineRows(false)

    if (ConnectedCount > 0)
    {
        Message :=
            "📺 다시보기 연결 완료`n"
            . ConnectedCount
            . "개 연결"

        if (FailedCount > 0)
            Message .= "`n⚠ " . FailedCount . "개는 아직 확인 필요"

        ToolTip(Message)
        SetTimer(ClearTimelineToolTip, -3500)
    }
    else if ForceRun
    {
        ToolTip(
            "⚠ VOD 확인 필요`n"
            . "매칭 가능한 다시보기를 찾지 못했습니다."
        )
        SetTimer(ClearTimelineToolTip, -3500)
    }

    ; 아직 연결되지 않은 행이 남아 있을 때만 10분 타이머 유지.
    if (RemainingRows.Length = 0)
        SetTimer(CheckPendingVodMatches, 0)
    else
        SetTimer(CheckPendingVodMatches, VodReconnectInterval)
}


; ============================================================
; VOD 수동 재연결
; ============================================================

ReconnectPendingVodsManually(*)
{
    ; 수동 재연결도 미연결 VOD만 검사한다.
    ; 이미 연결된 링크는 건드리지 않는다.
    CheckPendingVodMatches(true)
    ; 재연결 여부와 관계없이 기존 VOD 링크의 제목도 함께 보완한다.
    BackfillTimelineVodTitles()
}


; ============================================================
; VOD 연결 대상 타임라인 읽기
; ============================================================

GetPendingTimelineRows(IncludeConnected := false)
{
    global TimelineFile

    Result := []

    if !FileExist(TimelineFile)
        return Result

    try
    {
        Text := FileRead(TimelineFile, "UTF-8")
        Lines := StrSplit(Text, "`n")

        for Index, Line in Lines
        {
            Line := StrReplace(Line, "`r", "")

            if (Line = "" || Index = 1)
                continue

            Fields := ParseCsvLine(Line)

            if (Fields.Length < 5)
                continue

            SessionStart := Trim(Fields[1])
            TimeText := Trim(Fields[2])
            VodUrl := Trim(Fields[5])

            if (VodUrl != "" && !IncludeConnected)
                continue

            if (SessionStart = "" || TimeText = "")
                continue

            ElapsedSeconds := ParseElapsedTime(TimeText)

            if (ElapsedSeconds < 0)
                continue

            Result.Push({
                SessionStart: SessionStart,
                TimeText: TimeText,
                ElapsedSeconds: ElapsedSeconds
            })
        }
    }
    catch
    {
    }

    return Result
}


; ============================================================
; 툴팁 제거
; ============================================================

ClearTimelineToolTip()
{
    ToolTip()
}


; ============================================================
; VOD 찾기
;
; TargetStart:
;   방송 시작시간
;
; ElapsedSeconds:
;   해당 타임라인의 방송 경과시간
;
; 반환:
;   {
;       VideoNo: "...",
;       CurrentTime: 123,
;       VideoTitle: "영상 제목"
;   }
; ============================================================

FindMatchingVod(
    TargetStart,
    ElapsedSeconds,
    CandidateCache := 0,
    ForceRefresh := false,
    CandidateWindowSeconds := 0
)
{
    global VIDEO_LIST_BASE_URL
    global VodPageSize
    global VodMaxPages
    global VodTimeTolerance

    if (TargetStart = "" || ElapsedSeconds < 0)
        return ""

    NormalizedTarget := NormalizeSessionDate(TargetStart)

    if (NormalizedTarget = "")
        return ""

    ; 같은 방송의 여러 타임라인을 검사할 때마다
    ; VOD 600개를 다시 조회하면 수백~수천 번의 HTTP 요청이 발생한다.
    ; 세션 단위로 후보 VOD 목록을 한 번만 만든다.
    if (CandidateWindowSeconds < ElapsedSeconds)
        CandidateWindowSeconds := ElapsedSeconds

    CacheKey := NormalizedTarget . "|" . CandidateWindowSeconds

    Candidates := ""

    if IsObject(CandidateCache)
    {
        if CandidateCache.Has(CacheKey)
            Candidates := CandidateCache[CacheKey]
    }

    if !IsObject(Candidates)
    {
        Candidates := BuildVodCandidates(
            NormalizedTarget,
            CandidateWindowSeconds
        )

        if IsObject(CandidateCache)
            CandidateCache[CacheKey] := Candidates
    }

    if !IsObject(Candidates) || Candidates.Length = 0
        return ""

    ; 후보는 방송 시작 근처와 각 VOD 분할 시작 시각의 두 형태를 허용한다.
    ; 분할 VOD가 원래 liveOpenDate를 공유하면 누적 길이로 이어 붙인다.
    GroupElapsed := 0
    HasAnchor := false

    for _, Candidate in Candidates
    {
        Duration := Candidate.Duration
        try
        {
            StartOffset := DateDiff(
                NormalizedTarget,
                Candidate.LiveOpenDate,
                "Seconds"
            )
        }
        catch
        {
            continue
        }

        if !HasAnchor
        {
            if (Abs(StartOffset) > VodTimeTolerance)
                continue

            SegmentOffset := 0
            HasAnchor := true
        }
        else if (Abs(StartOffset) <= VodTimeTolerance)
        {
            ; 분할편들이 방송 시작 시각을 공유하는 CHZZK 응답 형식
            SegmentOffset := GroupElapsed
        }
        else if (Abs(StartOffset - GroupElapsed) <= VodTimeTolerance)
        {
            ; 분할편마다 실제 분할 시작 시각이 기록된 CHZZK 응답 형식
            SegmentOffset := StartOffset
        }
        else
        {
            ; 다음 구간 시작이 앞 VOD 끝과 이어지지 않으면 다른 방송으로 간주
            continue
        }

        LocalTime :=
            ElapsedSeconds
            - SegmentOffset

        if (
            LocalTime >= 0
            && LocalTime < Duration
        )
        {
            return {
                VideoNo: Candidate.VideoNo,
                CurrentTime: Floor(LocalTime),
                VideoTitle: Candidate.VideoTitle
            }
        }

        GroupElapsed := Max(
            GroupElapsed,
            SegmentOffset + Duration
        )
    }

    return ""
}


; ============================================================
; 방송 세션의 VOD 후보를 한 번만 조회
; ============================================================

BuildVodCandidates(NormalizedTarget, CandidateWindowSeconds := 0)
{
    global VIDEO_LIST_BASE_URL
    global VodPageSize
    global VodMaxPages
    global VodTimeTolerance

    Candidates := []
    SeenVideoNos := Map()

    try
    {
        Loop VodMaxPages
        {
            Page := A_Index - 1

            VideoListUrl :=
                VIDEO_LIST_BASE_URL
                . "?sortType=LATEST"
                . "&pagingType=PAGE"
                . "&page="
                . Page
                . "&size="
                . VodPageSize

            Http := ComObject("WinHttp.WinHttpRequest.5.1")
            Http.Open("GET", VideoListUrl, false)
            Http.SetRequestHeader("User-Agent", "Mozilla/5.0")
            Http.SetRequestHeader("Accept", "application/json")
            Http.Send()

            if (Http.Status != 200)
                continue

            ResponseText := Http.ResponseText
            VideoNos := []
            Pos := 1

            while RegExMatch(
                ResponseText,
                '"videoNo"\s*:\s*"?(\d+)"?',
                &Match,
                Pos
            )
            {
                VideoNo := Match[1]

                if !HasArrayValue(VideoNos, VideoNo)
                    VideoNos.Push(VideoNo)

                Pos := Match.Pos + Match.Len
            }

            if (VideoNos.Length = 0)
                break

            for _, VideoNo in VideoNos
            {
                if SeenVideoNos.Has(VideoNo)
                    continue

                Info := GetVodInfo(VideoNo)

                if !IsObject(Info)
                    continue

                VodStart := Info.LiveOpenDate
                Duration := Info.Duration

                if (VodStart = "" || Duration <= 0)
                    continue

                try
                {
                    StartDifference :=
                        DateDiff(
                            NormalizedTarget,
                            VodStart,
                            "Seconds"
                        )
                }
                catch
                {
                    continue
                }

                if (
                    StartDifference < -VodTimeTolerance
                    || StartDifference > CandidateWindowSeconds + VodTimeTolerance
                )
                    continue

                SeenVideoNos[VideoNo] := true

                Candidates.Push({
                    VideoNo: VideoNo,
                    VideoTitle: Info.VideoTitle,
                    LiveOpenDate: VodStart,
                    Duration: Duration,
                    PublishDate: Info.PublishDate,
                    VideoNoNumeric: Integer(VideoNo)
                })
            }
        }
    }
    catch
    {
        return []
    }

    if (Candidates.Length = 0)
        return Candidates

    SortVodCandidates(Candidates)
    return Candidates
}


; ============================================================
; VOD 후보 정렬
;
; 서로 다른 liveOpenDate는 시간순으로 정렬한다.
; 같은 liveOpenDate를 가진 분할 VOD는 publishDate가 빠른 순서,
; publishDate가 같거나 없으면 videoNo 오름차순으로 정렬한다.
; ============================================================

SortVodCandidates(Candidates)
{
    Count := Candidates.Length

    Loop Count - 1
    {
        I := A_Index

        Loop Count - I
        {
            J := A_Index

            Left := Candidates[J]
            Right := Candidates[J + 1]

            ShouldSwap := false

            if (
                Left.LiveOpenDate
                >
                Right.LiveOpenDate
            )
            {
                ShouldSwap := true
            }
            else if (
                Left.LiveOpenDate
                =
                Right.LiveOpenDate
            )
            {
                if (
                    Left.PublishDate != ""
                    && Right.PublishDate != ""
                    && Left.PublishDate != Right.PublishDate
                )
                {
                    if (Left.PublishDate > Right.PublishDate)
                        ShouldSwap := true
                }
                else if (
                    Left.VideoNoNumeric
                    >
                    Right.VideoNoNumeric
                )
                {
                    ShouldSwap := true
                }
            }

            if ShouldSwap
            {
                Temp := Candidates[J]
                Candidates[J] := Candidates[J + 1]
                Candidates[J + 1] := Temp
            }
        }
    }
}


; ============================================================
; 날짜 형식 통일
; ============================================================

NormalizeSessionDate(
    DateText
)
{
    DateText :=
        Trim(
            DateText
        )

    if (
        DateText = ""
    )
        return ""

    if RegExMatch(
        DateText,
        "^\d{14}$"
    )
    {
        return DateText
    }

    if RegExMatch(
        DateText,
        "^(\d{4})-(\d{2})-(\d{2})\s+(\d{2}):(\d{2}):(\d{2})$",
        &M
    )
    {
        return (
            M[1]
            . M[2]
            . M[3]
            . M[4]
            . M[5]
            . M[6]
        )
    }

    return ""
}


; ============================================================
; VOD 상세 정보
; ============================================================

GetVodInfo(
    VideoNo
)
{
    Url :=
        "https://api.chzzk.naver.com/service/v3/videos/"
        . VideoNo

    try
    {
        Http :=
            ComObject("WinHttp.WinHttpRequest.5.1")

        Http.Open("GET", Url, false)
        Http.SetRequestHeader("User-Agent", "Mozilla/5.0")
        Http.SetRequestHeader("Accept", "application/json")
        Http.SetTimeouts(3000, 3000, 5000, 5000)
        Http.Send()

        if (Http.Status != 200)
            return ""

        ; WinHTTP ResponseText가 UTF-8 제목을 시스템 코드페이지로 읽어
        ; ì ë... 같은 문자열로 만들 수 있어 응답 바이트를 UTF-8로 직접 해석한다.
        ResponseStream := ComObject("ADODB.Stream")
        ResponseStream.Type := 1
        ResponseStream.Open()
        ResponseStream.Write(Http.ResponseBody)
        ResponseStream.Position := 0
        ResponseStream.Type := 2
        ResponseStream.Charset := "utf-8"
        ResponseText := ResponseStream.ReadText()
        ResponseStream.Close()

        if !RegExMatch(
            ResponseText,
            '"liveOpenDate"\s*:\s*"([^"]+)"',
            &DateMatch
        )
            return ""

        LiveOpenDate :=
            ParseChzzkDate(DateMatch[1])

        Duration := 0

        if RegExMatch(
            ResponseText,
            '"duration"\s*:\s*(\d+)',
            &DurationMatch
        )
        {
            ; CHZZK VOD duration은 초 단위.
            Duration := Integer(DurationMatch[1])
        }

        PublishDate := ""

        if RegExMatch(
            ResponseText,
            '"publishDate"\s*:\s*"([^"]+)"',
            &PublishMatch
        )
        {
            PublishDate :=
                ParseChzzkDate(PublishMatch[1])
        }

        VideoTitle := GetJsonStringField(ResponseText, "videoTitle")

        return {
            LiveOpenDate: LiveOpenDate,
            Duration: Duration,
            PublishDate: PublishDate,
            VideoTitle: VideoTitle
        }
    }
    catch
    {
        return ""
    }
}


; 기존 호출부 호환용
GetVodLiveOpenDate(
    VideoNo
)
{
    Info := GetVodInfo(VideoNo)

    if IsObject(Info)
        return Info.LiveOpenDate

    return ""
}


; ============================================================
; 배열 중복 검사
; ============================================================

HasArrayValue(
    Arr,
    Value
)
{
    for _, Item in Arr
    {
        if (
            Item = Value
        )
            return true
    }

    return false
}


; ============================================================
; 특정 타임라인 VOD 링크 연결
;
; 같은 방송의 같은 경과시간을 가진 행만 연결
; ============================================================

UpdateTimelineVodLink(
    SessionStart,
    TimeText,
    VodUrl,
    ForceReplace := false,
    VodTitle := ""
)
{
    global TimelineFile

    if !FileExist(
        TimelineFile
    )
        return false

    UpdatedCount := 0

    try
    {
        Text :=
            FileRead(
                TimelineFile,
                "UTF-8"
            )

        Lines :=
            StrSplit(
                Text,
                "`n"
            )

        NewText := ""

        for Index, Line in Lines
        {
            Line :=
                StrReplace(
                    Line,
                    "`r",
                    ""
                )

            if (
                Line = ""
            )
                continue


            ; ==================================================
            ; 헤더
            ; ==================================================

            if (
                Index = 1
            )
            {
                HeaderFields := ParseCsvLine(Line)

                if (HeaderFields.Length < 6)
                    HeaderFields.Push("VOD제목")
                else
                    HeaderFields[6] := "VOD제목"

                NewText :=
                    BuildCsvLine(HeaderFields)
                    . "`r`n"

                continue
            }


            Fields :=
                ParseCsvLine(
                    Line
                )

            if (
                Fields.Length < 5
            )
            {
                NewText :=
                    NewText
                    . Line
                    . "`r`n"

                continue
            }


            RowSession :=
                Trim(
                    Fields[1]
                )

            RowTime :=
                Trim(
                    Fields[2]
                )

            RowVod :=
                Trim(
                    Fields[5]
                )


            ; ==================================================
            ; 대상이 아니면 그대로 유지
            ; ==================================================

            if (
                RowSession
                !=
                SessionStart
                ||
                RowTime
                !=
                TimeText
            )
            {
                NewText :=
                    NewText
                    . Line
                    . "`r`n"

                continue
            }


            ; 자동 연결에서는 기존 링크를 유지한다.
            ; 수동 재연결에서는 기존 링크도 최신 매칭 결과로 갱신한다.
            if (
                RowVod != ""
                && !ForceReplace
            )
            {
                NewText :=
                    NewText
                    . Line
                    . "`r`n"

                continue
            }


            ; ==================================================
            ; VOD URL 기록
            ; ==================================================

            Fields[5] :=
                VodUrl

            if (Fields.Length < 6)
                Fields.Push(VodTitle)
            else
                Fields[6] := VodTitle

            NewText :=
                NewText
                . BuildCsvLine(
                    Fields
                )
                . "`r`n"

            UpdatedCount += 1
        }


        if (
            UpdatedCount = 0
        )
            return false


        if !BackupTimelineCsv("before_vod_link", false)
            return false

        FileDelete(
            TimelineFile
        )

        FileAppend(
            NewText,
            TimelineFile,
            "UTF-8"
        )

        return true
    }
    catch
    {
        return false
    }
}


; ============================================================
; 타임라인 메모창
; ============================================================

ShowTimelineMemo()
{
    global BroadcastStart

    if (
        BroadcastStart = ""
    )
    {
        CheckLiveStatus()
    }

    if (
        BroadcastStart = ""
    )
    {
        MsgBox(
            "현재 방송 시작 시간을 확인하지 못했습니다.`n`n"
            . "방송이 시작된 후 잠시 기다렸다가 다시 시도해주세요.",
            "타임라인",
            "Icon!"
        )

        return
    }

    ElapsedSec :=
        GetBroadcastElapsed()

    if (
        ElapsedSec < 0
    )
    {
        MsgBox(
            "현재 방송 경과시간을 계산하지 못했습니다.",
            "타임라인",
            "Icon!"
        )

        return
    }

    TimeText :=
        FormatElapsed(
            ElapsedSec
        )

    MemoGui :=
        Gui(
            "+AlwaysOnTop -MaximizeBox -MinimizeBox",
            "타임라인 메모"
        )

    MemoGui.BackColor :=
        "11151C"

    MemoGui.SetFont(
        "s10",
        "맑은 고딕"
    )

    MemoGui.Add(
        "Text",
        "x20 y18 w340 cFFFFFF",
        "🔖 타임라인 메모"
    )

    MemoGui.Add(
        "Text",
        "x20 y50 w340 c8B949E",
        "현재 방송 시간"
    )

    TimeControl :=
        MemoGui.Add(
            "Text",
            "x20 y72 w340 h30 c00D68F",
            TimeText
        )

    TimeControl.SetFont(
        "s14 Bold"
    )

    MemoGui.Add(
        "Text",
        "x20 y115 w340 c8B949E",
        "메모"
    )

    MemoEditBackground :=
        MemoGui.Add(
            "Text",
            "x20 y137 w340 h32 Background202733",
            ""
        )

    MemoEdit :=
        MemoGui.Add(
            "Edit",
            "x20 y137 w340 h32"
            . " Background202733"
            . " cD6DCE5"
            . " -Border"
            . " -E0x200",
            ""
        )

    SaveButton :=
        MemoGui.Add(
            "Text",
            "x20 y185 w340 h35"
            . " Background00D68F"
            . " c11151C"
            . " Center 0x200",
            "저장"
        )

    SaveButton.SetFont(
        "s10 Bold"
    )

    SaveFunc :=
        SaveTimeline.Bind(
            MemoGui,
            MemoEdit,
            ElapsedSec
        )

    SaveButton.OnEvent(
        "Click",
        SaveFunc
    )

    MemoGui.OnEvent(
        "Close",
        (*) => DisableEnterHotkey()
    )

    MemoGui.Show(
        "w380 h245"
    )
    EnableRoundedGui(MemoGui)

    MemoEdit.Focus()

    HotIfWinActive(
        "ahk_id " MemoGui.Hwnd
    )

    Hotkey(
        "Enter",
        SaveFunc,
        "On"
    )
}


; ============================================================
; 수동 타임라인 추가
;
; 다시보기를 보면서 나중에 타임라인을 직접 추가한다.
; 영상 링크 → 방송 시작시간 자동 확인
; 시간(시:분:초) + 설명 → 기존 timeline.csv에 추가
; ============================================================

ShowManualTimelineGui(EditMode := false, EditData := 0)
{
    global TimelineCalendarState

    if (EditMode)
    {
        WindowTitle := "수동 타임라인 수정"
        HeaderTitle := "수동 타임라인 수정"
        HeaderSubTitle := "영상 시간과 설명을 수정합니다. 다시보기 링크는 고정됩니다."
        SaveButtonText := "타임라인 수정"
    }
    else
    {
        WindowTitle := "수동 타임라인 추가"
        HeaderTitle := "수동 타임라인 추가"
        HeaderSubTitle := "다시보기의 영상 위치와 설명을 타임라인에 직접 기록합니다."
        SaveButtonText := "타임라인 추가"
    }

    GuiObj :=
        Gui(
            "+AlwaysOnTop -MaximizeBox -MinimizeBox",
            WindowTitle
        )

    GuiObj.BackColor := "11151C"
    GuiObj.SetFont("s9", "맑은 고딕")

    GuiObj.SetFont("s15 Bold", "맑은 고딕")
    GuiObj.Add(
        "Text",
        "x20 y16 w400 h30 cFFFFFF",
        HeaderTitle
    )

    GuiObj.SetFont("s9", "맑은 고딕")
    GuiObj.Add(
        "Text",
        "x22 y47 w420 h22 c8B949E",
        HeaderSubTitle
    )

    ; ========================================================
    ; 영상 링크
    ; ========================================================

    GuiObj.SetFont("s11 Bold", "맑은 고딕")
    GuiObj.Add(
        "Text",
        "x22 y82 w400 h25 cFFFFFF",
        "영상 링크"
    )

    GuiObj.SetFont("s9", "맑은 고딕")
    LinkBg :=
        GuiObj.Add(
            "Text",
            "x15 y108 w440 h74 Background2A313B",
            ""
        )

    GuiObj.Add(
        "Text",
        "x16 y109 w438 h72 Background11151C",
        ""
    )

    LinkEdit :=
        GuiObj.Add(
            "Edit",
            "x30 y121 w315 h30 Background202733 cD6DCE5 -Border -E0x200",
            EditMode && IsObject(EditData) ? EditData.VodUrl : ""
        )
    RemoveEditBorder(LinkEdit.Hwnd)

    if (EditMode)
        LinkEdit.Opt("+ReadOnly")

    LoadButton :=
        GuiObj.Add(
            "Text",
            "x352 y121 w88 h30 Background202733 cD6DCE5 Center 0x200",
            EditMode ? "고정 링크" : "날짜 확인"
        )
    LoadButton.SetFont("s9 Bold")
    if !EditMode
        ApplyAccentOutline(GuiObj, LoadButton)

    LinkStatus :=
        GuiObj.Add(
            "Text",
            "x30 y155 w410 h20 c8B949E",
            "CHZZK 다시보기 링크를 입력하세요."
        )

    ; ========================================================
    ; 방송 날짜
    ; ========================================================

    GuiObj.SetFont("s11 Bold", "맑은 고딕")
    GuiObj.Add(
        "Text",
        "x22 y201 w400 h25 cFFFFFF",
        "방송 날짜"
    )

    GuiObj.SetFont("s9", "맑은 고딕")
    DateText :=
        GuiObj.Add(
            "Text",
            "x30 y229 w410 h28 c00D68F",
            EditMode && IsObject(EditData) ? EditData.SessionStart : "영상 링크를 확인하면 자동으로 지정됩니다."
        )
    DateText.SetFont("s10 Bold")

    ; ========================================================
    ; 시간
    ; ========================================================

    GuiObj.SetFont("s11 Bold", "맑은 고딕")
    GuiObj.Add(
        "Text",
        "x22 y275 w400 h25 cFFFFFF",
        "영상 시간"
    )

    GuiObj.SetFont("s9", "맑은 고딕")
    TimeBg :=
        GuiObj.Add(
            "Text",
            "x15 y302 w440 h70 Background2A313B",
            ""
        )
    GuiObj.Add(
        "Text",
        "x16 y303 w438 h68 Background11151C",
        ""
    )

    HourEdit := GuiObj.Add(
        "Edit",
        "x70 y319 w75 h32 Background202733 cD6DCE5 Center -Border -E0x200",
        EditMode && IsObject(EditData) ? SubStr(EditData.TimeText, 1, InStr(EditData.TimeText, ":") - 1) : ""
    )
    RemoveEditBorder(HourEdit.Hwnd)
    HourEdit.SetFont("s11 Bold")

    GuiObj.Add("Text", "x148 y323 w25 h22 c8B949E Center", ":")

    MinEdit := GuiObj.Add(
        "Edit",
        "x177 y319 w75 h32 Background202733 cD6DCE5 Center -Border -E0x200",
        EditMode && IsObject(EditData) ? SubStr(EditData.TimeText, InStr(EditData.TimeText, ":") + 1, 2) : ""
    )
    RemoveEditBorder(MinEdit.Hwnd)
    MinEdit.SetFont("s11 Bold")

    GuiObj.Add("Text", "x255 y323 w25 h22 c8B949E Center", ":")

    SecEdit := GuiObj.Add(
        "Edit",
        "x284 y319 w75 h32 Background202733 cD6DCE5 Center -Border -E0x200",
        EditMode && IsObject(EditData) ? SubStr(EditData.TimeText, -2) : ""
    )
    RemoveEditBorder(SecEdit.Hwnd)
    SecEdit.SetFont("s11 Bold")

    GuiObj.Add(
        "Text",
        "x365 y323 w65 h22 c8B949E",
        "시:분:초"
    )

    GuiObj.Add(
        "Text",
        "x30 y350 w400 h20 c8B949E",
        "다시보기에서 현재 재생 위치를 입력하세요."
    )

    ; ========================================================
    ; 설명
    ; ========================================================

    GuiObj.SetFont("s11 Bold", "맑은 고딕")
    GuiObj.Add(
        "Text",
        "x22 y390 w400 h25 cFFFFFF",
        "설명"
    )

    GuiObj.SetFont("s9", "맑은 고딕")
    MemoBg :=
        GuiObj.Add(
            "Text",
            "x15 y417 w440 h68 Background2A313B",
            ""
        )

    MemoEdit :=
        GuiObj.Add(
            "Edit",
            "x20 y422 w430 h58 Background202733 cD6DCE5 -Border -E0x200 +Multi",
            EditMode && IsObject(EditData) ? EditData.Memo : ""
        )
    RemoveEditBorder(MemoEdit.Hwnd)

    ; ========================================================
    ; 하단
    ; ========================================================

    CancelButton :=
        GuiObj.Add(
            "Text",
            "x15 y500 w105 h36 Background202733 cD6DCE5 Center 0x200",
            "취소"
        )

    SaveButton :=
        GuiObj.Add(
            "Text",
            "x130 y500 w325 h36 Background00D68F c11151C Center 0x200",
            SaveButtonText
        )
    SaveButton.SetFont("s10 Bold")

    ; 시간 → 분 → 초를 두 자리 입력하면 자동으로 다음 칸으로 이동
    HourEdit.OnEvent(
        "Change",
        AdvanceManualTimeField.Bind(HourEdit, MinEdit, 2)
    )

    MinEdit.OnEvent(
        "Change",
        AdvanceManualTimeField.Bind(MinEdit, SecEdit, 2)
    )

    State := {
        VodStart: "",
        VideoNo: "",
        LastCheckedUrl: ""
    }

    if (EditMode && IsObject(EditData))
    {
        State.VodStart := EditData.SessionStart
        State.VideoNo := GetVideoNoFromUrl(EditData.VodUrl)
        State.LastCheckedUrl := EditData.VodUrl
        LinkStatus.Text := "수정 중 · 링크는 고정됩니다."
        LinkStatus.Opt("c8B949E")
    }

    LoadFunc :=
        LoadManualTimelineVod.Bind(
            LinkEdit,
            DateText,
            LinkStatus,
            State
        )

    if (!EditMode)
    {
        LoadButton.OnEvent("Click", LoadFunc)
        LinkEdit.OnEvent("LoseFocus", LoadFunc)
    }

    SaveFunc :=
        SaveManualTimeline.Bind(
            GuiObj,
            LinkEdit,
            HourEdit,
            MinEdit,
            SecEdit,
            MemoEdit,
            DateText,
            State,
            EditMode,
            EditData
        )

    SaveButton.OnEvent("Click", SaveFunc)
    CancelButton.OnEvent("Click", (*) => GuiObj.Destroy())
    GuiObj.OnEvent("Close", (*) => GuiObj.Destroy())

    GuiObj.Show("w470 h555")
    EnableRoundedGui(GuiObj)
    LinkEdit.Focus()
}


; ============================================================
; 수동 타임라인 시간 입력 자동 이동
; ============================================================

AdvanceManualTimeField(CurrentEdit, NextEdit, MaxDigits, *)
{
    Value := Trim(CurrentEdit.Value)

    ; 숫자 이외의 문자가 들어오면 제거
    CleanValue := RegExReplace(Value, "[^0-9]", "")

    if (CleanValue != Value)
    {
        CurrentEdit.Value := CleanValue
        Value := CleanValue
    }

    ; 두 자리 입력 완료 시 다음 칸으로 이동
    if (StrLen(Value) >= MaxDigits)
    {
        if (StrLen(Value) > MaxDigits)
        {
            CurrentEdit.Value := SubStr(Value, 1, MaxDigits)
        }

        NextEdit.Focus()
    }
}


; ============================================================
; 수동 타임라인 VOD 정보 확인
; ============================================================

LoadManualTimelineVod(
    LinkEdit,
    DateText,
    StatusText,
    State,
    *
)
{
    Url := Trim(LinkEdit.Value)

    if (Url = "")
    {
        State.VodStart := ""
        State.VideoNo := ""
        State.LastCheckedUrl := ""
        DateText.Text := "영상 링크를 입력하면 자동으로 지정됩니다."
        StatusText.Text := "CHZZK 다시보기 링크를 입력하세요."
        StatusText.Opt("c8B949E")
        return false
    }

    if (Url = State.LastCheckedUrl)
        return State.VodStart != ""

    VideoNo := GetVideoNoFromUrl(Url)

    if (VideoNo = "")
    {
        State.VodStart := ""
        State.VideoNo := ""
        State.LastCheckedUrl := ""
        DateText.Text := "방송 날짜를 확인할 수 없습니다."
        StatusText.Text := "올바른 CHZZK VOD 링크를 입력해주세요."
        StatusText.Opt("cFF6B6B")
        return false
    }

    StatusText.Text := "영상 정보를 확인하는 중..."
    StatusText.Opt("c8B949E")

    VodStart := GetVodLiveOpenDate(VideoNo)

    if (VodStart = "")
    {
        State.VodStart := ""
        State.VideoNo := ""
        State.LastCheckedUrl := ""
        DateText.Text := "방송 날짜를 확인할 수 없습니다."
        StatusText.Text := "VOD 정보를 가져오지 못했습니다. 링크를 확인해주세요."
        StatusText.Opt("cFF6B6B")
        return false
    }

    State.VodStart := VodStart
    State.VideoNo := VideoNo
    State.LastCheckedUrl := Url

    DateText.Text := FormatSessionDate(VodStart)
    StatusText.Text := "✓ 방송 시작시간을 확인했습니다."
    StatusText.Opt("c00D68F")

    return true
}


; ============================================================
; CHZZK VOD 링크 → videoNo
; ============================================================

GetVideoNoFromUrl(Url)
{
    Url := Trim(Url)

    if RegExMatch(
        Url,
        "i)(?:chzzk\.naver\.com/(?:video|videos)/)([0-9]+)",
        &Match
    )
    {
        return Match[1]
    }

    return ""
}


BackfillTimelineVodTitles(*)
{
    global TimelineFile
    global TimelineCalendarState

    if !FileExist(TimelineFile)
    {
        TrayTip("기존 VOD 제목", "타임라인 파일이 없습니다.", 1)
        return
    }

    try
    {
        Text := FileRead(TimelineFile, "UTF-8")
        Lines := StrSplit(Text, "`n")
        TitleCache := Map()
        UpdatedCount := 0
        Changed := false

        for Index, Line in Lines
        {
            Line := StrReplace(Line, "`r", "")

            if (Line = "")
                continue

            Fields := ParseCsvLine(Line)

            if (Index = 1)
            {
                if (Fields.Length < 6)
                {
                    Fields.Push("VOD제목")
                    Changed := true
                }
                else if (Fields[6] != "VOD제목")
                {
                    Fields[6] := "VOD제목"
                    Changed := true
                }

                Lines[Index] := BuildCsvLine(Fields)
                continue
            }

            if (Fields.Length < 5)
                continue

            ExistingTitle := Fields.Length >= 6 ? Trim(Fields[6]) : ""
            if (ExistingTitle != "" && !IsLikelyMojibake(ExistingTitle))
                continue

            VideoNo := GetVideoNoFromUrl(Fields[5])

            if (VideoNo = "")
                continue

            if !TitleCache.Has(VideoNo)
            {
                ToolTip("기존 VOD 제목 조회 중...`n" . VideoNo)
                Info := GetVodInfo(VideoNo)
                TitleCache[VideoNo] := IsObject(Info) ? Info.VideoTitle : ""
            }

            VideoTitle := TitleCache[VideoNo]

            if (VideoTitle = "")
                continue

            if (VideoTitle = ExistingTitle)
                continue

            if (Fields.Length < 6)
                Fields.Push(VideoTitle)
            else
                Fields[6] := VideoTitle

            Lines[Index] := BuildCsvLine(Fields)
            UpdatedCount += 1
            Changed := true
        }

        ToolTip()

        if !Changed
        {
            TrayTip("기존 VOD 제목", "추가할 제목이 없습니다.", 1)
            return
        }

        if !BackupTimelineCsv("before_vod_title_backfill", true)
            throw Error("수정 전 타임라인 CSV 백업을 만들지 못했습니다.")

        RewriteTimelineFile(Lines)

        try
        {
            if IsObject(TimelineCalendarState)
            {
                LoadTimelineViewerList()
                RenderTimelineCalendar()
            }
        }
        catch
        {
        }

        TrayTip(
            "기존 VOD 제목",
            UpdatedCount . "개 타임라인의 VOD 제목을 보완했습니다.",
            1
        )
    }
    catch as Err
    {
        ToolTip()
        TrayTip("기존 VOD 제목", "제목을 채우지 못했습니다: " . Err.Message, 1)
    }
}


IsLikelyMojibake(Text)
{
    return RegExMatch(Text, "[ÃÂìëíê]")
        || RegExMatch(Text, "[\x{0080}-\x{009F}]")
}


; ============================================================
; 수동 타임라인 저장
; ============================================================

SaveManualTimeline(
    GuiObj,
    LinkEdit,
    HourEdit,
    MinEdit,
    SecEdit,
    MemoEdit,
    DateText,
    State,
    EditMode := false,
    EditData := 0,
    *
)
{
    global TimelineFile
    global TimelineCalendarState
    global VodReconnectInterval

    Url := Trim(LinkEdit.Value)
    Memo := Trim(MemoEdit.Value)

    if (State.VodStart = "" || State.LastCheckedUrl != Url)
    {
        DummyStatus := DateText
        if !LoadManualTimelineVod(
            LinkEdit,
            DateText,
            DummyStatus,
            State
        )
        {
            MsgBox(
                "먼저 유효한 CHZZK VOD 링크를 입력해주세요.",
                "수동 타임라인",
                "Icon!"
            )
            return
        }
    }

    if !RegExMatch(
        Trim(HourEdit.Value),
        "^\d{1,2}$",
        &HM
    )
    {
        MsgBox("시간(시)을 숫자로 입력해주세요.", "수동 타임라인", "Icon!")
        HourEdit.Focus()
        return
    }

    if !RegExMatch(
        Trim(MinEdit.Value),
        "^\d{1,2}$",
        &MM
    )
    {
        MsgBox("시간(분)을 숫자로 입력해주세요.", "수동 타임라인", "Icon!")
        MinEdit.Focus()
        return
    }

    if !RegExMatch(
        Trim(SecEdit.Value),
        "^\d{1,2}$",
        &SM
    )
    {
        MsgBox("시간(초)을 숫자로 입력해주세요.", "수동 타임라인", "Icon!")
        SecEdit.Focus()
        return
    }

    Hours := Integer(HourEdit.Value)
    Minutes := Integer(MinEdit.Value)
    Seconds := Integer(SecEdit.Value)

    if (Minutes > 59 || Seconds > 59)
    {
        MsgBox("분과 초는 0~59 사이로 입력해주세요.", "수동 타임라인", "Icon!")
        return
    }

    ElapsedSec :=
        Hours * 3600
        + Minutes * 60
        + Seconds

    if (ElapsedSec < 0)
        return

    if (Memo = "")
        Memo := "(메모 없음)"

    TimeText := FormatElapsed(ElapsedSec)
    RecordTime := FormatTime(A_Now, "yyyy-MM-dd HH:mm:ss")
    SessionStart := FormatSessionDate(State.VodStart)

    ; 저장되는 VOD 링크도 해당 타임라인 시점에서 바로 열리도록 만든다.
    TimelineVodUrl := BuildChzzkTimestampUrl(
        Url,
        ElapsedSec
    )

    ; ========================================================
    ; 기존 타임라인 수정
    ; ========================================================
    if (EditMode && IsObject(EditData))
    {
        if (EditData.FileLine <= 1 || !FileExist(TimelineFile))
        {
            MsgBox("수정할 타임라인을 찾을 수 없습니다.", "수정 오류", "Icon!")
            return
        }

        try
        {
            Text := FileRead(TimelineFile, "UTF-8")
            Lines := StrSplit(Text, "`n")
            FileLine := EditData.FileLine

            if (FileLine > Lines.Length)
                throw Error("타임라인 위치를 찾을 수 없습니다.")

            OriginalFields := ParseCsvLine(StrReplace(Lines[FileLine], "`r", ""))
            if (OriginalFields.Length < 5)
                throw Error("타임라인 데이터 형식이 올바르지 않습니다.")

            OriginalSessionStart := Trim(OriginalFields[1])
            OriginalRecordTime := Trim(OriginalFields[4])
            OriginalVodUrl := Trim(OriginalFields[5])

            UpdatedLine := BuildTimelineCsvLine(
                OriginalSessionStart,
                TimeText,
                Memo,
                OriginalRecordTime,
                BuildChzzkTimestampUrl(OriginalVodUrl, ElapsedSec),
                OriginalFields.Length >= 6 ? OriginalFields[6] : ""
            )

            Lines[FileLine] := UpdatedLine

            if !BackupTimelineCsv("before_edit", true)
                throw Error("수정 전 CSV 백업을 만들지 못했습니다.")

            RewriteTimelineFile(Lines)
        }
        catch as Err
        {
            MsgBox(
                "타임라인 수정에 실패했습니다.`n`n" . Err.Message,
                "수정 오류",
                "Icon!"
            )
            return
        }

        GuiObj.Destroy()

        if IsObject(TimelineCalendarState)
        {
            try
            {
                RenderTimelineCalendar()
                LoadTimelineViewerList()
            }
            catch
            {
            }
        }

        TrayTip(
            "수동 타임라인 수정",
            OriginalSessionStart . " / " . TimeText . "로 수정했습니다.",
            1
        )
        return
    }

    if !FileExist(TimelineFile)
    {
        try
        {
            FileAppend(
                "방송시작,방송시간,메모,기록시각,VOD링크,VOD제목`r`n",
                TimelineFile,
                "UTF-8"
            )
        }
        catch as Err
        {
            MsgBox(
                "타임라인 파일을 만들 수 없습니다.`n`n" . Err.Message,
                "저장 오류",
                "Icon!"
            )
            return
        }
    }

    Line := BuildTimelineCsvLine(
        SessionStart,
        TimeText,
        Memo,
        RecordTime,
        TimelineVodUrl
    )

    if FileExist(TimelineFile)
    {
        if !BackupTimelineCsv("before_add", true)
        {
            MsgBox(
                "타임라인을 저장하기 전에 CSV 백업을 만들지 못했습니다.",
                "백업 오류",
                "Icon!"
            )
            return
        }
    }

    try
    {
        FileAppend(Line, TimelineFile, "UTF-8")
    }
    catch as Err
    {
        MsgBox(
            "타임라인 저장에 실패했습니다.`n`n" . Err.Message,
            "저장 오류",
            "Icon!"
        )
        return
    }

    ; 현재 타임라인 뷰어가 열려 있으면 즉시 새로고침
    if IsObject(TimelineCalendarState)
    {
        try
        {
            CurrentDate := TimelineCalendarState.SelectedDate
            TimelineCalendarState.Month := SubStr(SessionStart, 1, 7)
            TimelineCalendarState.SelectedDate := SubStr(SessionStart, 1, 10)
            RenderTimelineCalendar()
            LoadTimelineViewerList()
            TimelineCalendarState.SelectedDate := CurrentDate
            if (CurrentDate != "")
            {
                TimelineCalendarState.Month := SubStr(CurrentDate, 1, 7)
                RenderTimelineCalendar()
                LoadTimelineViewerList()
            }
        }
        catch
        {
        }
    }

    GuiObj.Destroy()

    TrayTip(
        "수동 타임라인 추가",
        SessionStart . " / " . TimeText . "에 타임라인을 추가했습니다.",
        1
    )
}


; ============================================================
; 타임라인 CSV 한 줄 생성
; ============================================================

BuildTimelineCsvLine(SessionStart, TimeText, Memo, RecordTime, VodUrl, VodTitle := "")
{
    Quote := Chr(34)
    Memo := StrReplace(Memo, "`r", " ")
    Memo := StrReplace(Memo, "`n", " ")

    return (
        Quote . StrReplace(SessionStart, Quote, Quote . Quote) . Quote . ","
        . Quote . StrReplace(TimeText, Quote, Quote . Quote) . Quote . ","
        . Quote . StrReplace(Memo, Quote, Quote . Quote) . Quote . ","
        . Quote . StrReplace(RecordTime, Quote, Quote . Quote) . Quote . ","
        . Quote . StrReplace(VodUrl, Quote, Quote . Quote) . Quote . ","
        . Quote . StrReplace(VodTitle, Quote, Quote . Quote) . Quote . "`r`n"
    )
}


; ============================================================
; 타임라인 CSV 백업
;
; 기본: data\timeline_backup\
; 최대 100개 유지
; 실제 CSV 변경이 발생하기 직전에만 백업
; 수동 추가/수정/삭제는 강제 백업
; 자동 VOD 연결은 60초 내 중복 백업 방지
; ============================================================

BackupTimelineCsv(Reason := "auto", Force := false)
{
    global TimelineFile
    global TimelineBackupDir
    global LastTimelineBackupAt
    global TimelineBackupMaxCount

    if !FileExist(TimelineFile)
        return true

    NowTick := A_TickCount

    if (!Force && LastTimelineBackupAt && (NowTick - LastTimelineBackupAt < 60000))
        return true

    try
    {
        if !DirExist(TimelineBackupDir)
            DirCreate(TimelineBackupDir)

        Stamp := FormatTime(A_Now, "yyyyMMdd_HHmmss")
        SafeReason := RegExReplace(Reason, "[^0-9A-Za-z_-]", "_")
        BackupPath := TimelineBackupDir "\timeline_" Stamp "_" SafeReason ".csv"

        Counter := 1
        while FileExist(BackupPath)
        {
            BackupPath := TimelineBackupDir "\timeline_" Stamp "_" SafeReason "_" Counter ".csv"
            Counter += 1
        }

        FileCopy(TimelineFile, BackupPath, false)
        LastTimelineBackupAt := NowTick

        Files := []
        Loop Files, TimelineBackupDir "\*.csv", "F"
            Files.Push(A_LoopFileFullPath)

        ; Loop Files returns names in sorted order. Backup names start with a
        ; timestamp, so the first item is the oldest backup to remove.

        while (Files.Length > TimelineBackupMaxCount)
        {
            Oldest := Files.RemoveAt(1)
            try FileDelete(Oldest)
        }

        return true
    }
    catch
    {
        return false
    }
}


; ============================================================
; 타임라인 CSV 전체 다시 저장
; ============================================================

RewriteTimelineFile(Lines)
{
    global TimelineFile

    Output := ""

    for Index, Line in Lines
    {
        Line := StrReplace(Line, "`r", "")
        if (Index = Lines.Length && Line = "")
            continue

        Output .= Line . "`r`n"
    }

    FileObj := FileOpen(TimelineFile, "w", "UTF-8")
    if !FileObj
        throw Error("타임라인 파일을 열 수 없습니다.")

    try
    {
        FileObj.Write(Output)
    }
    finally
    {
        FileObj.Close()
    }
}


; ============================================================
; Enter 핫키 제거
; ============================================================

DisableEnterHotkey()
{
    try
    {
        HotIfWinActive()

        Hotkey(
            "Enter",
            "Off"
        )
    }
    catch
    {
    }
}


; ============================================================
; 타임라인 저장
; ============================================================

SaveTimeline(
    MemoGui,
    MemoEdit,
    ElapsedSec,
    *
)
{
    global TimelineFile
    global BroadcastStart

    DisableEnterHotkey()

    Memo :=
        Trim(
            MemoEdit.Value
        )

    if (
        Memo = ""
    )
    {
        Memo :=
            "(메모 없음)"
    }

    Memo :=
        StrReplace(
            Memo,
            Chr(34),
            Chr(34) Chr(34)
        )

    Memo :=
        StrReplace(
            Memo,
            "`r",
            " "
        )

    Memo :=
        StrReplace(
            Memo,
            "`n",
            " "
        )

    TimeText :=
        FormatElapsed(
            ElapsedSec
        )

    RecordTime :=
        FormatTime(
            A_Now,
            "yyyy-MM-dd HH:mm:ss"
        )

    SessionStart :=
        FormatSessionDate(
            BroadcastStart
        )

    if !FileExist(
        TimelineFile
    )
    {
        try
        {
            FileAppend(
                "방송시작,방송시간,메모,기록시각,VOD링크,VOD제목`r`n",
                TimelineFile,
                "UTF-8"
            )
        }
        catch as Err
        {
            MsgBox(
                "타임라인 파일을 만들 수 없습니다.`n`n"
                . Err.Message,
                "저장 오류",
                "Icon!"
            )

            return
        }
    }

    Quote :=
        Chr(34)

    Line :=
        Quote
        . SessionStart
        . Quote
        . ","
        . Quote
        . TimeText
        . Quote
        . ","
        . Quote
        . Memo
        . Quote
        . ","
        . Quote
        . RecordTime
        . Quote
        . ","
        . Quote
        . ""
        . Quote
        . ","
        . Quote
        . ""
        . Quote
        . "`r`n"

    if FileExist(TimelineFile)
    {
        if !BackupTimelineCsv("before_add", true)
        {
            MsgBox(
                "타임라인을 저장하기 전에 CSV 백업을 만들지 못했습니다.",
                "백업 오류",
                "Icon!"
            )
            return
        }
    }

    try
    {
        FileAppend(
            Line,
            TimelineFile,
            "UTF-8"
        )
    }
    catch as Err
    {
        MsgBox(
            "타임라인 저장 실패.`n`n"
            . Err.Message,
            "저장 오류",
            "Icon!"
        )

        return
    }

    try
    {
        MemoGui.Destroy()
    }
    catch
    {
    }

    ToolTip(
        "🔖 타임라인 저장 완료`n"
        . TimeText
        . "  "
        . Memo
    )

    SetTimer(
        ClearTimelineToolTip,
        -1500
    )

    ; VOD 매칭 즉시 1회 시도.
    ; 이미 VOD가 올라와 있으면 저장 직후 바로 연결하고,
    ; 아직 VOD가 없으면 CheckPendingVodMatches()가 10분 후 재시도한다.
    SetTimer(
        CheckPendingVodMatches,
        -1
    )
}


; ============================================================
; CSV 파싱
; ============================================================

ParseCsvLine(
    Line
)
{
    Result := []

    Current := ""
    InQuotes := false

    Length :=
        StrLen(
            Line
        )

    Index := 1

    while (
        Index <= Length
    )
    {
        Char :=
            SubStr(
                Line,
                Index,
                1
            )

        if (
            Char = Chr(34)
        )
        {
            if (
                InQuotes
                && Index < Length
                && SubStr(
                    Line,
                    Index + 1,
                    1
                ) = Chr(34)
            )
            {
                Current :=
                    Current
                    . Chr(34)

                Index += 2

                continue
            }

            InQuotes :=
                !InQuotes

            Index += 1

            continue
        }

        if (
            Char = ","
            && !InQuotes
        )
        {
            Result.Push(
                Current
            )

            Current := ""

            Index += 1

            continue
        }

        Current :=
            Current
            . Char

        Index += 1
    }

    Result.Push(
        Current
    )

    return Result
}


; ============================================================
; CSV 생성
; ============================================================

BuildCsvLine(
    Fields
)
{
    Quote :=
        Chr(34)

    Result := ""

    for Index, Field in Fields
    {
        if (
            Index > 1
        )
        {
            Result :=
                Result
                . ","
        }

        Field :=
            StrReplace(
                Field,
                Chr(34),
                Chr(34) Chr(34)
            )

        Result :=
            Result
            . Quote
            . Field
            . Quote
    }

    return Result
}


; ============================================================
; 타임라인 뷰어
; ============================================================

ShowTimelineViewer()
{
    global TimelineFile
    global TimelineCalendarState

    Viewer := Gui("+Resize MinSize700x650", "🔖 치지직 타임라인")
    Viewer.BackColor := "11151C"
    Viewer.SetFont("s10", "맑은 고딕")

    Viewer.Add("Text", "x20 y28 w430 c00D68F", "치지직 타임라인")
    Viewer.Add("Text", "x20 y65 w650 c8B949E", "방송 시작 날짜를 기준으로 정리합니다. 자정을 넘어간 방송도 시작한 날짜에 귀속됩니다.")

    ; 이전 달 / 다음 달 버튼
    ; Windows 기본 흰색 Button 대신 어두운 커스텀 UI를 사용한다.
    ; 상단 날짜 이동 버튼
    ManualButton := Viewer.Add(
        "Text",
        "x365 y25 w105 h30 Background202733 cD6DCE5 Center 0x200",
        "+ 수동 타임라인"
    )
    ManualButton.SetFont("s9 Bold")
    ApplyAccentOutline(Viewer, ManualButton)

    PrevButton := Viewer.Add(
        "Text",
        "x485 y25 w40 h30 Background202733 cD6DCE5 Center 0x200",
        "<"
    )
    PrevButton.SetFont("s12 Bold")
    ApplyAccentOutline(Viewer, PrevButton)
    PrevButton.SetFont("s12 Bold", "맑은 고딕")

    ; 오늘 버튼은 초록색
    TodayButton := Viewer.Add(
        "Text",
        "x535 y25 w65 h30 Background00D68F c11151C Center 0x200",
        "오늘"
    )
    TodayButton.SetFont("s9 Bold")

    NextButton := Viewer.Add(
        "Text",
        "x610 y25 w40 h30 Background202733 cD6DCE5 Center 0x200",
        ">"
    )
    NextButton.SetFont("s12 Bold")
    ApplyAccentOutline(Viewer, NextButton)
    NextButton.SetFont("s12 Bold", "맑은 고딕")

    TimelineCalendarState := {
        Viewer: Viewer,
        Month: "",
        SelectedDate: "",
        MonthText: Viewer.Add("Text", "x20 y102 w665 h30 cFFFFFF Center 0x200", ""),
        DayControls: Map(),
        WeekControls: [],
        CalendarSlots: [],
        SelectionFrame: [],
        List: 0,
        StatusImageList: 0,
        SummaryText: 0,
        SearchEdit: 0,
        HoverRow: -2
    }
    TimelineCalendarState.MonthText.SetFont("s12 Bold")

    LatestDate := FormatTime(A_Now, "yyyy-MM-dd")

    TimelineCalendarState.SelectedDate := LatestDate
    TimelineCalendarState.Month := SubStr(LatestDate, 1, 7)

    TimelineCalendarState.SummaryText := Viewer.Add("Text", "x20 y405 w240 h25 c8B949E", "")
    TimelineCalendarState.SummaryText.SetFont("s10 Bold")

    TimelineCalendarState.SearchEdit := Viewer.Add(
        "Edit",
        "x330 y404 w355 h27 -Border -E0x200 Background202733 cFFFFFF"
    )
    TimelineCalendarState.SearchEdit.SetFont("s9", "맑은 고딕")
    Viewer.Add(
        "Text",
        "x270 y409 w55 h20 c8B949E Right",
        "검색"
    )

    List := Viewer.Add("ListView", "x20 y440 w665 h155 -Hdr -HScroll -Border -E0x200 Background11151C cD6DCE5", ["방송 시작", "영상 시간", "메모", "VOD 영상", "연결"])
    TimelineCalendarState.StatusImageList := 0
    List.ModifyCol(1, 145)
    List.ModifyCol(2, 75)
    List.ModifyCol(3, 225)
    List.ModifyCol(4, 185)
    List.ModifyCol(5, 25)
    OnMessage(0x4E, TimelineListCustomDraw)
    DllCall("uxtheme\SetWindowTheme", "Ptr", List.Hwnd, "Str", " ", "Str", " ")
    SendMessage(0x1001, 0, 0x1C1511, List.Hwnd)
    SendMessage(0x1024, 0, 0xE5DCD6, List.Hwnd)
    SendMessage(0x1025, 0, 0x3B312A, List.Hwnd)

    TimelineCalendarState.List := List

    EditButton := Viewer.Add(
        "Text",
        "x20 y605 w105 h30 Background202733 cD6DCE5 Center 0x200",
        "수정"
    )
    EditButton.SetFont("s9 Bold")

    DeleteButton := Viewer.Add(
        "Text",
        "x135 y605 w105 h30 Background202733 cFF6B6B Center 0x200",
        "삭제"
    )
    DeleteButton.SetFont("s9 Bold")

    ReconnectButton := Viewer.Add(
        "Text",
        "x250 y605 w135 h30 Background202733 cD6DCE5 Center 0x200",
        "↻ VOD 재연결"
    )
    ApplyAccentOutline(Viewer, ReconnectButton)

    ChapterButton := Viewer.Add(
        "Text",
        "x400 y605 w135 h30 Background202733 cD6DCE5 Center 0x200",
        "챕터 생성"
    )
    ApplyAccentOutline(Viewer, ChapterButton)

    EditButton.OnEvent("Click", EditSelectedTimeline.Bind(List))
    DeleteButton.OnEvent("Click", DeleteSelectedTimeline.Bind(List))
    ReconnectButton.OnEvent("Click", ReconnectPendingVodsManually)
    ChapterButton.OnEvent("Click", GenerateSelectedVodChapters.Bind(List))
    List.OnEvent("DoubleClick", OpenSelectedTimeline.Bind(List))
    ManualButton.OnEvent("Click", (*) => ShowManualTimelineGui())
    PrevButton.OnEvent("Click", (*) => ChangeTimelineMonth(-1))
    NextButton.OnEvent("Click", (*) => ChangeTimelineMonth(1))
    TodayButton.OnEvent("Click", (*) => SelectTimelineToday())
    TimelineCalendarState.SearchEdit.OnEvent("Change", (*) => LoadTimelineViewerList())
    Viewer.OnEvent("Close", CloseTimelineViewer)

    ; 반드시 창을 먼저 표시한 뒤 날짜 컨트롤을 생성한다.
    Viewer.Show("w705 h650")
    SetTimer(UpdateTimelineHoverTip, 100)

    RenderTimelineCalendar()
    LoadTimelineViewerList()
}


; ============================================================
; 달력의 해당 월 날짜 수
; ============================================================

GetTimelineDaysInMonth(Year, MonthNum)
{
    ; 2월
    if (MonthNum = 2)
    {
        IsLeapYear :=
            Mod(Year, 400) = 0
            || (
                Mod(Year, 4) = 0
                && Mod(Year, 100) != 0
            )

        return IsLeapYear ? 29 : 28
    }

    ; 4, 6, 9, 11월은 30일
    if (
        MonthNum = 4
        || MonthNum = 6
        || MonthNum = 9
        || MonthNum = 11
    )
        return 30

    ; 나머지 1, 3, 5, 7, 8, 10, 12월은 31일
    return 31
}


; ============================================================
; 달력 렌더링
; ============================================================

RenderTimelineCalendar()
{
    global TimelineCalendarState

    if !IsObject(TimelineCalendarState)
        return

    Viewer := TimelineCalendarState.Viewer

    Month := TimelineCalendarState.Month
    if !RegExMatch(Month, "^(\d{4})-(\d{2})$", &m)
        return

    Year := Integer(m[1])
    MonthNum := Integer(m[2])

    if (MonthNum < 1 || MonthNum > 12)
        return

    DaysInMonth := GetTimelineDaysInMonth(Year, MonthNum)
    FirstDay := Format("{:04}{:02}01000000", Year, MonthNum)
    Weekday := Integer(FormatTime(FirstDay, "WDay"))

    TimelineCalendarState.MonthText.Text :=
        Year . "년 " . MonthNum . "월"

    CellW := 95
    CellH := 39
    StartX := 20
    StartY := 135

    ; --------------------------------------------------------
    ; 달력 컨트롤은 최초 1회만 만든다.
    ; 월을 넘길 때 기존 컨트롤을 삭제/재생성하지 않고
    ; 42칸을 재사용해서 이전 달력 잔상이 생기지 않게 한다.
    ; --------------------------------------------------------

    if (TimelineCalendarState.CalendarSlots.Length = 0)
    {
        WeekNames := ["일", "월", "화", "수", "목", "금", "토"]

        for Col, Name in WeekNames
        {
            Ctrl := Viewer.Add(
                "Text",
                "x" (StartX + (Col - 1) * CellW)
                . " y" StartY
                . " w" CellW
                . " h25 Background202733 c8B949E Center 0x200",
                Name
            )
            Ctrl.SetFont("s9 Bold")
            TimelineCalendarState.WeekControls.Push(Ctrl)
        }

        Loop 42
        {
            SlotIndex := A_Index

            Ctrl := Viewer.Add(
                "Text",
                "x" StartX
                . " y" (StartY + 28)
                . " w" (CellW - 3)
                . " h" (CellH - 3)
                . " Background202733 cD6DCE5 Center 0x200",
                ""
            )

            Ctrl.SetFont("s10")
            Ctrl.OnEvent(
                "Click",
                SelectTimelineSlot.Bind(SlotIndex)
            )

            TimelineCalendarState.CalendarSlots.Push(Ctrl)
        }

        ; 선택 날짜에 사용할 둥근 초록 테두리를 만든다.
        FrameControls := AddRoundedOutlineControls(
            Viewer,
            StartX,
            StartY + 28,
            CellW - 3,
            CellH - 3,
            "00D68F",
            1,
            6
        )
        for _, FrameControl in FrameControls
            FrameControl.Visible := false
        TimelineCalendarState.SelectionFrame := FrameControls
    }

    DatesWithTimeline := GetTimelineDateMap()

    ; 이전 달의 날짜 키를 제거하고 현재 달만 다시 채운다.
    TimelineCalendarState.DayControls := Map()

    ; --------------------------------------------------------
    ; 42칸 전체를 매번 초기화한다.
    ; 이번 달에 없는 칸은 숨긴다.
    ; --------------------------------------------------------

    Loop 42
    {
        SlotIndex := A_Index
        Ctrl := TimelineCalendarState.CalendarSlots[SlotIndex]

        Index := SlotIndex - 1
        Row := Floor(Index / 7)
        Col := Mod(Index, 7)

        Ctrl.Move(
            StartX + Col * CellW,
            StartY + 28 + Row * CellH,
            CellW - 3,
            CellH - 3
        )

        Ctrl.Visible := false
        Ctrl.Text := ""
        Ctrl.Opt("Background202733 cD6DCE5")
        Ctrl.SetFont("s10")
    }

    ; --------------------------------------------------------
    ; 현재 달의 날짜만 표시
    ; --------------------------------------------------------

    Loop DaysInMonth
    {
        Day := A_Index
        Index := (Weekday - 1) + (Day - 1)
        SlotIndex := Index + 1

        Ctrl := TimelineCalendarState.CalendarSlots[SlotIndex]

        DateKey :=
            Format(
                "{:04}-{:02}-{:02}",
                Year,
                MonthNum,
                Day
            )

        HasTimeline := DatesWithTimeline.Has(DateKey)
        IsSelected :=
            (DateKey = TimelineCalendarState.SelectedDate)

        Label :=
            HasTimeline
            ? (Day . "  ●")
            : Day

        if IsSelected
        {
            ; 선택 날짜는 기존 바탕을 유지하고 글자색과 테두리만 강조한다.
            Ctrl.Opt("Background202733 c00D68F")
            Ctrl.SetFont("s10 Bold", "맑은 고딕")
        }
        else
        {
            Ctrl.Opt("Background202733 cD6DCE5")

            if HasTimeline
                Ctrl.SetFont("s10 Bold")
            else
                Ctrl.SetFont("s10")
        }

        Ctrl.Text := Label
        Ctrl.Visible := true

        TimelineCalendarState.DayControls[DateKey] := Ctrl
    }

    ; 선택 날짜 둘레에만 1px 초록 테두리를 표시한다.
    for _, FrameEdge in TimelineCalendarState.SelectionFrame
        FrameEdge.Visible := false

    if TimelineCalendarState.DayControls.Has(TimelineCalendarState.SelectedDate)
    {
        SelectedCell := TimelineCalendarState.DayControls[TimelineCalendarState.SelectedDate]
        SelectedCell.GetPos(&CellX, &CellY, &CellW, &CellH)
        MoveRoundedOutlineControls(
            TimelineCalendarState.SelectionFrame,
            CellX,
            CellY,
            CellW,
            CellH,
            1,
            6
        )
        for _, FrameControl in TimelineCalendarState.SelectionFrame
            FrameControl.Visible := true
    }

    EnableRoundedGui(Viewer, true)
}


; ============================================================
; 달력 날짜 슬롯 클릭
; ============================================================

SelectTimelineSlot(
    SlotIndex,
    *
)
{
    global TimelineCalendarState

    Month := TimelineCalendarState.Month

    if !RegExMatch(
        Month,
        "^(\d{4})-(\d{2})$",
        &m
    )
        return

    Year := Integer(m[1])
    MonthNum := Integer(m[2])

    DaysInMonth :=
        GetTimelineDaysInMonth(
            Year,
            MonthNum
        )

    FirstDay :=
        Format(
            "{:04}{:02}01000000",
            Year,
            MonthNum
        )

    Weekday :=
        Integer(
            FormatTime(
                FirstDay,
                "WDay"
            )
        )

    Index := SlotIndex - 1
    Day := Index - (Weekday - 1) + 1

    if (
        Day < 1
        || Day > DaysInMonth
    )
        return

    DateKey :=
        Format(
            "{:04}-{:02}-{:02}",
            Year,
            MonthNum,
            Day
        )

    SelectTimelineDate(
        DateKey
    )
}

; ============================================================
; 달력 월 이동
; ============================================================

ChangeTimelineMonth(Offset)
{
    global TimelineCalendarState

    Month := TimelineCalendarState.Month

    if !RegExMatch(Month, "^(\d{4})-(\d{2})$", &m)
        return

    Year := Integer(m[1])
    MonthNum := Integer(m[2]) + Offset

    while (MonthNum > 12)
    {
        MonthNum -= 12
        Year += 1
    }

    while (MonthNum < 1)
    {
        MonthNum += 12
        Year -= 1
    }

    TimelineCalendarState.Month :=
        Format("{:04}-{:02}", Year, MonthNum)

    TimelineCalendarState.SelectedDate :=
        TimelineCalendarState.Month . "-01"

    RenderTimelineCalendar()
    LoadTimelineViewerList()
}

; ============================================================
; 오늘 선택
; ============================================================

SelectTimelineToday()
{
    global TimelineCalendarState

    DateKey :=
        FormatTime(
            A_Now,
            "yyyy-MM-dd"
        )

    TimelineCalendarState.SelectedDate :=
        DateKey

    TimelineCalendarState.Month :=
        SubStr(DateKey, 1, 7)

    RenderTimelineCalendar()
    LoadTimelineViewerList()
}


; ============================================================
; 날짜 선택
; ============================================================

SelectTimelineDate(
    DateKey,
    *
)
{
    global TimelineCalendarState

    TimelineCalendarState.SelectedDate :=
        DateKey

    TimelineCalendarState.Month :=
        SubStr(DateKey, 1, 7)

    RenderTimelineCalendar()
    LoadTimelineViewerList()
}


; ============================================================
; 기록이 존재하는 날짜 목록
; ============================================================

GetTimelineDateMap()
{
    global TimelineFile

    Result := Map()

    if !FileExist(TimelineFile)
        return Result

    try
    {
        Text :=
            FileRead(
                TimelineFile,
                "UTF-8"
            )

        Lines :=
            StrSplit(Text, "`n")

        for Index, Line in Lines
        {
            Line :=
                StrReplace(Line, "`r", "")

            if (Line = "" || Index = 1)
                continue

            Fields :=
                ParseCsvLine(Line)

            if (Fields.Length < 1)
                continue

            SessionStart :=
                Trim(Fields[1])

            if (SessionStart = "")
                continue

            DateKey :=
                GetTimelineDateKey(SessionStart)

            if (DateKey != "")
                Result[DateKey] := true
        }
    }
    catch
    {
    }

    return Result
}


; ============================================================
; 가장 최근 방송 시작 날짜
; ============================================================

GetLatestTimelineDate()
{
    global TimelineFile

    Latest := ""

    if !FileExist(TimelineFile)
        return ""

    try
    {
        Text := FileRead(TimelineFile, "UTF-8")
        Lines := StrSplit(Text, "`n")

        for Index, Line in Lines
        {
            if (Index = 1)
                continue

            Line := StrReplace(Line, "`r", "")

            if (Line = "")
                continue

            Fields := ParseCsvLine(Line)

            if (Fields.Length < 1)
                continue

            SessionStart := Trim(Fields[1])

            if (SessionStart = "")
                continue

            DateKey := GetTimelineDateKey(SessionStart)

            if (
                DateKey != ""
                && (Latest = "" || DateKey > Latest)
            )
            {
                Latest := DateKey
            }
        }
    }
    catch
    {
    }

    return Latest
}


; ============================================================
; 방송 시작시간 → 달력 날짜
; ============================================================

GetTimelineDateKey(
    SessionStart
)
{
    SessionStart := Trim(SessionStart)

    if (
        RegExMatch(
            SessionStart,
            "^(\d{4})-(\d{2})-(\d{2})\s+\d{2}:\d{2}:\d{2}$",
            &M
        )
    )
    {
        return M[1] . "-" . M[2] . "-" . M[3]
    }

    if RegExMatch(
        SessionStart,
        "^(\d{4})(\d{2})(\d{2})\d{6}$",
        &M
    )
    {
        return M[1] . "-" . M[2] . "-" . M[3]
    }

    return ""
}


; ============================================================
; 선택 날짜의 타임라인 목록
; ============================================================

LoadTimelineViewerList()
{
    global TimelineFile
    global TimelineViewerLinks
    global TimelineViewerRows
    global TimelineViewerHoverInfo
    global TimelineViewerStatusColors
    global TimelineCalendarState

    List := TimelineCalendarState.List

    if !List
        return

    List.Delete()
    TimelineViewerLinks := Map()
    TimelineViewerRows := Map()
    TimelineViewerHoverInfo := Map()
    TimelineViewerStatusColors := Map()
    TimelineCalendarState.HoverRow := -2

    SelectedDate :=
        TimelineCalendarState.SelectedDate

    SearchQuery := ""
    if IsObject(TimelineCalendarState.SearchEdit)
        SearchQuery := Trim(TimelineCalendarState.SearchEdit.Value)

    if (SelectedDate = "")
        return

    Count := 0
    SessionMap := Map()

    if !FileExist(TimelineFile)
    {
        if (SearchQuery != "")
            TimelineCalendarState.SummaryText.Text := "검색 결과 없음"
        else
            TimelineCalendarState.SummaryText.Text := SelectedDate . "  ·  기록 없음"
        return
    }

    try
    {
        Text := FileRead(TimelineFile, "UTF-8")
        Lines := StrSplit(Text, "`n")

        for Index, Line in Lines
        {
            if (Index = 1)
                continue

            Line := StrReplace(Line, "`r", "")

            if (Line = "")
                continue

            Fields := ParseCsvLine(Line)

            if (Fields.Length < 5)
                continue

            SessionStart := Trim(Fields[1])
            TimeText := Trim(Fields[2])
            Memo := Fields[3]
            VodUrl := Trim(Fields[5])
            VideoTitle := Fields.Length >= 6 ? Fields[6] : ""

            DateKey := GetTimelineDateKey(SessionStart)

            if (SearchQuery = "")
            {
                if (DateKey != SelectedDate)
                    continue
            }
            else
            {
                SearchTarget :=
                    SessionStart . " "
                    . TimeText . " "
                    . Memo . " "
                    . VodUrl . " "
                    . VideoTitle

                MatchesSearch := true
                for _, Term in StrSplit(SearchQuery, " ")
                {
                    Term := Trim(Term)
                    if (Term != "" && !InStr(SearchTarget, Term))
                    {
                        MatchesSearch := false
                        break
                    }
                }

                if !MatchesSearch
                    continue
            }

            Count += 1

            VodDisplay := VideoTitle != "" ? VideoTitle : (VodUrl != "" ? "다시보기" : "VOD 확인 필요")
            if VodUrl != ""
                VodDisplay := "◀ " . VodDisplay

            List.Add(
                "",
                SessionStart,
                TimeText,
                Memo,
                VodDisplay,
                "●"
            )
            TimelineViewerStatusColors[Count - 1] := VodUrl != "" ? 0x0060C840 : 0x004444F0

            TimelineViewerLinks[Count] := VodUrl
            TimelineViewerRows[Count] := Index
            TimelineViewerHoverInfo[Count] := {
                SessionStart: SessionStart,
                ElapsedSeconds: ParseElapsedTime(TimeText),
                VideoTitle: VideoTitle
            }
        }
    }
    catch
    {
    }

    if (SearchQuery != "")
    {
        TimelineCalendarState.SummaryText.Text :=
            "검색 결과 " . Count . "개"
    }
    else
    {
        TimelineCalendarState.SummaryText.Text :=
            SelectedDate
            . "  ·  타임라인 "
            . Count
            . "개"
    }

    List.Redraw()
}


GenerateSelectedVodChapters(List, *)
{
    global TimelineViewerLinks

    RowNumber := List.GetNext(0)
    if (RowNumber <= 0)
    {
        MsgBox("먼저 챕터를 만들 VOD의 타임라인을 선택하세요.", "챕터 생성", "Iconi")
        return
    }

    if !TimelineViewerLinks.Has(RowNumber) || TimelineViewerLinks[RowNumber] = ""
    {
        MsgBox("선택한 타임라인은 아직 VOD에 연결되지 않았습니다.", "챕터 생성", "Iconi")
        return
    }

    SessionStart := List.GetText(RowNumber, 1)
    VodUrl := TimelineViewerLinks[RowNumber]
    VideoTitle := StrReplace(List.GetText(RowNumber, 4), "◀ ", "")

    if !RegExMatch(VodUrl, "/video/(\d+)", &VideoMatch)
    {
        MsgBox("선택한 VOD 링크에서 영상 번호를 찾지 못했습니다.", "챕터 생성", "Icon!")
        return
    }

    VideoId := VideoMatch[1]
    ChapterText := BuildVodChapterText(SessionStart, VideoId, VideoTitle)
    if (ChapterText = "")
    {
        MsgBox("VOD 챕터를 만들 기록을 찾지 못했습니다.", "챕터 생성", "Iconi")
        return
    }

    ShowVodChapterPreview(VideoTitle, ChapterText)
}


BuildVodChapterText(SessionStart, TargetVideoId, VideoTitle := "")
{
    global TimelineFile
    global CategoryHistoryFile

    SessionKey := NormalizeSessionDate(SessionStart)
    if (SessionKey = "" || !FileExist(TimelineFile))
        return ""

    TimelineRows := []
    SegmentStarts := Map()

    try
    {
        Lines := StrSplit(FileRead(TimelineFile, "UTF-8"), "`n")
        for Index, Line in Lines
        {
            if (Index = 1)
                continue

            Line := StrReplace(Line, "`r", "")
            if (Line = "")
                continue

            Fields := ParseCsvLine(Line)
            if (Fields.Length < 5 || NormalizeSessionDate(Fields[1]) != SessionKey)
                continue

            ElapsedSeconds := ParseElapsedTime(Trim(Fields[2]))
            if (ElapsedSeconds < 0)
                continue

            VodUrl := Trim(Fields[5])
            RowVideoId := ""
            VodSeconds := -1
            if (
                VodUrl != ""
                && RegExMatch(VodUrl, "/video/(\d+)", &VideoMatch)
                && RegExMatch(VodUrl, "(?:\?|&)currentTime=(\d+)", &TimeMatch)
            )
            {
                RowVideoId := VideoMatch[1]
                VodSeconds := Integer(TimeMatch[1])
                SegmentStart := ElapsedSeconds - VodSeconds
                if !SegmentStarts.Has(RowVideoId) || SegmentStart < SegmentStarts[RowVideoId]
                    SegmentStarts[RowVideoId] := SegmentStart
            }

            RowTitle := Fields.Length >= 6 ? Trim(Fields[6]) : ""
            if (RowVideoId = TargetVideoId && VideoTitle = "" && RowTitle != "")
                VideoTitle := RowTitle

            TimelineRows.Push({
                Elapsed: ElapsedSeconds,
                Memo: Trim(Fields[3]),
                VideoId: RowVideoId
            })
        }
    }
    catch
    {
        return ""
    }

    if !SegmentStarts.Has(TargetVideoId)
        return ""

    SegmentStart := SegmentStarts[TargetVideoId]
    SegmentEnd := 2147483647
    for VideoId, OtherStart in SegmentStarts
    {
        if (VideoId != TargetVideoId && OtherStart > SegmentStart && OtherStart < SegmentEnd)
            SegmentEnd := OtherStart
    }

    if (VideoTitle = "" || VideoTitle = "다시보기")
        VideoTitle := "VOD " . TargetVideoId

    ChapterEvents := []
    CategoryAtStart := ""
    if FileExist(CategoryHistoryFile)
    {
        try
        {
            CategoryLines := StrSplit(FileRead(CategoryHistoryFile, "UTF-8"), "`n")
            for Index, Line in CategoryLines
            {
                if (Index = 1)
                    continue

                Line := StrReplace(Line, "`r", "")
                if (Line = "")
                    continue

                Fields := ParseCsvLine(Line)
                if (Fields.Length < 6 || NormalizeSessionDate(Fields[1]) != SessionKey)
                    continue

                ChangeKey := NormalizeSessionDate(Fields[2])
                CategoryName := Trim(Fields[6])
                if (ChangeKey = "" || CategoryName = "")
                    continue

                ChangeElapsed := DateDiff(ChangeKey, SessionKey, "Seconds")
                if (ChangeElapsed <= SegmentStart)
                {
                    CategoryAtStart := CategoryName
                    continue
                }

                if (ChangeElapsed >= SegmentEnd)
                    continue

                ChapterEvents.Push({
                    Seconds: ChangeElapsed - SegmentStart,
                    Label: "카테고리: " . CategoryName
                })
            }
        }
        catch
        {
        }
    }

    for _, Row in TimelineRows
    {
        if (Row.Elapsed < SegmentStart || Row.Elapsed >= SegmentEnd)
            continue
        if (Row.VideoId != "" && Row.VideoId != TargetVideoId)
            continue

        LocalSeconds := Row.Elapsed - SegmentStart
        if (LocalSeconds <= 0)
            continue

        Label := Row.Memo != "" ? Row.Memo : "타임라인"
        Label := StrReplace(StrReplace(Label, "`r", " "), "`n", " ")
        ChapterEvents.Push({Seconds: LocalSeconds, Label: Label})
    }

    ; Sort events by VOD time using insertion sort.
    Index := 2
    while (Index <= ChapterEvents.Length)
    {
        Current := ChapterEvents[Index]
        CompareIndex := Index - 1
        while (CompareIndex >= 1 && ChapterEvents[CompareIndex].Seconds > Current.Seconds)
        {
            ChapterEvents[CompareIndex + 1] := ChapterEvents[CompareIndex]
            CompareIndex -= 1
        }
        ChapterEvents[CompareIndex + 1] := Current
        Index += 1
    }

    StartLabel := CategoryAtStart != "" ? "카테고리: " . CategoryAtStart : "방송 시작"
    Chapters := [{Seconds: 0, Label: StartLabel}]
    for _, Event in ChapterEvents
    {
        if (Event.Seconds < 0)
            continue

        LastChapter := Chapters[Chapters.Length]
        if (Event.Seconds - LastChapter.Seconds < 10)
        {
            if !InStr(LastChapter.Label, Event.Label)
                LastChapter.Label .= " · " . Event.Label
            continue
        }

        Chapters.Push({Seconds: Event.Seconds, Label: Event.Label})
    }

    Output := ""
    for _, Chapter in Chapters
        Output .= FormatVodChapterTime(Chapter.Seconds) . " " . Chapter.Label . "`r`n"

    return RTrim(Output, "`r`n")
}


FormatVodChapterTime(Seconds)
{
    Seconds := Max(0, Floor(Seconds))
    Hours := Floor(Seconds / 3600)
    Minutes := Floor(Mod(Seconds, 3600) / 60)
    RemainingSeconds := Mod(Seconds, 60)

    if (Hours > 0)
        return Format("{:02}:{:02}:{:02}", Hours, Minutes, RemainingSeconds)

    return Format("{:02}:{:02}", Minutes, RemainingSeconds)
}


ShowVodChapterPreview(VideoTitle, ChapterText)
{
    ChapterGui := Gui("+AlwaysOnTop", "VOD 챕터 생성")
    ChapterGui.BackColor := "11151C"
    ChapterGui.SetFont("s9", "맑은 고딕")
    ChapterGui.Add("Text", "x20 y18 w550 h22 c00D68F", "VOD 챕터")
    ChapterGui.Add("Text", "x20 y44 w550 h22 c8B949E", VideoTitle . " · 내용을 확인한 뒤 복사하세요.")

    ChapterEdit := ChapterGui.Add(
        "Edit",
        "x20 y75 w550 h235 Multi -Wrap Background202733 cFFFFFF",
        ChapterText
    )
    ChapterEdit.SetFont("s10", "맑은 고딕")
    ChapterGui.Add("Text", "x20 y312 w550 h16 c8B949E", "유튜브 챕터는 00:00 시작, 10초 이상 간격, 3개 이상이어야 인식됩니다.")

    CopyButton := ChapterGui.Add(
        "Text",
        "x20 y330 w135 h30 Background202733 cD6DCE5 Center 0x200",
        "클립보드 복사"
    )
    ApplyAccentOutline(ChapterGui, CopyButton)

    CloseButton := ChapterGui.Add(
        "Text",
        "x435 y330 w135 h30 Background202733 cD6DCE5 Center 0x200",
        "닫기"
    )
    CloseButton.SetFont("s9 Bold")
    CopyButton.OnEvent("Click", CopyVodChapterText.Bind(ChapterEdit))
    CloseButton.OnEvent("Click", CloseVodChapterPreview.Bind(ChapterGui))
    ChapterGui.Show("w590 h385")
}


CopyVodChapterText(EditControl, *)
{
    A_Clipboard := EditControl.Value
    ClipWait(1)
    ToolTip("VOD 챕터를 클립보드에 복사했습니다.")
    SetTimer(ClearTimelineToolTip, -2000)
}


CloseVodChapterPreview(GuiObj, *)
{
    GuiObj.Destroy()
}

TimelineListCustomDraw(wParam, lParam, msg, hwnd)
{
    global TimelineCalendarState
    global TimelineViewerStatusColors

    try
    {
        List := TimelineCalendarState.List
        if (!List || NumGet(lParam, 0, "Ptr") != List.Hwnd)
            return

        DrawStageOffset := A_PtrSize * 3
        DrawStage := NumGet(lParam, DrawStageOffset, "UInt")
        if (DrawStage = 0x00000001) ; CDDS_PREPAINT
            return 0x00000020 ; CDRF_NOTIFYITEMDRAW
        if (DrawStage = 0x00010001) ; CDDS_ITEMPREPAINT
            return 0x00000020 ; CDRF_NOTIFYSUBITEMDRAW
        if (DrawStage != 0x00030001) ; CDDS_ITEMPREPAINT | CDDS_SUBITEM
            return

        ItemOffset := A_PtrSize = 8 ? 56 : 36
        ColorOffset := A_PtrSize = 8 ? 80 : 48
        SubItemOffset := A_PtrSize = 8 ? 88 : 56
        ItemIndex := NumGet(lParam, ItemOffset, "UPtr")
        SubItemIndex := NumGet(lParam, SubItemOffset, "Int")
        if (SubItemIndex != 4 || !TimelineViewerStatusColors.Has(ItemIndex))
            return

        NumPut("UInt", TimelineViewerStatusColors[ItemIndex], lParam, ColorOffset)
        return 0x00000002 ; CDRF_NEWFONT: apply the custom status-circle color
    }
}



CreateVodStatusImageList()
{
    ImageList := IL_Create(2)
    if !ImageList
        return 0

    MaskColor := 0x00FF00FF
    GreenBitmap := CreateStatusCircleBitmap(0x0060C840, MaskColor, true)
    RedBitmap := CreateStatusCircleBitmap(0x004444F0, MaskColor)

    if GreenBitmap
    {
        DllCall("Comctl32\ImageList_AddMasked", "Ptr", ImageList, "Ptr", GreenBitmap, "UInt", MaskColor, "Int")
        DllCall("Gdi32\DeleteObject", "Ptr", GreenBitmap)
    }

    if RedBitmap
    {
        DllCall("Comctl32\ImageList_AddMasked", "Ptr", ImageList, "Ptr", RedBitmap, "UInt", MaskColor, "Int")
        DllCall("Gdi32\DeleteObject", "Ptr", RedBitmap)
    }

    return ImageList
}


CreateStatusCircleBitmap(CircleColor, MaskColor, IncludeArrow := false)
{
    IconWidth := DllCall("GetSystemMetrics", "Int", 49, "Int")
    IconHeight := DllCall("GetSystemMetrics", "Int", 50, "Int")
    if (IconWidth < 8 || IconHeight < 8)
        return 0

    ScreenDC := DllCall("GetDC", "Ptr", 0, "Ptr")
    if !ScreenDC
        return 0

    MemoryDC := DllCall("Gdi32\CreateCompatibleDC", "Ptr", ScreenDC, "Ptr")
    Bitmap := DllCall("Gdi32\CreateCompatibleBitmap", "Ptr", ScreenDC, "Int", IconWidth, "Int", IconHeight, "Ptr")
    if (!MemoryDC || !Bitmap)
    {
        if MemoryDC
            DllCall("Gdi32\DeleteDC", "Ptr", MemoryDC)
        if Bitmap
            DllCall("Gdi32\DeleteObject", "Ptr", Bitmap)
        DllCall("ReleaseDC", "Ptr", 0, "Ptr", ScreenDC)
        return 0
    }

    PreviousBitmap := DllCall("Gdi32\SelectObject", "Ptr", MemoryDC, "Ptr", Bitmap, "Ptr")
    BackgroundBrush := DllCall("Gdi32\CreateSolidBrush", "UInt", MaskColor, "Ptr")
    CircleBrush := DllCall("Gdi32\CreateSolidBrush", "UInt", CircleColor, "Ptr")
    NullPen := DllCall("Gdi32\GetStockObject", "Int", 8, "Ptr")
    Rect := Buffer(16, 0)
    NumPut("Int", 0, Rect, 0)
    NumPut("Int", 0, Rect, 4)
    NumPut("Int", IconWidth, Rect, 8)
    NumPut("Int", IconHeight, Rect, 12)

    DllCall("User32\FillRect", "Ptr", MemoryDC, "Ptr", Rect.Ptr, "Ptr", BackgroundBrush)
    PreviousBrush := DllCall("Gdi32\SelectObject", "Ptr", MemoryDC, "Ptr", CircleBrush, "Ptr")
    PreviousPen := DllCall("Gdi32\SelectObject", "Ptr", MemoryDC, "Ptr", NullPen, "Ptr")
    if IncludeArrow
    {
        ArrowPoints := Buffer(24, 0)
        NumPut("Int", 1, ArrowPoints, 0)
        NumPut("Int", 3, ArrowPoints, 4)
        NumPut("Int", IconWidth - 9, ArrowPoints, 8)
        NumPut("Int", Floor(IconHeight / 2), ArrowPoints, 12)
        NumPut("Int", 1, ArrowPoints, 16)
        NumPut("Int", IconHeight - 3, ArrowPoints, 20)
        DllCall("Gdi32\Polygon", "Ptr", MemoryDC, "Ptr", ArrowPoints.Ptr, "Int", 3)
        DllCall("Gdi32\Ellipse", "Ptr", MemoryDC, "Int", IconWidth - 8, "Int", 3, "Int", IconWidth - 2, "Int", IconHeight - 3)
    }
    else
        DllCall("Gdi32\Ellipse", "Ptr", MemoryDC, "Int", 3, "Int", 3, "Int", IconWidth - 3, "Int", IconHeight - 3)

    DllCall("Gdi32\SelectObject", "Ptr", MemoryDC, "Ptr", PreviousPen)
    DllCall("Gdi32\SelectObject", "Ptr", MemoryDC, "Ptr", PreviousBrush)
    DllCall("Gdi32\SelectObject", "Ptr", MemoryDC, "Ptr", PreviousBitmap)
    DllCall("Gdi32\DeleteObject", "Ptr", CircleBrush)
    DllCall("Gdi32\DeleteObject", "Ptr", BackgroundBrush)
    DllCall("Gdi32\DeleteDC", "Ptr", MemoryDC)
    DllCall("ReleaseDC", "Ptr", 0, "Ptr", ScreenDC)

    return Bitmap
}


UpdateTimelineHoverTip()
{
    global TimelineCalendarState
    global TimelineViewerHoverInfo

    try
    {
        List := TimelineCalendarState.List
        if !List
            return

        CursorPoint := Buffer(8, 0)
        if !DllCall("GetCursorPos", "Ptr", CursorPoint.Ptr)
            return

        if !DllCall("ScreenToClient", "Ptr", List.Hwnd, "Ptr", CursorPoint.Ptr)
        {
            if (TimelineCalendarState.HoverRow != -1)
                ToolTip()
            TimelineCalendarState.HoverRow := -1
            return
        }

        HitInfo := Buffer(24, 0)
        NumPut("Int", NumGet(CursorPoint, 0, "Int"), HitInfo, 0)
        NumPut("Int", NumGet(CursorPoint, 4, "Int"), HitInfo, 4)
        HitRow := SendMessage(0x1012, 0, HitInfo.Ptr, List.Hwnd)

        if (HitRow < 0)
        {
            if (TimelineCalendarState.HoverRow != -1)
                ToolTip()
            TimelineCalendarState.HoverRow := -1
            return
        }

        RowNumber := HitRow + 1
        if (TimelineCalendarState.HoverRow = RowNumber)
            return

        TimelineCalendarState.HoverRow := RowNumber
        if !TimelineViewerHoverInfo.Has(RowNumber)
            return

        HoverInfo := TimelineViewerHoverInfo[RowNumber]
        CategoryName := GetTimelineCategoryAtTime(
            HoverInfo.SessionStart,
            HoverInfo.ElapsedSeconds
        )

        TipText :=
            "게임/카테고리: "
            . (CategoryName != "" ? CategoryName : "기록 없음")

        if (HoverInfo.VideoTitle != "")
            TipText .= "`nVOD: " . HoverInfo.VideoTitle

        MouseGetPos(&MouseX, &MouseY)
        ToolTip(TipText, MouseX + 18, MouseY + 18)
    }
    catch
    {
    }
}


GetTimelineCategoryAtTime(SessionStart, ElapsedSeconds)
{
    global CategoryHistoryFile

    if !FileExist(CategoryHistoryFile)
        return ""

    SessionKey := NormalizeSessionDate(SessionStart)
    if (SessionKey = "" || ElapsedSeconds < 0)
        return ""

    try
    {
        TargetTime := DateAdd(SessionKey, ElapsedSeconds, "Seconds")
        Lines := StrSplit(FileRead(CategoryHistoryFile, "UTF-8"), "`n")
        CategoryName := ""

        for Index, Line in Lines
        {
            if (Index = 1 || Trim(Line) = "")
                continue

            Fields := ParseCsvLine(StrReplace(Line, "`r", ""))
            if (Fields.Length < 6)
                continue

            if (NormalizeSessionDate(Fields[1]) != SessionKey)
                continue

            ChangeTime := NormalizeSessionDate(Fields[2])
            if (ChangeTime = "" || ChangeTime > TargetTime)
                continue

            if (Fields[6] != "")
                CategoryName := Fields[6]
        }

        return CategoryName
    }
    catch
    {
        return ""
    }
}


CloseTimelineViewer(GuiObj, *)
{
    SetTimer(UpdateTimelineHoverTip, 0)
    ToolTip()
    GuiObj.Destroy()
}


; ============================================================
; 선택된 타임라인 수정
; ============================================================

EditSelectedTimeline(List, *)
{
    global TimelineViewerLinks
    global TimelineViewerRows

    RowNumber := List.GetNext(0)
    if (RowNumber <= 0)
        return

    if !TimelineViewerRows.Has(RowNumber)
        return

    try
    {
        EditData := {
            FileLine: TimelineViewerRows[RowNumber],
            SessionStart: List.GetText(RowNumber, 1),
            TimeText: List.GetText(RowNumber, 2),
            Memo: List.GetText(RowNumber, 3),
            VodUrl: TimelineViewerLinks.Has(RowNumber) ? TimelineViewerLinks[RowNumber] : ""
        }

        if (EditData.VodUrl = "")
        {
            MsgBox(
                "다시보기 링크가 없는 타임라인은 수동 수정할 수 없습니다.",
                "타임라인 수정",
                "Icon!"
            )
            return
        }

        ShowManualTimelineGui(true, EditData)
    }
    catch
    {
    }
}


; ============================================================
; 선택된 타임라인 삭제
; ============================================================

DeleteSelectedTimeline(List, *)
{
    global TimelineFile
    global TimelineViewerRows
    global TimelineCalendarState

    RowNumber := List.GetNext(0)
    if (RowNumber <= 0)
        return

    if !TimelineViewerRows.Has(RowNumber)
        return

    FileLine := TimelineViewerRows[RowNumber]
    SessionStart := List.GetText(RowNumber, 1)
    TimeText := List.GetText(RowNumber, 2)
    Memo := List.GetText(RowNumber, 3)

    Result := MsgBox(
        "이 타임라인을 삭제할까요?`n`n"
        . SessionStart . "`n"
        . TimeText . "  ·  " . Memo . "`n`n"
        . "삭제한 타임라인은 복구할 수 없습니다.",
        "타임라인 삭제 확인",
        "YesNo Icon!"
    )

    if (Result != "Yes")
        return

    if !FileExist(TimelineFile)
        return

    try
    {
        Text := FileRead(TimelineFile, "UTF-8")
        Lines := StrSplit(Text, "`n")

        if (FileLine <= 1 || FileLine > Lines.Length)
            throw Error("삭제할 타임라인을 찾을 수 없습니다.")

        Lines.RemoveAt(FileLine)

        if !BackupTimelineCsv("before_delete", true)
            throw Error("삭제 전 CSV 백업을 만들지 못했습니다.")

        RewriteTimelineFile(Lines)

        RenderTimelineCalendar()
        LoadTimelineViewerList()

        TrayTip(
            "수동 타임라인 삭제",
            SessionStart . " / " . TimeText . " 타임라인을 삭제했습니다.",
            1
        )
    }
    catch as Err
    {
        MsgBox(
            "타임라인 삭제에 실패했습니다.`n`n" . Err.Message,
            "삭제 오류",
            "Icon!"
        )
    }
}


; ============================================================
; 선택된 타임라인 열기
; ============================================================

OpenSelectedTimeline(
    List,
    *
)
{
    global TimelineViewerLinks

    RowNumber :=
        List.GetNext(
            0
        )

    if (
        RowNumber <= 0
    )
        return

    try
    {
        if !TimelineViewerLinks.Has(
            RowNumber
        )
        {
            return
        }

        Url :=
            TimelineViewerLinks[
                RowNumber
            ]

        if (
            Url = ""
        )
        {
            MsgBox(
                "아직 다시보기와 연결되지 않은 타임라인입니다.",
                "타임라인",
                "Iconi"
            )

            return
        }

        ; 기존 CSV에 저장된 링크가 예전 형식의 순수 VOD 링크여도
        ; 목록의 방송시간을 이용해 해당 시점으로 이동시킨다.
        TimeText := List.GetText(
            RowNumber,
            2
        )

        ElapsedSec := ParseElapsedTime(
            TimeText
        )

        ; 자동 매칭/수동 타임라인은 이미 해당 VOD 내부의
        ; currentTime을 저장하므로 전체 방송 경과시간으로 덮어쓰지 않는다.
        ; currentTime이 없는 오래된 링크만 기존 방식으로 보정한다.
        if (ElapsedSec >= 0 && !RegExMatch(Url, "i)([?&])currentTime=[0-9]+"))
        {
            Url := BuildChzzkTimestampUrl(
                Url,
                ElapsedSec
            )
        }

        Run(
            Url
        )
    }
    catch
    {
    }
}


; ============================================================
; CHZZK VOD 링크에 재생 시점 추가
; ============================================================

BuildChzzkTimestampUrl(
    Url,
    ElapsedSeconds
)
{
    Url := Trim(Url)

    if (Url = "")
        return ""

    try
        Seconds := Integer(ElapsedSeconds)
    catch
        Seconds := 0

    if (Seconds < 0)
        Seconds := 0

    ; 이미 currentTime이 있으면 값을 교체
    if RegExMatch(
        Url,
        "i)([?&])currentTime=[0-9]+",
        &Match
    )
    {
        return RegExReplace(
            Url,
            "i)([?&])currentTime=[0-9]+",
            Match[1] . "currentTime=" . Seconds
        )
    }

    ; 기존 쿼리가 있으면 &로 연결
    if InStr(Url, "?")
        return Url . "&currentTime=" . Seconds

    return Url . "?currentTime=" . Seconds
}


; ============================================================
; 방송 경과시간
; ============================================================

GetBroadcastElapsed()
{
    global BroadcastStart

    if (
        BroadcastStart = ""
    )
        return -1

    try
    {
        Now :=
            FormatTime(
                A_Now,
                "yyyyMMddHHmmss"
            )

        return DateDiff(
            Now,
            BroadcastStart,
            "Seconds"
        )
    }
    catch
    {
        return -1
    }
}


; ============================================================
; 초 → HH:MM:SS
; ============================================================

FormatElapsed(
    Seconds
)
{
    Seconds :=
        Floor(
            Seconds
        )

    if (
        Seconds < 0
    )
        Seconds := 0

    Hours :=
        Floor(
            Seconds / 3600
        )

    Minutes :=
        Floor(
            Mod(
                Seconds,
                3600
            ) / 60
        )

    Sec :=
        Mod(
            Seconds,
            60
        )

    return Format(
        "{:02}:{:02}:{:02}",
        Hours,
        Minutes,
        Sec
    )
}


; ============================================================
; HH:MM:SS → 초
; ============================================================

ParseElapsedTime(
    Text
)
{
    try
    {
        if RegExMatch(
            Text,
            "^(\d+):(\d{2}):(\d{2})$",
            &M
        )
        {
            return (
                M[1] * 3600
                + M[2] * 60
                + M[3]
            )
        }

        return -1
    }
    catch
    {
        return -1
    }
}


; ============================================================
; 치지직 날짜 → AHK 날짜
; ============================================================

ParseChzzkDate(
    DateText
)
{
    if (
        DateText = ""
    )
        return ""

    try
    {
        if !RegExMatch(
            DateText,
            "^(\d{4})-(\d{2})-(\d{2})\s+(\d{2}):(\d{2}):(\d{2})$",
            &M
        )
        {
            return ""
        }

        return (
            M[1]
            . M[2]
            . M[3]
            . M[4]
            . M[5]
            . M[6]
        )
    }
    catch
    {
        return ""
    }
}


; ============================================================
; 방송 시작시간 표시
; ============================================================

FormatSessionDate(
    DateText
)
{
    if (
        DateText = ""
    )
        return ""

    try
    {
        return FormatTime(
            DateText,
            "yyyy-MM-dd HH:mm:ss"
        )
    }
    catch
    {
        return ""
    }
}


; ============================================================
; Edit 컨트롤 테두리 제거
; ============================================================

RemoveEditBorder(
    hwnd
)
{
    global EditSubclassOldProc
    global EditSubclassCallback

    if !hwnd
        return

    if EditSubclassOldProc.Has(
        hwnd
    )
        return

    if !EditSubclassCallback
    {
        EditSubclassCallback :=
            CallbackCreate(
                EditSubclassProc,
                "Fast",
                4
            )
    }

    oldProc :=
        DllCall(
            "GetWindowLongPtr",
            "Ptr",
            hwnd,
            "Int",
            -4,
            "Ptr"
        )

    if !oldProc
        return

    EditSubclassOldProc[
        hwnd
    ] :=
        oldProc

    DllCall(
        "SetWindowLongPtr",
        "Ptr",
        hwnd,
        "Int",
        -4,
        "Ptr",
        EditSubclassCallback
    )

    DllCall(
        "RedrawWindow",
        "Ptr",
        hwnd,
        "Ptr",
        0,
        "Ptr",
        0,
        "UInt",
        0x85
    )
}


; ============================================================
; Edit subclass
; ============================================================

EditSubclassProc(
    hwnd,
    msg,
    wParam,
    lParam
)
{
    global EditSubclassOldProc

    if (
        msg = 0x0085
    )
        return 0

    if (
        msg = 0x0086
    )
        return 1

    if EditSubclassOldProc.Has(
        hwnd
    )
    {
        oldProc :=
            EditSubclassOldProc[
                hwnd
            ]

        return DllCall(
            "CallWindowProc",
            "Ptr",
            oldProc,
            "Ptr",
            hwnd,
            "UInt",
            msg,
            "Ptr",
            wParam,
            "Ptr",
            lParam,
            "Ptr"
        )
    }

    return DllCall(
        "DefWindowProc",
        "Ptr",
        hwnd,
        "UInt",
        msg,
        "Ptr",
        wParam,
        "Ptr",
        lParam,
        "Ptr"
    )
}


; ============================================================
; LoL 솔로랭크 조회
; ============================================================

ShowLolRankGui(*)
{
    global LolRankGuiObj
    global LolRankRiotIdEdit
    global LolRankStatusText
    global LolRankNameText
    global LolRankRankText
    global LolRankRecordText
    global LolRankRateText
    global LolRankSettingsFile
    global LolGameStatusText
    global LolGameNotifyCheckbox

    LolRankSettingsFile := A_ScriptDir "\data\lol_rank.ini"

    if IsObject(LolRankGuiObj)
    {
        try
        {
            if WinExist("ahk_id " . LolRankGuiObj.Hwnd)
            {
                WinActivate("ahk_id " . LolRankGuiObj.Hwnd)
                return
            }
        }
    }

    RiotId := IniRead(
        LolRankSettingsFile,
        "LoL",
        "LastRiotId",
        "롤불구자#119"
    )

    LolRankGuiObj := Gui("+AlwaysOnTop", "LoL 랭크 조회")
    LolRankGuiObj.BackColor := "11151C"
    LolRankGuiObj.SetFont("s9", "맑은 고딕")

    LolRankGuiObj.SetFont("s16 Bold", "맑은 고딕")
    LolRankGuiObj.Add("Text", "x22 y18 w340 h30 cFFFFFF", "LoL 솔로랭크 조회")

    LolRankGuiObj.SetFont("s9", "맑은 고딕")
    LolRankGuiObj.Add("Text", "x24 y57 w420 h22 c8B949E", "Riot ID  (게임이름#태그)")

    LolRankRiotIdEdit := LolRankGuiObj.Add(
        "Edit",
        "x22 y82 w315 h31 Background202733 cFFFFFF",
        RiotId
    )
    RemoveEditBorder(LolRankRiotIdEdit.Hwnd)

    LookupButton := LolRankGuiObj.Add(
        "Text",
        "x347 y81 w105 h33 Background202733 c00D68F Center 0x200",
        "조회"
    )
    ApplyAccentOutline(LolRankGuiObj, LookupButton)
    LookupButton.OnEvent(
        "Click",
        StartLolRankLookup.Bind(LolRankGuiObj, LolRankRiotIdEdit)
    )

    LolRankGuiObj.Add("Text", "x22 y129 w430 h1 Background303844", "")
    LolRankGuiObj.Add("Text", "x24 y146 w420 h22 c8B949E", "솔로랭크")

    LolRankNameText := LolRankGuiObj.Add(
        "Text",
        "x24 y176 w420 h26 cFFFFFF",
        "Riot ID를 입력하고 조회를 눌러주세요."
    )
    LolRankRankText := LolRankGuiObj.Add(
        "Text",
        "x24 y208 w420 h38 c00D68F",
        ""
    )
    LolRankRecordText := LolRankGuiObj.Add(
        "Text",
        "x24 y253 w420 h25 cD6DCE5",
        ""
    )
    LolRankRateText := LolRankGuiObj.Add(
        "Text",
        "x24 y280 w420 h25 cD6DCE5",
        ""
    )
    LolRankGuiObj.Add("Text", "x22 y316 w430 h1 Background303844", "")
    LolRankGuiObj.SetFont("s10 Bold", "맑은 고딕")
    LolGameStatusText := LolRankGuiObj.Add(
        "Text",
        "x24 y329 w428 h27 c8B949E",
        "연결 상태 확인 중..."
    )
    LolGameNotifyEnabled := IniRead(
        LolRankSettingsFile,
        "LoL",
        "MatchUpdateNotificationEnabled",
        IniRead(
            LolRankSettingsFile,
            "LoL",
            "GameStartNotificationEnabled",
            IniRead(LolRankSettingsFile, "LoL", "GameDetectionEnabled", "1")
        )
    ) = "1"
    LolGameNotifyCheckbox := CreateStyledCheckbox(
        LolRankGuiObj,
        24,
        357,
        "전적 갱신 알림",
        LolGameNotifyEnabled,
        150
    )
    LolGameNotifyCheckbox.Box.OnEvent("Click", LolGameNotificationToggled)
    LolGameNotifyCheckbox.Frame.OnEvent("Click", LolGameNotificationToggled)
    LolGameNotifyCheckbox.Label.OnEvent("Click", LolGameNotificationToggled)
    LolRankGuiObj.SetFont("s9", "맑은 고딕")
    LolRankGuiObj.Add("Text", "x190 y357 w262 h20 c8B949E", "완료된 솔로랭크 기록 알림")
    LolRankGuiObj.Add("Text", "x22 y383 w430 h1 Background303844", "")
    LolRankStatusText := LolRankGuiObj.Add(
        "Text",
        "x24 y391 w428 h34 c8B949E",
        ""
    )

    LolRankGuiObj.OnEvent("Close", CloseLolRankGui)
    LolRankGuiObj.Show("w475 h445")
    EnableRoundedGui(LolRankGuiObj)
    RefreshLolGamePollingState()
}


LolGameNotificationToggled(*)
{
    global LolGameNotifyCheckbox
    global LolRankSettingsFile

    Enabled := LolGameNotifyCheckbox.State.Value = 1
    try IniWrite(Enabled ? "1" : "0", LolRankSettingsFile, "LoL", "MatchUpdateNotificationEnabled")
    RefreshLolGamePollingState()
}


IsLolGamePollingAllowed(BroadcastState := "")
{
    global LolRankSettingsFile
    global LastStatus
    global LastLiveStatusCheckTick
    global CheckInterval

    if (BroadcastState = "")
        BroadcastState := LastStatus

    NotifyEnabled := IniRead(
        LolRankSettingsFile,
        "LoL",
        "MatchUpdateNotificationEnabled",
        IniRead(
            LolRankSettingsFile,
            "LoL",
            "GameStartNotificationEnabled",
            IniRead(LolRankSettingsFile, "LoL", "GameDetectionEnabled", "1")
        )
    ) = "1"

    return (
        NotifyEnabled
        && BroadcastState = "CLOSE"
        && LastLiveStatusCheckTick > 0
        && A_TickCount - LastLiveStatusCheckTick <= CheckInterval * 2
    )
}


RefreshLolGamePollingState(BroadcastState := "")
{
    global LolGameStatusText

    if IsLolGamePollingAllowed(BroadcastState)
    {
        StartLolMatchPush()
        return
    }

    StopLolMatchPush()
    if IsObject(LolGameStatusText)
        LolGameStatusText.Text := "⏸ 방송 중 또는 알림 꺼짐 · 연결 중지"
}


StartLolMatchPush()
{
    global LolWorkerBaseUrl
    global LolMatchPushPID
    global LolMatchEventDirectory
    global ChatHelperScript
    global ChannelID
    global ChatQueueFile
    global ChatTriggerConfigFile
    global ChatDebugLogFile
    global LolGameStatusText

    if !IsLolGamePollingAllowed()
    {
        return
    }

    if (LolWorkerBaseUrl = "")
    {
        if IsObject(LolGameStatusText)
            LolGameStatusText.Text := "⚠ Worker 주소 미설정"
        return
    }
    if (LolMatchPushPID && ProcessExist(LolMatchPushPID))
        return
    LolMatchPushPID := 0
    if !FileExist(ChatHelperScript)
    {
        if IsObject(LolGameStatusText)
            LolGameStatusText.Text := "⚠ chzzk_chat.ps1 파일을 찾을 수 없습니다"
        return
    }

    try
    {
        DirCreate(LolMatchEventDirectory)
        PowerShellPath := A_WinDir . "\System32\WindowsPowerShell\v1.0\powershell.exe"
        command := '"' . PowerShellPath . '" -NoProfile -ExecutionPolicy Bypass'
            . ' -File ' . UpdaterQuote(ChatHelperScript)
            . ' -ChannelId ' . UpdaterQuote(ChannelID)
            . ' -TriggerFile ' . UpdaterQuote(ChatQueueFile)
            . ' -TriggerConfigFile ' . UpdaterQuote(ChatTriggerConfigFile)
            . ' -LogFile ' . UpdaterQuote(ChatDebugLogFile)
            . ' -LolMatchPushMode'
            . ' -WorkerUrl ' . UpdaterQuote(Trim(LolWorkerBaseUrl))
            . ' -EventDirectory ' . UpdaterQuote(LolMatchEventDirectory)
        Run(command, A_ScriptDir, "Hide", &LolMatchPushPID)
        if IsObject(LolGameStatusText)
            LolGameStatusText.Text := "연결 중..."
    }
    catch
    {
        LolMatchPushPID := 0
        if IsObject(LolGameStatusText)
            LolGameStatusText.Text := "⚠ WebSocket helper 실행 실패"
    }
}


StopLolMatchPush(*)
{
    global LolMatchPushPID
    global LolMatchEventDirectory
    global LolGameStatusText

    if LolMatchPushPID
    {
        try
        {
            if ProcessExist(LolMatchPushPID)
                ProcessClose(LolMatchPushPID)
        }
        catch
        {
        }
        LolMatchPushPID := 0
    }
    try FileDelete(LolMatchEventDirectory . "\connected.flag")
    ClearLolMatchEvents()
}


EnsureLolMatchPushConnection()
{
    global LolMatchPushPID
    global LolMatchPushRestartTick
    global LolMatchEventDirectory
    global LolGameStatusText

    if !IsLolGamePollingAllowed()
    {
        StopLolMatchPush()
        return
    }

    if (LolMatchPushPID && ProcessExist(LolMatchPushPID))
    {
        if FileExist(LolMatchEventDirectory . "\connected.flag")
        {
            if IsObject(LolGameStatusText)
                LolGameStatusText.Text := "🟢 전적 알림 서버 연결됨"
        }
        else if IsObject(LolGameStatusText)
            LolGameStatusText.Text := "연결 중..."
        return
    }

    LolMatchPushPID := 0
    if (A_TickCount - LolMatchPushRestartTick < 5000)
        return
    LolMatchPushRestartTick := A_TickCount
    StartLolMatchPush()
}


PollLolMatchPushEvents()
{
    global LolMatchEventDirectory
    global LolRankSettingsFile

    if !DirExist(LolMatchEventDirectory)
        return

    MatchCount := 0
    WinCount := 0
    LossCount := 0
    RemakeCount := 0
    MatchDetails := ""

    Loop Files, LolMatchEventDirectory . "\*.event", "F"
    {
        EventFile := A_LoopFileFullPath
        try EventText := FileRead(EventFile, "UTF-8")
        catch
        {
            try FileDelete(EventFile)
            continue
        }
        try FileDelete(EventFile)

        if !IsLolGamePollingAllowed()
            return
        if !RegExMatch(EventText, '"type"\s*:\s*"match_completed"')
            continue
        MatchId := RegExReplace(A_LoopFileName, "\.event$")
        if !RegExMatch(MatchId, "^[A-Za-z0-9_-]+$")
            continue

        Result := GetJsonStringField(EventText, "result")
        Champion := GetJsonStringField(EventText, "champion")
        if (Result != "win" && Result != "loss" && Result != "remake")
            continue

        SettingKey := "NotifiedMatch_" . MatchId
        if (IniRead(LolRankSettingsFile, "LoL", SettingKey, "0") = "1")
            continue
        try IniWrite("1", LolRankSettingsFile, "LoL", SettingKey)

        MatchCount += 1
        if RegExMatch(EventText, '"kills"\s*:\s*(\d+)', &KillsMatch)
            MatchKills := Integer(KillsMatch[1])
        else
            MatchKills := 0
        if RegExMatch(EventText, '"deaths"\s*:\s*(\d+)', &DeathsMatch)
            MatchDeaths := Integer(DeathsMatch[1])
        else
            MatchDeaths := 0
        if RegExMatch(EventText, '"assists"\s*:\s*(\d+)', &AssistsMatch)
            MatchAssists := Integer(AssistsMatch[1])
        else
            MatchAssists := 0

        if (Result = "win")
        {
            WinCount += 1
            ResultLabel := "승"
        }
        else if (Result = "loss")
        {
            LossCount += 1
            ResultLabel := "패"
        }
        else
        {
            RemakeCount += 1
            ResultLabel := "다시하기"
        }

        MatchDetails .= (MatchDetails = "" ? "" : "`n")
            . "챔피언 [" . (Champion = "" ? "정보 없음" : Champion) . "] KDA ["
            . MatchKills . "/" . MatchDeaths . "/" . MatchAssists . "] " . ResultLabel
    }

    if (MatchCount = 0)
        return

    Summary := MatchCount . "판의 게임 감지!`n"
        . "결과 " . WinCount . "승 / " . LossCount . "패 / " . RemakeCount . "다시하기`n"
        . MatchDetails
    TrayTip("솔로랭크 전적 갱신", Summary, 1)
}


ClearLolMatchEvents()
{
    global LolMatchEventDirectory
    if !DirExist(LolMatchEventDirectory)
        return
    Loop Files, LolMatchEventDirectory . "\*.event", "F"
        try FileDelete(A_LoopFileFullPath)
}


StartLolRankLookup(GuiObj, RiotIdEdit, *)
{
    global LolWorkerBaseUrl
    global LolRankSettingsFile
    global LolRankCooldownSeconds
    global LolRankLastRequestTick
    global LolRankHttp
    global LolRankRequestStartedTick
    global LolRankStatusText
    global LolRankNameText
    global LolRankRankText
    global LolRankRecordText
    global LolRankRateText

    RiotId := Trim(RiotIdEdit.Value)
    SeparatorPos := InStr(RiotId, "#")
    if !SeparatorPos || InStr(RiotId, "#", false, SeparatorPos + 1)
    {
        LolRankStatusText.Text := "Riot ID를 게임이름#태그 형식으로 입력해주세요."
        return
    }

    GameName := Trim(SubStr(RiotId, 1, SeparatorPos - 1))
    TagLine := Trim(SubStr(RiotId, SeparatorPos + 1))
    if (GameName = "" || TagLine = "")
    {
        LolRankStatusText.Text := "Riot ID를 게임이름#태그 형식으로 입력해주세요."
        return
    }

    if (LolWorkerBaseUrl = "")
    {
        LolRankStatusText.Text := "Cloudflare Worker 배포 후 조회할 수 있습니다."
        return
    }

    if IsObject(LolRankHttp)
    {
        LolRankStatusText.Text := "이미 조회 중입니다. 잠시만 기다려주세요."
        return
    }

    NowTick := A_TickCount
    if (
        LolRankLastRequestTick
        && NowTick - LolRankLastRequestTick < LolRankCooldownSeconds * 1000
    )
    {
        WaitSeconds := Ceil(
            (LolRankCooldownSeconds * 1000 - (NowTick - LolRankLastRequestTick)) / 1000
        )
        LolRankStatusText.Text := "요청 간격 제한입니다. " . WaitSeconds . "초 후 다시 조회해주세요."
        return
    }

    try
    {
        IniWrite(RiotId, LolRankSettingsFile, "LoL", "LastRiotId")
    }

    LolRankNameText.Text := RiotId
    LolRankRankText.Text := ""
    LolRankRecordText.Text := ""
    LolRankRateText.Text := ""
    LolRankStatusText.Text := "Riot API 조회 중..."

    RequestUrl := Trim(LolWorkerBaseUrl, "/")
        . "/lol/rank?gameName=" . UrlEncodeUtf8(GameName)
        . "&tagLine=" . UrlEncodeUtf8(TagLine)

    try
    {
        Http := ComObject("WinHttp.WinHttpRequest.5.1")
        Http.Open("GET", RequestUrl, true)
        Http.SetTimeouts(3000, 3000, 5000, 20000)
        Http.SetRequestHeader("Accept", "application/json")
        Http.Send()

        LolRankHttp := Http
        LolRankLastRequestTick := A_TickCount
        LolRankRequestStartedTick := A_TickCount
        SetTimer(PollLolRankRequest, 120)
    }
    catch
    {
        LolRankHttp := 0
        LolRankStatusText.Text := "조회 요청을 시작하지 못했습니다. 인터넷 연결을 확인해주세요."
    }
}


PollLolRankRequest()
{
    global LolRankHttp
    global LolRankRequestStartedTick
    global LolRankStatusText

    if !IsObject(LolRankHttp)
    {
        SetTimer(PollLolRankRequest, 0)
        return
    }

    if (A_TickCount - LolRankRequestStartedTick > 25000)
    {
        try LolRankHttp.Abort()
        LolRankHttp := 0
        SetTimer(PollLolRankRequest, 0)
        LolRankStatusText.Text := "응답 시간이 초과됐습니다. 잠시 후 다시 시도해주세요."
        return
    }

    try
    {
        if (LolRankHttp.ReadyState != 4)
            return

        StatusCode := LolRankHttp.Status
        ResponseText := ReadWinHttpResponseUtf8(LolRankHttp)
        LolRankHttp := 0
        SetTimer(PollLolRankRequest, 0)
        HandleLolRankResponse(StatusCode, ResponseText)
    }
    catch
    {
        LolRankHttp := 0
        SetTimer(PollLolRankRequest, 0)
        LolRankStatusText.Text := "응답을 읽지 못했습니다. 인터넷 연결 또는 서버 상태를 확인해주세요."
    }
}


HandleLolRankResponse(StatusCode, ResponseText)
{
    global LolRankStatusText
    global LolRankNameText
    global LolRankRankText
    global LolRankRecordText
    global LolRankRateText

    if !RegExMatch(ResponseText, '"success"\s*:\s*true')
    {
        ErrorCode := GetJsonStringField(ResponseText, "error")
        LolRankStatusText.Text := LolRankErrorMessage(ErrorCode, StatusCode)
        return
    }

    Tier := GetJsonStringField(ResponseText, "tier")
    Rank := GetJsonStringField(ResponseText, "rank")
    Wins := GetJsonNumberField(ResponseText, "wins")
    Losses := GetJsonNumberField(ResponseText, "losses")
    LeaguePoints := GetJsonNumberField(ResponseText, "leaguePoints")
    WinRate := GetJsonNumberField(ResponseText, "winRate")
    GameName := GetJsonStringField(ResponseText, "gameName")
    TagLine := GetJsonStringField(ResponseText, "tagLine")

    if (
        Tier = ""
        || Rank = ""
        || Wins = ""
        || Losses = ""
        || LeaguePoints = ""
    )
    {
        LolRankStatusText.Text := "서버 응답 형식이 올바르지 않습니다."
        return
    }

    LolRankNameText.Text := GameName . "#" . TagLine
    LolRankRankText.Text := Tier . " " . Rank . "  ·  " . LeaguePoints . " LP"
    LolRankRecordText.Text := Wins . "승  " . Losses . "패"
    LolRankRateText.Text := (WinRate = "" ? "" : Format("승률 {:.1f}%", WinRate))
    LolRankStatusText.Text := "조회 완료"
}


LolRankErrorMessage(ErrorCode, StatusCode)
{
    switch ErrorCode
    {
        case "INVALID_RIOT_ID":
            return "Riot ID 형식을 확인해주세요."
        case "ACCOUNT_NOT_FOUND":
            return "해당 Riot ID 계정을 찾지 못했습니다."
        case "UNRANKED":
            return "이번 시즌 솔로랭크 배정 정보가 없습니다."
        case "RIOT_RATE_LIMITED", "TOO_MANY_REQUESTS":
            return "요청이 많습니다. 잠시 후 다시 시도해주세요."
        case "RIOT_TIMEOUT", "RIOT_UNAVAILABLE":
            return "Riot API가 응답하지 않습니다. 잠시 후 다시 시도해주세요."
        case "RIOT_API_KEY_INVALID_OR_FORBIDDEN":
            return "랭크 서버 설정에 문제가 있습니다. 관리자에게 문의해주세요."
        case "WORKER_NOT_CONFIGURED":
            return "랭크 서버 설정이 완료되지 않았습니다."
        default:
            return "조회에 실패했습니다. (HTTP " . StatusCode . ") 인터넷 또는 서버 상태를 확인해주세요."
    }
}


GetJsonNumberField(Response, FieldName)
{
    Pattern := '"' . FieldName . '"\s*:\s*(-?\d+(?:\.\d+)?)'
    if !RegExMatch(Response, Pattern, &Match)
        return ""
    return Match[1]
}


ReadWinHttpResponseUtf8(Http)
{
    try
    {
        ResponseStream := ComObject("ADODB.Stream")
        ResponseStream.Type := 1
        ResponseStream.Open()
        ResponseStream.Write(Http.ResponseBody)
        ResponseStream.Position := 0
        ResponseStream.Type := 2
        ResponseStream.Charset := "utf-8"
        ResponseText := ResponseStream.ReadText()
        ResponseStream.Close()
        return ResponseText
    }
    catch
    {
        try ResponseStream.Close()
        return Http.ResponseText
    }
}


UrlEncodeUtf8(Value)
{
    ByteCount := StrPut(Value, "UTF-8")
    Utf8Buffer := Buffer(ByteCount)
    StrPut(Value, Utf8Buffer, "UTF-8")
    Encoded := ""

    Loop (ByteCount - 1)
    {
        Byte := NumGet(Utf8Buffer, A_Index - 1, "UChar")
        if (
            (Byte >= 0x41 && Byte <= 0x5A)
            || (Byte >= 0x61 && Byte <= 0x7A)
            || (Byte >= 0x30 && Byte <= 0x39)
            || Byte = 0x2D || Byte = 0x2E || Byte = 0x5F || Byte = 0x7E
        )
            Encoded .= Chr(Byte)
        else
            Encoded .= "%" . Format("{:02X}", Byte)
    }

    return Encoded
}


CloseLolRankGui(*)
{
    global LolRankGuiObj
    global LolRankHttp
    global LolGameStatusText

    SetTimer(PollLolRankRequest, 0)
    if IsObject(LolRankHttp)
    {
        try LolRankHttp.Abort()
    }
    LolRankHttp := 0
    ; Game status polling belongs to the app lifetime, not the GUI lifetime.
    LolGameStatusText := 0
    LolRankGuiObj := 0
}



















