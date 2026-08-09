@echo off
REM manage.cmd: Windows launcher for the Loom Foundation workspace management CLI.
REM
REM Bootstrap symlinks this at the workspace root, so you can run e.g.
REM   .\manage.cmd update
REM from the workspace top directory. All the logic lives in manage.mjs; this
REM is a thin shim that hands off to node.
REM
REM When run via the workspace-root symlink, %~dp0 is the workspace topdir, so
REM manage.mjs lives under manifest\. When run from manifest directly,
REM manage.mjs is a sibling. Handle both.
if exist "%~dp0manage.mjs" (
  node "%~dp0manage.mjs" %*
) else (
  node "%~dp0manifest\manage.mjs" %*
)
