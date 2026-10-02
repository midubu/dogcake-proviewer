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
;
; ============================================================


; dogcake proviewer v1.8.27
; CSV 자동 백업 추가
; ============================================================
; 단축키
; ============================================================

^!c::
{
    CancelShutdownReservation(true)
}


^!p::
{
    result := MsgBox(
        "치지직 방송 감시를 종료할까요?",
        "방송 감시 종료",
        "YesNo Icon?"
    )

    if (result = "Yes")
        ExitApp
}


^!m::
{
    Sleep(2000)

    SendMessage(
        0x112,
        0xF170,
        2,
        ,
        "Program Manager"
    )
}


^!l::
{
    ShowSettingsGui()
}


^!k::
{
    ShowTimelineMemo()
}


^!o::
{
    ShowTimelineViewer()
}


; ============================================================
; 트레이 아이콘
; ============================================================

try
{
    TraySetIcon(
        A_ScriptDir "\dogicon.ico"
    )
}


; ============================================================
; 사용자 설정
; ============================================================

ChannelID :=
    "b68af124ae2f1743a1dcbf5e2ab41e0b"

SettingsFile :=
    A_ScriptDir "\settings.ini"

ProtectedAppsFile :=
    A_ScriptDir "\protected_apps.ini"

DefaultShutdownEnabled := 1
DefaultShutdownMinutes := 5
DefaultNightStart := "22:30"
DefaultNightEnd := "04:00"
DefaultYoutubeEnabled := 0
DefaultYoutubeTrigger := "똥! ㅋㅋ"
DefaultYoutubeCooldown := 60

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
    A_ScriptDir "\timeline.csv"

; CSV 백업 폴더
TimelineBackupDir :=
    A_ScriptDir "\timeline_backup"

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

TimelineViewerLinks :=
    Map()

TimelineViewerRows :=
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
        List: 0,
        SummaryText: 0
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
    A_ScriptDir "\chzzk_chat_queue.txt"

ChatTriggerConfigFile :=
    A_ScriptDir "\chzzk_chat_trigger.txt"

ChatHelperScript :=
    A_ScriptDir "\chzzk_chat.ps1"

ChatStatus := "OFF"


; ============================================================
; Edit subclass 전역 변수
; ============================================================

EditSubclassOldProc := Map()
EditSubclassCallback := 0


; ============================================================
; 초기화
; ============================================================

LoadSettings()
LoadProtectedApps()

StartChatMonitor()
OnExit(StopChatMonitor)

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

        http.Send()

        if (http.Status != 200)
        {
            A_IconTip :=
                "치지직 방송 감시 | API 오류"

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
                "치지직 방송 감시 | 상태 확인 실패"

            return
        }


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


        PreviousState :=
            CurrentState

        UpdateTrayStatus(
            CurrentState
        )
    }
    catch
    {
        A_IconTip :=
            "치지직 방송 감시 | API 연결 오류"

        return
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
    initialValue
)
{
    State := {
        Value: initialValue ? 1 : 0
    }

    Box :=
        GuiObj.Add(
            "Text",
            "x" x
            . " y" y
            . " w20 h20"
            . " Background202733"
            . " c8B949E"
            . " Center 0x200",
            ""
        )

    LabelControl :=
        GuiObj.Add(
            "Text",
            "x" (x + 28)
            . " y" (y - 1)
            . " w360 h22"
            . " cD6DCE5",
            label
        )

    Check := {
        Box: Box,
        Label: LabelControl,
        State: State,
        ExeName: label
    }

    Box.OnEvent(
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
        "x22 y47 w330 h22 c8B949E",
        "방송 종료 및 자동 실행 설정"
    )

    GuiObj.Add(
        "Text",
        "x375 y22 w80 h24 Center c00D68F",
        "● 실행 중"
    )

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

    if !FileExist(
        ChatQueueFile
    )
        return

    try
    {
        content :=
            FileRead(
                ChatQueueFile,
                "UTF-8"
            )

        FileDelete(
            ChatQueueFile
        )

        for line in StrSplit(
            content,
            "`n",
            "`r"
        )
        {
            line :=
                Trim(line)

            if (line = "")
                continue

            HandleChatMessage(
                line
            )
        }
    }
    catch
    {
    }
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
        return

    if (
        message
        !=
        YoutubeTrigger
    )
        return

    if (
        A_TickCount
        <
        YoutubeCooldownUntil
    )
        return

    Run(
        "https://www.youtube.com/"
    )

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

    for _, Row in Rows
    {
        SessionStart := Row.SessionStart
        ElapsedSeconds := Row.ElapsedSeconds
        TimeText := Row.TimeText

        ; 같은 세션이면 VOD API 검색 결과를 공유한다.
        ; 수동 실행이어도 미연결 행만 대상으로 한다.
        Match := FindMatchingVod(
            SessionStart,
            ElapsedSeconds,
            VodCache,
            false
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
            false
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
;       CurrentTime: 123
;   }
; ============================================================

FindMatchingVod(
    TargetStart,
    ElapsedSeconds,
    CandidateCache := 0,
    ForceRefresh := false
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
    CacheKey := NormalizedTarget

    Candidates := ""

    if IsObject(CandidateCache)
    {
        if CandidateCache.Has(CacheKey)
            Candidates := CandidateCache[CacheKey]
    }

    if !IsObject(Candidates)
    {
        Candidates := BuildVodCandidates(NormalizedTarget)

        if IsObject(CandidateCache)
            CandidateCache[CacheKey] := Candidates
    }

    if !IsObject(Candidates) || Candidates.Length = 0
        return ""

    ; 방송 전체 경과시간을 각 VOD 내부 시간으로 변환한다.
    GroupElapsed := 0

    for _, Candidate in Candidates
    {
        Duration := Candidate.Duration

        LocalTime :=
            ElapsedSeconds
            - GroupElapsed

        if (
            LocalTime >= 0
            && LocalTime < Duration
        )
        {
            return {
                VideoNo: Candidate.VideoNo,
                CurrentTime: Floor(LocalTime)
            }
        }

        GroupElapsed += Duration
    }

    return ""
}


; ============================================================
; 방송 세션의 VOD 후보를 한 번만 조회
; ============================================================

BuildVodCandidates(NormalizedTarget)
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

                if (Abs(StartDifference) > VodTimeTolerance)
                    continue

                SeenVideoNos[VideoNo] := true

                Candidates.Push({
                    VideoNo: VideoNo,
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
; 같은 liveOpenDate를 가진 분할 VOD는 publishDate가 빠른 순서,
; publishDate가 없으면 videoNo 오름차순으로 정렬한다.
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
        Http.Send()

        if (Http.Status != 200)
            return ""

        ResponseText := Http.ResponseText

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

        return {
            LiveOpenDate: LiveOpenDate,
            Duration: Duration,
            PublishDate: PublishDate
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
    ForceReplace := false
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
                NewText :=
                    Line
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
        "Segoe UI"
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
        HeaderSubTitle := "기존 타임라인의 시간과 설명을 수정합니다. 링크는 고정됩니다."
        SaveButtonText := "타임라인 수정"
    }
    else
    {
        WindowTitle := "수동 타임라인 추가"
        HeaderTitle := "수동 타임라인 추가"
        HeaderSubTitle := "다시보기를 보면서 원하는 장면을 타임라인에 직접 기록합니다."
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
        "방송 시간"
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
                BuildChzzkTimestampUrl(OriginalVodUrl, ElapsedSec)
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
                "방송시작,방송시간,메모,기록시각,VOD링크`r`n",
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

BuildTimelineCsvLine(SessionStart, TimeText, Memo, RecordTime, VodUrl)
{
    Quote := Chr(34)
    Memo := StrReplace(Memo, "`r", " ")
    Memo := StrReplace(Memo, "`n", " ")

    return (
        Quote . StrReplace(SessionStart, Quote, Quote . Quote) . Quote . ","
        . Quote . StrReplace(TimeText, Quote, Quote . Quote) . Quote . ","
        . Quote . StrReplace(Memo, Quote, Quote . Quote) . Quote . ","
        . Quote . StrReplace(RecordTime, Quote, Quote . Quote) . Quote . ","
        . Quote . StrReplace(VodUrl, Quote, Quote . Quote) . Quote . "`r`n"
    )
}


; ============================================================
; 타임라인 CSV 백업
;
; 기본: A_ScriptDir\timeline_backup\
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

        Files.Sort()

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
                "방송시작,방송시간,메모,기록시각,VOD링크`r`n",
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
    Viewer.SetFont("s10", "Segoe UI")

    Viewer.Add("Text", "x20 y18 w430 c00D68F", "치지직 타임라인")
    Viewer.Add("Text", "x20 y45 w650 c8B949E", "방송 시작 날짜를 기준으로 정리합니다. 자정을 넘어간 방송도 시작한 날짜에 귀속됩니다.")

    ; 이전 달 / 다음 달 버튼
    ; Windows 기본 흰색 Button 대신 어두운 커스텀 UI를 사용한다.
    ; 상단 날짜 이동 버튼
    ManualButton := Viewer.Add(
        "Text",
        "x365 y15 w105 h30 Background202733 cD6DCE5 Center 0x200",
        "+ 수동 타임라인"
    )
    ManualButton.SetFont("s9 Bold")

    PrevButton := Viewer.Add(
        "Text",
        "x485 y15 w40 h30 Background202733 cD6DCE5 Center 0x200",
        "<"
    )
    PrevButton.SetFont("s12 Bold")

    ; 오늘 버튼은 초록색
    TodayButton := Viewer.Add(
        "Text",
        "x535 y15 w65 h30 Background00D68F c11151C Center 0x200",
        "오늘"
    )
    TodayButton.SetFont("s9 Bold")

    NextButton := Viewer.Add(
        "Text",
        "x610 y15 w40 h30 Background202733 cD6DCE5 Center 0x200",
        ">"
    )
    NextButton.SetFont("s12 Bold")

    TimelineCalendarState := {
        Viewer: Viewer,
        Month: "",
        SelectedDate: "",
        MonthText: Viewer.Add("Text", "x20 y92 w665 h30 cFFFFFF Center 0x200", ""),
        DayControls: Map(),
        WeekControls: [],
        CalendarSlots: [],
        List: 0,
        SummaryText: 0
    }
    TimelineCalendarState.MonthText.SetFont("s12 Bold")

    LatestDate := GetLatestTimelineDate()
    if (LatestDate = "")
        LatestDate := FormatTime(A_Now, "yyyy-MM-dd")

    TimelineCalendarState.SelectedDate := LatestDate
    TimelineCalendarState.Month := SubStr(LatestDate, 1, 7)

    TimelineCalendarState.SummaryText := Viewer.Add("Text", "x20 y395 w665 h25 c8B949E", "")
    TimelineCalendarState.SummaryText.SetFont("s10 Bold")

    List := Viewer.Add("ListView", "x20 y430 w665 h155 -Hdr -HScroll -Border -E0x200 Background11151C cD6DCE5", ["방송 시작", "방송 시간", "메모", "상태"])
    List.ModifyCol(1, 145)
    List.ModifyCol(2, 85)
    List.ModifyCol(3, 330)
    List.ModifyCol(4, 100)
    DllCall("uxtheme\SetWindowTheme", "Ptr", List.Hwnd, "Str", " ", "Str", " ")
    SendMessage(0x1001, 0, 0x1C1511, List.Hwnd)
    SendMessage(0x1024, 0, 0xE5DCD6, List.Hwnd)
    SendMessage(0x1025, 0, 0x3B312A, List.Hwnd)

    TimelineCalendarState.List := List

    EditButton := Viewer.Add(
        "Text",
        "x20 y595 w105 h30 Background202733 cD6DCE5 Center 0x200",
        "수정"
    )
    EditButton.SetFont("s9 Bold")

    DeleteButton := Viewer.Add(
        "Text",
        "x135 y595 w105 h30 Background202733 cFF6B6B Center 0x200",
        "삭제"
    )
    DeleteButton.SetFont("s9 Bold")

    ReconnectButton := Viewer.Add(
        "Text",
        "x250 y595 w135 h30 Background202733 cD6DCE5 Center 0x200",
        "↻ VOD 재연결"
    )
    ReconnectButton.SetFont("s9 Bold")

    EditButton.OnEvent("Click", EditSelectedTimeline.Bind(List))
    DeleteButton.OnEvent("Click", DeleteSelectedTimeline.Bind(List))
    ReconnectButton.OnEvent("Click", ReconnectPendingVodsManually)
    List.OnEvent("DoubleClick", OpenSelectedTimeline.Bind(List))
    ManualButton.OnEvent("Click", (*) => ShowManualTimelineGui())
    PrevButton.OnEvent("Click", (*) => ChangeTimelineMonth(-1))
    NextButton.OnEvent("Click", (*) => ChangeTimelineMonth(1))
    TodayButton.OnEvent("Click", (*) => SelectTimelineToday())
    Viewer.OnEvent("Close", (*) => Viewer.Destroy())

    ; 반드시 창을 먼저 표시한 뒤 날짜 컨트롤을 생성한다.
    Viewer.Show("w705 h640")

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
    StartY := 125

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
            Ctrl.Opt("Background00D68F c11151C")
            Ctrl.SetFont("s10 Bold")
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
    global TimelineCalendarState

    List := TimelineCalendarState.List

    if !List
        return

    List.Delete()
    TimelineViewerLinks := Map()
    TimelineViewerRows := Map()

    SelectedDate :=
        TimelineCalendarState.SelectedDate

    if (SelectedDate = "")
        return

    Count := 0
    SessionMap := Map()

    if !FileExist(TimelineFile)
    {
        TimelineCalendarState.SummaryText.Text :=
            SelectedDate . "  ·  기록 없음"
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

            DateKey := GetTimelineDateKey(SessionStart)

            if (DateKey != SelectedDate)
                continue

            Count += 1

            Status :=
                VodUrl != ""
                ? "▶ 다시보기"
                : "⚠ VOD 확인 필요"

            List.Add(
                "",
                SessionStart,
                TimeText,
                Memo,
                Status
            )

            TimelineViewerLinks[Count] := VodUrl
            TimelineViewerRows[Count] := Index
        }
    }
    catch
    {
    }

    TimelineCalendarState.SummaryText.Text :=
        SelectedDate
        . "  ·  타임라인 "
        . Count
        . "개"

    List.Redraw()
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