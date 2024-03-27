; SidecarT GEMDRIVE Emulator
; (C) 2023-24 by Diego Parrilla
; License: GPL v3

; Emulate a GEM hard disk drive using a folder in the microSD card

; Bootstrap the code in ASM

    XREF    rom_function

    XDEF    nf_has_flag
    XDEF    nf_stderr_crlf
    XDEF    nf_stderr_id
    XDEF    nf_hexnum_buff
    XDEF    nf_debugger_id


    XDEF    random_token
    XDEF    random_token_seed

  	include inc/tos.s
    include inc/debug.s

	section code

main:

    move.l  4(sp),a0        ; Pointer to BASEPAGE

    move.l #mystack + (end_stack - mystack - 4),sp     ; Set the stack

    move.l    #$100,d0      ; Length of basepage
    add.l     $c(a0),d0     ; Length of the TEXT segment
    add.l     $14(a0),d0    ; Length of the DATA segment
    add.l     $1c(a0),d0    ; Length of the BSS segment

    move.l    d0, reserved_mem      ; Save the length to use in Ptermres()
    move.l    d0,-(sp)      ; Return to the stack
    move.l    a0,-(sp)      ; Basepage address to stack
    clr.w   -(sp)           ; Fill parameter
    move.w  #$4A,-(sp)      ; Mshrink
    trap    #1              ; Call GEMDOS 
    lea     $c(sp), sp      ; Correct stack

    ifeq _DEBUG
    tst.l   d0              ; Check for errors
    bne     prg_memory_error; Exit if error
    endif

	; Supervisor mode
	EnterSuper

    ifne _DEBUG
	; Save the ID for triggering stderr
	pea     nf_stderr         ;dc.b "NF_STDERR",
	clr.l   -(a7)                   ;dummy because of C API
	dc.w    $7300                   ;query natfeats
	move.l  d0,nf_stderr_id ;save ID. ID is 0 if not supported.
	or.l d0, nf_has_flag
	addq.l  #8,a7

	; Save the ID for triggering debugger
	pea     nf_debugger_name        ;dc.b "NF_DEBUGGER",0
	clr.l   -(a7)                   ;dummy because of C API
	dc.w    $7300                   ;query natfeats
	move.l  d0,nf_debugger_id ;save ID. ID is 0 if not supported.
	or.l d0, nf_has_flag
	addq.l  #8,a7
    endif

    bsr rom_function

    ; Exit supervisor mode
    ExitSuper

    ifeq _DEBUG
        move.l reserved_mem, d0             ; Get length of memory to keep
    else
        move.l (end_main-main), d0    ; Get length of memory to keep as the size of the executable
    endif
    move.w #0, -(sp)                    ; Return value of the program
    move.l  d0,-(sp)                    ; Length of memory to keep
    move.w  #$31,-(sp)                  ; Ptermres
    trap    #1                          ; Call GEMDOS

prg_memory_error:
    pea prg_memory_error_msg

exit_failure:
	move	#9,-(sp)	; Cconws
	trap	#1
	addq.l	#6,sp

	move.w	#7,-(sp)	; Crawcin
	trap	#1
	addq.l	#2,sp

    move.w  d0,-(sp)                ; Error code
    move.w  #$4C,-(sp)              ; GEMDOS function Pterm
    trap    #1                      ; Call GEMDOS
    rts

; ---- data section

data:
        even
random_token: dc.l $12345678   ; Random token to check if the command returns a value
random_token_seed: dc.l $12345678   ; Random token seed passed to the command
    
        even
; Debugging
nf_has_flag         dc.l 0              ; Natfeats flag. 0 = not installed, Not zero = installed
nf_stderr           dc.b "NF_STDERR",0  ; Natfeats stderr device name
nf_debugger_name    dc.b "NF_DEBUGGER",0; Natfeats debugger device name
nf_stderr_crlf      dc.b 13,10,0        ; Carriage return + line feed

        even
; Messages
gemdrive_emulator_msg:
          	dc.b	"SidecarT GEMDRIVE",$d,$a,0

prg_memory_error_msg:
            dc.b "Error reserving memory for the program",$d,$a,0

; ---- BSS section
bss:
            even

; Debugging
nf_stderr_id:       ds.l  1
nf_debugger_id:     ds.l  1
nf_hexnum_buff:     ds.b  10    ; 8 hex digits + 0 + blank

            even
changed:            ds.w    1
reserved_mem:       ds.l    1
savestack:          ds.l    1


mystack:
            ds.l    2000          ; 8000 bytes stack
end_stack:  

end_main:
