@echo off
:: new-skill.bat -- scaffold a new skill by copying a template (Windows).
::
:: Usage: new-skill.bat [template] [skill-name] [dest-dir]
::
::   [template]    folder under templates\ (e.g. minimal, full).
::                 Omit to pick from an interactive menu.
::   [skill-name]  kebab-case name for the new skill (also the folder name).
::                 Omit to be prompted.
::   [dest-dir]    where to create it (default: current directory).
::
:: Copies templates\<template> to <dest-dir>\<skill-name> and rewrites the
:: SKILL.md `name:` field to match the new folder name.

setlocal EnableDelayedExpansion

set "REPO_ROOT=%~dp0"
if "%REPO_ROOT:~-1%"=="\" set "REPO_ROOT=%REPO_ROOT:~0,-1%"
set "TEMPLATES_DIR=%REPO_ROOT%\templates"

set "TEMPLATE=%~1"
set "SKILL_NAME=%~2"
set "DEST_DIR=%~3"
if "%DEST_DIR%"=="" set "DEST_DIR=%CD%"

:: build a numbered list of available templates
set /a COUNT=0
for /d %%D in ("%TEMPLATES_DIR%\*") do (
  if exist "%%D\SKILL.md" (
    set /a COUNT+=1
    set "TPL_!COUNT!=%%~nxD"
  )
)
if %COUNT%==0 (
  echo error: no templates found under %TEMPLATES_DIR% 1>&2
  exit /b 1
)

:: if a template was given, verify it exists
if not "%TEMPLATE%"=="" (
  if not exist "%TEMPLATES_DIR%\%TEMPLATE%\SKILL.md" (
    echo Unknown template: "%TEMPLATE%" 1>&2
    set "TEMPLATE="
  )
)

:: choose a template interactively if we still don't have one
if "%TEMPLATE%"=="" call :choose_template

:: skill name -- prompt if not provided
if "%SKILL_NAME%"=="" set /p "SKILL_NAME=Skill name (kebab-case): "

:: validate skill name: kebab-case only (lowercase, digits, hyphens)
echo(%SKILL_NAME%| findstr /R "[^a-z0-9-]" >nul
if not errorlevel 1 (
  echo error: skill name must be kebab-case ^(lowercase, digits, hyphens^): "%SKILL_NAME%" 1>&2
  exit /b 1
)
if "%SKILL_NAME%"=="" (
  echo error: no skill name given 1>&2
  exit /b 1
)

set "DEST=%DEST_DIR%\%SKILL_NAME%"
if exist "%DEST%\" (
  echo error: "%DEST%" already exists -- pick another name or remove it first 1>&2
  exit /b 1
)

xcopy "%TEMPLATES_DIR%\%TEMPLATE%" "%DEST%\" /E /I /Q >nul
if errorlevel 1 (
  echo error: failed to copy template to "%DEST%" 1>&2
  exit /b 1
)

:: rewrite the first frontmatter `name:` line to match the folder name
set "SKILL_MD=%DEST%\SKILL.md"
powershell -NoProfile -Command "$p=$env:SKILL_MD; $n=$env:SKILL_NAME; $lines=Get-Content -LiteralPath $p; $done=$false; for($i=0;$i -lt $lines.Count;$i++){ if(-not $done -and $lines[$i] -match '^name:'){ $lines[$i]='name: '+$n; $done=$true } }; Set-Content -LiteralPath $p -Value $lines"

echo Created skill "%SKILL_NAME%" from template "%TEMPLATE%":
echo   %DEST%
echo.
echo Next steps:
echo   1. Edit %SKILL_MD% -- write the description and guidance (fill in ^<...^> placeholders).
if exist "%DEST%\references\" echo   2. Flesh out the guides under %DEST%\references\.
if exist "%DEST%\scripts\"    echo   3. Implement the helper(s) under %DEST%\scripts\.
echo   4. Add a row for it to the skills table in README.md.
exit /b 0

:choose_template
echo Select a template:
for /l %%I in (1,1,%COUNT%) do echo   %%I. !TPL_%%I!
:choose_loop
set "SEL="
set /p "SEL=Template number: "
if not defined SEL goto :choose_loop
set "TEMPLATE=!TPL_%SEL%!"
if not defined TEMPLATE (
  echo Invalid selection -- enter a number from the list.
  goto :choose_loop
)
goto :eof
