; SidecarT GEMDRIVE
; (C) 2023 by Diego Parrilla
; License: GPL v3

; Emulate a GEM hard disk drive using the SidecarT in a folder of the SD card

; Bootstrap the code in ASM

    XDEF   rom_function

    ifne _DEBUG
    XREF    nf_has_flag
    XREF    nf_stderr_crlf
    XREF    nf_stderr_id
    XREF    nf_hexnum_buff
    XREF    nf_debugger_id
    endif

; CONSTANTS
RANDOM_SEED             equ $1284FBCD  ; Random seed for the random number generator. Should be provided by the pico in the future
DELAY_NOPS              equ 0          ; Number of nops to wait each test of the random number generator
BUFFER_READ_SIZE        equ 8192       ; Number of bytes to read from the Sidecart in each read call
BUFFER_WRITE_SIZE       equ 1024       ; Number of bytes to write to the Sidecart in each write call
BASEPAGE_OFFSET_DTA     equ 32         ; Offset of the DTA in the basepage
FWRITE_RETRIES          equ 3          ; Number of retries to write the data to the Sidecart per each Sidecart call
EMULATED_DRIVE          equ 2          ; Emulated drive number: C = 2, D = 3, E = 4, F = 5, G = 6, H = 7, I = 8, J = 9, K = 10, L = 11, M = 12
                                       ; N = 13, O = 14, P = 15
EMULATED_DRIVE_BITMAP   equ 2          ; Bit number of the emulated drive in the _drvbits variable
PE_LOAD_GO              equ 0          ; Pexec mode to load the program and execute it
PE_LOAD                 equ 3          ; Pexec mode to load the program and return
PE_GO                   equ 4          ; Pexec mode to execute the program
PE_CREATE_BASEPAGE      equ 5          ; Pexec mode to create the basepage
PE_GO_AND_FREE          equ 6          ; Pexec mode to execute the program with the new format
PRG_STRUCT_SIZE         equ 28         ; Size of the GEMDOS structure in the executable header file (PRG)
                                       ; 2 bytes: g_magic
                                       ; 4 bytes: g_tsize
                                       ; 4 bytes: g_dsize
                                       ; 4 bytes: g_bsize
                                       ; 4 bytes: g_ssize
                                       ; 4 bytes: g_junk1
                                       ; 4 bytes: g_hflags
                                       ; 2 bytes: g_absflg
PRG_MAGIC_NUMBER        equ $601A      ; Magic number of the PRG file

ROM4_START_ADDR         equ $FA0000 ; ROM4 start address
ROM3_START_ADDR         equ $FB0000 ; ROM3 start address
ROM_EXCHG_BUFFER_ADDR   equ (ROM3_START_ADDR)               ; ROM4 buffer address
RANDOM_TOKEN_ADDR:        equ (ROM_EXCHG_BUFFER_ADDR)
RANDOM_TOKEN_SEED_ADDR:   equ (RANDOM_TOKEN_ADDR + 4) ; RANDOM_TOKEN_ADDR + 0 bytes
RANDOM_TOKEN_POST_WAIT:    equ $8        ; Wait this cycles after the random number generator is ready

CMD_MAGIC_NUMBER        equ (ROM3_START_ADDR + $ABCD)       ; Magic number to identify a command
APP_GEMDRVEMUL          equ $0400                           ; MSB is the app code. GEMDRIVE is $04
CMD_PING                equ ($0 + APP_GEMDRVEMUL)           ; Command code to ping to the Sidecart
CMD_SAVE_VECTORS        equ ($1 + APP_GEMDRVEMUL)           ; Command code to save the vectors in the Sidecart
CMD_SHOW_VECTOR_CALL    equ ($2 + APP_GEMDRVEMUL)           ; Command code to send to the RP2040 the GEMDOS command executed
CMD_REENTRY_LOCK        equ ($3 + APP_GEMDRVEMUL)           ; Command to enable reentry GEMDOS calls
CMD_REENTRY_UNLOCK      equ ($5 + APP_GEMDRVEMUL)           ; Command to disable reentry GEMDOS calls
CMD_RTC_START           equ ($6 + APP_GEMDRVEMUL)           ; Start the RTC
CMD_RTC_STOP            equ ($7 + APP_GEMDRVEMUL)           ; Stop the RTC
CMD_NETWORK_START       equ ($8 + APP_GEMDRVEMUL)           ; Start the network stack
CMD_NETWORK_STOP        equ ($9 + APP_GEMDRVEMUL)           ; Stop the network stock

CMD_DGETDRV_CALL        equ ($19 + APP_GEMDRVEMUL)           ; Command code to send to the RP2040 the Dgetdrv() command executed
CMD_FSETDTA_CALL        equ ($1A + APP_GEMDRVEMUL)           ; Command code to send to the RP2040 the Fsetdta() command executed
CMD_FSFIRST_CALL        equ ($4E + APP_GEMDRVEMUL)           ; Command code to send to the RP2040 the Fsfirst() command executed
CMD_FSNEXT_CALL         equ ($4F + APP_GEMDRVEMUL)           ; Command code to send to the RP2040 the Fsnext() command executed

CMD_FCREATE_CALL        equ ($3C + APP_GEMDRVEMUL)           ; Command code to send to the RP2040 the Fcreate() command executed
CMD_FOPEN_CALL          equ ($3D + APP_GEMDRVEMUL)           ; Command code to send to the RP2040 the Fopen() command executed
CMD_FCLOSE_CALL         equ ($3E + APP_GEMDRVEMUL)           ; Command code to send to the RP2040 the Fclose() command executed
CMD_DFREE_CALL          equ ($36 + APP_GEMDRVEMUL)           ; Command code to send to the RP2040 the Dfree() command executed
CMD_DGETPATH_CALL       equ ($47 + APP_GEMDRVEMUL)           ; Command code to send to the RP2040 the Dgetpath() command executed
CMD_DSETPATH_CALL       equ ($3B + APP_GEMDRVEMUL)           ; Command code to send to the RP2040 the Dsetpath() command executed
CMD_DCREATE_CALL        equ ($39 + APP_GEMDRVEMUL)           ; Command code to send to the RP2040 the Dcreate() command executed
CMD_DDELETE_CALL        equ ($3A + APP_GEMDRVEMUL)           ; Command code to send to the RP2040 the Ddelete() command executed
CMD_FDELETE_CALL        equ ($41 + APP_GEMDRVEMUL)           ; Command code to send to the RP2040 the Fdelete() command executed
CMD_FSEEK_CALL          equ ($42 + APP_GEMDRVEMUL)           ; Command code to send to the RP2040 the Fseek() command executed
CMD_FATTRIB_CALL        equ ($43 + APP_GEMDRVEMUL)           ; Command code to send to the RP2040 the Fattrib() command executed

CMD_FRENAME_CALL        equ ($56 + APP_GEMDRVEMUL)           ; Command code to send to the RP2040 the Frename() command executed
CMD_FDATETIME_CALL      equ ($57 + APP_GEMDRVEMUL)           ; Command code to send to the RP2040 the Fdatetime() command executed

CMD_MALLOC_CALL         equ ($48 + APP_GEMDRVEMUL)           ; Command code to send to the RP2040 the malloc() command executed
CMD_PEXEC_CALL          equ ($4B + APP_GEMDRVEMUL)           ; Command code to send to the RP2040 the Pexec() command executed

; This commands are not direct GEMDOS calls, but they are used to send data to the Sidecart
CMD_READ_BUFF_CALL      equ ($81 + APP_GEMDRVEMUL)           ; Command code to send to the RP2040 the read the buffer
CMD_DEBUG               equ ($82 + APP_GEMDRVEMUL)           ; Command code to send to the RP2040 the debug command
CMD_SAVE_BASEPAGE       equ ($83 + APP_GEMDRVEMUL)           ; Command code to send to the RP2040 the save basepage command
CMD_SAVE_EXEC_HEADER    equ ($84 + APP_GEMDRVEMUL)           ; Command code to send to the RP2040 the save exec header command 

CMD_SET_SHARED_VAR      equ ($87 + APP_GEMDRVEMUL)           ; Set a shared variable
CMD_WRITE_BUFF_CALL     equ ($88 + APP_GEMDRVEMUL)           ; Command code to send to the RP2040 the write the buffer
CMD_WRITE_BUFF_CHECK    equ ($89 + APP_GEMDRVEMUL)           ; Write to sdCard the write buffer check call
CMD_DTA_EXIST_CALL      equ ($8A + APP_GEMDRVEMUL)           ; Check if the DTA exists in the rp2040 memory
CMD_DTA_RELEASE_CALL    equ ($8B + APP_GEMDRVEMUL)           ; Release the DTA from the rp2040 memory



; Shared variables indexes
SHARED_VARIABLE_PEXEC_RESTORE           equ 0             ; Pexec address to restore the program
SHARED_VARIABLE_SVERSION                equ 1             ; Sidecart version from Sversion
SHARED_VARIABLE_FIRST_FILE_DESCRIPTOR   equ 2             ; First file descriptor to use in the Sidecart
SHARED_VARIABLE_DRIVE_LETTER            equ 3             ; Drive letter of the emulated drive
SHARED_VARIABLE_DRIVE_NUMBER            equ 4             ; Drive number of the emulated drive
SHARED_VARIABLE_BUFFER_TYPE             equ 5             ; Buffer type to use in the Sidecart

GEMDRVEMUL_TIMEOUT_SEC  equ (ROM_EXCHG_BUFFER_ADDR + $8)     ; ROM_EXCHG_BUFFER_ADDR + 8 bytes
GEMDRVEMUL_PING_STATUS  equ (GEMDRVEMUL_TIMEOUT_SEC + $4)    ; GEMDRVEMUL_TIMEOUT_SEC + 4 bytes
GEMDRVEMUL_RTC_STATUS   equ (GEMDRVEMUL_PING_STATUS + 4)     ; ping status + 4 bytes
GEMDRVEMUL_NETWORK_STATUS   equ (GEMDRVEMUL_RTC_STATUS + 4)  ; rtc status + 4 bytes
GEMDRVEMUL_NETWORK_ENABLED  equ (GEMDRVEMUL_NETWORK_STATUS + 4) ; network status + 4 bytes
GEMDRVEMUL_OLD_GEM_VEC  equ (GEMDRVEMUL_NETWORK_ENABLED + $4)    ; GEMDRVEMUL_NETWORK_ENABLED + 4 bytes
GEMDRVEMUL_REENTRY_TRAP equ (GEMDRVEMUL_OLD_GEM_VEC + $4)   ; GEMDRVEMUL_OLD_GEM_VEC + 4 bytes
GEMDRVEMUL_DEFAULT_PATH equ (GEMDRVEMUL_REENTRY_TRAP + $4)  ; GEMDRVEMUL_REENTRY_TRAP + 4 bytes
GEMDRVEMUL_DTA_F_FOUND  equ (GEMDRVEMUL_DEFAULT_PATH + $80)  ; GEMDRVEMUL_DEFAULT_PATH + 128 bytes
GEMDRVEMUL_DTA_TRANSFER equ (GEMDRVEMUL_DTA_F_FOUND + $4)   ; GEMDRVEMUL_DTA_F_FOUND + 4 bytes
GEMDRVEMUL_DTA_EXIST    equ (GEMDRVEMUL_DTA_TRANSFER + 48) ; dta transfer + sizeof(DTA) bytes
GEMDRVEMUL_DTA_RELEASE  equ (GEMDRVEMUL_DTA_EXIST + 4)     ; dta exist + 4 bytes
GEMDRVEMUL_SET_DPATH_STATUS equ (GEMDRVEMUL_DTA_RELEASE + 4)  ; dta release + 4 bytes
GEMDRVEMUL_FOPEN_HANDLE equ (GEMDRVEMUL_SET_DPATH_STATUS + 2)    ; GEMDRVEMUL_SET_DPATH_STATUS + 2 bytes
GEMDRVEMUL_READ_BYTES  equ (GEMDRVEMUL_FOPEN_HANDLE + 2)        ; GEMDRVEMUL_FOPEN_HANDLE + 2 bytes
GEMDRVEMUL_READ_BUFFER  equ (GEMDRVEMUL_READ_BYTES + 4)         ; GEMDRVEMUL_READ_BYTES + 4 bytes
GEMDRVEMUL_WRITE_BYTES equ (GEMDRVEMUL_READ_BUFFER + BUFFER_READ_SIZE) ; GEMDRVEMUL_READ_BUFFER + BUFFER_READ_SIZE bytes
GEMDRVEMUL_WRITE_CHK  equ (GEMDRVEMUL_WRITE_BYTES + 4)         ; GEMDRVEMUL_WRITE_BYTES + 4 bytes
GEMDRVEMUL_WRITE_CONFIRM_STATUS equ (GEMDRVEMUL_WRITE_CHK + 4)     ; GEMDRVEMUL_WRITE_CHK+ 4 bytes
GEMDRVEMUL_FCLOSE_STATUS equ (GEMDRVEMUL_WRITE_CONFIRM_STATUS + 4) ; GEMDRVEMUL_WRITE_CONFIRM_STATUS + 4 bytes
GEMDRVEMUL_DCREATE_STATUS equ (GEMDRVEMUL_FCLOSE_STATUS + 2)     ; GEMDRVEMUL_FCLOSE_STATUS + 2 bytes
GEMDRVEMUL_DDELETE_STATUS equ (GEMDRVEMUL_DCREATE_STATUS + 2)    ; GEMDRVEMUL_DCREATE_STATUS + 2 bytes
GEMDRVEMUL_EXEC_HEADER  equ (GEMDRVEMUL_DDELETE_STATUS + 4)   ; GEMDRVEMUL_DDELETE_STATUS + 2 bytes + 2 bytes padding. Must be aligned to 4 bytes/32 bits
GEMDRVEMUL_FCREATE_HANDLE equ (GEMDRVEMUL_EXEC_HEADER + 32)         ; GEMDRVEMUL_EXEC_HEADER + 32 bytes
GEMDRVEMUL_FDELETE_STATUS equ (GEMDRVEMUL_FCREATE_HANDLE + 4)       ; GEMDRVEMUL_FCREATE_HANDLE + 4 bytes
GEMDRVEMUL_FSEEK_STATUS equ (GEMDRVEMUL_FDELETE_STATUS + 4)         ; GEMDRVEMUL_FDELETE_STATUS + 4 bytes
GEMDRVEMUL_FATTRIB_STATUS equ (GEMDRVEMUL_FSEEK_STATUS + 4)             ;  GEMDRVEMUL_FSEEK_STATUS + 4 bytes
GEMDRVEMUL_FRENAME_STATUS equ (GEMDRVEMUL_FATTRIB_STATUS + 4)         ; GEMDRVEMUL_FSEEK_STATUS + 4 bytes
GEMDRVEMUL_FDATETIME_DATE       equ (GEMDRVEMUL_FRENAME_STATUS + 4)      ; GEMDRVEMUL_FRENAME_STATUS + 4 bytes
GEMDRVEMUL_FDATETIME_TIME       equ (GEMDRVEMUL_FDATETIME_DATE + 4)      ; GEMDRVEMUL_FDATETIME_DATE + 4
GEMDRVEMUL_FDATETIME_STATUS     equ (GEMDRVEMUL_FDATETIME_TIME + 4)      ; GEMDRVEMUL_FDATETIME_TIME + 4 bytes
GEMDRVEMUL_DFREE_STATUS         equ (GEMDRVEMUL_FDATETIME_STATUS + 4)    ; GEMDRVEMUL_FRENAME_STATUS + 4 bytes
GEMDRVEMUL_DFREE_STRUCT         equ (GEMDRVEMUL_DFREE_STATUS + 4)        ; GEMDRVEMUL_DFREE_STATUS + 4 bytes

GEMDRVEMUL_PEXEC_MODE       equ (GEMDRVEMUL_DFREE_STRUCT + 32)       ; dfree struct + 32 bytes
GEMDRVEMUL_PEXEC_STACK_ADDR equ (GEMDRVEMUL_PEXEC_MODE + 4)         ; pexec mode status + 4 bytes
GEMDRVEMUL_PEXEC_FNAME      equ (GEMDRVEMUL_PEXEC_STACK_ADDR + 4)   ; pexec mode + 4 bytes
GEMDRVEMUL_PEXEC_CMDLINE    equ (GEMDRVEMUL_PEXEC_FNAME + 4)        ; pexec fname + 4 bytes
GEMDRVEMUL_PEXEC_ENVSTR     equ (GEMDRVEMUL_PEXEC_CMDLINE + 4)      ; pexec cmd line + 4 bytes


GEMDRVEMUL_SHARED_VARIABLES equ (GEMDRVEMUL_PEXEC_ENVSTR + 4)       ; exec PD + 4 bytes

GEMDRVEMUL_EXEC_PD          equ (GEMDRVEMUL_SHARED_VARIABLES + 256) ; shared variables + 256 bytes


_drvbits                equ $4c2                            ; Each of 32 bits in this longword represents a drive connected to the system. Bit #0 is A, Bit #1 is B and so on.
_dskbufp                equ $4c6                            ; Address of the disk buffer pointer    
_sysbase                equ $4f2                            ; Address of the system base
_longframe              equ $59e                            ; Address of the long frame flag. If this value is 0 then the processor uses short stack frames, otherwise it uses long stack frames.
VEC_GEMDOS              equ $21                             ; Trap #1 GEMDOS vector
DSKBUFP_TMP_ADDR        equ $100                            ; Address of the temporary registry buffer to store the DSKBUF pointer
DSKBUFP_SWAP_ADDR       equ $200                            ; Address of the temporary swap buffer to store the DSKBUF pointer

USE_DSKBUF              equ 0                               ; Use the DSKBUF pointer to store the address of the buffer to read the data from the Sidecart. 0 = Stack, 1 = disk buffer

GEMDOS_EINTRN           equ -65 ; GEMDOS Internal error


; Macros

; Send a synchronous command to the Sidecart passing arguments in the Dx registers
; /1 : The command code
; /2 : The payload size (even number always)
send_sync           macro
                    moveq.l #\2, d1                      ; Set the payload size of the command
                    move.w #\1,d0                        ; Command code
                    bsr send_sync_command_to_sidecart    ; Send the command to the Sidecart
                    endm    

; Send a synchronous write command to the Sidecart passing arguments in the D3-D5 registers
; A4 address of the buffer to send
; /1 : The command code
; /2 : The buffer size to send in bytes (will be rounded to the next word)
send_write_sync     macro
                    move.w #\1,d0                           ; Command code
                    moveq.l #12, d1                         ; Set the payload size of the command (d3.l, d4.l and d5.l)
                    move.l #\2,d6                           ; Number of bytes to send
                    bsr send_sync_write_command_to_sidecart ; Send the command to the Sidecart
                    endm    

; Return the error code from the Sidecart and restore the registers in the interrupt handler
; /1 : The memory address to return the error code
return_interrupt_w  macro
                    move.w \1, d0                        ; Return the error code from the Sidecart
                    ext.l d0                             ; Extend the sign of the value
                    movem.l (sp)+,d2-d7/a2-a6            ; Restore registers
                    rte
                    endm

return_interrupt_l  macro
                    move.l \1, d0                        ; Return the error code from the Sidecart
                    movem.l (sp)+,d2-d7/a2-a6            ; Restore registers
                    rte
                    endm

; Send a synchronous command to the Sidecart setting the reentry flag for the next GEMDOS calls
; inside our trapped GEMDOS calls. Should be always paired with reentry_gem_unlock
reentry_gem_lock	macro
                    move.w #CMD_REENTRY_LOCK,d0          ; Command code to lock the reentry
                    moveq.w #0,d1                        ; Payload size is 0 bytes
                    bsr send_sync_command_to_sidecart
                	endm

; Send a synchronous command to the Sidecart clearing the reentry flag for the next GEMDOS calls
; inside our trapped GEMDOS calls. Should be always paired with reentry_gem_lock
reentry_gem_unlock  macro
                    move.w #CMD_REENTRY_UNLOCK,d0        ; Command code to unlock the reentry
                    moveq.w #0,d1                        ; Payload size is 0 bytes
                    bsr send_sync_command_to_sidecart
                	endm
; Check if the drive is the emulated one. If not, exec_old_handler the code
; otherwise continue with the code
detect_emulated_drive   macro
                        reentry_gem_lock
                        gemdos Dgetdrv, 2                    ; Call Dgetdrv() and get the drive number
                        move.l d0, -(sp)                     ; Save the return value with the drive number
                        reentry_gem_unlock              
                        move.l (sp)+, d0                     ; Restore the drive number
                        cmp.w (GEMDRVEMUL_SHARED_VARIABLES + 2 + (SHARED_VARIABLE_DRIVE_NUMBER * 4)), d0            ; Check if the drive is the emulated one
                        bne .exec_old_handler
                        endm

; Check if the first letter of the path is the emulated drive. If not, exec_old_handler the code
; Pass the address of the file specification string in a4
detect_emulated_drive_letter   macro
                        cmp.b #':', 1(a4)                    ; Check if the second character of the file specification string is the colon
                        bne.s .\@detect_emulated_drive_continue; If not, exec_old_handler the code. Otherwise continue with the code
                        move.b (a4), d0                      ; Get the first letter of the file specification string
                        cmp.b (GEMDRVEMUL_SHARED_VARIABLES + 3 + (SHARED_VARIABLE_DRIVE_LETTER * 4)), d0 ; Check if the first letter is the emulated drive
                        bne .exec_old_handler                ; If not, exec_old_handler the code. Otherwise continue with the code
                        bra.s .\@detect_emulated_drive_ignore; The drive is the emulated one, ignoe detect the current drive
.\@detect_emulated_drive_continue:
                        detect_emulated_drive                ; Check if the drive is the emulated one.
.\@detect_emulated_drive_ignore:
                        endm

; Check if the file handler is of the SidecarT or not.
detect_emulated_file_handler   macro
                        and.l #$FFFF, d3                     ; Mask the upper word of the file handle
;                        move.l d3, -(sp)                     ; Save the file handle
;                        send_sync CMD_DEBUG, 4               ; Send the command to the Sidecart. 4 bytes of payload
;                        move.l (GEMDRVEMUL_SHARED_VARIABLES + (SHARED_VARIABLE_FIRST_FILE_DESCRIPTOR * 4)), d3
;                        send_sync CMD_DEBUG, 4
;                        move.l (sp)+, d3                     ; Restore the file handle
                        cmp.l (GEMDRVEMUL_SHARED_VARIABLES + (SHARED_VARIABLE_FIRST_FILE_DESCRIPTOR * 4)), d3 ; Check if the file handle is the first one
                        blt .exec_old_handler                ; If less than, exec_old_handler the code. Otherwise continue with the code
                        endm

; Wait for second (aprox 50 VBlanks)
wait_sec                macro
                        move.l d7, -(sp)                    ; Save the number counter reg
                        move.w #50, d7                      ; Loop to wait a second (aprox 50 VBlanks)
.\@wait_sec_loop:
                        move.w 	#37,-(sp)                   ; Wait for the VBlank. Add a delay
                        trap 	#14
                        addq.l 	#2,sp
                        dbf d7, .\@wait_sec_loop
                        move.l (sp)+, d7                    ; Restore the number counter reg
                        endm

    include inc/tos.s
    include inc/debug.s

    ifne _RELEASE
        org $FA0040
    endif
rom_function:
    print gemdrive_emulator_msg

; Setup the RTC
    tst.l GEMDRVEMUL_NETWORK_ENABLED
    beq.s .network_conf_bypass
    bsr setup_rtc

.network_conf_bypass:
    tst.l (GEMDRVEMUL_SHARED_VARIABLES + (SHARED_VARIABLE_BUFFER_TYPE * 4))
    bne.s .show_stack_buffer_msg

    print dskbuf_buffer_msg
    bra.s .get_tos_version
.show_stack_buffer_msg:
    print stack_buffer_msg

.get_tos_version:
    print ok_msg

    bsr get_tos_version

    bsr print_tos_version
    
; Wait for the folder in the sd card of the Sidecart to be mounted
    print query_ping_msg
    bsr test_ping
    tst.w d0
    bne _exit_timemout

; Ping was successful
_ping_ready:
    print ok_msg
    print ready_gemdrive_msg

; Clean GEM reentry lock on start
; This is necessary in case there was a crash during a reentry call
    bsr clean_gem_reentry_lock
    print ok_msg

; Show the disk drive to emulate
    print emulated_drive_msg
    move.b (GEMDRVEMUL_SHARED_VARIABLES + 3 + (SHARED_VARIABLE_DRIVE_LETTER * 4)), d0 
    pchar_reg
    pchar ':'
    pchar '\'
    pchar ' '
    pchar ' '
    pchar ' '
    print ok_msg

; Set the virtual hard disk
    bsr create_virtual_hard_disk

; Save the old GEMDRVEMUL_OLD_GEM_VEC and set our own vector
    print set_vectors_msg
    bsr save_vectors
    tst.w d0
    bne _exit_timemout
    print ok_msg
    rts

_exit_timemout:
    asksil error_sidecart_comm_msg
    rts

; Obtain the version of the TOS
get_tos_version:
    gemdos Sversion, 2
    and.l #$FFFF,d0
    cmp.w #$FC, $4.w              ; Check if the TOS version is a 192Kb or 256Kb
    bne.s .get_tos_version_is_256k
.get_tos_version_is_192k:
    move.w $FC0002, d1          ; Read the TOS version from the ROM
    bra.s .exit_get_tos_version
.get_tos_version_is_256k:
    move.w $E00002, d1          ; Read the TOS version from the ROM

.exit_get_tos_version:
    and.l #$FFFF,d1             ; Mask the upper word
    swap d1
    or.l d1, d0                 ; Set the TOS version in the upper word of d0
    move.l #SHARED_VARIABLE_SVERSION, d3     ; Variable index
    move.l d0, d4                           ; Variable value
    send_sync CMD_SET_SHARED_VAR, 8
    rts

; Print the obtained TOS version
print_tos_version:
    print set_version_msg   ; Print the TOS version message

    move.l (GEMDRVEMUL_SHARED_VARIABLES + (SHARED_VARIABLE_SVERSION * 4)), d0   ; Get the TOS version from the shared variables
    swap d0
    and.l #$FFFF,d0
    move.w d0, d1
    lsr.w #8, d1    ; Major version

    move.w d0, d2
    and.w #$FF, d2  ; Minor version

    add.w #48, d1
    move.w d1, d0
    pchar_reg

    pchar '.'

;    move.w d2, d0
;    print_num
    move.w d2, d0
    swap d0
    lsl.l #8, d0
    moveq #1, d1    ; Number of digits to print minus 1 
    print_hex

    pchar '.'
    pchar '.'
    pchar '.'

    print ok_msg
    rts

; Wait for the RPP2040 to have a mounted folder in the SD card
test_ping:
    move.l GEMDRVEMUL_TIMEOUT_SEC, d7           ; Wait for a while until ping responds
_retest_ping:
    move.w d7, -(sp)                 

    send_sync CMD_PING, 0                ; Send the command to the Sidecart. 0 bytes of payload

    move.w (sp)+, d7
    tst.w d0                            ; 0 if no error
    bne.s _test_ping_timeout            ; The RP2040 is not responding, timeout now

    cmp.w #$FFFF, GEMDRVEMUL_PING_STATUS
    bne.s _ping_not_yet                ; The NTP has a valid date, exit
_exit_test_ping:
    moveq #0, d0
    rts


_ping_not_yet:

    move.w d7,d0                        ; Pass the number of seconds to print
    print_num                           ; Print the decimal number

    print backwards_msg

    move.w #50, d6                      ; Loop to wait a second (aprox 50 VBlanks)
_ping_not_yet_loop:
    move.w 	#37,-(sp)                   ; Wait for the VBlank. Add a delay
    trap 	#14
    addq.l 	#2,sp
    dbf d6, _ping_not_yet_loop

    dbf d7, _retest_ping                 ; The ping command does not have a valid path, wait a bit more

_test_ping_timeout:
    moveq #-1, d0
    rts

; Configure the SidecarT to get the NTP time
setup_rtc:
    tst.l GEMDRVEMUL_RTC_STATUS     ; Test if the RTC is already started
    beq.s _setup_rtc_start          ; If the RTC is not started, continue with the code
    print rtc_already_started_msg
    bra _set_datetime

; Start the RTC because it was not initalized yet
_setup_rtc_start:
    print query_network_msg
     
; Loop to wait for the Network to be ready
    move.l GEMDRVEMUL_TIMEOUT_SEC, d7   ; Wait for a while until ping responds
_wait_for_network_stack:
    move.w d7,d0                    ; Pass the number of seconds to print
    print_num                       ; Print the decimal number
    print backwards_msg
    wait_sec
    tst.l GEMDRVEMUL_NETWORK_STATUS ; Test if the network stack is ready
    bne.s _wait_for_rtc             ; The network is ok. Wait for the RTC to be ready now
    dbf d7, _wait_for_network_stack ; The network is not ready yet, wait a bit more
    bra _test_rtc_timeout         ; The network stack is not ready yet, timeout now

; Network is ready, but the RTC is not ready yet
_wait_for_rtc:
    print ok_msg
    print query_ntp_msg

    move.l GEMDRVEMUL_TIMEOUT_SEC, d7       ; Wait for a while until the RTC is ready
_wait_for_rtc_loop:
    move.w d7,d0                    ; Pass the number of seconds to print
    print_num                       ; Print the decimal number
    print backwards_msg
    wait_sec
    tst.l GEMDRVEMUL_RTC_STATUS     ; Test if the RTC is ready
    bne.s _rtc_ready                ; The RTC is ready to start now
    dbf d7, _wait_for_rtc_loop      ; The RTC is not ready yet, wait a bit more
    bra.s _test_rtc_timeout         ; The RTC is not ready yet, timeout now
_rtc_ready:
    print ok_msg

; Get the date and time from the RP2040 and set the IKBD information
_set_datetime:
    ; The date and time comes in the buffer
    pea GEMDRVEMUL_RTC_STATUS           ; Buffer should have a valid IKBD date and time format
    move.w #6, -(sp)                    ; Six bytes plus the header = 7 bytes
    move.w #25, -(sp)                   ; 
    trap #14
    addq.l #8, sp

    moveq #0, d0

	move.w #23,-(sp)                    ; gettime from XBIOS
	trap #14
	addq.l #2,sp

    add.l #$3c000000,d0                 ; Fix the Y2K problem

	move.l d0,d7

	move.w d7,-(sp)
	move.w #$2d,-(sp)                   ; settime with GEMDOS
	trap #1
	addq.l #4,sp

	swap d7

	move.w d7,-(sp)
	move.w #$2b,-(sp)                   ; settime with GEMDOS  
	trap #1
	addq.l #4,sp

    ; And we are done!
    moveq #0, d0
    rts

    moveq #0, d0
    rts
_test_rtc_timeout:
    print timeout_msg
    moveq #-1, d0
    rts
;
; Clean the gem reentry lock flag on start
;
clean_gem_reentry_lock:
    move.w #CMD_REENTRY_UNLOCK,d0          ; Command code to unlock the reentry
    moveq.w #0,d1                        ; Payload size is 0 bytes
    bra send_sync_command_to_sidecart

create_virtual_hard_disk:
    move.w (GEMDRVEMUL_SHARED_VARIABLES + 2 + (SHARED_VARIABLE_DRIVE_NUMBER * 4)), d0    ; Get the drive number
    moveq.l #1, d1
    lsl.l d0, d1                        ; Calculate the bit number of the drive
    move.l _drvbits.w, d0
    add.l d1, d0    ; Set the drive bit
    move.l d0, _drvbits.w
    move.w (GEMDRVEMUL_SHARED_VARIABLES + 2 + (SHARED_VARIABLE_DRIVE_NUMBER * 4)), -(sp)        ; Emulated drive in the parameter of Dsetdrv()
    gemdos Dsetdrv, 4                    ; Call Dsetdrv() and set the emulated drive
    rts

save_vectors:
    move.l #gemdrive_trap,-(sp)
    move.w #VEC_GEMDOS,-(sp)
    move.w #5,-(sp)                     ; Setexc() modify GEMDOS vector and add our trap
    trap #13
    addq.l #8,sp

    move.l d0, d3                       ; Address of the old GEMDOS vector
    move.l #old_handler, d4             ; Address of the old handler
    send_sync CMD_SAVE_VECTORS, 8       ; Send the command to the Sidecart. 8 bytes of payload
    tst.w d0                            ; 0 if no error
    bne.s _read_timeout                 ; The RP2040 is not responding, timeout now
    rts

_read_timeout:
    moveq #-1, d0
    rts


    dc.l 'XBRA'                             ; XBRA structure
    dc.l 'SDGD'                             ; Put your cookie here
old_handler:
    dc.l 0                                  ; We can't modify this address because it's in ROM, but we can modify it in the RP2040 memory

    even

gemdrive_trap:
; 
; Shortcut in case of reentry
;
    btst #0, GEMDRVEMUL_REENTRY_TRAP    ; Check if the reentry is locked
    beq.s .exec_trapped_handler           ; If the bit is active, we are in a reentry call. We need to exec_old_handler the code
    move.l old_handler,-(sp)            ; Fake a return
    rts                                 ; to old code.

;
; No reentry, we can exec the trapped handler
; But first, check user or supervisor mode and the CPU type
;
.exec_trapped_handler:
    btst #5, (sp)                         ; Check if called from user mode
    beq.s _user_mode                      ; if so, do correct stack pointer
_not_user_mode:
    move.l sp,a0                          ; Move stack pointer to a0
    bra.s _check_cpu
_user_mode:
    move.l usp,a0                          ; if user mode, correct stack pointer
    subq.l #6,a0
;
; This code checks if the CPU is a 68000 or not
;
_check_cpu:
    tst.w _longframe                          ; Check if the CPU is a 68000 or not
    beq.s _notlong
_long:
    addq.w #2, a0                             ; Correct the stack pointer parameters for long frames 
_notlong:

;
; Trap #1 handler goes here
;
    movem.l d2-d7/a2-a6,-(sp)
    move.w 6(a0),d3                      ; get GEMDOS opcode number
;    cmp.w #$0e, d3                       ; Check if it's a Dsetdrv() call
;    beq.s .Dsetdrv
;    cmp.w #$19, d3                       ; Check if it's a Dgetdrv() call
;    beq.s .Dgetdrv
    cmp.w #$1a, d3                       ; Check if it's a Fsetdta() call
    beq .Fsetdta
    cmp.w #Dfree, d3                     ; Check if it's a Dfree() call
    beq .Dfree
    cmp.w #$39, d3                       ; Check if it's a Dcreate() call
    beq .Dcreate
    cmp.w #$3a, d3                       ; Check if it's a Ddelete() call
    beq .Ddelete
    cmp.w #$3b, d3                       ; Check if it's a Dsetpath() call
    beq .Dsetpath
    cmp.w #$3c, d3                       ; Check if it's a Fcreate() call
    beq .Fcreate
    cmp.w #$47, d3                       ; Check if it's a Dgetpath() call
    beq .Dgetpath
    cmp.w #$3d, d3                       ; Check if it's a Fopen() call
    beq .Fopen
    cmp.w #$3e, d3                       ; Check if it's a Fclose() call
    beq .Fclose
    cmp.w #Frename, d3                   ; Check if it's a Frename() call
    beq .Frename
    cmp.w #Fdatime, d3                 ; Check if it's a Fdatetime() call
    beq .Fdatime
    cmp.w #$3f, d3                       ; Check if it's a Fread() call
    beq .Fread
    cmp.w #$40, d3                       ; Check if it's a Fwrite() call
    beq .Fwrite
    cmp.w #Fattrib, d3                   ; Check if it's a Fattrib() call
    beq .Fattrib
    cmp.w #$4e, d3                       ; Check if it's a Fsfirst() call
    beq .Fsfirst
    cmp.w #$4f, d3                       ; Check if it's a Fsnext() call
    beq .Fsnext
    cmp.w #Pexec, d3                     ; Check if it's a Pexec() call
    beq .Pexec
    cmp.w #$41, d3                       ; Check if it's a Fdelete() call
    beq .Fdelete
    cmp.w #Fseek, d3                     ; Check if it's a Fseek() call
    beq .Fseek

.show_vector_calls:
    ; Trace the not implemented GEMDOS call
;    send_sync CMD_SHOW_VECTOR_CALL, 2    ; Send the command to the Sidecart. 2 bytes of payload

.exec_old_handler:
    movem.l (sp)+,d2-d7/a2-a6
    move.l old_handler,-(sp)            ; Fake a return
    rts                                 ; to old code.

; Start of the GEMDOS calls
.Fsetdta:
    move.l 8(a0),d3                      ; get address of DTA and save in the payload
    send_sync CMD_FSETDTA_CALL, 4        ; Send the command to the Sidecart. 4 bytes of payload
    bra .exec_old_handler

; Get the storage space available on the disk
.Dfree:
    move.w 8(a0),d3                      ; get the drive number
    subq.w #1, d3                        ; Remove 1 to the drive number. I don't want to use the default drive
    cmp.w (GEMDRVEMUL_SHARED_VARIABLES + 2 + (SHARED_VARIABLE_DRIVE_NUMBER * 4)), d3            ; Check if the drive is the emulated one
    bne .exec_old_handler                ; If not, exec_old_handler the code
    move.l 10(a0),a4                     ; get the address of the structure to store the information
    send_sync CMD_DFREE_CALL, 2          ; Send the command to the Sidecart. 2 bytes of payload

    move.l GEMDRVEMUL_DFREE_STATUS, d0   ; Copy here the result status of the Dfree call
    tst.l d0                             ; Check if the call was successful
    bne.s .Dfree_exit                    ; If not, exit with the error code
    ; Copy here to the DISKINFO structure pointed by a4
    move.l GEMDRVEMUL_DFREE_STRUCT, a5   ; Address of the structure where the result is stored
    move.l (a5)+, (a4)+                  ; Copy the total number of free clusters
    move.l (a5)+, (a4)+                  ; Copy the number of clusters per drive
    move.l (a5)+, (a4)+                  ; Copy the number of bytes per sector
    move.l (a5)+, (a4)+                  ; Copy the number of sectors per cluster
    ; We are done, exit with the success code
.Dfree_exit:
    movem.l (sp)+,d2-d7/a2-a6            ; Restore registers
    rte

.Dcreate:
    move.l 8(a0),a4                      ; get the fpath address

    detect_emulated_drive_letter         ; If not, exec_old_handler the code. Otherwise continue with the code

    send_write_sync CMD_DCREATE_CALL, 256 ; Send the command to the Sidecart. 256 bytes of buffer to send

    return_interrupt_w GEMDRVEMUL_DCREATE_STATUS    ; Return the error code from the Sidecart

.Ddelete:
    move.l 8(a0),a4                      ; get the fpath address

    detect_emulated_drive_letter         ; If not, exec_old_handler the code. Otherwise continue with the code

    send_write_sync CMD_DDELETE_CALL, 256 ; Send the command to the Sidecart. 256 bytes of buffer to send

    return_interrupt_w GEMDRVEMUL_DDELETE_STATUS    ; Return the error code from the Sidecart


.Dsetpath:
    move.l 8(a0),a4                      ; Address to the new GEMDOS path

    detect_emulated_drive 0              ; Check if the drive is the emulated one. If not, exec_old_handler the code. 
                                         ; Otherwise continue with the code

    ; This is the emulated drive, it's our moment!
    send_write_sync CMD_DSETPATH_CALL, 256    

    return_interrupt_w GEMDRVEMUL_SET_DPATH_STATUS ; Return the error code from the Sidecart

.Dgetpath:
    move.l 8(a0),a4                      ; Address to the  new GEMDOS path
    move.w 12(a0),d3                     ; get the drive number
    subq.w #1, d3                        ; Remove 1 to the drive number. I don't want to use the default drive
    cmp.w (GEMDRVEMUL_SHARED_VARIABLES + 2 + (SHARED_VARIABLE_DRIVE_NUMBER * 4)), d3            ; Check if the drive is the emulated one
    bne .exec_old_handler                ; If not, exec_old_handler the code        

    ; This is the emulated drive, it's our moment!
    send_write_sync CMD_DGETPATH_CALL, 256    

    move.w #0, d0                        ; Error code. -33 is the error code for the file not found
    ext.l d0                             ; Extend the sign of the value
    movem.l (sp)+,d2-d7/a2-a6            ; Restore registers
    rte

.Fopen:
    move.l 8(a0),a4                      ; get the fpname address
    move.w 12(a0),d3                     ; get mode attribute

    detect_emulated_drive_letter         ; If not, exec_old_handler the code. Otherwise continue with the code

    ; This is an emulated drive, it's our moment!
    send_write_sync CMD_FOPEN_CALL, 256

    return_interrupt_w GEMDRVEMUL_FOPEN_HANDLE    ; Return the error code from the Sidecart

.Fclose:
    move.w 8(a0),d3                      ; get the file handle

    detect_emulated_file_handler         ; If not emulated, exec_old_handler the code. Otherwise continue with the code

    send_sync CMD_FCLOSE_CALL, 2         ; Send the command to the Sidecart.

    return_interrupt_w GEMDRVEMUL_FCLOSE_STATUS    ; Return the error code from the Sidecart

.Fcreate:
    move.l 8(a0),a4                      ; get the fpname address
    move.w 12(a0),d3                     ; get mode attribute

    detect_emulated_drive_letter         ; If not, exec_old_handler the code. Otherwise continue with the code

    ; This is an emulated drive, it's our moment!
    send_write_sync CMD_FCREATE_CALL, 256

    return_interrupt_l GEMDRVEMUL_FCREATE_HANDLE    ; Return the error code from the Sidecart

.Fdelete:
    move.l 8(a0),a4                      ; get the fpname address

    detect_emulated_drive_letter         ; If not, exec_old_handler the code. Otherwise continue with the code

    ; This is an emulated drive, it's our moment!
    send_write_sync CMD_FDELETE_CALL, 256

    return_interrupt_l GEMDRVEMUL_FDELETE_STATUS    ; Return the error code from the Sidecart

.Frename:
    move.l 10(a0),a5                     ; get the fpname address
    move.l 14(a0),a6                    ; get the new fpname address

    detect_emulated_drive_letter         ; If not, exec_old_handler the code. Otherwise continue with the code

    lea -256(sp), sp
    move.l sp, a4

    move.w #127, d3
.frename_copy_src:
    move.b (a5)+, (a4)+
    dbf d3, .frename_copy_src

    move.w #127, d3
.frename_copy_dst:
    move.b (a6)+, (a4)+
    dbf d3, .frename_copy_dst

    move.l sp, a4
    ; This is an emulated drive, it's our moment!
    send_write_sync CMD_FRENAME_CALL, 256
    lea 256(sp), sp

    return_interrupt_l GEMDRVEMUL_FRENAME_STATUS    ; Return the error code from the Sidecart

.Fseek:
    move.l 8(a0),d4                      ; get the offset
    move.w 12(a0),d3                     ; get the handle
    move.w 14(a0),d5                     ; get the mode

    detect_emulated_file_handler         ; If not emulated, exec_old_handler the code. Otherwise continue with the code

    send_sync CMD_FSEEK_CALL, 12         ; Send the command to the Sidecart. 12 bytes of payload

    return_interrupt_l GEMDRVEMUL_FSEEK_STATUS    ; Return the error code from the Sidecart or the absolute position

.Fattrib:
    move.l 8(a0),a4                      ; get the fpname address
    move.w 12(a0),d3                     ; get the mode attribute
    move.w 14(a0),d4                     ; get the attribute

    detect_emulated_drive_letter         ; If not, exec_old_handler the code. Otherwise continue with the code

    ; This is an emulated drive, it's our moment!
    send_write_sync CMD_FATTRIB_CALL, 128

    return_interrupt_l GEMDRVEMUL_FATTRIB_STATUS    ; Return the error code from the Sidecart

.Fdatime:
    move.l 8(a0),a4                      ; get the datetime struct address
    move.w 12(a0),d4                     ; get the handle
    move.w 14(a0),d3                     ; get the flag

    detect_emulated_drive_letter         ; If not, exec_old_handler the code. Otherwise continue with the code

    move.l a4, -(sp)
    ; This is an emulated drive, it's our moment!
    send_write_sync CMD_FDATETIME_CALL, 128
    move.l (sp)+, a4
    
    lea GEMDRVEMUL_FDATETIME_TIME, a6
    move.b 1(a6), 0(a4)
    move.b 2(a6), 1(a4)
    move.b 3(a6), 2(a4)
    lea GEMDRVEMUL_FDATETIME_DATE, a6
    move.b 1(a6), 3(a4)
    move.b 2(a6), 4(a4)
    move.b 3(a6), 5(a4) 

    return_interrupt_l GEMDRVEMUL_FDATETIME_STATUS    ; Return the error code from the Sidecart



.Fread:
    move.w 8(a0),d3                      ; get the file handle
    move.l 10(a0),d4                     ; get number of bytes to read
    move.l 14(a0),a4                     ; get address of buffer to read into

    detect_emulated_file_handler         ; If not emulated, exec_old_handler the code. Otherwise continue with the code

    bsr.s .Fread_core                    ; Read the data from the Sidecart

;    movem.l d0-d7/a0-a6, -(sp)
;    move.l d0, d3
;    send_sync CMD_DEBUG, 4
;    movem.l (sp)+,d0-d7/a0-a6

    movem.l (sp)+,d2-d7/a2-a6            ; Restore registers
    rte

.Fread_core:
    move.l d4, d5                        ; Save the number of bytes to read in d5
    clr.l  d6                            ; d6 is the bytes read counter
.fread_loop:
;    ifeq USE_DSKBUF
;        move.l _dskbufp, a5               ; Address of the buffer to read the data from the Sidecart
;        movem.l d3-d7, DSKBUFP_TMP_ADDR(a5) ; Save the registers
;    else    
;        movem.l d3-d7, -(sp)                 ; Save the registers
;    endif
;
;    send_sync CMD_READ_BUFF_CALL, 12     ; Send the command to the Sidecart. handle.w, padding.w, bytes_to_read.l, pending_bytes_to_read.l
;
;    ifeq USE_DSKBUF
;        move.l _dskbufp, a5               ; Address of the buffer to read the data from the Sidecart
;        movem.l DSKBUFP_TMP_ADDR(a5), d3-d7 ; Restore the registers
;    else
;        movem.l (sp)+,d3-d7                 ; Restore the registers
;    endif

    tst.l (GEMDRVEMUL_SHARED_VARIABLES + (SHARED_VARIABLE_BUFFER_TYPE * 4))
    bne.s .fread_loop_use_stack_buffer
    move.l _dskbufp, a5               ; Address of the buffer to read the data from the Sidecart
    movem.l d3-d7, DSKBUFP_TMP_ADDR(a5) ; Save the registers
    send_sync CMD_READ_BUFF_CALL, 12     ; Send the command to the Sidecart. handle.w, padding.w, bytes_to_read.l, pending_bytes_to_read.l
    move.l _dskbufp, a5               ; Address of the buffer to read the data from the Sidecart
    movem.l DSKBUFP_TMP_ADDR(a5), d3-d7 ; Restore the registers
    bra.s .fread_loop_continue
.fread_loop_use_stack_buffer:
    movem.l d3-d7, -(sp)                 ; Save the registers
    send_sync CMD_READ_BUFF_CALL, 12     ; Send the command to the Sidecart. handle.w, padding.w, bytes_to_read.l, pending_bytes_to_read.l
    movem.l (sp)+,d3-d7                 ; Restore the registers

.fread_loop_continue
    tst.w d0                             ; Check if there is an error
    beq.s .fread_command_ok              ; If not, we can continue
    moveq.l #GEMDOS_EINTRN, d0           ; Error code. GEMDOS_EINTRN is the error code for the internal error
    bra.s .fread_exit                    ; Exit the loop

.fread_command_ok:
    move.l GEMDRVEMUL_READ_BYTES, d0     ; The number of bytes actually read from the Sidecart or the error code
    ext.l d0                             ; Extend the sign of the value
    ; If d0 is negative, there is an error
    bmi.s .fread_exit                    ; Exit the loop
    tst.l d0                             ; Check if the number of bytes read is 0
    beq.s .fread_exit_ok                 ; If 0, we are done

    lea GEMDRVEMUL_READ_BUFFER, a5       ; Address of the buffer to copy the data from the Sidecart
    move.l a4, d7                        ; Test if the dest address is odd or even
    btst #0, d7                          ; Check if the address is odd
    beq.s .fread_loop_copy_even    ; If even go to copy longword 
.fread_copy_odd:
    move.l d0, d7                        ; Number of bytes to copy to the buffer
    subq.l #1, d7                        ; We need to copy one byte less because dbf counts 0
.fread_loop_copy:
    move.b (a5)+, (a4)+                  ; Copy the byte
    dbf d7, .fread_loop_copy             ; Loop until we copy all the bytes
    bra.s .fread_copy_exit               ; No copy anymore

.fread_loop_copy_even:
    move.l d0, d7                        ; Number of bytes to copy to the buffer
    lsr.l #1, d7                         ; Divide the number of bytes by 2
;    btst #1, d0                          ; Check if can copy longwords
;    beq.s .fread_loop_copy_lword_even    ; If so, copy longwords
    subq.l #1, d7                        ; We need to copy one byte less because dbf counts 0
.fread_loop_copy_word:
    move.w (a5)+, (a4)+                  ; Copy word
    dbf d7, .fread_loop_copy_word        ; Loop until we copy all the bytes
    btst #0, d0                          ; Check if the number of bytes to copy is odd
    beq.s .fread_copy_exit               ; If not, we are done
    move.b (a5)+, (a4)+                  ; Copy the last byte
;    bra.s .fread_copy_exit               ; No copy anymore
;
;.fread_loop_copy_lword_even:
;    move.l d0, d7                        ; Number of bytes to copy to the buffer
;    lsr.l #2, d7                         ; Divide the number of words by 2
;    tst.l d7                             ; Check if we have to copy the last bytes
;    beq.s .fread_loop_copy_tail_bytes    ; if zero, only copy the last bytes
;    subq.l #1, d7                        ; We need to copy one byte less because dbf counts 0
;.fread_loop_copy_lword:
;    move.l (a5)+, (a4)+                  ; Copy longword
;    dbf d7, .fread_loop_copy_lword       ; Loop until we copy all the bytes
;
;    move.l d0, d7                        ; Number of bytes to copy to the buffer
;    and.l #%11, d7                       ; Check if we have to copy the last bytes        
;    beq.s .fread_copy_exit               ; If not, we are done
;    subq.l #1, d7                        ; We need to copy one byte less because dbf counts 0
;.fread_loop_copy_tail_bytes:
;    move.b (a5)+, (a4)+                  ; Copy the last byte
;    dbf d7, .fread_loop_copy_tail_bytes  ; No copy anymore


.fread_copy_exit:
    add.l d0, d6                         ; Add the number of bytes read to the counter
    cmp.l #BUFFER_READ_SIZE, d0          ; Check if the number of bytes read is not equal than the buffer size
    bne.s .fread_exit_ok                 ; if not equal, it's smaller than the buffer size. We are done

    sub.l d0, d5                         ; Subtract the number of bytes read from the total number of bytes to read
    bpl .fread_loop                    ; If there are more bytes to read, continue

.fread_exit_ok:
    move.l d6, d0                        ; Return the number of bytes read

.fread_exit:
    rts


.Fwrite:
    move.w 8(a0),d3                      ; get the file handle
    move.l 10(a0),d4                     ; get number of bytes to write
    move.l 14(a0),a4                     ; get address of buffer to the data to write

    detect_emulated_file_handler         ; If not emulated, exec_old_handler the code. Otherwise continue with the code

    bsr.s .Fwrite_core                    ; Read the data from the Sidecart

;    ext.l d0

    movem.l (sp)+,d2-d7/a2-a6            ; Restore registers
    rte

.Fwrite_core:
    move.l d4, d5                        ; Save the number of bytes to write in d5
    clr.l  d6                            ; d6 is the bytes write counter
.fwrite_loop:
    move.w #FWRITE_RETRIES, d7           ; Number of retries to write the data to the Sidecart    
.fwrite_loop_retry:
    tst.w d7                             ; Check if the number of retries is 0
    bne.s .fwrite_loop_retry_start       ; If not 0, simply retry to send the data
    moveq.l #GEMDOS_EINTRN, d0           ; Error code. GEMDOS_EINTRN is the error code for the internal error
    bra .fwrite_exit                   ; Exit the loop
.fwrite_loop_retry_start:                ; Start the loop to retry to send the data
;    ifeq USE_DSKBUF
;        move.l _dskbufp, a5                 ; Address of the buffer to save the registers
;        movem.l d3-d7/a4, DSKBUFP_TMP_ADDR(a5) ; Save the registers
;    else    
;        movem.l d3-d7/a4, -(sp)                ; Save the registers
;    endif
;
;    ; Send the command to the Sidecart. handle.w, padding.w, bytes_to_write.l, pending_bytes_to_write.l and bytes to send
;    send_write_sync CMD_WRITE_BUFF_CALL, BUFFER_WRITE_SIZE
;
;    ifeq USE_DSKBUF
;        move.l _dskbufp, a5               ; Address of the buffer to save the registers
;        movem.l DSKBUFP_TMP_ADDR(a5), d3-d7/a4 ; Restore the registers
;    else
;        movem.l (sp)+,d3-d7/a4                 ; Restore the registers
;    endif

    tst.l (GEMDRVEMUL_SHARED_VARIABLES + (SHARED_VARIABLE_BUFFER_TYPE * 4))
    bne.s .fwrite_loop_use_stack_buffer
    move.l _dskbufp, a5                    ; Address of the buffer to read the data from the Sidecart
    movem.l d3-d7/a4, DSKBUFP_TMP_ADDR(a5) ; Save the registers
    send_write_sync CMD_WRITE_BUFF_CALL, BUFFER_WRITE_SIZE       ; Send the command to the Sidecart. handle.w, padding.w, bytes_to_read.l, pending_bytes_to_read.l
    move.l _dskbufp, a5                    ; Address of the buffer to read the data from the Sidecart
    movem.l DSKBUFP_TMP_ADDR(a5), d3-d7/a4 ; Restore the registers
    bra.s .fwrite_loop_continue
.fwrite_loop_use_stack_buffer:
    movem.l d3-d7/a4, -(sp)                ; Save the registers
    send_write_sync CMD_WRITE_BUFF_CALL, BUFFER_WRITE_SIZE       ; Send the command to the Sidecart. handle.w, padding.w, bytes_to_read.l, pending_bytes_to_read.l
    movem.l (sp)+,d3-d7/a4                 ; Restore the registers

.fwrite_loop_continue
    tst.w d0                             ; Check if there is an error
    beq.s .fwrite_command_ok             ; If not, we can continue
    moveq.l #GEMDOS_EINTRN, d0           ; Error code. GEMDOS_EINTRN is the error code for the internal error
    bra .fwrite_exit                     ; Exit the loop

; Calculate the CHK value of the buffer to write
.fwrite_command_ok:
    subq.w #1, d7                        ; Subtract 1 to the number of retries
    move.l GEMDRVEMUL_WRITE_BYTES, d2    ; The number of bytes to check the CHK
    subq.l #1, d2                        ; Subtract 1 to the number of bytes to check the CHK, as usual
    clr.l d0                             ; Clear the CHK value
    clr.l d1                             ; Clear the sum buffer of the CHK
.fwrite_check_crc:
    move.b (a4)+, d1                     ; Add the value to to the CHK sum
    add.l d1, d0                         ; Add the value to the CHK sum
    dbf d2, .fwrite_check_crc            ; Loop until we check all the bytes

;    movem.l d0-d3, -(sp)                ; Save the CHK value
;    move.l d0, d3
;    send_sync CMD_DEBUG, 4              ; Send the command to the Sidecart. 4 bytes of payload
;    movem.l (sp)+, d0-d3                ; Restore the CHK value

    cmp.l GEMDRVEMUL_WRITE_CHK, d0       ; Check if the CHK value is the same
    bne.s .fwrite_loop_retry             ; If not, retry to send the data until the number of retries is 0

;    ifeq USE_DSKBUF
;        move.l _dskbufp, a5                 ; Address of the buffer to save the registers
;        movem.l d3-d7/a4, DSKBUFP_TMP_ADDR(a5) ; Save the registers
;    else    
;        movem.l d3-d7/a4, -(sp)                ; Save the registers
;    endif
;
;    ; Send the command to the Sidecart. Bytes to move forward the offset in d4.l. handle.w in d3.w
;    move.l GEMDRVEMUL_WRITE_BYTES, d4    ; The number of bytes to move forward the offset
;    send_sync CMD_WRITE_BUFF_CHECK, 8
;
;    ifeq USE_DSKBUF
;        move.l _dskbufp, a5               ; Address of the buffer to save the registers
;        movem.l DSKBUFP_TMP_ADDR(a5), d3-d7/a4 ; Restore the registers
;    else
;        movem.l (sp)+,d3-d7/a4                 ; Restore the registers
;    endif

    tst.l (GEMDRVEMUL_SHARED_VARIABLES + (SHARED_VARIABLE_BUFFER_TYPE * 4))
    bne.s .fwrite_check_use_stack_buffer
    move.l _dskbufp, a5                    ; Address of the buffer to read the data from the Sidecart
    movem.l d3-d7/a4, DSKBUFP_TMP_ADDR(a5) ; Save the registers
    ; Send the command to the Sidecart. Bytes to move forward the offset in d4.l. handle.w in d3.w
    move.l GEMDRVEMUL_WRITE_BYTES, d4    ; The number of bytes to move forward the offset
    send_sync CMD_WRITE_BUFF_CHECK, 8
    move.l _dskbufp, a5                    ; Address of the buffer to read the data from the Sidecart
    movem.l DSKBUFP_TMP_ADDR(a5), d3-d7/a4 ; Restore the registers
    bra.s .fwrite_check_continue
.fwrite_check_use_stack_buffer:
    movem.l d3-d7/a4, -(sp)                ; Save the registers
    ; Send the command to the Sidecart. Bytes to move forward the offset in d4.l. handle.w in d3.w
    move.l GEMDRVEMUL_WRITE_BYTES, d4    ; The number of bytes to move forward the offset
    send_sync CMD_WRITE_BUFF_CHECK, 8
    movem.l (sp)+,d3-d7/a4                 ; Restore the registers

.fwrite_check_continue
    move.l GEMDRVEMUL_WRITE_BYTES, d0    ; The number of bytes actually write to the Sidecart or the error code
    ext.l d0                             ; Extend the sign of the value
    ; If d0 is negative, there is an error
    bmi.s .fwrite_exit                   ; Exit the loop
    tst.l d0                             ; Check if the number of bytes written is 0
    beq.s .fwrite_exit_ok                ; If 0, we are done
    add.l d0, d6                         ; Add the number of bytes written to the counter
    cmp.w #BUFFER_WRITE_SIZE, d0         ; Check if the number of bytes written is not equal than the buffer size
    bne.s .fwrite_exit_ok                ; if not equal, it's smaller than the buffer size. We are done

    sub.l d0, d5                         ; Subtract the number of bytes written from the total number of bytes to write
    bpl .fwrite_loop                     ; If there are more bytes to write, continue

.fwrite_exit_ok:
    move.l d6, d0                        ; Return the number of bytes written

.fwrite_exit:
    rts


.Fsfirst:
    move.l 8(a0), a4                     ; Get the address of the file specification string
    move.w 12(a0),d4                     ; get attribs

    cmp.b #':', 1(a4)                    ; Check if the second character of the file specification string is the colon
    bne .fs_first_emulated               ; If not, go to the emulated code
    move.b (a4), d0                      ; Get the first character of the file specification string
    cmp.b (GEMDRVEMUL_SHARED_VARIABLES + 3 + (SHARED_VARIABLE_DRIVE_LETTER * 4)), d0   ; Check if the first letter of the file specification string is the hard disk drive letter
    beq.s .fs_first_emulated             ; If so, execute specific fsfirst emulated code
; We need to clean the DTA to avoid issues with previous DTAs used in the emulated code
    reentry_gem_lock
    gemdos Fgetdta, 2                    ; Call Fgetdta() and get the address of the DTA
    move.l d0, -(sp)                     ; Save the return value with the address of the DTA
    reentry_gem_unlock
    move.l (sp)+, d3                     ; Restore the DTA value

;    move.l _sysbase, a6
;    move.l 40(a6), a6
;    move.l 0(a6), d3                     ; Pointer to the BASEPAGE structure of the process
;    add.l #BASEPAGE_OFFSET_DTA, d3       ; Address of the DTA in the BASEPAGE structure

    send_sync CMD_DTA_RELEASE_CALL, 4    ; Send the command to the Sidecart. 4 bytes of payload
    bra .exec_old_handler                ; Now it's safe to execute the old handler

.fs_first_emulated:
    reentry_gem_lock

    gemdos Fgetdta, 2                    ; Call Fgetdta() and get the address of the DTA
    move.l d0, -(sp)                     ; Save the return value with the address of the DTA

    reentry_gem_unlock

    move.l (sp), d3                            ; Restore the DTA value
    move.l a4, d5                              ; Save the address of the file specification string
    send_write_sync CMD_FSFIRST_CALL, 256      ; Send the command to the Sidecart. 256 bytes of buffer to send

.populate_fsdta_struct:
    move.l (sp)+, a4                            ; Restore the DTA value into a4

    ; Test if there is a file found
    move.w GEMDRVEMUL_DTA_F_FOUND, d0           ; Get the value of the file found
    ext.l d0                                    ; Extend the sign of the value
    ; A file found, restore the DTA from the Sidecart
    lea GEMDRVEMUL_DTA_TRANSFER, a5             ; Address of the buffer to receive the DTA
    move.w #47, d2                              ; Number of bytes to read
    move.l a4, d3                               ; Address of the DTA
.populate_fsdta_struct_loop:
    move.b (a5)+, (a4)+                         ; Copy the DTA
    dbf d2, .populate_fsdta_struct_loop         ; Loop until we copy all the bytes
    tst.w d0                                    ; If the value is 0, there is a file found (E_OK)
    bne.s .empty_fsdta_struct                   ; If not, exit with the error code
    movem.l (sp)+,d2-d7/a2-a6                   ; Restore registers
    rte
.empty_fsdta_struct:
;    move.l d0, -(sp)                            ; Save the return value of the operation with the DTA
;    send_sync CMD_DTA_RELEASE_CALL, 4           ; Send the command to the Sidecart. 4 bytes of payload
;    move.l (sp)+, d0                            ; Restore the return value with the address of the DTA
;    move.l #$ffffffd1, d0                       ; Error code. -47 is the error code for the no more files found
    movem.l (sp)+,d2-d7/a2-a6                   ; Restore registers
    rte


.Fsnext:
    reentry_gem_lock
    gemdos Fgetdta, 2                     ; Call Fgetdta() and get the address of the DTA
    move.l d0, -(sp)                      ; Save the return value with the address of the DTA
    reentry_gem_unlock

    move.l (sp), d3                       ; Check if the DTA exists in the rp2040 memory
    send_sync CMD_DTA_EXIST_CALL, 4       ; Send the command to the Sidecart. 4 bytes of payload
    move.l GEMDRVEMUL_DTA_EXIST, d0       ; Restore the DTA value
    tst.l d0                              ; Check if the DTA exists
    beq.s .Fsnext_bypass                  ; If not, exec_old_handler the code

    move.l d0, d3                         ; Restore the DTA value
    send_sync CMD_FSNEXT_CALL, 4          ; Send the command to the Sidecart.
    bra .populate_fsdta_struct

.Fsnext_bypass:
    ; Force the exec_old_handler
    move.l (sp)+, d0                      ; Restore the DTA value into a scratch register
    bra .exec_old_handler

.Pexec:
    move.l a0, d4                         ; Otherwise continue with the code
    move.w 8(a0), d3                      ; get the Pexec mode
    move.l 10(a0), a4                     ; get the address of the file name string
    move.l a4, d5
    move.l 14(a0), d6                     ; get the address of the command line string
    move.l 18(a0), d7                     ; get the address of the environment string

    detect_emulated_drive_letter          ; If not, exec_old_handler the code. Otherwise continue with the code

    send_sync CMD_PEXEC_CALL, 20          ; Send the command to the Sidecart. 16 bytes of buffer to send    

    cmp.w #PE_LOAD_GO, GEMDRVEMUL_PEXEC_MODE    ; Check if the mode is PE_LOAD_GO
    beq.s .pexec_load_go                        ; If yes, continue with the code
    cmp.w #PE_LOAD, GEMDRVEMUL_PEXEC_MODE       ; Check if the mode is PE_LOAD
    bne .exec_old_handler                       ; if not, exec_old_handler the code

.pexec_load_go:
    clr.w d3                              ; open mode read only 
    send_write_sync CMD_FOPEN_CALL, 256
    move.w GEMDRVEMUL_FOPEN_HANDLE, d0    ; Error code obtained from the Sidecart
    ext.l d0                              ; Extend the sign of the value
    ; If d0 is negative, there is an error
    bmi .pexec_exit                     ; If there is an error, exit

.pexec_load_header:

    move.w d0,d3                            ; get the file handle
    move.l #PRG_STRUCT_SIZE,d4           ; get number of bytes to read

;    ifeq USE_DSKBUF
;        move.l _dskbufp, a4                  ; Address of the buffer to read the data from the Sidecart
;        lea DSKBUFP_SWAP_ADDR(a4), a4        ; This is the swap area
;        bsr .Fread_core                      ; Read the data from the Sidecart
;        move.l _dskbufp, a4                  ; Address of the buffer to read the data from the Sidecart
;        lea DSKBUFP_SWAP_ADDR(a4), a4        ; This is the swap area
;    else    
;        sub.l #PRG_STRUCT_SIZE,sp            ; reserve space for the header of the file
;        move.l sp,a4                         ; get address of buffer to read into
;        move.l a4, -(sp)                     ; Save the address of the buffer to read
;        bsr .Fread_core                      ; Read the data from the Sidecart
;        move.l (sp)+, a4                     ; Restore the address of the buffer to read
;    endif

    tst.l (GEMDRVEMUL_SHARED_VARIABLES + (SHARED_VARIABLE_BUFFER_TYPE * 4))
    bne.s .pexec_load_header_use_stack_buffer
    move.l _dskbufp, a4                  ; Address of the buffer to read the data from the Sidecart
    lea DSKBUFP_SWAP_ADDR(a4), a4        ; This is the swap area
    bsr .Fread_core                      ; Read the data from the Sidecart
    move.l _dskbufp, a4                  ; Address of the buffer to read the data from the Sidecart
    lea DSKBUFP_SWAP_ADDR(a4), a4        ; This is the swap area    
    bra.s .pexec_load_header_continue
.pexec_load_header_use_stack_buffer:
    sub.l #PRG_STRUCT_SIZE,sp            ; reserve space for the header of the file
    move.l sp,a4                         ; get address of buffer to read into
    move.l a4, -(sp)                     ; Save the address of the buffer to read
    bsr .Fread_core                      ; Read the data from the Sidecart
    move.l (sp)+, a4                     ; Restore the address of the buffer to read

.pexec_load_header_continue:
    cmp.l #PRG_STRUCT_SIZE,d0            ; Check if the number of bytes read is not equal than the buffer size
    bne   .pexec_close_exit_fix_hdr_buf  ; if not equal, it's smaller than the buffer size. We are done
    cmp.w #PRG_MAGIC_NUMBER, 0(a4)       ; Check if the magic number is correct
    bne   .pexec_close_exit_fix_hdr_buf  ; if not equal, it's not a valid PRG file. We are done

; Send all the structure read from the header of the file
    send_write_sync CMD_SAVE_EXEC_HEADER, $1c   ; Send the command to the Sidecart

;    ifeq USE_DSKBUF
;        nop
;    else    
;        add.l #PRG_STRUCT_SIZE,sp            ; restore the stack pointer
;    endif

    tst.l (GEMDRVEMUL_SHARED_VARIABLES + (SHARED_VARIABLE_BUFFER_TYPE * 4))
    beq.s .pexec_load_header_not_restore_stack
    add.l #PRG_STRUCT_SIZE,sp            ; restore the stack pointer

.pexec_load_header_not_restore_stack:
; Save in the SidecarT the basepage of the current process for later use
; Get the values from _sysbase
;    move.l _sysbase, a4
;    move.l 40(a4), a4
;    move.l 0(a4), a4
;    send_write_sync CMD_SAVE_BASEPAGE, 256 ; Send the command to the Sidecart. 256 bytes of buffer to send

; Shrink the memory of the current process, if necessary
; Get the values from _sysbase
;    reentry_gem_lock
;    move.l _sysbase, a4
;    move.l 40(a4), a4
;    clr.l -(sp)                          ; NULL address of the environment string
;    move.l 0(a4), -(sp)                  ; Pointer to the BASEPAGE structure of the process
;    clr.w -(sp)                          ; NULL address of the command line string
;    gemdos Mshrink, 12                   ; Call Mshrink() and create the basepage    
;    reentry_gem_unlock    
;    ext.l d0                             ; Extend the sign of the value
    ; If d0 is negative, there is an error
;    bmi .pexec_exit                    ; If there is an error, exit

; Reserve memory for the process
;    reentry_gem_lock
;    lea GEMDRVEMUL_EXEC_HEADER, a5        ; Address of the buffer to receive the header
;    move.l 2(a5), -(sp)                   ; Get the text size.
;    gemdos Malloc, 6                      ; Call Mshrink() and create the basepage    
;    reentry_gem_unlock    
;    ext.l d0                             ; Extend the sign of the value
;    ; If d0 is negative, there is an error
;    bmi .pexec_exit                    ; If there is an error, exit

; Now we have to do a reentry call to the GEMDOS Pexec in mode PE_CREATE_BASEPAGE
; to create the basepage of the new process
    reentry_gem_lock
    move.l GEMDRVEMUL_PEXEC_STACK_ADDR, a0
    pea 18(a0)                            ; get the address of the environment string
    pea 14(a0)                            ; get the address of the command line string
    clr.l -(sp)                           ; unused
    move.w #PE_CREATE_BASEPAGE, -(sp)     ; create basepage mode
    gemdos Pexec, 16                      ; Call Pexec() and create the basepage
    move.l d0, a4
    reentry_gem_unlock

; We need to populate the basepage with the values from the header of the PRG file
    lea GEMDRVEMUL_EXEC_HEADER, a5        ; Address of the buffer to receive the header
    move.l 2(a5), d3                      ; Get the text size.
    move.l 6(a5), d4                      ; Get the data size.
    move.l 10(a5), d5                     ; Get the bss size.
    move.l 14(a5), d6                     ; Get the symbol size.

    move.l a4, d7                         ; Get the address of the basepage
    add.l #$100, d7                       ; Add 256 bytes to the basepage address to point to the start of the text segment

    move.l d7, 8(a4)                      ; Save the address of the start of the text segment
    move.l d3, 12(a4)                     ; Save the size of the text segment

    add.l d3, d7                          ; Add the text size to the basepage address to point to the start of the data segment
    move.l d7, 16(a4)                     ; Save the address of the start of the data segment
    move.l d4, 20(a4)                     ; Save the size of the data segment

    add.l d4, d7                          ; Add the data size to the basepage address to point to the start of the bss segment
    move.l d7, 24(a4)                     ; Save the address of the start of the bss segment
    move.l d5, 28(a4)                     ; Save the size of the bss segment

    send_write_sync CMD_SAVE_BASEPAGE, 256 ; Send the command to the Sidecart. 256 bytes of buffer to send

; Now we need to load the file in the area where the memory is
.pexec_read_rest_of_file:
    lea GEMDRVEMUL_EXEC_HEADER, a5        ; Address of the buffer to receive the header
    lea GEMDRVEMUL_EXEC_PD, a4            ; load the rest of the file
    move.l 8(a4), a4                     ; Start of the text segment
    move.l 2(a5), d4                     ; Get the TEXT size.
    add.l  6(a5), d4                     ; Add the DATA size.
    add.l 14(a5), d4                     ; Add the SYMBOL size.
    add.l #$FFFF, d4

    move.w GEMDRVEMUL_FOPEN_HANDLE, d3   ; Pass the file handle to close
    bsr .Fread_core                      ; Read the data from the Sidecart

; Close the file
.pexec_close_exit:
    move.w GEMDRVEMUL_FOPEN_HANDLE, d3   ; Pass the file handle to close
    send_sync CMD_FCLOSE_CALL, 2         ; Send the command to the Sidecart.
    move.w GEMDRVEMUL_FCLOSE_STATUS, d0  ; Error code obtained from the Sidecart
    ext.l d0                             ; Extend the sign of the value
    bmi .pexec_exit                      ; If there is an error, exit

; Relocating if needed
    lea GEMDRVEMUL_EXEC_PD, a5            
    move.l 8(a5), a5                      ; Start of the text segment
    move.l a5, d1                         ; Pass the address of the TEXT segment to the relocation code to d1
    move.l a5, a6                         ; Pass the address of the TEXT segment to the relocation code to a6

    lea GEMDRVEMUL_EXEC_HEADER, a4        ; Address of the buffer to receive the header
    add.l 2(a4), a5                       ; Add the TEXT segment size to the TEXT segment address
    add.l 6(a4), a5                       ; Add the DATA segment size to the TEXT segment address + TEXT segment size
    add.l 14(a4), a5                      ; Add the SYMBOL segment size to the TEXT segment address + TEXT segment size + DATA segment size
    tst.l (a5)                            ; If long word stored at the address is 0, we don't need to relocate
    beq.s .zeroing_bss_no_reloc
    moveq #0, d0                          ; Clear the d0 register
    add.l (a5)+, a6                       ; a6 -> first fixup
.fixup_get_next_reloc_byte:
    add.l d1, (a6)                       ; longword += TEXT base
.get_next_reloc_byte:
    move.b (a5)+, d0                     ; get the next fixup byte
    beq.s .zeroing_bss                   ; If 0, we are done
    cmp.b #1, d0                         ; If 1, a6 += 0xfe
    bne.s .bypass_bump_location_ptr
    add.w #$fe, a6                       ; bump location pointer
    bra.s .get_next_reloc_byte           ; get next reloc byte
.bypass_bump_location_ptr:
    add.w d0, a6                         ; a6 += byte
    bra.s .fixup_get_next_reloc_byte     ; fixup and get next reloc byte

; Do not reloc here
.zeroing_bss_no_reloc:
; Zeroing the BSS segment
.zeroing_bss:
    move.l GEMDRVEMUL_EXEC_PD, a4        ; load the pointer to the basepage of the new process of the file
    move.l 24(a4), a5                    ; Get the address of the start of the bss segment
    move.l 28(a4), d5                    ; Get the size of the bss segment
    bsr .fill_zero                     ; Zero the memory

.pexec_pexec_go:
; New we continue to the Pexec() call modifying the parameters to PE_GO and the address of the basepage
; By pass if not GO mode
    cmp.w #PE_LOAD, GEMDRVEMUL_PEXEC_MODE; Check if the mode is PE_LOAD
    beq .pexec_exit_load               ; If so, don't continue with the code GO mode and exit

; Before continuing, we need to figure out if PE_GO_AND_FREE is implemented or not
; if so, do not trap the exit of the PE_GO call
    move.l GEMDRVEMUL_PEXEC_STACK_ADDR, a0
    move.w #PE_GO_AND_FREE, 8(a0)        ; overwrite the mode with PE_GO_AND_FREE
    move.l (GEMDRVEMUL_SHARED_VARIABLES + (SHARED_VARIABLE_SVERSION * 4)), d0
    and.l #$FFFF, d0                     ; Mask the version number
    cmp.w #$1500, d0    ; If the version is higher than 0x1500 (TOS 1.04 or TOS 1.06), PE_GO_AND_FREE exists
    bhi.s .pexec_go_and_free_exists

; Trap the exit of the classic PE_GO call
    move.l #SHARED_VARIABLE_PEXEC_RESTORE, d3
    move.l 46(sp),d4                     ; Store the return address in the shared variable PEXEC_RESTORE
    send_sync CMD_SET_SHARED_VAR, 8      ; Send the command to the Sidecart. 8 bytes of payload
    move.l #.pexec_mshrink_exit, 46(sp)  ; Trap the exit of the PE_GO before exiting to release memory

    move.l GEMDRVEMUL_PEXEC_STACK_ADDR, a0  ; We need to set again the a0 register
    move.w #PE_GO, 8(a0)                    ; overwrite the mode with PE_GO

.pexec_go_and_free_exists:
; Try to execute the new process
; The GO_AND_FREE also releases the memory of the current process
; The GO does not release the memory and must be manually released
    clr.l 10(a0)                         ; NULL address of the environment string
    move.l GEMDRVEMUL_EXEC_PD, 14(a0)    ; overwrite the address of the pointer to the fname with the address of the basepage
    clr.l 18(a0)                         ; NULL address of the command line string
    bra .exec_old_handler

; The code here is executed when the PE_GO is finished. It must release the memory of the current process
; and restore the basepage of the current process
.pexec_mshrink_exit:
; Release the memory of the current process, if necessary
; Get the values from _sysbase
    movem.l d1-d7/a0-a6, -(sp)           ; Save registers
    reentry_gem_lock
    move.l GEMDRVEMUL_EXEC_PD, -(sp)     ; Pointer to the BASEPAGE structure of the process
    gemdos Mfree, 6                      ; Call Mfree() and release the memory of the current process
    reentry_gem_unlock    
    ext.l d0                             ; Extend the sign of the value
    movem.l (sp)+,d1-d7/a0-a6            ; Restore registers

    move.l (GEMDRVEMUL_SHARED_VARIABLES + (SHARED_VARIABLE_PEXEC_RESTORE * 4)), -(sp)
    rts

.pexec_exit_load:
    move.l GEMDRVEMUL_EXEC_PD, d0        ; Return in D0 the address of the basepage of the new process
.pexec_exit:
    movem.l (sp)+,d2-d7/a2-a6             ; Restore registers
    rte

.pexec_close_exit_fix_hdr_buf:
;    ifeq USE_DSKBUF
;        nop
;    else    
;        add.l #PRG_STRUCT_SIZE,sp            ; restore the stack pointer
;    endif

    tst.l (GEMDRVEMUL_SHARED_VARIABLES + (SHARED_VARIABLE_BUFFER_TYPE * 4))
    beq.s .pexec_close_exit_fix_hdr_buf_not_restore_stack
    add.l #PRG_STRUCT_SIZE,sp            ; restore the stack pointer

.pexec_close_exit_fix_hdr_buf_not_restore_stack:
    move.w GEMDRVEMUL_FOPEN_HANDLE, d3   ; Pass the file handle to close
    send_sync CMD_FCLOSE_CALL, 2         ; Send the command to the Sidecart.
    move.w GEMDRVEMUL_FCLOSE_STATUS, d0  ; Error code obtained from the Sidecart
    ext.l d0                             ; Extend the sign of the value
    bra.s .pexec_exit                    ; If there is an error, exit

; Zero the memory given the address and the size
; Input registers:
; a5: address of the memory to zero
; d5.l: size of the memory to zero
; Output registers:
; a5: modified
; d5: modified
.fill_zero:
    tst.l d5                            ; Check if the size is 0
    beq.s .fill_zero_exit               ; If 0, we are done
.fill_zero_loop:
    clr.b (a5)+                         ; Zero the memory
    subq.l #1, d5                       ; Decrement the counter
    bne.s .fill_zero_loop               ; Loop until the counter is 0
.fill_zero_exit:
    rts

; Send an sync command to the Sidecart
; Wait until the command sets a response in the memory with a random number used as a token
; Input registers:
; d0.w: command code
; d1.w: payload size
; From d3 to d7 the payload based on the size of the payload field d1.w
; Output registers:
; d0: error code, 0 if no error
; d1-d7 are modified. a0-a3 modified.
send_sync_command_to_sidecart:
    move.l (sp)+, a0                 ; Return address
    move.l #_end_sync_code_in_stack - _start_sync_code_in_stack, d7

;    ifeq USE_DSKBUF
;        ; Put the code in the disk buffer
;        move.l _dskbufp, a2                ; Address of the buffer to send the command
;    else
;        ; Put the code in the stack
;        lea -(_end_sync_code_in_stack - _start_sync_code_in_stack)(sp), sp
;        move.l sp, a2
;    endif

    tst.l (GEMDRVEMUL_SHARED_VARIABLES + (SHARED_VARIABLE_BUFFER_TYPE * 4))
    bne.s .send_sync_command_to_sidecart_use_stack_buffer
    move.l _dskbufp, a2                ; Address of the buffer to send the command
    bra.s .send_sync_command_to_sidecart_continue
.send_sync_command_to_sidecart_use_stack_buffer:
    lea -(_end_sync_code_in_stack - _start_sync_code_in_stack)(sp), sp
    move.l sp, a2
.send_sync_command_to_sidecart_continue:
    move.l a2, a3
    lea _start_sync_code_in_stack, a1    ; a1 points to the start of the code in ROM
    lsr.w #2, d7
    subq #1, d7
_copy_sync_code:
    move.l (a1)+, (a2)+
    dbf d7, _copy_sync_code

    move.l a0, a2                       ; Return address to a2

    ; The sync command synchronize with a random token
    move.l RANDOM_TOKEN_SEED_ADDR,d2
    addq.w #4, d1                       ; Add 4 bytes to the payload size to include the token

_start_async_code_in_stack:
    move.l #ROM3_START_ADDR, a0 ; Start address of the ROM3

    ; SEND HEADER WITH MAGIC NUMBER
    swap d0                     ; Save the command code in the high word of d0         
    move.b CMD_MAGIC_NUMBER, d0 ; Command header. d0 is a scratch register

    ; SEND COMMAND CODE
    swap d0                     ; Recover the command code
    move.l a0, a1               ; Address of the ROM3
    add.w d0, a1                ; We can use add because the command code msb is 0 and there is no sign extension            
    move.b (a1), d0             ; Command code. d0 is a scratch register

    ; SEND PAYLOAD SIZE
    move.l a0, d0               ; Address of the ROM3 in d0    
    or.w d1, d0                 ; OR high and low words in d0
    move.l d0, a1               ; move to a1 ready to read from this address
    move.b (a1), d0             ; Command payload size. d0 is a scratch register
    tst.w d1
    beq _no_more_payload_stack        ; If the command does not have payload, we are done.

    ; SEND PAYLOAD
    move.l a0, d0
    or.w d2, d0
    move.l d0, a1
    move.b (a1), d0           ; Command payload low d2
    cmp.w #2, d1
    beq _no_more_payload_stack

    swap d2
    move.l a0, d0
    or.w d2, d0
    move.l d0, a1
    move.b (a1), d0           ; Command payload high d2
    cmp.w #4, d1
    beq _no_more_payload_stack

    move.l a0, d0
    or.w d3, d0
    move.l d0, a1
    move.b (a1), d0           ; Command payload low d3
    cmp.w #6, d1
    beq _no_more_payload_stack

    swap d3
    move.l a0, d0
    or.w d3, d0
    move.l d0, a1
    move.b (a1), d0           ; Command payload high d3
    cmp.w #8, d1
    beq _no_more_payload_stack

    move.l a0, d0
    or.w d4, d0
    move.l d0, a1
    move.b (a1), d0           ; Command payload low d4
    cmp.w #10, d1
    beq _no_more_payload_stack

    swap d4
    move.l a0, d0
    or.w d4, d0
    move.l d0, a1
    move.b (a1), d0           ; Command payload high d4
    cmp.w #12, d1
    beq.s _no_more_payload_stack

    move.l a0, d0
    or.w d5, d0
    move.l d0, a1
    move.b (a1), d0           ; Command payload low d5
    cmp.w #14, d1
    beq.s _no_more_payload_stack

    swap d5
    move.l a0, d0
    or.w d5, d0
    move.l d0, a1
    move.b (a1), d0           ; Command payload high d5
    cmp.w #16, d1
    beq.s _no_more_payload_stack

    move.l a0, d0
    or.w d6, d0
    move.l d0, a1
    move.b (a1), d0           ; Command payload low d6
    cmp.w #18, d1
    beq.s _no_more_payload_stack

    swap d6
    move.l a0, d0
    or.w d6, d0
    move.l d0, a1
    move.b (a1), d0           ; Command payload high d6

_no_more_payload_stack:
    swap d2                   ; D2 is the only register that is not used as a scratch register
    move.l #$000FFFFF, d7     ; Most significant word is the inner loop, least significant word is the outer loop
    moveq #0, d0              ; Timeout
    jmp (a3)                  ; Jump to the code in the stack
; This is the code that cannot run in ROM while waiting for the command to complete
_start_sync_code_in_stack:
    cmp.l RANDOM_TOKEN_ADDR, d2              ; Compare the random number with the token
    beq.s _sync_token_found                  ; Token found, we can finish succesfully
    subq.l #1, d7                            ; Decrement the inner loop
    bne.s _start_sync_code_in_stack          ; If the inner loop is not finished, continue


    ; Sync token not found, timeout
    subq.l #1, d0                            ; Timeout
_sync_token_found:

    move.l #RANDOM_TOKEN_POST_WAIT, d7
_wait_me:
    subq.l #1, d7                            ; Decrement the outer loop
    bne.s _wait_me                           ; Wait for the timeout

;    ifeq USE_DSKBUF
;        jmp (a2)                                 ; Return to the code in the ROM
;    else
;        lea (_end_sync_code_in_stack - _start_sync_code_in_stack)(sp), sp
;        jmp (a2)                                 ; Return to the code in the ROM
;    endif
    tst.l (GEMDRVEMUL_SHARED_VARIABLES + (SHARED_VARIABLE_BUFFER_TYPE * 4))
    beq.s ._wait_me_restore_dskbuff
    lea (_end_sync_code_in_stack - _start_sync_code_in_stack)(sp), sp
._wait_me_restore_dskbuff:
    jmp (a2)                                 ; Return to the code in the ROM

    even    ; Do not remove this line
    nop     ; Do not remove this line
    nop     ; Do not remove this line
_end_sync_code_in_stack:

; Send an sync write command to the Sidecart
; Wait until the command sets a response in the memory with a random number used as a token
; Input registers:
; d0.w: command code
; d3.l: long word to send to the sidecart
; d4.l: long word to send to the sidecart
; d5.l: long word to send to the sidecart
; d6.w: number of bytes to write to the sidecart starting in a4 address
; a4: address of the buffer to write in the sidecart
; Output registers:
; d0: error code, 0 if no error
; a4: next address in the computer memory to retrieve
; d1-d7 are modified. a0-a3 modified.
send_sync_write_command_to_sidecart:
    move.l (sp)+, a0                 ; Return address
    move.l #_end_sync_write_code_in_stack - _start_sync_write_code_in_stack, d7

;    ifeq USE_DSKBUF
;        ; Put the code in the disk buffer
;        move.l _dskbufp, a2                ; Address of the buffer to send the command 
;    else
;        ; Put the code in the stack
;        lea -(_end_sync_write_code_in_stack - _start_sync_write_code_in_stack)(sp), sp
;        move.l sp, a2
;    endif

    tst.l (GEMDRVEMUL_SHARED_VARIABLES + (SHARED_VARIABLE_BUFFER_TYPE * 4))
    bne.s .send_sync_write_command_to_sidecart_use_stack_buffer
    move.l _dskbufp, a2                ; Address of the buffer to send the command
    bra.s .send_sync_write_command_to_sidecart_continue
.send_sync_write_command_to_sidecart_use_stack_buffer:
    lea -(_end_sync_write_code_in_stack - _start_sync_write_code_in_stack)(sp), sp
    move.l sp, a2

.send_sync_write_command_to_sidecart_continue:
    move.l a2, a3
    lea _start_sync_write_code_in_stack, a1    ; a1 points to the start of the code in ROM
    lsr.w #2, d7
    subq #1, d7
_copy_write_sync_code:
    move.l (a1)+, (a2)+
    dbf d7, _copy_write_sync_code

    move.l a0, a2                       ; Return address to a2

    ; The sync write command synchronize with a random token
    move.l RANDOM_TOKEN_SEED_ADDR,d2
    addq.w #4, d1                       ; Add 4 bytes to the payload size to include the token
    add.w d6, d1                        ; Add the number of bytes to write to the sidecart
    addq.w #1, d1                       ; Add one byte to the payload before rounding to the next word
    lsr.w #1, d1                        ; Round to the next word
    lsl.w #1, d1                        ; Multiply by 2 because we are sending two bytes each iteration

_start_async_write_code_in_stack:   
    move.l #ROM3_START_ADDR, a0 ; We have to keep in A0 the address of the ROM3 because we need to read from it

    ; SEND HEADER WITH MAGIC NUMBER
    swap d0                     ; Save the command code in the high word of d0         
    move.b CMD_MAGIC_NUMBER, d0; Command header. d0 is a scratch register

    ; SEND COMMAND CODE
    swap d0                     ; Recover the command code
    move.l a0, a1               ; Address of the ROM3
    add.w d0, a1                ; We can use add because the command code msb is 0 and there is no sign extension            
    move.b (a1), d0             ; Command code. d0 is a scratch register

    ; SEND PAYLOAD SIZE
    move.l a0, d0               ; Address of the ROM3 in d0    
    or.w d1, d0                 ; OR high and low words in d0
    move.l d0, a1               ; move to a1 ready to read from this address
    move.b (a1), d0             ; Command payload size. d0 is a scratch register

    ; SEND PAYLOAD
    move.l a0, d0
    or.w d2, d0
    move.l d0, a1
    move.b (a1), d0           ; Command payload low d2

    swap d2
    move.l a0, d0
    or.w d2, d0
    move.l d0, a1
    move.b (a1), d0           ; Command payload high d2

    move.l a0, d0
    or.w d3, d0
    move.l d0, a1
    move.b (a1), d0           ; Command payload low d3

    swap d3
    move.l a0, d0
    or.w d3, d0
    move.l d0, a1
    move.b (a1), d0           ; Command payload high d3

    move.l a0, d0
    or.w d4, d0
    move.l d0, a1
    move.b (a1), d0           ; Command payload low d4

    swap d4
    move.l a0, d0
    or.w d4, d0
    move.l d0, a1
    move.b (a1), d0           ; Command payload high d4

    move.l a0, d0
    or.w d5, d0
    move.l d0, a1
    move.b (a1), d0           ; Command payload low d5

    swap d5
    move.l a0, d0
    or.w d5, d0
    move.l d0, a1
    move.b (a1), d0           ; Command payload high d5

    ;
    ; SEND MEMORY BUFFER TO WRITE
    ;
    lsr.w #1, d6              ; Copy two bytes each iteration
    subq.w #1, d6             ; one less

    ; Test if the address in A4 is even or odd
    move.l a4, d0
    btst #0, d0
    beq.s _write_to_sidecart_even_loop
_write_to_sidecart_odd_loop:
    move.b  (a4)+, d3       ; Load the high byte
    lsl.w   #8, d3          ; Shift it to the high part of the word
    move.b  (a4)+, d3       ; Load the low byte
    move.l a0, d0
    or.w d3, d0
    move.l d0, a1
    move.b (a1), d0           ; Write the memory to the sidecart
    dbf d6, _write_to_sidecart_odd_loop
    bra.s _write_to_sidecart_end_loop

 _write_to_sidecart_even_loop:
    move.w (a4)+, d3        ; Load the word
    move.l a0, d0
    or.w d3, d0
    move.l d0, a1
    move.b (a1), d0           ; Write the memory to the sidecart
    dbf d6, _write_to_sidecart_even_loop

_write_to_sidecart_end_loop:
    ; End of the command loop. Now we need to wait for the token
    swap d2                   ; D2 is the only register that is not used as a scratch register
    move.l #$000FFFFF, d7     ; Most significant word is the inner loop, least significant word is the outer loop
    moveq #0, d0              ; Timeout
    jmp (a3)                  ; Jump to the code in the stack

; This is the code that cannot run in ROM while waiting for the command to complete
_start_sync_write_code_in_stack:
    cmp.l RANDOM_TOKEN_ADDR, d2                    ; Compare the random number with the token
    beq.s _sync_write_token_found                  ; Token found, we can finish succesfully
    subq.l #1, d7                                  ; Decrement the inner loop
    bne.s _start_sync_write_code_in_stack          ; If the inner loop is not finished, continue

    ; Sync token not found, timeout
    subq.l #1, d0                                  ; Timeout

_sync_write_token_found:

    move.l #RANDOM_TOKEN_POST_WAIT, d7
_wait_me_write:
    subq.l #1, d7                            ; Decrement the outer loop
    bne.s _wait_me_write                     ; Wait for the timeout

;    ifeq USE_DSKBUF
;        jmp (a2)                                 ; Return to the code in the ROM
;    else
;        lea (_end_sync_write_code_in_stack - _start_sync_write_code_in_stack)(sp), sp
;        jmp (a2)                                 ; Return to the code in the ROM
;    endif

    tst.l (GEMDRVEMUL_SHARED_VARIABLES + (SHARED_VARIABLE_BUFFER_TYPE * 4))
    beq.s ._wait_me_write_restore_dskbuff
    lea (_end_sync_write_code_in_stack - _start_sync_write_code_in_stack)(sp), sp
._wait_me_write_restore_dskbuff:
    jmp (a2)                                 ; Return to the code in the ROM

    even    ; Do not remove this line
    nop     ; Do not remove this line
    nop     ; Do not remove this line
_end_sync_write_code_in_stack:




        even
gemdrive_emulator_msg:
        dc.b	"SidecarT GEMDRIVE - "
        
version:
        dc.b    "v"
        dc.b    VERSION_MAJOR
        dc.b    "."
        dc.b    VERSION_MINOR
        dc.b    "."
        dc.b    VERSION_PATCH
        dc.b    $d,$a

spacing:
        dc.b    "+" ,$d,$a,0

set_version_msg:
        dc.b	"+- TOS version: ",0

set_vectors_msg:
        dc.b	"+- Set vectors...",0

stack_buffer_msg:
        dc.b	"+- Using stack as temp buffer...",0

dskbuf_buffer_msg:
        dc.b	"+- Using _dskbuf as temp buffer...",0

query_ping_msg:
        dc.b	"+- Mounting microSD card...",0

query_network_msg:
        dc.b	"+- Network initialization...",0

query_ntp_msg:
        dc.b	"+- NTP synchronization...",0

rtc_already_started_msg:
        dc.b	"+- RTC already started.",$d,$a,0

emulated_drive_msg:
        dc.b	"+- Emulating drive ",0

ready_gemdrive_msg:
        dc.b	"+- GEMDRIVE driver loaded...",0

error_sidecart_comm_msg:
        dc.b	$d,$a,"Sidecart error communication. Reset!",$d,$a,0

backwards_msg:
        dc.b    $8, $8,0

ok_msg:
        dc.b	"OK",$d,$a,0

timeout_msg:
        dc.b	"Timeout!",$d,$a,0 

        even

null_pointer:
        dc.l    0

        even
rom_function_end: