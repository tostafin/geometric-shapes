;DOS 21h interrupts comments are taken from this page: http://spike.scu.edu.au/~barry/interrupts.html (last access: 28.05.2022)

.186 ;to use "sal" with more than 1

data1			segment
;....................FILE DATA....................
file_name		db		100 dup(?)
file_ptr		dw		?
file_buf		db		5000 dup(?)

color			db		0 ;ASCII character
;max x value: 319, so we need a word
;to be consistent we're going to leave y as a word too
;we need to save the first point coordinates in order to draw the last line segment
x0				dw		0 ;the first point abscissa
y0				dw		0 ;the first point ordinate
;two end points coordinates of a line segment
x1				dw		0
y1				dw		0
x2				dw		0
;y2 won't be needed since it will be calculated in AX
;....................FILE DATA ENDS....................

;....................Bresenham's line algorithm variables....................
;assuming two end points of a line segment: (xs, ys), (xe, ye)
xs				dw		0
ys				dw		0
xe				dw		0
ye				dw		0
delx			dw		0 ;delta x = xe - xs
dely			dw		0 ;delta y = ye - ys
rob				dw		0 ;2(dely - delx)
mx				dw		0 ;value to add to the address to light pixel on the left or on the right
my				dw		0 ;ditto for the top and the bottom
di1				dw		0 ;DD_{i+1} = 2dely(x_{i+1} + 1 - xs) + 2delx(ys - y_{i+1}) - delx
d_i				dw		0 ;DD_{i}

;....................ERROR HANDLING STRINGS....................
debug			db		"DEBUG$"
no_param		db		"No parameters on program start: you must pass a file name which contains data of geometric shapes to be drawn.$"
white_chars		db		"You must pass exactly one parameter (no whitespace characters allowed).$"
file_open_err 	db		"Error while opening the file.$"
file_close_err	db		"Error while closing the file.$"
file_read_err	db		"Error while reading the file.$"
wrong_color		db		"Wrong color inside the file: must be one of the following: W, B, G, B.$"
two_spaces		db		"Wrong file format: each pair of coordinates must be seperated from other pairs by two spaces.$"
not_digit		db		"Wrong value: coordinates must be non-negative integers.$"
x_val_exceed	db		"Wrong value: the abscissa must be an integer between 0 and 319.$"
no_comma		db		"Wrong file format: the first and second coordinate of a point must be seperated by a comma.$"
y_val_exceed	db		"Wrong value: the ordinate must be an integer between 0 and 199.$"
new_line_format	db		"Wrong file format: no new line. The program expects a carriage return and a line feed.$"
;....................ERROR HANDLING STRINGS ENDS....................
data1			ends


stack1		segment stack
;in case of our Assembly the stack starts from high addresses and goes down to lower ones
;16-bit stack, so we need to operate on words
			dw		255 dup(?) ;define 255 words of any value
peek		dw		? ;peek of the stack - when we push something onto it, we go down to allocated 255 words above
stack1		ends


code1		segment
start_prog:
	;............................STACK INITIALIZATION............................
	mov		ax, seg stack1 ;move to AX the stack1 segment address (directive seg)		
	mov		ss, ax ;now move it to the stack segment
	mov		sp, offset peek ;point the stack pointer to the stack peek
	;............................STACK INITIALIZATION ENDS............................
	call	get_and_save_file_name
	call	open_file
	call	read_file
	call	close_file
	call	enter_graphic_mode
	call	parse_and_draw
	call	wait_esc
	call 	exit_graphic_mode
	call	exit_prog


;............................PROCEDURES............................
;............................get file name and save it............................
get_and_save_file_name:
;getting a file name from PSP (Program Segment Prefix) with our data
	;PSP is saved in DS, so we can't destroy it
	;that's why we're going to use ES
	;080h -> number of characters passed
	;081h -> space
	;082h -> parameters string
			
	;write parameters to a buffer
	mov		ax, seg file_name
	mov		es, ax
	mov		si, 82h ;the beginning of the parameters string
	mov		di, offset file_name
	xor		cx, cx ;CX = 0
	mov		cl, byte ptr ds:[80h] ;80h is just 1 byte, so move it to CL instead of CX
	;loop copying the file name char by char
	loop_file_name_chars:		
		mov 	al, byte ptr ds:[si]
		;............................INPUT VALIDATION............................
		;don't accept null
		cmp		al, 0
		jz		err_no_param
		;don't accept whitespace characters
		cmp		al, 9 ;horizontal tab
		jz		err_whitespace_chars
		cmp		al, 10 ;line feed
		jz		err_whitespace_chars
		cmp		al, 11 ;vertical tab
		jz		err_whitespace_chars
		cmp		al, 12 ;form feed
		jz		err_whitespace_chars
		cmp		al, 32 ;space
		jz		err_whitespace_chars
		cmp		al, 13 ;carriage return
		jz		break_loop_file_name_chars ;end of input
		;............................INPUT VALIDATION ENDS............................
		mov		byte ptr es:[di], al
		inc		si
		inc		di
		loop	loop_file_name_chars
	
	break_loop_file_name_chars:
		mov		byte ptr es:[di], 0
	ret


;............................open a file............................
open_file:
;Entry:
    ;AL = access and sharing modes
    ;DS:DX -> ASCIZ filename

;Return:
    ;CF clear if successful, AX = file handle
    ;CF set on error AX = error code (01h,02h,03h,04h,05h,0Ch,56h)

;Notes:
    ;file pointer is set to start of file
    ;file handles which are inherited from a parent also inherit sharing and access restrictions
    ;files may be opened even if given the hidden or system attributes

	mov		ax, seg file_name
	mov 	ds, ax
	mov		dx, offset file_name
	xor		al, al
	mov		ah, 3dh
	int		21h
	jc		err_file_open
	;if no error, AX has the file handle
	mov		word ptr ds:[file_ptr], ax
	ret


;............................read a file............................
read_file:
;Entry:
    ;BX = file handle
    ;CX = number of bytes to read
    ;DS:DX -> buffer for data

;Return:
    ;CF clear if successful - AX = number of bytes actually read (0 if at EOF before call)
    ;CF set on error AX = error code (05h,06h)

;Notes:
    ;data is read beginning at current file position, and the file position is updated after a successful read
    ;the returned AX may be smaller than the request in CX if a partial read occurred
    ;if reading from CON, read stops at first CR

	mov		ax, seg file_buf
	mov 	ds, ax ;now we can use DX because we don't need the PSP data anymore
	mov		dx, offset file_buf
	mov		cx, 4999
	mov		bx, word ptr ds:[file_ptr]
	mov		ah, 3fh
	int		21h
	;if CF=0 then AX = the real number of read characters
	jc		err_file_read
	mov		cx, ax ;we're gonna save it to CX to use it for reading the buffer content
	ret


;............................zamknięcie pliku............................
close_file:
;Entry: BX = file handle

;Return:
    ;CF clear if successful, AX destroyed
    ;CF set on error, AX = error code (06h)

;Note: if the file was written to, any pending disk writes are performed, the time and date stamps are set to the current time, and the directory entry is updated

	mov		bx, word ptr ds:[file_ptr]
	mov		ah, 3eh
	int 	21h
	jc		err_file_close
	ret


;............................enter the graphic mode............................
enter_graphic_mode:
	mov		al, 13h ;graphic mode 320x200, 256 colors
	mov		ah, 0 ;graphic card VGA mode change
	int 	10h
	ret


;............................parse the coordinates and draw geometric shapes............................
parse_and_draw:
	;we have a number of characters in the buffer saved in CX from the read_file procedure
	;so we're going to use it in order to know when to stop parsing the file
	mov		si, offset file_buf
	add		cx, si ;if CX == SI then EOF
	parse_and_draw_loop:
		;first there's a color
		mov		dl, byte ptr ds:[si]
		white:
			cmp		dl, 'W'
			jnz		red
			mov		byte ptr ds:[color], 15
			jmp		color_spaces
		
		red:
			cmp		dl, 'R'
			jnz		green
			mov		byte ptr ds:[color], 4
			jmp		color_spaces
		
		green:
			cmp		dl, 'G'
			jnz		blue
			mov		byte ptr ds:[color], 2
			jmp		color_spaces
		
		blue:
			cmp		dl, 'B'
			jnz		err_color ;wrong color passed
			mov		byte ptr ds:[color], 1
		
		;then we have two spaces seperating it and the coordinates
		color_spaces:
			inc		si
			call	check_two_spaces
		
		;we need to seperate getting the first coordinates and the rest
		first_abscissa:
			xor		ax, ax
			loop_first_abscissa:
				inc		si
				mov		dl, byte ptr ds:[si]
				;check if the characater is a digit
				cmp		dl, '0'
				jb		first_comma ;',' == 44, '0' == 48
				cmp		dl, '9'
				ja		err_not_digit
				;if so, take its real value
				sub		dl, '0'
				call	mul_ax_by_10 ;AX = current value of the abscissa
				call	chk_width
				jmp		loop_first_abscissa
			
		first_comma:
			call	check_comma
			mov		word ptr ds:[x0], ax
			mov		word ptr ds:[x1], ax
		
		first_ordinate:
			xor		ax, ax
			loop_first_ordinate:
				inc		si
				mov		dl, byte ptr ds:[si]
				;check if the characater is a digit
				cmp		dl, '0'
				jb		first_spaces ;' ' == 32, '0' == 48
				cmp		dl, '9'
				ja		err_not_digit
				;if so, take its real value
				sub		dl, '0'
				call	mul_ax_by_10 ;AX = current value of the abscissa
				call	chk_height
				jmp		loop_first_ordinate
		
		first_spaces:
			call	check_two_spaces
			mov		word ptr ds:[y0], ax
			mov		word ptr ds:[y1], ax
		
		rem_abscissa:
			xor		ax, ax
			loop_rem_abscissa:
				inc		si
				mov		dl, byte ptr ds:[si]
				;check if the characater is a digit
				cmp		dl, '0'
				jb		rem_comma ;',' == 44, '0' == 48
				cmp		dl, '9'
				ja		err_not_digit
				;if so, take its real value
				sub		dl, '0'
				call	mul_ax_by_10 ;AX = current value of the abscissa
				call	chk_width
				jmp		loop_rem_abscissa
		
		rem_comma:
			call	check_comma
			mov		word ptr ds:[x2], ax
		
		rem_ordinate:
			xor		ax, ax
			loop_rem_ordinate:
				inc		si
				mov		dl, byte ptr ds:[si]
				;check if EOF
				cmp		si, cx
				jz		draw_last_line_seg
				;check if the characater is a digit
				cmp		dl, '0'
				jb		rem_spaces ;' ' == 32, '0' == 48
				cmp		dl, '9'
				ja		err_not_digit
				;if so, take its real value
				sub		dl, '0'
				call	mul_ax_by_10 ;AX = current value of the abscissa
				call	chk_height
				jmp		loop_rem_ordinate
		
		rem_spaces:
			;if we don't find a space, then it might be a new line
			cmp		dl, ' '
			jnz		check_cr
			;if it's a space, check for the second one
			inc		si
			call	check_space
			;if everything is alright, we rearrange current coordinates and draw a line segment
			mov		word ptr ds:[ye], ax ;AX = current ye
			push	ax ;need to save it for y1 later
			mov		ax, word ptr ds:[x2]
			mov		word ptr ds:[xe], ax
			mov		ax, word ptr ds:[y1]
			mov		word ptr ds:[ys], ax
			mov		ax, word ptr ds:[x1]
			mov		word ptr ds:[xs], ax
			call	draw_curve
			;now we need to "move" them forward to make space for the next ones
			pop		ax ;AX = ye
			mov		word ptr ds:[y1], ax ;the current end point will be the start point of the next line segment
			mov		ax, word ptr ds:[x2] ;ditto
			mov		word ptr ds:[x1], ax
			jmp		rem_abscissa ;more than two points
		
		check_cr:
			cmp		dl, 13
			jz		check_lf
			call	err_new_line
		
		check_lf:
			inc		si
			mov		dl, byte ptr ds:[si]
			cmp		dl, 10
			jz		draw_last_line_seg
			call	err_new_line
		
		draw_last_line_seg:
			;first the line segment point we have just calculated
			mov		word ptr ds:[ye], ax
			push 	ax
			mov		ax, word ptr ds:[x2]
			mov		word ptr ds:[xe], ax
			mov		ax, word ptr ds:[y1]
			mov		word ptr ds:[ys], ax
			mov		ax, word ptr ds:[x1]
			mov		word ptr ds:[xs], ax
			call	draw_curve
			;the last line segment
			pop		ax ;AX = y2
			mov		word ptr ds:[ys], ax
			mov		ax, word ptr ds:[x2]
			mov		word ptr ds:[xs], ax
			mov		ax, word ptr ds:[y0]
			mov		word ptr ds:[ye], ax
			mov		ax, word ptr ds:[x0]
			mov		word ptr ds:[xe], ax
			call	draw_curve
			inc		si
			cmp		si, cx
			jb		parse_and_draw_loop
		
	ret


;............................wait for ESC............................
wait_esc:
;int 16,0 could also be used here
	in		al, 60h
	cmp		al, 1
	jnz		wait_esc
	ret


;............................exit the graphic mode............................
exit_graphic_mode:
	mov		al, 3 ;text mode
	mov		ah, 0 ;change graphic card VGA mode
	int 	10h
	ret


;............................exit program............................
exit_prog:
	mov		ax, 4c00h
	int		21h


;............................ERROR HANDLING PROCEDURES............................
;............................print error and exit program............................
print_err:			
	call print_string
	call exit_prog


;............................error - no parameter on program start............................
err_no_param: 		
	mov 	dx, offset no_param
	call	print_err


;............................error - whitespace characters............................
err_whitespace_chars: 	
	mov 	dx, offset white_chars
	call	print_err		


;............................error - can't open a file............................
err_file_open:		
	mov		dx, offset file_open_err
	call	print_err


;............................error - can't close a file............................
err_file_close:	
	mov		dx, offset file_close_err
	call	print_err


;............................error - can't read a file............................
err_file_read:		
	mov		dx, offset file_read_err
	call 	exit_graphic_mode
	call	print_err


;............................error - wrong color inside a file............................
err_color:			
	mov 	dx, offset wrong_color
	call 	exit_graphic_mode
	call	print_err


;............................check - two spaces............................
check_two_spaces:
	call	check_space
	inc		si
	call	check_space
	ret


;............................check - one space............................
check_space:
	mov		dl, byte ptr ds:[si]
	cmp		dl, ' '
	jnz		err_no_spaces
	ret


;............................check - width between 0 and 319............................
chk_width:
	add		al, dl ;current value of the abscissa
	cmp		ax, 319
	ja		err_x_val_exceed
	ret


;............................check - height between 0 and 199............................
chk_height:
	add		al, dl
	cmp		ax, 199
	ja		err_y_val_exceed
	ret


;............................check - DL value is a comma............................
check_comma:
	cmp		dl, ','
	jnz		err_no_comma
	ret


;............................error - no two spaces between pairs of coordinates............................
err_no_spaces:		
	mov		dx, offset two_spaces
	call 	exit_graphic_mode
	call 	print_err


;............................error - coordinates aren't non-negative integers............................
err_not_digit:		
	mov		dx, offset not_digit
	call	exit_graphic_mode
	call	print_err


;............................error - width isn't between 0 and 319............................
err_x_val_exceed:	
	mov		dx, offset x_val_exceed
	call	exit_graphic_mode
	call	print_err


;............................error - pairs of coordinates aren't seperated with a comma............................
err_no_comma:		
	mov		dx, offset no_comma
	call 	exit_graphic_mode
	call	print_err


;............................error - height isn't between 0 and 199............................
err_y_val_exceed:	
	mov		dx, offset y_val_exceed
	call	exit_graphic_mode
	call	print_err


;............................error - no new line............................
err_new_line:		
	mov		dx, offset new_line_format
	call	exit_graphic_mode
	call	print_err


;............................PROCEDURY POMOCNICZE............................
;............................print string ending with a '$' character............................
;in: 
;DX = offset of a string to be printed (must end with a '$')
;out:
print_string:
;Entry: DS:DX -> '$'-terminated string
	mov		ax, seg data1
	mov		ds, ax
	;the above could be done otherwise:
	;push	ax
	;pop	ds
	;but it's slower since the former method accesses the memory only once, whereas the latter accesses it twice
	
	mov		ah, 9
	int 	21h
	ret


;............................mul AX by 10............................
mul_ax_by_10:
	mov		bx, ax ;BX = AX
	sal		ax, 3 ;AX *= 8
	sal		bx, 1 ;BX *= 2
	add		ax, bx ;AX *= 10
	ret


;............................Bresenham's line algorithm............................
draw_curve:
	push	ax
	push	bx
	push	cx
	push	dx
	;the angle in range [0, pi/4]:
	mov		word ptr ds:[mx], 1
	mov		word ptr ds:[my], 320
	mov		ax, word ptr ds:[xs]
	mov		bx, word ptr ds:[xe]
	;check if xs < xe
	cmp		ax, bx
	jb		rev_Y_ax
	;else we exchange xs with xe and ys with ye
	xchg	ax, bx
	mov		word ptr ds:[xs], ax
	mov		word ptr ds:[xe], bx
	mov		ax, word ptr ds:[ys]
	mov		bx, word ptr ds:[ye]
	xchg	ax, bx
	mov		word ptr ds:[ys], ax
	mov		word ptr ds:[ye], bx
rev_Y_ax:	
	;reverse the OY axis so the starting point is in the bottom left (as opposed to the upper left)
	mov		bx, word ptr ds:[ys]
	mov		ax, 199
	sub 	ax, bx
	mov		word ptr ds:[ys], ax
	mov		bx, word ptr ds:[ye]
	mov		ax, 199
	sub 	ax, bx
	mov		word ptr ds:[ye], ax
	;reverse ends
	mov		bx, word ptr ds:[xe]
	sub		bx, word ptr ds:[xs] ;BX = delx = xe - xs
	mov		ax, word ptr ds:[ye]
	sub		ax, word ptr ds:[ys] ;AX = dely = ye - ys
	jge		dely_ge_zero ;if dely >= 0 (signed) then dely_ge_zero (intuitively --- a non-decreasing function, so case1 or case3)
	;else a non-increasing function, so case 2 or case4
	mov		dx, ax ;copy dely beacuse in case2 the sign of AX is changed (as is the sign of BX in case4) and to modify it I would have to duplicate the code
	neg		dx ;dx = abs(dely)
	cmp		dx, bx ;if abs(dely) >= delx <=> a >= 1 <=> angle >= pi/4
	jge		case4 ;then case4
	jmp		case2 ;else case2
dely_ge_zero:
	cmp		ax, bx ;if dely >= delx <=> a >= 1 <=> angle >= pi/4
	jge		case3 ;then case3 else case1
	;case 1.: the angle in range [0, pi/4]:
	;0 <= a <= 1
	;delx = xe - xs
	;dely = ye - ys
	;my = 320
	;mx = 1
	case1:
		jmp		draw
	;case 2.: the angle in range [3pi/4, pi]:
	;-1 <= a <= 0
	;delx = xe - xs
	;dely = ye - ys
	;my = -320
	;mx = 1
	case2:
		neg		ax ;dely = -dely
		mov		word ptr ds:[my], -320
		jmp		draw
	;case 3.: the angle in range [pi/4, pi/2]:
	;we "exchange" axes
	;a >= 1
	;delx = ye - ys
	;dely = xe - xs
	;my = 1
	;mx = 320
	case3:
		xchg	ax, bx
		mov		word ptr ds:[my], 1
		mov		word ptr ds:[mx], 320
		jmp		draw
	;case 4.: the angle in range [pi/2, 3pi/4]:
	;connecting case2 and case3
	;a <= -1
	;delx = ye - ys
	;dely = xe - xs
	;my = 1
	;mx = -320
	case4:
		xchg	ax, bx
		neg		bx ;dely := -dely
		mov		word ptr ds:[my], 1
		mov		word ptr ds:[mx], -320

	draw:
		mov		word ptr ds:[delx], bx
		mov		word ptr ds:[dely], ax

		mov		ax, word ptr ds:[dely]
		sal		ax, 1 ;ax = 2*dely
		sub		ax, word ptr ds:[delx]
		mov		word ptr ds:[d_i], ax ;d_i := 2*dely - delx
		mov		ax, word ptr ds:[dely]
		sub		ax, word ptr ds:[delx]
		sal		ax, 1
		mov		word ptr ds:[rob], ax ;rob := 2*(dely - delx)
		;address = 320*ys + xs; we're going to keep it in CX beacuse we're going to need AX to light pixels
		mov		ax, word ptr ds:[ys]
		mov		cx, ax
		sal		cx, 8 ;CX = 256*ys
		sal		ax, 6 ;AX = 64*ys
		add		cx, ax ;CX = 320*ys
		add		cx, word ptr ds:[xs] ;CX = 320*ys + xs

	put_pixel_loop:
		cmp		word ptr ds:[delx], 0 ;delx seems like a good counter since in each step we increment the abscissa
		jl		delx_l_zero
		;............................PUT PIXEL............................
		mov		ax, 0a000h
		mov		es, ax
		mov		bx, cx
		mov		al, byte ptr ds:[color]
		mov		byte ptr es:[bx], al
		;............................PUT PIXEL ENDS............................
		cmp		word ptr ds:[d_i], 0 ;if DD_I < 0
		jl		di_l_zero ;then di_l_zero
		;DD_I >= 0
		;di1 = d_i + 2(dely - delx)
		mov		ax, word ptr ds:[d_i]
		add		ax, word ptr ds:[rob]
		mov		word ptr ds:[di1], ax ;di1 = d_i + rob = d_i + 2(dely - delx)
		mov		ax, cx
		add		ax, word ptr ds:[my] ;address = address + my
		mov		cx, ax
		jmp		adjust_mx

		di_l_zero:
		;di1 = d_i + 2*dely
			mov		ax, word ptr ds:[dely]
			sal		ax, 1
			add		ax, word ptr ds:[d_i]
			mov		word ptr ds:[di1], ax

		adjust_mx:
			mov		ax, cx
			add		ax, word ptr ds:[mx] ;address = address + mx
			mov		cx, ax
			mov		ax, word ptr ds:[di1]
			mov		word ptr ds:[d_i], ax ;in the next iteration DD_i = DD_{i+1}
			dec		word ptr ds:[delx] ;decrement our loop counter
			jmp		put_pixel_loop
	
	delx_l_zero:
		pop	dx
		pop	cx
		pop	bx
		pop	ax
		ret


code1		ends

end		start_prog ;letting the compiler know to start the program from this label