@echo off
setlocal EnableExtensions EnableDelayedExpansion

:: ==========================================================
:: AnyDesk Cache Cleanup Tool
:: v1.3 (15.09.2025)
:: ==========================================================

:: ====== ОПЦИИ ======
set "APP_LOG=%TEMP%\AnyDesk_Cache_Cleanup.log"
set "AD_APPDATA=%APPDATA%\AnyDesk"
set "AD_PROGDATA=%PROGRAMDATA%\AnyDesk"

:: Флаги: /y (тихий), /norestart, /dryrun, /utf8, /checknet, /allusers
set "FLAG_SILENT="
set "FLAG_NORESTART="
set "FLAG_DRYRUN="
set "FLAG_UTF8="
set "FLAG_CHECKNET="
set "FLAG_ALLUSERS="

for %%A in (%*) do (
    if /I "%%~A"=="/y" set "FLAG_SILENT=1"
    if /I "%%~A"=="/norestart" set "FLAG_NORESTART=1"
    if /I "%%~A"=="/dryrun" set "FLAG_DRYRUN=1"
    if /I "%%~A"=="/utf8" set "FLAG_UTF8=1"
    if /I "%%~A"=="/checknet" set "FLAG_CHECKNET=1"
    if /I "%%~A"=="/allusers" set "FLAG_ALLUSERS=1"
)

if defined FLAG_UTF8 chcp 65001 >nul
color 02

:: === ЗАМЕНИ под свой allowlist (пример) ===
set "AD_HOSTS=relay.anydesk.com dispatcher.anydesk.com update.anydesk.com license.anydesk.com"
set "AD_PORTS=80 443 6568"

:: ====== ПРОВЕРКА АДМИНА + ПОВЫШЕНИЕ ПРАВ ======
net session >nul 2>&1
if errorlevel 1 (
    if not defined FLAG_SILENT echo Требуются права администратора. Перезапуск с повышением...
    powershell -NoProfile -ExecutionPolicy Bypass -Command "Start-Process -FilePath '%~f0' -ArgumentList '%*' -Verb RunAs"
    exit /b
)

call :log "==== Start: %DATE% %TIME% ===="
call :log "Args: %*"
call :log "Log: %APP_LOG%"

:: ====== (ОПЦИОНАЛЬНО) ПРОВЕРКА ДОСТУПНОСТИ СЕТИ ANYDESK ======
if defined FLAG_CHECKNET (
    call :log "[STEP] Проверка доступности AnyDesk endpoints"
    call :check_anydesk_endpoints
    if errorlevel 1 (
        echo [WARN] Есть проблемы с доступностью серверов AnyDesk. Смотрите лог: %APP_LOG%
        :: При необходимости — прервать выполнение:
        :: exit /b 2
    )
)

:: ====== DRY-RUN ======
if defined FLAG_DRYRUN (
    echo [DRY-RUN] Будут удалены следующие пути (если существуют):
    if defined FLAG_ALLUSERS (
        for /d %%U in ("%SystemDrive%\Users\*") do (
            call :should_skip_profile "%%~nxU" && (echo    [SKIP] %%~nxU) || (echo    "%%U\AppData\Roaming\AnyDesk")
        )
    ) else (
        echo    "%AD_APPDATA%"
    )
    echo    "%AD_PROGDATA%"
    goto after_cleanup
)

:: ====== ОСТАНОВКА ANYDESK ======
call :stop_anydesk

:: ====== УДАЛЕНИЕ ДАННЫХ/КЭША ======
set "DELETE_ERRORS=0"

:: (A) Очистка профилей пользователей
if defined FLAG_ALLUSERS (
    call :log "[STEP] Очистка AnyDesk в профилях всех пользователей"
    for /d %%U in ("%SystemDrive%\Users\*") do (
        call :should_skip_profile "%%~nxU"
        if not errorlevel 1 (
            call :cleanup_user_profile "%%U"
            if errorlevel 1 set "DELETE_ERRORS=1"
        ) else (
            call :log "[INFO] Пропуск профиля: %%~nxU"
        )
    )
) else (
    :: ТОЛЬКО текущий пользователь (как раньше)
    if exist "%AD_APPDATA%" (
        rd /s /q "%AD_APPDATA%" 2>nul
        if errorlevel 1 ( call :log "[WARN] Не удалось удалить %AD_APPDATA%" & set "DELETE_ERRORS=1" ) else ( call :log "[OK] Удалено: %AD_APPDATA%" )
    ) else (
        call :log "[INFO] Папка отсутствует: %AD_APPDATA%"
    )
)

:: (B) Общие данные ProgramData (осторожно: тут и ID/настройки)
if exist "%AD_PROGDATA%" (
    rd /s /q "%AD_PROGDATA%" 2>nul
    if errorlevel 1 ( call :log "[WARN] Не удалось удалить %AD_PROGDATA%" & set "DELETE_ERRORS=1" ) else ( call :log "[OK] Удалено: %AD_PROGDATA%" )
) else (
    call :log "[INFO] Папка отсутствует: %AD_PROGDATA%"
)

echo AnyDesk cache has been successfully cleared!
call :log "Message: AnyDesk cache has been successfully cleared!"

:after_cleanup
:: ====== ПЕРЕЗАГРУЗКА ======
if defined FLAG_NORESTART goto end_ok

if defined FLAG_SILENT (
    call :log "[INFO] Silent mode: перезагрузка не запрошена."
) else (
    choice /C YN /M "Do you want to restart your computer now? (Y/N)"
    if errorlevel 2 (
        echo Restart is not required. Press any key to continue...
        pause >nul
        goto end_ok
    )
    if errorlevel 1 (
        call :log "[INFO] Пользователь выбрал перезагрузку. shutdown /r /t 10"
        shutdown /r /t 10
        goto end_ok
    )
)

:end_ok
if "%DELETE_ERRORS%"=="1" (
    call :log "Завершено с предупреждениями."
    call :log "==== End: %DATE% %TIME% ===="
    exit /b 1
) else (
    call :log "Завершено успешно."
    call :log "==== End: %DATE% %TIME% ===="
    exit /b 0
)

:: ==================== ПОДПРОГРАММЫ ====================

:cleanup_user_profile
:: %~1 = полный путь к профилю, напр. C:\Users\User1
setlocal
set "UROOT=%~1"
set "TARGET=%UROOT%\AppData\Roaming\AnyDesk"
if exist "%TARGET%" (
    call :log "[INFO] Удаляю у пользователя %~nx1: %TARGET%"
    rd /s /q "%TARGET%" 2>nul
    if errorlevel 1 (
        :: На случай проблем с ACL — дать доступ Администраторам и повторить
        icacls "%TARGET%" /grant *S-1-5-32-544:(OI)(CI)(F) /t /c >nul 2>&1
        rd /s /q "%TARGET%" 2>nul
    )
    if errorlevel 1 (
        endlocal & call :log "[WARN] Не удалось удалить %TARGET%" & exit /b 1
    ) else (
        endlocal & call :log "[OK] Удалено в профиле %~nx1: %TARGET%" & exit /b 0
    )
) else (
    endlocal & call :log "[INFO] У пользователя %~nx1 папка AnyDesk отсутствует" & exit /b 0
)

:should_skip_profile
:: %~1 = имя профиля (только имя папки)
setlocal
set "NAME=%~1"
set "NAME=%NAME:"=%"
:: Список исключений (дополните при необходимости)
if /I "%NAME%"=="Default"          endlocal & exit /b 1
if /I "%NAME%"=="Default User"     endlocal & exit /b 1
if /I "%NAME%"=="Public"           endlocal & exit /b 1
if /I "%NAME%"=="All Users"        endlocal & exit /b 1
if /I "%NAME%"=="WDAGUtilityAccount" endlocal & exit /b 1
if /I "%NAME%"=="Administrator"    endlocal & exit /b 1
if /I "%NAME%"=="Администратор"    endlocal & exit /b 1
endlocal & exit /b 0

:stop_anydesk
    call :log "[STEP] Остановка AnyDesk"
    tasklist /FI "IMAGENAME eq AnyDesk.exe" | find /I "AnyDesk.exe" >nul
    if not errorlevel 1 (
        call :log "[INFO] Найден процесс AnyDesk.exe — taskkill"
        taskkill /IM AnyDesk.exe /T >nul 2>&1
        timeout /t 2 /nobreak >nul
    )
    sc query AnyDesk >nul 2>&1
    if not errorlevel 1 (
        for /f "tokens=3 delims=: " %%S in ('sc query AnyDesk ^| find "STATE"') do set "AD_STATE=%%S"
        call :log "[INFO] Сервис AnyDesk: состояние %AD_STATE%"
        sc stop AnyDesk >nul 2>&1
        for /l %%I in (1,1,10) do (
            sc query AnyDesk | find /I "STOPPED" >nul && goto svc_stopped
            timeout /t 1 /nobreak >nul
        )
        :svc_stopped
        call :log "[OK] Сервис AnyDesk остановлен (или отсутствует)."
    ) else (
        call :log "[INFO] Сервис AnyDesk не найден."
    )
    taskkill /IM AnyDesk.exe /F /T >nul 2>&1
    exit /b 0

:check_anydesk_endpoints
    setlocal EnableDelayedExpansion
    set "FAIL=0"

    :: --- 1) DNS ---
    for %%H in (%AD_HOSTS%) do (
        nslookup %%H >nul 2>&1
        if errorlevel 1 (
            call :log "[DNS][FAIL] %%H не резолвится"
            set "FAIL=1"
        ) else (
            call :log "[DNS][OK]   %%H резолвится"
        )
    )

    :: --- 2) TCP через PowerShell, иначе ICMP ---
    where powershell >nul 2>&1
    if errorlevel 1 (
        call :log "[INFO] PowerShell нет — fallback ping"
        for %%H in (%AD_HOSTS%) do (
            ping -n 1 -w 1000 %%H >nul 2>&1
            if errorlevel 1 (
                call :log "[PING][FAIL] %%H не отвечает по ICMP (ICMP может быть закрыт)"
            ) else (
                call :log "[PING][OK]   %%H отвечает по ICMP"
            )
        )
    ) else (
        for %%H in (%AD_HOSTS%) do (
            for %%P in (%AD_PORTS%) do (
                for /f %%R in ('powershell -NoProfile -ExecutionPolicy Bypass -Command "Test-NetConnection -ComputerName ''%%H'' -Port %%P -InformationLevel Quiet -WarningAction SilentlyContinue"') do (
                    if "%%R"=="True" (
                        call :log "[TCP][OK]   %%H:%%P"
                    ) else (
                        call :log "[TCP][FAIL] %%H:%%P"
                        set "FAIL=1"
                    )
                )
            )
        )
    )

    endlocal & if "%FAIL%"=="1" (exit /b 1) else (exit /b 0)

:log
    >>"%APP_LOG%" echo [%DATE% %TIME%] %~1
    goto :eof
