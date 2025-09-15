@echo off
setlocal EnableExtensions EnableDelayedExpansion

rem === Опции ===
set "APP_LOG=%TEMP%\AnyDesk_Cache_Cleanup.log"
set "AD_APPDATA=%APPDATA%\AnyDesk"
set "AD_PROGDATA=%PROGRAMDATA%\AnyDesk"

rem Параметры: /y (тихий), /norestart, /dryrun, /utf8
set "FLAG_SILENT="
set "FLAG_NORESTART="
set "FLAG_DRYRUN="
set "FLAG_UTF8="

for %%A in (%*) do (
    if /I "%%~A"=="/y" set "FLAG_SILENT=1"
    if /I "%%~A"=="/norestart" set "FLAG_NORESTART=1"
    if /I "%%~A"=="/dryrun" set "FLAG_DRYRUN=1"
    if /I "%%~A"=="/utf8" set "FLAG_UTF8=1"
)

if defined FLAG_UTF8 chcp 65001 >nul

color 02

rem === Проверка администратора и подъём прав через PowerShell ===
net session >nul 2>&1
if errorlevel 1 (
    if not defined FLAG_SILENT echo Требуются права администратора. Перезапуск с повышением...
    powershell -NoProfile -ExecutionPolicy Bypass -Command "Start-Process -FilePath '%~f0' -ArgumentList '%*' -Verb RunAs"
    exit /b
)

call :log "==== Start: %DATE% %TIME% ===="
call :log "Args: %*"
call :log "APP_LOG=%APP_LOG%"

rem === Опциональный dry-run ===
if defined FLAG_DRYRUN (
    echo [DRY-RUN] Были бы остановлены процессы/сервис AnyDesk и удалены папки:
    echo    "%AD_APPDATA%"
    echo    "%AD_PROGDATA%"
    echo [DRY-RUN] Перезагрузка: ^(%= если нет /norestart =%без запроса^)
    goto after_cleanup
)

rem === Остановка AnyDesk (процессы и сервис) ===
call :stop_anydesk

rem === Удаление кэша/данных ===
set "DELETE_ERRORS=0"

if exist "%AD_APPDATA%" (
    rd /s /q "%AD_APPDATA%" 2>nul
    if errorlevel 1 (
        call :log "[WARN] Не удалось удалить %AD_APPDATA%"
        set "DELETE_ERRORS=1"
    ) else (
        call :log "[OK] Удалено: %AD_APPDATA%"
    )
) else (
    call :log "[INFO] Папка отсутствует: %AD_APPDATA%"
)

if exist "%AD_PROGDATA%" (
    rem ВНИМАНИЕ: ProgramData содержит ID и настройки AnyDesk (в т.ч. пароли). Это осознанно.
    rd /s /q "%AD_PROGDATA%" 2>nul
    if errorlevel 1 (
        call :log "[WARN] Не удалось удалить %AD_PROGDATA%"
        set "DELETE_ERRORS=1"
    ) else (
        call :log "[OK] Удалено: %AD_PROGDATA%"
    )
) else (
    call :log "[INFO] Папка отсутствует: %AD_PROGDATA%"
)

echo AnyDesk cache has been successfully cleared!
call :log "Сообщение пользователю: AnyDesk cache has been successfully cleared!"

:after_cleanup
rem === Перезагрузка ===
if defined FLAG_NORESTART goto end_ok

if defined FLAG_SILENT (
    rem Тихий режим: не спрашиваем, перезагрузка не выполняется автоматически — оставим на усмотрение вызвавшего
    call :log "[INFO] Silent mode: перезагрузка не запрошена."
) else (
    choice /C YN /M "Do you want to restart your computer now? (Y/N)"
    if errorlevel 2 (
        echo Restart is not required. Press any key to continue...
        pause >nul
        goto end_ok
    )
    if errorlevel 1 (
        call :log "[INFO] Пользователь выбрал перезагрузку. Выполняем shutdown /r /t 10"
        shutdown /r /t 10
        goto end_ok
    )
)

goto :eof

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

rem ==================== Подпрограммы ====================

:stop_anydesk
    call :log "[STEP] Остановка AnyDesk"

    rem Попытка мягко закрыть пользовательский процесс
    tasklist /FI "IMAGENAME eq AnyDesk.exe" | find /I "AnyDesk.exe" >nul
    if not errorlevel 1 (
        call :log "[INFO] Найден процесс AnyDesk.exe — пытаемся завершить мягко"
        taskkill /IM AnyDesk.exe /T >nul 2>&1
        timeout /t 2 /nobreak >nul
    )

    rem Остановка сервиса (если есть)
    sc query AnyDesk >nul 2>&1
    if not errorlevel 1 (
        for /f "tokens=3 delims=: " %%S in ('sc query AnyDesk ^| find "STATE"') do set "AD_STATE=%%S"
        call :log "[INFO] Сервис AnyDesk: состояние %AD_STATE%"
        sc stop AnyDesk >nul 2>&1
        rem Ждём до 10 секунд полной остановки
        for /l %%I in (1,1,10) do (
            sc query AnyDesk | find /I "STOPPED" >nul && goto svc_stopped
            timeout /t 1 /nobreak >nul
        )
        :svc_stopped
        call :log "[OK] Сервис AnyDesk остановлен (или отсутствует)."
    ) else (
        call :log "[INFO] Сервис AnyDesk не найден."
    )

    rem Форс-килл на случай залипших экземпляров
    taskkill /IM AnyDesk.exe /F /T >nul 2>&1

    exit /b 0

:log
    rem %~1 — строка
    >>"%APP_LOG%" echo [%DATE% %TIME%] %~1
    goto :eof
