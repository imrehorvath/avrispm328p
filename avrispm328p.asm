;******************************************************************************
;* Title        : AVR ISP (ATmega328P, Addr. auto inc., STK500v1 at 115.2 kbps)
;* Version      : 1.0
;* Last updated : Feb 08 2024 
;* Target       : ATmega328P clocked at 16 MHz
;* File         : avrispm328p.asm 
;* Author       : Imre Horvath <imi.horvath [at] gmail [dot] com>
;* License      : GNU GPLv3
;* Description  : This AVR ISP firmware turns your ATmega328P-based board (like
;*                an Arduino Nano, Uno, etc.) into an AVR ISP with adjus-
;*                table SCK half-period, using the STK500v1 protocol.
;*                (The pin assignment matches the already established practice,
;*                so this firmware can be used with existing rigs.)
;******************************************************************************

.nolist
.include "m328Pdef.inc"
.list

;**** Programmer version numbers ****

.equ HWVER =  2
.equ SWMAJ =  1
.equ SWMIN = 18

;**** Input-, Port- and Data Direction Assignments ****

.equ ICSP_PIN  = PINB
.equ ICSP_PORT = PORTB
.equ ICSP_DDR  = DDRB

.equ LED_PORT = PORTB
.equ LED_DDR  = DDRB

;**** Bit Assignments ****

.equ RED   = PB0
.equ GREEN = PB1
.equ RST   = PB2
.equ MOSI  = PB3
.equ MISO  = PB4
.equ SCK   = PB5

;**** STK500v1 Constants ****

.equ Resp_STK_OK             = 0x10
.equ Resp_STK_FAILED         = 0x11
.equ Resp_STK_UNKNOWN        = 0x12
.equ Resp_STK_NODEVICE       = 0x13
.equ Resp_STK_INSYNC         = 0x14
.equ Resp_STK_NOSYNC         = 0x15

.equ Sync_CRC_EOP            = 0x20

.equ Cmnd_STK_GET_SYNC       = 0x30
.equ Cmnd_STK_GET_SIGN_ON    = 0x31
.equ Cmnd_STK_SET_PARAMETER  = 0x40
.equ Cmnd_STK_GET_PARAMETER  = 0x41
.equ Cmnd_STK_SET_DEVICE     = 0x42
.equ Cmnd_STK_SET_DEVICE_EXT = 0x45
.equ Cmnd_STK_ENTER_PROGMODE = 0x50
.equ Cmnd_STK_LEAVE_PROGMODE = 0x51
.equ Cmnd_STK_LOAD_ADDRESS   = 0x55
.equ Cmnd_STK_UNIVERSAL      = 0x56
.equ Cmnd_STK_PROG_PAGE      = 0x64
.equ Cmnd_STK_READ_PAGE      = 0x74
.equ Cmnd_STK_READ_SIGN      = 0x75

.equ Parm_STK_HW_VER         = 0x80
.equ Parm_STK_SW_MAJOR       = 0x81
.equ Parm_STK_SW_MINOR       = 0x82
.equ Parm_STK_SCK_DURATION   = 0x89
.equ Parm_STK_PROGMODE       = 0x93

;**** Status register bits ****

.equ STAT_PS    = 0             ; Parameters are set
.equ STAT_RSTAH = 1             ; Target has active high reset
.equ STAT_PM    = 2             ; In programming mode
.equ STAT_ERR   = 3             ; In error state

;**** Global Register Variables ****

.def ramtemp    = r2
.def stash2     = r3
.def stash3     = r4
.def stash4     = r5
.def prev_pagel = r6
.def prev_pageh = r7
.def curr_pagel = r8
.def curr_pageh = r9
.def page_maskl = r10
.def page_maskh = r11
.def sck_durat  = r12           ; SCK half-period duration in microseconds
.def bit_cnt    = r13

.def temp       = r16
.def temp2      = r17
.def temp3      = r18
.def u_data     = r19           ; USART data byte
.def s_data     = r20           ; SPI data byte
.def status     = r21           ; Programmer status (see above)
.def stash      = r22
.def cnt        = r23
.def addrl      = r24
.def addrh      = r25

;**** Data stored in SRAM ****

.dseg

;**** Device Programming Parameters ****

devparams:
devicecode:     .byte 1
revision:       .byte 1
progtype:       .byte 1
parmode:        .byte 1
polling:        .byte 1
selftimed:      .byte 1
lockbytes:      .byte 1
fusebytes:      .byte 1
flashpollval1:  .byte 1
flashpollval2:  .byte 1
eeprompollval1: .byte 1
eeprompollval2: .byte 1
pagesizehigh:   .byte 1
pagesizelow:    .byte 1
eepromsizehigh: .byte 1
eepromsizelow:  .byte 1
flashsize4:     .byte 1
flashsize3:     .byte 1
flashsize2:     .byte 1
flashsize1:     .byte 1

;**** Buffer ****

buff:           .byte 256

.cseg
.org 0
        rjmp  reset

;******************************************************************************
;*
;* FUNCTION
;*	delay
;*
;* DESCRIPTION
;*	 Delay for temp x 1 milliseconds at 16 MHz.
;*
;******************************************************************************

delay:  
        ldi   temp2, low((16000000/1000)/5)
        ldi   temp3, high((16000000/1000)/5)
d_5_cycles:
        subi  temp2, 1
        sbci  temp3, 0
        nop
        brne  d_5_cycles
        dec   temp
        brne  delay
        ret

;******************************************************************************
;*
;* FUNCTION
;*	delay_us
;*
;* DESCRIPTION
;*	 Delay for temp x 1 microseconds at 16 MHz.
;*
;******************************************************************************

delay_us:
        cpi   temp, 1
        breq  du_7_plus_9_cycles
        dec   temp
        ldi   temp2, 16
        mul   temp, temp2
        rjmp  PC+1
du_16_cycles:
        ldi   temp2, 16
        ldi   temp3, 0
        sub   r0, temp2
        sbc   r1, temp3
        rjmp  PC+1
        rjmp  PC+1
        rjmp  PC+1
        rjmp  PC+1
        rjmp  PC+1
        brne  du_16_cycles
        nop
        ret
du_7_plus_9_cycles:
        rjmp  PC+1
        rjmp  PC+1
        nop
        ret

;******************************************************************************
;*
;* FUNCTION
;*	u_init
;*
;* DESCRIPTION
;*	 Set up the USART0 interface for serial communication.
;*       Note: At 16 MHz, the 115.2 kbps only seems to work, when the x2 speed
;*       is selected. With x1 speed, constant frame errors are experienced.
;*
;******************************************************************************

u_init:
        ldi   temp, 0x00                     ; Set up 115.2 kbps
        sts   UBRR0H, temp                   ;
        ldi   temp, 0x10                     ;
        sts   UBRR0L, temp                   ;
        ldi   temp, (1<<U2X0)                ;
        sts   UCSR0A, temp                   ;

        ldi   temp, (1<<RXEN0)|(1<<TXEN0)    ; Enable RX and TX
        sts   UCSR0B, temp                   ;

        ldi   temp, (3<<UCSZ00)              ; Frame format: 8N1
        sts   UCSR0C, temp                   ;
        ret

;******************************************************************************
;*
;* FUNCTION
;*	getc
;*
;* DESCRIPTION
;*	 Receive a data byte on the USART0 Rx line and put it into u_data.
;*
;******************************************************************************

getc:
        lds   temp, UCSR0A   ; Wait for the data to be received
        sbrs  temp, RXC0     ;
        rjmp  getc           ;
        lds   u_data, UDR0   ; Put the received data byte into u_data
        ret

;******************************************************************************
;*
;* FUNCTION
;*	putc
;*
;* DESCRIPTION
;*	 Transmit the data byte in u_data on the USART0 Tx line.
;*
;******************************************************************************

putc:
        lds   temp, UCSR0A   ; Wait until the transmit buffer is empty
        sbrs  temp, UDRE0    ;
        rjmp  putc           ;
        sts   UDR0, u_data   ; Transmit the data byte in u_data
        ret

;******************************************************************************
;*
;* FUNCTION
;*	put_string
;*
;* DESCRIPTION
;*	 Transmit the 0 terminated string pointed by Z on the USART0 Tx line.
;*
;******************************************************************************

put_string:
        lpm                   ; Load char from program memory into r0
        tst   r0
        breq  ps_ret          ; Check if end of string reached
        mov   u_data, r0
        rcall putc            ; putc char loaded from the program memory
        adiw  ZL, 1           ; increment Z
        rjmp  put_string      ; loop over the entire string
ps_ret:
        ret

;******************************************************************************
;*
;* FUNCTION
;*	s_init
;*
;* DESCRIPTION
;*	 Set up the SPI interface as Master.
;*
;******************************************************************************

s_init:
        in    temp, ICSP_PORT                ; Set up SCK and MOSI as LOW
        cbr   temp, (1<<SCK)|(1<<MOSI)       ;
        out   ICSP_PORT, temp                ;

        in    temp, ICSP_DDR                 ; Set SCK and MOSI as output
        sbr   temp, (1<<SCK)|(1<<MOSI)       ;
        out   ICSP_DDR, temp                 ;
        ret

;******************************************************************************
;*
;* FUNCTION
;*	s_deinit
;*
;* DESCRIPTION
;*	 Let go of the SPI interface lines.
;*
;******************************************************************************

s_deinit:
        in    temp, ICSP_DDR                 ; Set SCK and MOSI as input
        cbr   temp, (1<<SCK)|(1<<MOSI)       ;
        out   ICSP_DDR, temp                 ;

        in    temp, ICSP_PORT                ; Set no pullups for SCK, MOSI
        cbr   temp, (1<<SCK)|(1<<MOSI)       ;
        out   ICSP_PORT, temp                ;
        ret

;******************************************************************************
;*
;* FUNCTION
;*	s_transmit
;*
;* DESCRIPTION
;*	 Transmit and receive data on the SPI interface. The same register
;*       (s_data) is used for both input and output.
;*
;******************************************************************************

s_transmit:
        ldi   temp, 8
        mov   bit_cnt, temp
st_loop:
        lsl   s_data

        brcc  st_mosi_low             ; MOSI
        sbi   ICSP_PORT, MOSI         ;
        rjmp  st_mosi_setup_done      ;
st_mosi_low:                          ;
        cbi   ICSP_PORT, MOSI         ;
        rjmp  st_mosi_setup_done      ;

st_mosi_setup_done:
        sbic  ICSP_PIN, MISO          ; MISO
        inc   s_data                  ;

        sbi   ICSP_PORT, SCK          ; SCK
        mov   temp, sck_durat         ;
        rcall delay_us                ;
        cbi   ICSP_PORT, SCK          ;
        mov   temp, sck_durat         ;
        rcall delay_us                ;

        dec   bit_cnt
        brne  st_loop
        ret

;******************************************************************************
;*
;* FUNCTION
;*	drive_rst_pin
;*
;* DESCRIPTION
;*	 Drive the RST pin. Device params must be set before.
;*
;******************************************************************************

drive_rst_pin:
        sbrs  status, STAT_RSTAH
        cbi   ICSP_PORT, RST          ; Set RST LOW, when target is act. low
        sbrc  status, STAT_RSTAH
        sbi   ICSP_PORT, RST          ; Set RST HIGH, when target is act. hi

        sbi   ICSP_DDR, RST           ; Set RST as output
        ret

;******************************************************************************
;*
;* FUNCTION
;*	leave_rst_pin
;*
;* DESCRIPTION
;*	 Let go of the RST pin.
;*
;******************************************************************************

leave_rst_pin:
        cbi   ICSP_DDR, RST           ; Set RST as input
        cbi   ICSP_PORT, RST          ; Set no pullup
        ret

;******************************************************************************
;*
;* FUNCTION
;*	reset_on
;*
;* DESCRIPTION
;*	 Reset the target device. Device params must be set before.
;*
;******************************************************************************

reset_on:
        sbrs  status, STAT_RSTAH
        cbi   ICSP_PORT, RST          ; Set RST LOW, when target is act. low
        sbrc  status, STAT_RSTAH
        sbi   ICSP_PORT, RST          ; Set RST HIGH, when target is act. hi
        ret

;******************************************************************************
;*
;* FUNCTION
;*	reset_off
;*
;* DESCRIPTION
;*	 Allow target device to run. Device params must be set before.
;*
;******************************************************************************

reset_off:
        sbrs  status, STAT_RSTAH
        sbi   ICSP_PORT, RST          ; Set RST HIGH, when target is act. low
        sbrc  status, STAT_RSTAH
        cbi   ICSP_PORT, RST          ; Set RST LOW, when target is act. high
        ret

;******************************************************************************
;*
;* FUNCTION
;*	usart_to_sram
;*
;* DESCRIPTION
;*	 Fill SRAM, pointed by Y, with cnt (up to 256) number of bytes
;*       read from USART0.
;*
;******************************************************************************

usart_to_sram:
        rcall getc
        st    Y+, u_data
        dec   cnt 
        brne  usart_to_sram
        ret

;******************************************************************************
;*
;* FUNCTION
;*	sram_copy
;*
;* DESCRIPTION
;*	 Copy cnt (up to 256) number of bytes in SRAM from location
;*       pointed by Z to location pointed by Y.
;*
;******************************************************************************

sram_copy:
        ld    ramtemp, Z+
        st    Y+, ramtemp
        dec   cnt 
        brne  sram_copy
        ret

;******************************************************************************
;*
;* FUNCTION
;*	deter_rst_level
;*
;* DESCRIPTION
;*	 Determinte the target RST signal-level based on the devicecode.
;*
;******************************************************************************

deter_rst_level:
        lds   temp, devicecode
        cpi   temp, 0xE0
        brsh  drl_act_high
        cbr   status, (1<<STAT_RSTAH)
        rjmp  drl_done
drl_act_high:
        sbr   status, (1<<STAT_RSTAH)
drl_done:
        ret

;******************************************************************************
;*
;* FUNCTION
;*	calc_page_addr_mask
;*
;* DESCRIPTION
;*	 Calculate the address mask for program pages.
;*
;******************************************************************************

calc_page_addr_mask:
        lds   temp2, pagesizehigh
        lds   temp, pagesizelow
        subi  temp, 1
        sbci  temp2, 0                ; -1
        lsr   temp2
        ror   temp                    ; Shift to the right
        com   temp2
        com   temp                    ; Flip all bits
        mov   page_maskh, temp2
        mov   page_maskl, temp
        ret

;******************************************************************************
;*
;* FUNCTION
;*	current_page
;*
;* DESCRIPTION
;*	 (Re-)Calculate the current page from the address.
;*
;******************************************************************************

current_page:
        mov   curr_pageh, addrh
        and   curr_pageh, page_maskh
        mov   curr_pagel, addrl
        and   curr_pagel, page_maskl
        ret

;******************************************************************************
;*
;* FUNCTION
;*	poll_rdybsy
;*
;* DESCRIPTION
;*	 Poll RDY/BSY status.
;*
;******************************************************************************

poll_rdybsy:
        ldi   s_data, 0xF0    ; Poll RDY/BSY
        rcall s_transmit
        ldi   s_data, 0x00
        rcall s_transmit
        ldi   s_data, 0x00
        rcall s_transmit
        ldi   s_data, 0x00
        rcall s_transmit
        sbrc  s_data, 0       ; Bit 0 = 1 indicates BSY
        rjmp  poll_rdybsy
        ret

;******************************************************************************
;*
;* FUNCTION
;*	commit_page
;*
;* DESCRIPTION
;*	 Commit the page buffer.
;*
;******************************************************************************

commit_page:
        ldi   s_data, 0x4C    ; Commit prev-page when page-change
        rcall s_transmit
        mov   s_data, prev_pageh
        rcall s_transmit
        mov   s_data, prev_pagel
        rcall s_transmit
        ldi   s_data, 0x00
        rcall s_transmit
        rcall poll_rdybsy     ; Poll until the write is completed
        ret

;******************************************************************************
;*
;* FUNCTION
;*	init_params
;*
;* DESCRIPTION
;*	 Init the parameters to their default values.
;*
;*       sck_durat: A 2 microseconds SCK half-period setting is a reasonable
;*                  default for most of the cases. (Eg. for parts with a 1 MHz 
;*                  default clock)
;*
;******************************************************************************

init_params:
        ldi   temp, 2                ; Set a 2 microseconds SCK half-period
        mov   sck_durat, temp        ; duration as default.
        ret

;******************************************************************************
;*
;* FUNCTION
;*	init_LEDs
;*
;* DESCRIPTION
;*	 Initialize the indicator LEDs.
;*
;******************************************************************************

init_LEDs:
        cbi   LED_PORT, GREEN   ; Set LOW signal level for PM LED
        sbi   LED_DDR, GREEN    ; Set it as output

        cbi   LED_PORT, RED     ; Set LOW signal level for ERR LED
        sbi   LED_DDR, RED      ; Set it as output
        ret

;******************************************************************************
;*
;* FUNCTION
;*	update_LEDs
;*
;* DESCRIPTION
;*	 Update the indicator LEDs, based on the programmer status.
;*
;******************************************************************************

update_LEDs:
        sbrs  status, STAT_PM
        cbi   LED_PORT, GREEN   ; Turn off the PM LED, when flag is 0
        sbrc  status, STAT_PM
        sbi   LED_PORT, GREEN   ; Turn on the PM LED, when flag is 1

        sbrs  status, STAT_ERR
        cbi   LED_PORT, RED     ; Turn off the ERR LED, when flag is 0
        sbrc  status, STAT_ERR
        sbi   LED_PORT, RED     ; Turn on the ERR LED, when flag is 1
        ret

;******************************************************************************
;*
;* reset
;*
;* DESCRIPTION
;*	 Called at power-on, and on reset.
;*       Perform initialization of the programmer.
;*
;******************************************************************************

reset:
        ldi   temp, high(RAMEND)
        out   SPH, temp
        ldi   temp, low(RAMEND)
        out   SPL, temp

        clr   status
        rcall init_params
        rcall init_LEDs
        rcall u_init

;******************************************************************************
;*
;* waitcmd
;*
;* DESCRIPTION
;*	 Wait for, and execute commands.
;*       Main loop of the programmer.
;*
;******************************************************************************

waitcmd:

;**** Update Status Indicator LEDs ****

        rcall update_LEDs

;**** Cmnd_STK_GET_SYNC ****

        rcall getc

        cpi   u_data, Cmnd_STK_GET_SYNC
        brne  w0

        rcall getc
        ldi   temp, Sync_CRC_EOP
        cpse  u_data, temp
        rjmp  put_nosync

        cbr   status, (1<<STAT_ERR)   ; Clear error status
        rjmp  put_insync_ok

;**** Cmnd_STK_GET_SIGN_ON ****

w0:
        cpi   u_data, Cmnd_STK_GET_SIGN_ON
        brne  w1

        rcall getc
        ldi   temp, Sync_CRC_EOP
        cpse  u_data, temp
        rjmp  put_nosync

        ldi   u_data, Resp_STK_INSYNC
        rcall putc

        ldi   ZH, high(2*sign_on_msg)
        ldi   ZL, low(2*sign_on_msg)    ; Load the 16-bit byte address of msg.
        rcall put_string                ; Send the sign on msg to the host.

        rjmp  put_ok

;**** Cmnd_STK_SET_PARAMETER ****

w1:
        cpi   u_data, Cmnd_STK_SET_PARAMETER
        brne  w2

        rcall getc
        mov   stash, u_data           ; parameter
        rcall getc
        mov   stash2, u_data          ; value

        rcall getc
        ldi   temp, Sync_CRC_EOP
        cpse  u_data, temp
        rjmp  put_nosync

        cpi   stash, Parm_STK_SCK_DURATION
        brne  sp_failed
        mov   sck_durat, stash2       ; Set sck half-period duration
        rjmp  put_insync_ok

sp_failed:
        ldi   u_data, Resp_STK_INSYNC
        rcall putc
        mov   u_data, stash           ; parameter
        rcall putc
        rjmp  put_failed      ; Attempt to set unsupported params is a fail

;**** Cmnd_STK_GET_PARAMETER ****

w2:
        cpi   u_data, Cmnd_STK_GET_PARAMETER
        brne  w3

        rcall getc
        mov   stash, u_data           ; parameter

        rcall getc
        ldi   temp, Sync_CRC_EOP
        cpse  u_data, temp
        rjmp  put_nosync

        ldi   u_data, Resp_STK_INSYNC
        rcall putc

        cpi   stash, Parm_STK_HW_VER
        brne  gp_not_hwver
        ldi   u_data, HWVER
        rjmp  gp_put
gp_not_hwver:
        cpi   stash, Parm_STK_SW_MAJOR
        brne  gp_not_swmajor
        ldi   u_data, SWMAJ
        rjmp  gp_put
gp_not_swmajor:
        cpi   stash, Parm_STK_SW_MINOR
        brne  gp_not_swminor
        ldi   u_data, SWMIN
        rjmp  gp_put
gp_not_swminor:
        cpi   stash, Parm_STK_SCK_DURATION
        brne  gp_not_sckdurat
        mov   u_data, sck_durat       ; Get sck half-period duration
        rjmp  gp_put
gp_not_sckdurat:
        cpi   stash, Parm_STK_PROGMODE
        brne  gp_default
        ldi   u_data, 'S'             ; Serial programming mode
        rjmp  gp_put

gp_default:
        ldi   u_data, 0               ; All params defaults to 0
gp_put:
        rcall putc
        rjmp  put_ok

;**** Cmnd_STK_SET_DEVICE ****

w3:
        cpi   u_data, Cmnd_STK_SET_DEVICE
        brne  w4

        ldi   YH, high(buff)
        ldi   YL, low(buff)
        ldi   cnt, 20
        rcall usart_to_sram   ; Stash data until protocol is verified

        rcall getc
        ldi   temp, Sync_CRC_EOP
        cpse  u_data, temp
        rjmp  put_nosync

        ldi   YH, high(devparams)
        ldi   YL, low(devparams)
        ldi   ZH, high(buff)
        ldi   ZL, low(buff)
        ldi   cnt, 20
        rcall sram_copy       ; Copy device parameters into place

        rcall deter_rst_level         ; Determine the target RST level
        rcall calc_page_addr_mask     ; Calculate the address mask for pages

        sbr   status, (1<<STAT_PS)    ; Set status. Params are set.
        rjmp  put_insync_ok

;**** Cmnd_STK_SET_DEVICE_EXT ****

w4:
        cpi   u_data, Cmnd_STK_SET_DEVICE_EXT
        brne  w5

        rcall getc
        mov   cnt, u_data     ; commandsize
        dec   cnt
sde_parms:
        rcall getc            ; ignore ext parm
        dec   cnt
        brne  sde_parms

        rcall getc
        ldi   temp, Sync_CRC_EOP
        cpse  u_data, temp
        rjmp  put_nosync
        rjmp  put_insync_ok

;**** Cmnd_STK_ENTER_PROGMODE ****

w5:
        cpi   u_data, Cmnd_STK_ENTER_PROGMODE
        brne  w6

        rcall getc
        ldi   temp, Sync_CRC_EOP
        cpse  u_data, temp
        rjmp  put_nosync

        sbrs  status, STAT_PS
        rjmp  put_insync_nodevice     ; Fail if parameters are not set

        rcall drive_rst_pin   ; Control RST pin, and reset target
        rcall s_init          ; Initialize SPI Master (SCK is set LOW)

        ldi   cnt, 8          ; Retry count
ep_pulse_reset:
        rcall reset_off       ; Make a positive pulse on RST
        ldi   temp, 100
        rcall delay_us
        rcall reset_on
        ldi   temp, 20
        rcall delay

        ldi   s_data, 0xAC    ; Issue the command
        rcall s_transmit
        ldi   s_data, 0x53
        rcall s_transmit
        ldi   s_data, 0x00
        rcall s_transmit
        mov   stash, s_data   ; Stash received byte for sync-check
        ldi   s_data, 0x00
        rcall s_transmit

        cpi   stash, 0x53
        breq  ep_insync       ; If we received 0x53 back, then we are in sync
        dec   cnt 
        brne  ep_pulse_reset  ; Otherwise loop, and try again

ep_insync:
        sbr   status, (1<<STAT_PM)    ; Set status: In Programming Mode
        rjmp  put_insync_ok

;**** Cmnd_STK_LEAVE_PROGMODE ****

w6:
        cpi   u_data, Cmnd_STK_LEAVE_PROGMODE
        brne  w7

        rcall getc
        ldi   temp, Sync_CRC_EOP
        cpse  u_data, temp
        rjmp  put_nosync

        rcall s_deinit                ; Let go of the SPI interface lines
        rcall reset_off               ; Allow target to run
        rcall leave_rst_pin           ; Let go of the RST pin

        cbr   status, (1<<STAT_PM)|(1<<STAT_ERR)     ; Update status
        rjmp  put_insync_ok

;**** Cmnd_STK_LOAD_ADDRESS ****

w7:
        cpi   u_data, Cmnd_STK_LOAD_ADDRESS
        brne  w8

        rcall getc
        mov   stash, u_data           ; addr_low
        rcall getc
        mov   stash2, u_data          ; addr_high

        rcall getc
        ldi   temp, Sync_CRC_EOP
        cpse  u_data, temp
        rjmp  put_nosync

        mov   addrl, stash
        mov   addrh, stash2

        rjmp  put_insync_ok

;**** Cmnd_STK_UNIVERSAL ****

w8:
        cpi   u_data, Cmnd_STK_UNIVERSAL
        brne  w9

        rcall getc
        mov   stash, u_data
        rcall getc
        mov   stash2, u_data
        rcall getc
        mov   stash3, u_data
        rcall getc
        mov   stash4, u_data

        rcall getc
        ldi   temp, Sync_CRC_EOP
        cpse  u_data, temp
        rjmp  put_nosync

        mov   s_data, stash
        rcall s_transmit
        mov   s_data, stash2
        rcall s_transmit
        mov   s_data, stash3
        rcall s_transmit
        mov   s_data, stash4
        rcall s_transmit

        ldi   u_data, Resp_STK_INSYNC
        rcall putc
        mov   u_data, s_data
        rcall putc
        rjmp  put_ok

;**** Cmnd_STK_PROG_PAGE ****

w9:
        ldi   temp, Cmnd_STK_PROG_PAGE
        cpse  u_data, temp
        rjmp  w10

        rcall getc
        mov   stash3, u_data  ; bytes_high
        rcall getc
        mov   stash2, u_data  ; bytes_low
        rcall getc
        mov   stash, u_data   ; memtype

        ldi   YH, high(buff)
        ldi   YL, low(buff)
        mov   cnt, stash2     ; This impl. handles all cases by bytes_low
        rcall usart_to_sram   ; Fill buff with data bytes

        rcall getc
        ldi   temp, Sync_CRC_EOP
        cpse  u_data, temp
        rjmp  put_nosync

        ldi   ZH, high(buff)  ; Set pointer to buffer for reading
        ldi   ZL, low(buff)   ;

        mov   cnt, stash2     ; Set available bytes for programming

        cpi   stash, 'F'
        breq  pp_flash        ; Flash is to be programmed
        cpi   stash, 'E'
        breq  pp_eeprom       ; EEPROM is to be programmed
        rjmp  put_failed      ; Undefined mem. type (protocol error)

pp_flash:
        rcall current_page
        movw  prev_pagel, curr_pagel  ; Initialize prev-page as curr-page

pp_flash_pages:
        ldi   s_data, 0x40    ; Load program memory page, low byte
        rcall s_transmit
        mov   s_data, addrh
        rcall s_transmit
        mov   s_data, addrl
        rcall s_transmit
        ld    s_data, Z+
        rcall s_transmit      ; Low byte of the word loaded first

        ldi   s_data, 0x48    ; Load program memory page, high byte
        rcall s_transmit
        mov   s_data, addrh
        rcall s_transmit
        mov   s_data, addrl
        rcall s_transmit
        ld    s_data, Z+
        rcall s_transmit      ; High byte of the word loaded second

        adiw  addrl, 1        ; Increment word address before page-check
 
        rcall current_page    ; Check whether we need to commit the page
        cp    curr_pagel, prev_pagel  ; before the next word load.
        cpc   curr_pageh, prev_pageh
        breq  pp_flash_same_page      ; Next load goes into the same page

        rcall commit_page     ; Commit, since next load goes to next page
        movw  prev_pagel, curr_pagel  ; Update the prev-page tracking

pp_flash_same_page:
        subi  cnt, 2          ; The flash is programmed by words
        brne  pp_flash_pages  ; Continue untill all words are programmed

        rcall commit_page     ; Commit last loads
        rjmp  pp_done         ; Flash programming done

pp_eeprom:
        lds   temp, eepromsizelow
        lds   temp2, eepromsizehigh
        cp    temp, stash2
        cpc   temp2, stash3
        brsh  pp_eeprom_sizeok
        rjmp  put_failed      ; Fail when more bytes in buff than eeprom size

pp_eeprom_sizeok:
        lsl   addrl           ; Convert word address to byte address
        rol   addrh           ;

pp_eeprom_bytes:
        ldi   s_data, 0xC0    ; Write EEPROM memory
        rcall s_transmit
        mov   s_data, addrh
        rcall s_transmit
        mov   s_data, addrl
        rcall s_transmit
        ld    s_data, Z+
        rcall s_transmit      ; Program byte
        rcall poll_rdybsy     ; Poll completion

        adiw  addrl, 1        ; Increment byte address

        dec   cnt             ; Decrement buffer counter
        brne  pp_eeprom_bytes

pp_done:
        rjmp  put_insync_ok   ; Success programming

;**** Cmnd_STK_READ_PAGE ****

w10:
        cpi   u_data, Cmnd_STK_READ_PAGE
        brne  w11

        rcall getc
        mov   stash3, u_data  ; bytes_high
        rcall getc
        mov   stash2, u_data  ; bytes_low
        rcall getc
        mov   stash, u_data   ; memtype

        rcall getc
        ldi   temp, Sync_CRC_EOP
        cpse  u_data, temp
        rjmp  put_nosync

        mov   cnt, stash2

        cpi   stash, 'F'
        breq  rp_flash        ; Flash is to be read
        cpi   stash, 'E'
        breq  rp_eeprom       ; EEPROM is to be read
        rjmp  put_failed      ; Undefined mem. type (protocol error)

rp_flash:
        ldi   u_data, Resp_STK_INSYNC
        rcall putc

rp_flash_words:
        ldi   s_data, 0x20    ; Read program memory, low byte
        rcall s_transmit
        mov   s_data, addrh
        rcall s_transmit
        mov   s_data, addrl
        rcall s_transmit
        ldi   s_data, 0x00
        rcall s_transmit

        mov   u_data, s_data
        rcall putc            ; Send low byte

        ldi   s_data, 0x28    ; Read program memory, high byte
        rcall s_transmit
        mov   s_data, addrh
        rcall s_transmit
        mov   s_data, addrl
        rcall s_transmit
        ldi   s_data, 0x00
        rcall s_transmit

        mov   u_data, s_data
        rcall putc            ; Send high byte

        adiw  addrl, 1        ; Increment word address
        subi  cnt, 2          ; Flash is read by words
        brne  rp_flash_words
        rjmp  rp_done

rp_eeprom:
        ldi   u_data, Resp_STK_INSYNC
        rcall putc

        lsl   addrl
        rol   addrh           ; Convert word address to byte address

rp_eeprom_bytes:
        ldi   s_data, 0xA0
        rcall s_transmit
        mov   s_data, addrh
        rcall s_transmit
        mov   s_data, addrl
        rcall s_transmit
        ldi   s_data, 0x00
        rcall s_transmit

        mov   u_data, s_data
        rcall putc            ; Send data byte

        adiw  addrl, 1        ; Increment byte address
        dec   cnt
        brne  rp_eeprom_bytes

rp_done:
        rjmp  put_ok

;**** Cmnd_STK_READ_SIGN ****

w11:
        cpi   u_data, Cmnd_STK_READ_SIGN
        brne  w12

        rcall getc
        ldi   temp, Sync_CRC_EOP
        cpse  u_data, temp
        rjmp  put_nosync

        ldi   u_data, Resp_STK_INSYNC
        rcall putc

        ldi   s_data, 0x30
        rcall s_transmit
        ldi   s_data, 0x00
        rcall s_transmit
        ldi   s_data, 0x00
        rcall s_transmit
        ldi   s_data, 0x00
        rcall s_transmit

        mov   u_data, s_data
        rcall putc            ; Send high byte

        ldi   s_data, 0x30
        rcall s_transmit
        ldi   s_data, 0x00
        rcall s_transmit
        ldi   s_data, 0x01
        rcall s_transmit
        ldi   s_data, 0x00
        rcall s_transmit

        mov   u_data, s_data
        rcall putc            ; Send middle byte

        ldi   s_data, 0x30
        rcall s_transmit
        ldi   s_data, 0x00
        rcall s_transmit
        ldi   s_data, 0x02
        rcall s_transmit
        ldi   s_data, 0x00
        rcall s_transmit

        mov   u_data, s_data
        rcall putc            ; Send low byte

        rjmp  put_ok

w12:

;**** UNKNOWN Command ****

        rcall getc
        cpi   u_data, Sync_CRC_EOP
        brne  put_nosync

        sbr   status, (1<<STAT_ERR)   ; Set error status

        ldi   u_data, Resp_STK_UNKNOWN
        rcall putc
        rjmp  waitcmd

;**** Replies and looping ****

put_nosync:
        sbr   status, (1<<STAT_ERR)   ; Set error status

        ldi   u_data, Resp_STK_NOSYNC
        rcall putc
        rjmp  waitcmd

put_insync_ok:
        ldi   u_data, Resp_STK_INSYNC
        rcall putc
put_ok:
        ldi   u_data, Resp_STK_OK
        rcall putc
        rjmp  waitcmd

put_failed:
        sbr   status, (1<<STAT_ERR)   ; Set error status

        ldi   u_data, Resp_STK_FAILED
        rcall putc
        rjmp  waitcmd

put_insync_nodevice:
        ldi   u_data, Resp_STK_INSYNC
        rcall putc

        sbr   status, (1<<STAT_ERR)   ; Set error status

        ldi   u_data, Resp_STK_NODEVICE
        rcall putc
        rjmp  waitcmd

;**** The Sign On message ****

sign_on_msg: .db "AVR ISP", 0
