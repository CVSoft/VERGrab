#include "ti83plus.inc"
#define BUF_SIZE 32
.binarymode TI8X

 .org userMem-2
 .db t2ByteTok, tAsmCmp      ; header stuff
 bcall(_RclAns)              ; load Ans into OP1, we use it for the machine ID
 bcall(_Trunc)               ; remove fractional bits
 bcall(_ConvOP1)             ; put it in a and de
 ld a,e                      ; shouldn't be necessary to do this
 ld (MachineID),a            ; put the desired Machine ID in its little memory spot
 ld a,$2d                    ; load command for VER
 ld (CommandID),a            ; set the command ID to VER
 AppOnErr(VERFailedSend)     ; let's handle the error here, it's easier
 ld hl,MachineID             ; send the packet from the start
 call Send4Bytes             ; send the VER command
 ld hl,Response              ; check for a response
 call Receive4Bytes          ; grab some bytes
 AppOffErr                   ; shut off the error handler
 ld a,(Response+1)           ; check for $56 positive ACK
 cp $56                      ; which should be there
 jp nz,VERNotFiftySix        ; and whine if it doesn't
 ld a,$09                    ; put CTS command ID in a
 ld (CommandID),a            ; set command ID for CTS
 ld hl,MachineID             ; and point to the beginning of the packet
 call Send4Bytes             ; send the CTS command
 jp c,CTSFailedSend          ; go to error handler
 call ResetResponse          ; set response to zero to make sure it's fresh
 ld hl,Response              ; get address for the response buffer
 call Receive4Bytes          ; try to receive the CTS acknowledge
 jp c,CTSFailedSend          ; go to error handler if fail. Otherwise we have data to fetch
 call ResetResponse          ; clear the response storage again
 ld hl,Response              ; we're going to receive another header
 call Receive4Bytes          ;   and put it in Response
 ld a,(Response+1)           ; check for $15 DATA packet
 cp $15                      ; which should be there
 jp nz,CTSNotFifteen         ; and whine if it doesn't
 ld a,(Response+2)           ; this time, we need the length
 ld (lenList),a              ; store this now, i think it gets killed
 ld b,a                      ; which will feed a djnz loop (len around $e)
 cp BUF_SIZE                 ; check for buffer overrun
 jp nc,VEROverrun            ;   and just crash if it would. 
 ld hl,scratchMem            ; that receives data into scratchMem
 call ReceiveManyBytes       ; receive amount of data in lenList
 jp c,VERIncomplete          ; if it fails, throw an error (we want the whole packet)
 ld a,$56                    ; set a command ID for acknowledgemet
 ld (CommandID),a            ; put it in memory
 ld hl,MachineID             ; set hl to start of final ACK packet
 AppOnErr(FinalACKIgnoreErr) ; don't care if it fails, we have our data
 call Send4Bytes             ; send ACK
 AppOffErr                   ; turn off the error handler
FinalACKIgnoreErr:           ; which would just land here anyways
 
 ; in theory, scratchMem now contains the received data, all
 ; registers destroyed. 
 
 ld hl,L1name                ; name of L1 for FindSym
 rst rMov9ToOP1              ; put L1's name in OP1
 rst rFindSym                ; and look it up
 jr c,createList             ; skip deleting it if already deleted
 bcall(_DelVarArc)           ; delete it should it exist
createList:                  ; if we're jumping here, the list didn't exist
 ld hl,byteCounter           ; load length from number of values stored to buffer
 ld a,(hl)                   ; put saved value for lenList in a
 ld l,a                      ; and set hl = a
 ld h,0                      ; we don't like h very much, do we
 bcall(_CreateRList)         ; create list, data at de
 inc de                      ; the first two bytes are length data,
 inc de                      ; so we inc de to get to the first element
 ld c,0                      ; ??
 ld a,(byteCounter)          ; the ACTUAL list length, to ensure data in buffer is accurate
 ld b,a                      ; set it as the loop counter
 cp 0                        ; before we go, make sure it isn't 0
 jp z,ListOverrun            ;   or it'll hit djnz and become 255, which is bad.
 ld hl,scratchMem            ; loads list with bytes from scratchMem to scratchMem+lenList
loadList:                    ; begin loop
 push bc                     ; bc contains our loop counter
 push hl                     ; hl contains our buffer position, but list writing will destroy this
 push de                     ; de contains the address of our list element
 ld a,(hl)                   ; hl points to a buffer position in scratchMem, a contains its value
 ld l,a                      ; we need this in hl, not a
 ld h,0                      ; hl now contains a
 bcall(_SetXXXXOP2)          ; unlike _SetXXOP1, this reads from hl
 bcall(_OP2ToOP1)            ;   and writes to OP2 instead of OP1
 pop de                      ; we need de back, so we can put OP1 somewhere useful
 bcall(_MovFrOP1)            ; copy OP1 to list position, this routine automatically increments de by 9
 pop hl                      ; recover our buffer position
 inc hl                      ; and set it to the next byte
 pop bc                      ; recover our loop counter
 djnz loadList               ; and continue the loop
CleanExit:                   ; is this label used? it's great for debugging, though.
 ld a,(Response)             ; prepare to return the received Machine ID as positive int
 ld h,0                      ; set h to 0
 ld l,a                      ; shove response in l
 bcall(_SetXXXXOP2)          ; set OP2 to hl
 bcall(_OP2ToOP1)            ; move OP2 to OP1
 bcall(_StoAns)              ; so we can put it in Ans
 ret                         ; and return that as our result


Send4Bytes: ; sends 4 bytes from hl, carry flag set if failure
 push bc                     ; preserve because we're probably inside a loop
 push de                     ; preserve because we're probably copying from a buffer
 ld a,(hl)                   ; get the first byte we need to send
 bcall(_SendAByte)           ; send the first byte
 inc hl                      ;   point to the next one
 ld a,(hl)                   ;   and load its data
 bcall(_SendAByte)           ; send the second byte
 inc hl                      ;   point to the next one
 ld a,(hl)                   ;   and load its data
 bcall(_SendAByte)           ; send the third byte
 inc hl                      ;   point to the next one
 ld a,(hl)                   ;   and load its data
 bcall(_SendAByte)           ; send the fourth byte
 pop de                      ; recover this register
 pop bc                      ; recover our registers and be stack neutral
 scf                         ; set carry flag 1
 ccf                         ; flip it to 0
 ret                         ; exit the subroutine


Receive4Bytes: ; receive 4 bytes starting at hl, destroy af/hl
 push bc                     ; save this register for loop counters
 push de                     ; save this register for data copying
 bcall(_RecAByteIO)          ; receive first byte over link into a
 ld (hl),a                   ;   save the result
 inc hl                      ;   and point to the next destination
 bcall(_RecAByteIO)          ; receive second byte over link into a
 ld (hl),a                   ;   save the result
 inc hl                      ;   and point to the next destination
 bcall(_RecAByteIO)          ; receive third byte over link into a
 ld (hl),a                   ;   save the result
 inc hl                      ;   and point to the next destination
 bcall(_RecAByteIO)          ; receive fourth byte over link into a
 ld (hl),a                   ;   save the result, no need to increment
 pop de                      ; recover this register
 pop bc                      ; recover our registers and be stack neutral
 scf                         ; set carry flag 1
 ccf                         ; flip it to 0
 ret                         ; and exit subroutine with that flag

ReceiveManyBytes: ; receive lenList bytes over link into mem at hl
 ; This routine also keeps track of how many bytes were
 ; actually received, up to the number requested.
 ; This can be used to make sure an entire packet was
 ; received, per the header. 
 push bc                       ; save this, we may be in a loop
 push de                       ; save this, we may be copying data
 call ResetByteCounter         ; reset the counter
 ld c,0                        ; ??
 ld a,(lenList)                ; recover lenList from RAM
 ld b,a                        ;   and use it as loop counter
ReceiveBytesLoop:              ; beginning of receiving loop
 push bc                       ; _RecAByteIO overwrites loop counter
 push hl                       ; i think AppOnErr overwrites
 AppOnErr(ReceiveBytesFailure) ; if we crash, save what we have
 bcall(_RecAByteIO)            ; receive one byte into a
 ld (tempByte),a               ; keep it out of harm's way
 AppOffErr                     ; we can't hit ERR:LINK anymore
 pop hl
 pop bc                        ; recover loop counter
 ld a,(tempByte)
 ld (hl),a
 inc hl                        ; and point at the next byte
 call CountAnotherByte         ; update our received byte count
 djnz ReceiveBytesLoop         ; continue the loop
 scf                           ; set carry flag
 ccf                           ; then flip it
ReceiveBytesExit:
 pop de                        ; needs to be stack neutral
 pop bc                        ; so we recover these registers
 ret                           ; clean exit will have no carry flag

ReceiveBytesFailure:           ; stack position? idk.
 pop bc                        ; bc is in the stack, could be used to find error location (bytes to go in b)
 scf                           ; set the carry flag because we failed
 jr ReceiveBytesExit           ; exit the subroutine

ResetByteCounter:
 push hl                       ; preserve hl
 ld hl,byteCounter             ; load address of byte counter
 ld (hl),0                     ; zero it
 pop hl                        ; recover hl
 ret                           ; and exit

CountAnotherByte:
 push hl            ; whatever calls this needs hl
 ld hl,byteCounter  ; get address of the counter
 inc (hl)           ; increment it
 pop hl             ; recover hl
 ret                ; exit subroutine

ResetResponse:  ; set Response to zero, preserve registers
 push af        ; preserve a
 push hl        ; preserve hl
 ld hl,Response ; load address to reset
 ld a,0         ; and we will fill it with zero
 ld (hl),a      ; faster than a loop
 inc hl         ; .
 ld (hl),a      ; ..
 inc hl         ; ...
 ld (hl),a      ; ...
 inc hl         ; ..
 ld (hl),a      ; .
 pop hl         ; restore values
 pop af         ; of registers
 ret

SomethingCrashed:
 ld h,0             ; hl = a, set h first
 ld l,a             ; hl = a, then set l
 bcall(_SetXXXXOp2) ; set OP2 to hl
 bcall(_OP2ToOP1)   ; move OP2 to OP1
 bcall(_InvOP1S)    ; negate it
 bcall(_StoAns)     ; set Ans to OP1
 ret                ; clean exit program

; a variety of error handling endpoints. Ans gets set to -a
VERFailedSend:        ; ERR:LINK caught when sending VER request
 ld a,1
 jr SomethingCrashed
VERNotFiftySix:       ; Other device responded but did not acknowledge
 ld a,2
 jr SomethingCrashed
CTSFailedSend:        ; ERR:LINK caught when sending CTS
 ld a,3
 jr SomethingCrashed
CTSNotFifteen: ; yeah, it's actually Fifteen. Copy/paste is easier.
 ld a,4
 jr SomethingCrashed
VEROverrun:
 ld a,5
 jr SomethingCrashed
VERIncomplete:
 ld a,6
 jr SomethingCrashed
ListOverrun:
 ld a,7
 jr SomethingCrashed

L1name:
 .db ListObj,tVarLst,tL1,0,0
; the next 4 bytes are used for the link send routines
MachineID:         ; machine ID used by calculator
 .db 0
CommandID:         ; command ID sent by calculator
 .db 0
Length:            ; not written to, but used in link-send
 .db 0,0
lenList:           ; Length of list the other device is clear to send
 .db 0
byteCounter:       ; actual number of bytes received into scratchMem
 .db 0
Response:          ; The headers sent by the other device
 .ds 4             ; keep these together
scratchMem:        ; so that the CTS-ACK and
 .ds BUF_SIZE      ; VER response are together
tempByte:          ; safe place to hide received data during error handling
 .db 0