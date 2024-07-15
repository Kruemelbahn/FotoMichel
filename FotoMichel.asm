	list p=PIC12F629
;**************************************************************
;*  	Pinbelegung
;*	-------------------------------------------------------	
;*	GPIO: 	0 Testeingang, aktiviert alle Ausgänge nacheinander
;*		1 Hilfstaster zur Blitzauslösung (0 = Auslösung)
;*		2 1.BlitzLED, Leuchtdauer ca. 1ms
;*		3 Ausgang von Lichtschranke (0 = Auslösung)
;*		4 Ausgang Warnblinker
;*		5 2.BlitzLED, Leuchtdauer ca. 1ms
;*	
;**************************************************************
;
; Hauptdatei = FotoMichel.ASM
;
; M.Zimmermann 18.02.2009
;
; FotoMichel : Blitzelektronik für den fotografierenden Michael
;
; Prozessor PIC 12F629 
;
; Prozessor-Takt intern (~4MHz)
;
; das HEX-File kann erstellt werden durch: build.bat
;
;**************************************************************
; *  Copyright (c) 2018 Michael Zimmermann <http://www.kruemelsoft.privat.t-online.de>
; *  All rights reserved.
; *
; *  LICENSE
; *  -------
; *  This program is free software: you can redistribute it and/or modify
; *  it under the terms of the GNU General Public License as published by
; *  the Free Software Foundation, either version 3 of the License, or
; *  (at your option) any later version.
; *  
; *  This program is distributed in the hope that it will be useful,
; *  but WITHOUT ANY WARRANTY; without even the implied warranty of
; *  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
; *  GNU General Public License for more details.
; *  
; *  You should have received a copy of the GNU General Public License
; *  along with this program. If not, see <http://www.gnu.org/licenses/>.
; *
;**************************************************************
; Includedatei für den 12F629 einbinden

	#include <P12F629.INC>

	ERRORLEVEL      -302   	;SUPPRESS BANK SELECTION MESSAGES

; Configuration festlegen: 
; Power up Timer, kein Watchdog, int-Oscillator, kein Brown out 
	__CONFIG	_MCLRE_OFF & _PWRTE_OFF & _WDT_OFF & _INTRC_OSC_NOCLKOUT & _BODEN_OFF


;#define OSC_CALIB
;**************************************************************
LED1_OFF	MACRO
	BCF	LED_1
	ENDM	

LED1_ON	MACRO
	BSF	LED_1
	ENDM	

LED2_OFF	MACRO
	BCF	LED_2
	ENDM	

LED2_ON	MACRO
	BSF	LED_2
	ENDM	

FLASH_OFF	MACRO
	BCF	Warnblinker
	ENDM	

FLASH_ON	MACRO
	BSF	Warnblinker
	ENDM	

IS_IN_0 MACRO 	port,inport,label
        BTFSC   port,inport
        GOTO    label		; Sprung, wenn Eingang = 1
        CALL    WAIT_1ms	; Entprellzeit
        BTFSC   port,inport
        GOTO    label		; Sprung, wenn Eingang = 1
				; weiter wenn Eingang = 0
	ENDM

;**************************************************************
; EEPROM
#define eeprom_start	2100h

		org	eeprom_start
sw_kennung:	de	"MZ", .5
version:	de	.2

;**************************************************************
#define Test		GPIO,0	; Input
#define Taster		GPIO,1	; Input
#define LED_1		GPIO,2	; Output
#define	LichtSchranke	GPIO,3	; Input
#define Warnblinker	GPIO,4	; Output
#define LED_2		GPIO,5	; Output

	CBLOCK		H'20'
W_save		: 1	; ISR-Zwischenspeicher
Status_save	: 1	; ISR-Zwischenspeicher
counter		: 1	; ISR-Zähler

loops		: 1	; interner Zähler für wait
loops2		: 1	; interner Zähler für wait
loops3		: 1	; interner Zähler für wait
	ENDC

;**************************************************************

	ORG	0x0000
	CLRF	GPIO
	movlw	.61
	movwf	counter		; Counter laden (61/122Hz = 0,5s)
	GOTO	Init

;**************************************************************
        org     0x04 		; InterruptServiceVector 
        movwf   W_save         	; save W 
        swapf   STATUS,W 
        bcf     STATUS, RP0	; Bank 0 
        movwf   Status_save 

;--------------------------------------------------------------
        decfsz  counter, F 	; 0,5 s vorbei? 
        goto    end_isr		; nein, noch nicht 
				; ja: Blinken
	BTFSC	Warnblinker	; Warnblinker High?
	GOTO	Warn_off	;  ja...
				; nein: Low!
	FLASH_ON
	GOTO	load_cnt	
Warn_off:
	FLASH_OFF
	
load_cnt:
	movlw	.61
	movwf	counter		; Counter laden (61/122Hz = 0,5s)
;--------------------------------------------------------------
end_isr:
	bcf     INTCON, T0IF 

        ; End ISR, restore context and return to the main program 
        swapf   Status_save, w 
        movwf   STATUS 
        swapf   W_save,f	; restore W without corrupting STATUS 
        swapf   W_save,w 
        retfie 
;**************************************************************

Init:
#ifdef	OSC_CALIB
	; Oszillatorkalibrierung:
	CALL	0x3FF
	banksel	OSCCAL
	MOVWF	OSCCAL
	banksel	GPIO
#endif

	MOVLW	B'00000111'	; CM0:CM2 setzen (Comparator off)
	MOVWF	CMCON

	; Portinitialisierung:
	banksel	TRISIO

	MOVLW	B'00001011'	; input = 1, output = 0
	MOVWF	TRISIO
	MOVLW	B'00000011'	; internal Pull-Up
	MOVWF	WPU

	; Initialisierung des Timer0 
        ; TIMER0 muß eingestellt sein!  
        ; 32:1 bei 4 MHz -> 31,25 kHz 
        ; Überlauf nach 8,192 ms 
        ; 122 int in 1 Sekunde 
        bcf     OPTION_REG, PS0 ; Vorteiler 32:1 
        bcf     OPTION_REG, PS1 
        bsf     OPTION_REG, PS2 
        bcf     OPTION_REG, PSA ; Vorteiler am Timer0 
        bcf     OPTION_REG, T0CS; interner Takt/4 
	bcf	OPTION_REG, NOT_GPPU; GPPU löschen

	banksel	INTCON

        ; Interrupt freigeben
	bcf     INTCON, T0IF  	; Int-Flag löschen 
        bsf     INTCON, T0IE    ; Timer0-Int ein 
        bsf     INTCON, GIE     ; Int aktiviert 

	call	FLASH_IT	; Begrüßung :-)

;..............................................................
Start:	IS_IN_0	Taster,CHK_LS

	call	FLASH_IT
	
TA_1:	BTFSS	Taster
	GOTO	TA_1

	GOTO	Start

;..............................................................
CHK_LS:	IS_IN_0	LichtSchranke,Start

	call	FLASH_IT
	
LS_1:	BTFSS	LichtSchranke
	GOTO	LS_1

	GOTO	Start

;**************************************************************
; LED's blitzen - auch beim Einschalten
FLASH_IT:
	LED1_ON
	CALL	WAIT_1ms
	LED1_OFF

	CALL	WAIT_250ms	; nach 250ms blitzt auch der zweite :-)

	LED2_ON
	CALL	WAIT_1ms
	LED2_OFF

	goto	WAIT_2s		; 2 Sekunden Pause 

;**************************************************************
; Warteschleife 1 ms für einen 4MHz-PIC-Takt 
WAIT_1ms: 
        movlw   .110		; Zeitkonstante für 1ms 
        movwf   loops 

Wai1:   nop  
        nop 
        nop 
        nop 
        nop 
        nop 
        decfsz  loops, F 	; 1 ms vorbei? 
        goto    Wai1		; nein, noch nicht 
	return

; Warteschleife 250 ms für einen 4MHz-PIC-Takt 
WAIT_250ms: 
        movlw   .250 
        movwf   loops2 

Wai2:	call	WAIT_1ms

        decfsz  loops2, F 	; 250 ms vorbei? 
        goto    Wai2		; nein, noch nicht 
	return

; Warteschleife 2s für einen 4MHz-PIC-Takt 
WAIT_2s:
        movlw   .8 
        movwf   loops3 

Wai3:	call	WAIT_250ms

        decfsz  loops3, F 	; 2 s vorbei? 
        goto    Wai3		; nein, noch nicht 
	return

;**************************************************************
; Kalibrierwert für Oszillator
#ifdef	OSC_CALIB
	ORG	0x03FF
	RETLW	0x80		; center frequency
#endif

	end
; end of file
