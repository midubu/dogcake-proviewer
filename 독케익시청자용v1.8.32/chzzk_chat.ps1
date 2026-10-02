param(
    [Parameter(Mandatory=$true)]
    [string]$ChannelId,

    [Parameter(Mandatory=$true)]
    [string]$TriggerFile,

    [Parameter(Mandatory=$true)]
    [string]$TriggerConfigFile
)

$ErrorActionPreference = 'Continue'


# ============================================================
# 고정 스트리머의 채팅 Channel ID
# ============================================================

$ChatChannelId = "N2lraP"


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

function Test-Live {

    try {

        $liveUrl =
            "https://api.chzzk.naver.com/polling/v2/channels/$ChannelId/live-status"

        $live = Invoke-RestMethod `
            -Uri $liveUrl `
            -Headers $Headers `
            -Method Get `
            -TimeoutSec 10

        if ($live.content.status -eq "OPEN") {
            return $true
        }

        return $false
    }
    catch {
        return $false
    }
}


# ============================================================
# Access Token 획득
# ============================================================

function Get-AccessToken {

    param(
        [string]$ChatId
    )

    try {

        $tokenUrl =
            "https://comm-api.game.naver.com/nng_main/v1/chats/access-token?channelId=$([uri]::EscapeDataString($ChatId))&chatType=STREAMING"

        $token = Invoke-RestMethod `
            -Uri $tokenUrl `
            -Headers $Headers `
            -Method Get `
            -TimeoutSec 10

        if (-not $token.content.accessToken) {
            return $null
        }

        return [string]$token.content.accessToken
    }
    catch {
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
        # ----------------------------------------------------

        try {

            $auth =
                $authMessage |
                ConvertFrom-Json

        }
        catch {

            return $false
        }


        # ----------------------------------------------------
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

                    if (-not $data.bdy) {
                        continue
                    }


                    foreach ($item in @($data.bdy)) {

                        if (-not $item.msg) {
                            continue
                        }


                        $msg =
                            [string]$item.msg


                        # 정확히 일치하는 경우만 AHK에 전달
                        if ($msg -eq $TriggerText) {

                            try {

                                Add-Content `
                                    -LiteralPath $TriggerFile `
                                    -Value $msg `
                                    -Encoding UTF8

                            }
                            catch {
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

        if (-not (Test-Live)) {

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

        Start-Sleep -Seconds 5
    }
}