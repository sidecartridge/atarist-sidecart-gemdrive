; SidecarTridge Multi-device macros for the shared SidecarTridge library

; Macros

; Send a synchronous command to the Multi-device passing arguments in the Dx registers
; /1 : The command code
; /2 : The payload size (even number always)
send_sync           macro
                    moveq.l #\2, d1                      ; Set the payload size of the command
                    move.w #\1,d0                        ; Command code
                    bsr send_sync_command_to_sidecart    ; Send the command to the Multi-device
                    endm    

; Send a synchronous write command to the Multi-device passing arguments in the D3-D5 registers
; A4 address of the buffer to send
; /1 : The command code
; /2 : The buffer size to send in bytes (will be rounded to the next word)
send_write_sync     macro
                    move.w #\1,d0                           ; Command code
                    moveq.l #12, d1                         ; Set the payload size of the command (d3.l, d4.l and d5.l)
                    move.l #\2,d6                           ; Number of bytes to send
                    bsr send_sync_write_command_to_sidecart ; Send the command to the Multi-device
                    endm    


