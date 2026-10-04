param(
    [Parameter(Mandatory=$true)]
    [string]$ChannelId,

    [Parameter(Mandatory=$true)]
    [string]$TriggerFile,

    [Parameter(Mandatory=$true)]
    [string]$TriggerConfigFile,

    [string]$LogFile = (Join-Path $PSScriptRoot 'chzzk_chat_debug.log')
)

$ErrorActionPreference = 'Continue'
function Write-Trace {
    param([string]$Message)
    try {
        $line = '[' + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff') + '] ' + $Message + [Environment]::NewLine
        [IO.File]::AppendAllText($LogFile, $line, [Text.UTF8Encoding]::new($false))
    } catch {}
}
Write-Trace ("HELPER_START channel=" + $ChannelId)


# ============================================================
# 고정 스트리머의 채팅 Channel ID
# ============================================================

$ChatChannelId = ""


# ============================================================
# HTTPS 설정
# ============================================================

[Net.ServicePointManager]::SecurityProtocol =
    [Net.SecurityProtocolType]::Tls12

$Headers = @{
    'User-Agent' =
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/153 Safari/537.36'
}


# ============================================================
# 트리거 문자열 읽기
# ============================================================

try {
    if (Test-Path -LiteralPath $TriggerConfigFile) {

        $TriggerText = [IO.File]::ReadAllText(
            $TriggerConfigFile,
            [Text.UTF8Encoding]::new($false)
        ).TrimEnd("`r", "`n")

    }
    else {
        $TriggerText = "똥!"
    }
}
catch {
    $TriggerText = "똥!"
}


# ============================================================
# 방송 상태 확인
# ============================================================

function Get-LiveStatus {
    try {
        $liveUrl = "https://api.chzzk.naver.com/polling/v2/channels/$ChannelId/live-status"
        $live = Invoke-RestMethod -Uri $liveUrl -Headers $Headers -Method Get -TimeoutSec 10
        Write-Trace ("LIVE status=" + $live.content.status + " chatChannelId=" + $live.content.chatChannelId)
        return $live.content
    } catch {
        Write-Trace ("LIVE_ERROR " + $_.Exception.Message)
        return $null
    }
}

# ============================================================
# Access Token 획득
# ============================================================

function Get-AccessToken {
    param([string]$ChatId)
    try {
        $tokenUrl = "https://comm-api.game.naver.com/nng_main/v1/chats/access-token?channelId=$([uri]::EscapeDataString($ChatId))&chatType=STREAMING"
        $token = Invoke-RestMethod -Uri $tokenUrl -Headers $Headers -Method Get -TimeoutSec 10
        if (-not $token.content.accessToken) {
            Write-Trace ("TOKEN_MISSING id=" + $ChatId)
            return $null
        }
        Write-Trace ("TOKEN_OK id=" + $ChatId)
        return [string]$token.content.accessToken
    } catch {
        Write-Trace ("TOKEN_ERROR id=" + $ChatId + " " + $_.Exception.Message)
        return $null
    }
}

# ============================================================
# WebSocket 서버 계산
# ============================================================

function Get-ServerIndex {

    param(
        [string]$Text
    )

    $sum = 0

    foreach ($ch in $Text.ToCharArray()) {
        $sum += [int][char]$ch
    }

    return (($sum % 9) + 1)
}


# ============================================================
# JSON 전송
# ============================================================

function Send-Json {

    param(
        $Socket,
        [string]$Text
    )

    $bytes = [Text.Encoding]::UTF8.GetBytes($Text)

    $segment =
        [ArraySegment[byte]]::new($bytes)

    $Socket.SendAsync(
        $segment,
        [Net.WebSockets.WebSocketMessageType]::Text,
        $true,
        [Threading.CancellationToken]::None
    ).GetAwaiter().GetResult()
}


# ============================================================
# WebSocket 수신
# ============================================================

function Receive-Message {

    param(
        $Socket
    )

    $buffer = New-Object byte[] 65536
    $ms = New-Object IO.MemoryStream

    try {

        do {

            $seg =
                [ArraySegment[byte]]::new($buffer)

            $result =
                $Socket.ReceiveAsync(
                    $seg,
                    [Threading.CancellationToken]::None
                ).GetAwaiter().GetResult()

            if (
                $result.MessageType -eq
                [Net.WebSockets.WebSocketMessageType]::Close
            ) {
                return $null
            }

            if ($result.Count -gt 0) {

                $ms.Write(
                    $buffer,
                    0,
                    $result.Count
                )
            }

        } while (-not $result.EndOfMessage)

        return [Text.Encoding]::UTF8.GetString(
            $ms.ToArray()
        )
    }
    finally {

        $ms.Dispose()
    }
}


# ============================================================
# WebSocket 채팅 연결
# ============================================================

function Connect-Chat {

    param(
        [string]$ChatId,
        [string]$AccessToken
    )

    $server =
        Get-ServerIndex $ChatId

    $wsUrl =
        "wss://kr-ss$server.chat.naver.com/chat"

    $ws =
        [Net.WebSockets.ClientWebSocket]::new()

    try {

        # ----------------------------------------------------
        # WebSocket 연결
        # ----------------------------------------------------

        Write-Trace ("WS_OPENING id=" + $ChatId + " server=" + $server)

        $ws.ConnectAsync(
            [Uri]$wsUrl,
            [Threading.CancellationToken]::None
        ).GetAwaiter().GetResult()


        # ----------------------------------------------------
        # 인증 정보
        # ----------------------------------------------------

        $connect = @{
            ver   = '2'
            cmd   = 100
            svcid = 'game'
            cid   = $ChatId
            tid   = 1

            bdy   = @{
                uid      = $null
                devType  = 2001
                accTkn   = $AccessToken
                auth     = 'READ'
                libVer   = '4.9.3'
                osVer    = 'Windows/11'
                devName  = 'AutoHotkey CHZZK monitor'
                locale   = 'ko'
                timezone = 'Asia/Seoul'
            }
        } |
        ConvertTo-Json `
            -Depth 8 `
            -Compress


        Send-Json `
            $ws `
            $connect


        # ----------------------------------------------------
        # 인증 응답
        # ----------------------------------------------------

        $authMessage =
            Receive-Message $ws

        if ($null -eq $authMessage) {
            return $false
        }


        # ----------------------------------------------------
        # 인증 응답 확인

        try {
            $auth = $authMessage | ConvertFrom-Json
        }
        catch {
            Write-Trace "AUTH_JSON_ERROR"
            return $false
        }

        $sid = [string]$auth.bdy.sid
        Write-Trace ("AUTH cmd=" + $auth.cmd + " hasSid=" + (-not [string]::IsNullOrWhiteSpace($sid)))
        if ([string]::IsNullOrWhiteSpace($sid)) {
            return $false
        }

        $recentChatRequest = @{
            ver = '2'
            cmd = 5101
            svcid = 'game'
            cid = $ChatId
            tid = 2
            sid = $sid
            bdy = @{ recentMessageCount = 1 }
        } | ConvertTo-Json -Depth 8 -Compress

        Send-Json $ws $recentChatRequest
        $recentChatResponse = Receive-Message $ws
        if ($null -eq $recentChatResponse) {
            Write-Trace "RECENT_RESPONSE_MISSING"
            return $false
        }

        try {
            $recentData = $recentChatResponse | ConvertFrom-Json
            Write-Trace ("RECENT cmd=" + $recentData.cmd)
        }
        catch {
            Write-Trace "RECENT_JSON_ERROR"
            return $false
        }
        # 채팅 수신 루프
        # ----------------------------------------------------

        while (
            $ws.State -eq
            [Net.WebSockets.WebSocketState]::Open
        ) {

            $message =
                Receive-Message $ws

            if ($null -eq $message) {
                break
            }


            try {

                $data =
                    $message |
                    ConvertFrom-Json


                # ------------------------------------------------
                # Ping
                # ------------------------------------------------

                if ($data.cmd -eq 0) {

                    $pong = @{
                        ver = '3'
                        cmd = 10000
                    } |
                    ConvertTo-Json `
                        -Compress

                    Send-Json `
                        $ws `
                        $pong

                    continue
                }


                # ------------------------------------------------
                # 일반 채팅
                # ------------------------------------------------

                if ($data.cmd -eq 93101) {
                    Write-Trace ("CHAT_BATCH count=" + @($data.bdy).Count)

                    if (-not $data.bdy) {
                        continue
                    }


                    foreach ($item in @($data.bdy)) {

                        if (-not $item.msg) {
                            continue
                        }


                        $msg =
                            [string]$item.msg


                        # 키워드가 포함된 채팅을 AHK에 전달
                        if (-not [string]::IsNullOrWhiteSpace($TriggerText) -and $msg.IndexOf($TriggerText, [StringComparison]::OrdinalIgnoreCase) -ge 0) {
                            Write-Trace "KEYWORD_MATCH"

                            try {

                                Add-Content `
                                    -LiteralPath $TriggerFile `
                                    -Value $msg `
                                    -Encoding UTF8
                                Write-Trace "QUEUE_WRITE_OK"

                            }
                            catch {
                                Write-Trace ("QUEUE_WRITE_ERROR " + $_.Exception.Message)
                            }
                        }
                    }
                }


                # ------------------------------------------------
                # 후원
                # ------------------------------------------------

                if ($data.cmd -eq 93102) {
                    continue
                }

            }
            catch {
                continue
            }
        }

        return $false
    }
    catch {

        return $false
    }
    finally {

        try {

            if ($ws) {
                $ws.Dispose()
            }

        }
        catch {
        }
    }
}


# ============================================================
# 메인 루프
# ============================================================

while ($true) {

    try {

        # ----------------------------------------------------
        # 방송이 꺼져 있으면 잠시 후 다시 확인
        # ----------------------------------------------------

        $LiveStatus =
            Get-LiveStatus

        if ($null -eq $LiveStatus -or $LiveStatus.status -ne "OPEN") {

            Start-Sleep -Seconds 5
            continue
        }

        $ChatChannelId =
            [string]$LiveStatus.chatChannelId

        if ([string]::IsNullOrWhiteSpace($ChatChannelId)) {

            Write-Trace "LIVE_CHAT_ID_MISSING"
            Start-Sleep -Seconds 5
            continue
        }


        # ----------------------------------------------------
        # Access Token 획득
        # ----------------------------------------------------

        $AccessToken =
            Get-AccessToken $ChatChannelId


        if ([string]::IsNullOrWhiteSpace($AccessToken)) {

            Start-Sleep -Seconds 5
            continue
        }


        # ----------------------------------------------------
        # 채팅 연결
        # ----------------------------------------------------

        Connect-Chat `
            $ChatChannelId `
            $AccessToken


        # ----------------------------------------------------
        # 연결이 끊어졌으면 재연결
        # ----------------------------------------------------

        Start-Sleep -Seconds 3

    }
    catch {
        Write-Trace ("MAIN_ERROR " + $_.Exception.Message)
        Start-Sleep -Seconds 5
    }
}
