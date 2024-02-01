@echo off
REM  This Source Code Form is subject to the terms of the Mozilla Public
REM  License, v. 2.0. If a copy of the MPL was not distributed with this
REM  file, You can obtain one at https://mozilla.org/MPL/2.0/.
REM
REM  Copyright (c) 2007-2020 VMware, Inc. or its affiliates.  All rights reserved.
REM

REM Scopes the variables to the current batch file
setlocal

rem Preserve values that might contain exclamation marks before
rem enabling delayed expansion
set TDP0=%~dp0
set STAR=%*
setlocal enabledelayedexpansion

REM Get default settings with user overrides for (RABBITMQ_)<var_name>
REM Non-empty defaults should be set in rabbitmq-env
call "%TDP0%\rabbitmq-env.bat" %~n0

if not exist "!ERLANG_HOME!\bin\erl.exe" (
    echo.
    echo ******************************
    echo ERLANG_HOME not set correctly.
    echo ******************************
    echo.
    echo Please either set ERLANG_HOME to point to your Erlang installation or place the
    echo RabbitMQ server distribution in the Erlang lib folder.
    echo.
    exit /B 1
)

REM Disable erl_crash.dump by default for control scripts.
if not defined ERL_CRASH_DUMP_SECONDS (
    set ERL_CRASH_DUMP_SECONDS=0
)

if "%1"=="remote_shell" (
    set ERL_CMD=werl.exe
) else (
    set ERL_CMD=erl.exe
)

REM Note: do NOT add -noinput because "observer" depends on it
"!ERLANG_HOME!\bin\!ERL_CMD!" +B ^
-boot !CLEAN_BOOT_FILE! ^
-noshell -hidden -smp enable ^
!RABBITMQ_CTL_ERL_ARGS! ^
-kernel inet_dist_listen_min !RABBITMQ_CTL_DIST_PORT_MIN! ^
-kernel inet_dist_listen_max !RABBITMQ_CTL_DIST_PORT_MAX! ^
-run escript start ^
-escript main rabbitmqctl_escript ^
-extra "%RABBITMQ_HOME%\escript\rabbitmq-diagnostics" !STAR!

if ERRORLEVEL 1 (
    exit /B %ERRORLEVEL%
)

EXIT /B 0

endlocal
