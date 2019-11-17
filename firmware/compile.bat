@echo off

rem set AVRDIR="C:\Program Files\WinAVR\bin"
set AVRDIR="C:\data\bin\avr8-gnu-toolchain-win32_x86\bin"
"%AVRDIR%\avr-gcc.exe" -g -Os -mmcu=attiny13a -nostartfiles -o blinkyswr.bin blinkyswr.c
rem "%AVRDIR%\avr-gcc.exe" -g -Os -mcall-prologues -mmcu=attiny13a -o blinkyswr.bin blinkyswr.c
"%AVRDIR%\avr-size.exe" --mcu=attiny13a -C blinkyswr.bin
"%AVRDIR%\avr-objcopy" -j .text -j .data -O ihex blinkyswr.bin blinkyswr.hex
"%AVRDIR%\avr-objdump" -h -S blinkyswr.bin 1>blinkyswr.asm

REM ----- Set fuses on ATTiny85 to use max 8mhz internal clock, no external oscillator
REM ----- Created here:  http://www.engbedded.com/fusecalc/
rem avrdude -c usbtiny -p t85 -U lfuse:w:0xe2:m -U hfuse:w:0xdf:m -U efuse:w:0xff:m
