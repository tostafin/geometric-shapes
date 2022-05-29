# geometric-shapes
An x86 Assembly program to draw geometric shapes.

## Overview
The program draws geometric shapes provided in a text file. All line segments are drawn using Bresenham's line algorithm.

## Requirements
The program takes a file name as a command line parameter. The file must contain a color of a geometric shape followed by two or more coordinates (in the first quadrant). Each parameter must be seperated by two spaces and each point must have its coordinates seperated by a single comma. New lines must have CRLF format.

### Tools
An easy way of running the program is to use DOSBOX and Microsoft Macro Assembler.

## Sample program execution
First, compile the program:
```
ml main.asm
```
Then execute it:
```
main data.txt
```
Result:

![alt text](https://github.com/tostafin/geometric-shapes/blob/master/sample_exec.PNG?raw=true)

You can exit it by pressing ESC.
