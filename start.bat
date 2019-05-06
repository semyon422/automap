@echo off

if defined ProgramFiles(x86) (
	start aqua\bin64\love.exe .
) else (
	start aqua\bin32\love.exe .
)