@echo off

"c:\Program Files\WinAVR\bin\avr-gcc.exe" -g -Os -mmcu=attiny13a -o blinkyswr.bin blinkyswr.c
"c:\Program Files\WinAVR\bin\avr-size.exe" --mcu=attiny13a -C blinkyswr.bin
"c:\Program Files\WinAVR\bin\avr-objcopy" -j .text -j .data -O ihex blinkyswr.bin blinkyswr.hex

REM ----- Set fuses on ATTiny85 to use max 8mhz internal clock, no external oscillator
REM ----- Created here:  http://www.engbedded.com/fusecalc/
rem avrdude -c usbtiny -p t85 -U lfuse:w:0xe2:m -U hfuse:w:0xdf:m -U efuse:w:0xff:m
