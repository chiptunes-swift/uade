????                              ;               T

*************************************************************************
* This is the main Assembler file to Assemble EMS V6 modules. Place the *
*  desired module file in an include line at the label called "module"	*
*-----------------------------------------------------------------------*
*MusicPlayer coding by Sean Connolly. AudioMixer code by Jarno Paananen.*
*************************************************************************

; The module files are completely detachable from the main code, and can be
; anywhere within both chipram/fastram areas! The audio mixer will fetch
; samples from anywhere in valid ram areas and mix them into buffers within
; the chipram range. Obviously, the processing time will reduce by as much
; as 50% providing the module is being driven on a machine under 32-bit
; fastram. All memory (de)allocations are performed by the mixer routine.

; The audio mixer requires a fair whack of processor power, but the player
; is very fast (doesn't use more than 20 scanlines on my A4000/ec030 when
; processing 32 channels). Also the audio buffers are circular buffers, and
; the audio is filled in well in advance of being played.

; There is also an audio latency between the filling of the audio buffers
; and the audible sound being output. This can be as much as 4 or 5 seconds,
; depending on the buffer size settings and the selected mixing rate.

; By setting a buffer size of 32K and a 28Khz mixing rate, the latency is
; marginally over 1 second.

asmone = 0

MONO = 1
STEREO = 2
SURROUND = 3
REAL = 4
STEREO14 = 5

BUFFER	equ	32*1024		;Audio mixing buffer size is 32K.

fforwrd	equ	0	;Turn fast forward checks on.

_ciaa	=	$bfe001
_ciab	=	$bfd000

	incdir	nfs:deli/
	include	RMacros.i
	include	custom.i
	incdir	include:
	include	exec/memory.i
	include	exec/execbase.i
	include	LVO3.0/exec_lib.i
	include	LVO3.0/dos_lib.i
	include	LVO3.0/cia_lib.i
	include	hardware/cia.i
	include	include:misc/deliplayer.i

	section	ems_player,code
	if asmone=1
	jmp	test
	endif
	moveq	#-1,d0
	rts
	dc.b	'DELIRIUM'
	dc.l	table
	even

table	dc.l	DTP_PlayerName,emsname
	dc.l	DTP_Creator,emscreator
	dc.l	DTP_DeliBase,eaglebase
	dc.l	DTP_Check2,Check2
;	dc.l	DTP_SubSongRange,SubSongRange
	dc.l	DTP_InitPlayer,InitPlayer
	dc.l	DTP_InitSound,InitSound
	dc.l	DTP_StartInt,StartInt
	dc.l	DTP_StopInt,StopInt
	dc.l	DTP_EndSound,EndSound
	dc.l	DTP_EndPlayer,EndPlayer
	dc.l	$80004474,2			* songend support
	dc.l	0
emsname	dc.b	'EMS v6',0
emscreator	dc.b	'EMS v6 player by Sean Connolly,',10
	dc.b	'Audio mixer code by Jarno Paananen',10
	dc.b	'Adapted for UADE by shd',0
uadename	dc.b	'uade.library',0
	even

eaglebase	dc.l	0
moduleptr	dc.l	0
mixing_mode	dc.l	STEREO
mixing_rate	dc.l	14000
volume_boost	dc.l	0
uadebase	dc.l	0
end_song_bit	dc.l	0

Check2	move.l	dtg_ChkData(a5),a0
	move.l	a0,moduleptr
	bsr	CheckSong
	rts

cfgfile	dc.b	'ENV:EaglePlayer/ems_v6.cfg',0
	even
cfgbuffer	ds.b	256

* sample cfgfile format:
* 1
* 14000
* 2
*
* 1 means mono (2 would mean stereo)
* 14000 is mixing rate
* 2 is volume boost (in range 0-8)

InitPlayer	push	all
	move.l	dtg_AudioAlloc(a5),A0
	jsr	(A0)

	move.l	4.w,a6
	lea	uadename(pc),a1
	moveq	#0,d0
	jsr	_LVOOpenLibrary(a6)
	move.l	d0,uadebase

	bsr	uade_time_critical_on

	move.l	dtg_DOSBase(a5),a6
	move.l	#cfgfile,d1
	move.l	#1005,d2		* MODE_OLDFILE
	jsr	_LVOOpen(a6)
	move.l	d0,d1
	beq	dont_read_cfgfile
	move.l	d1,-(a7)
	move.l	#cfgbuffer,d2
	move.l	#256,d3
	jsr	_LVORead(a6)
	push	all
	lea	cfgbuffer,a0

	move.b	(a0)+,d0
	sub.b	#$30,d0
	and.l	#$7,d0
	move.l	d0,mixing_mode

	move.b	(a0)+,d0
	cmp.b	#10,d0
	bne.b	illegal_config_file

	moveq	#0,d0
	moveq	#0,d1
digit_loop	move.b	(a0)+,d1
	cmp.b	#10,d1
	beq.b	end_digit_loop
	cmp.b	#$20,d1
	beq.b	end_digit_loop
	cmp	#$30,d1
	blt.b	illegal_config_file
	cmp	#$39,d1
	bgt.b	illegal_config_file
	sub.b	#$30,d1
	mulu	#10,d0
	add.b	d1,d0
	bra.b	digit_loop
end_digit_loop	move.l	d0,mixing_rate

	moveq	#3-1,d7
volume_boost_l	move.b	(a0)+,d0
	moveq	#$f,d1
	and.l	d0,d1
	and	#$f0,d0
	cmp	#$30,d0
	bne.b	not_a_digit
	move.l	d1,volume_boost
	moveq	#0,d7
not_a_digit	dbf	d7,volume_boost_l

illegal_config_file
	pull	all
	move.l	(a7)+,d1
	jsr	_LVOClose(a6)
dont_read_cfgfile
	pull	all
	moveq	#0,d0
	rts

report_song_end	push	all
	st	end_song_bit
	if asmone=0
	move.l	eaglebase(pc),a5
	move.l	dtg_SongEnd(a5),a0
	jsr	(a0)
	endif
	pull	all
	rts

EndSound	push	all
	lea	$dff000,a2
	moveq	#0,d0
	move	d0,aud0vol(a2)
	move	d0,aud1vol(a2)
	move	d0,aud2vol(a2)
	move	d0,aud3vol(a2)
	move	#$000f,dmacon(a2)
	pull	all
	rts

EndPlayer	move.l	dtg_AudioFree(a5),A0
	jsr	(a0)
	rts

	if asmone=1
test	lea	Module,a0
	move.l	a0,moduleptr
	bsr	CheckSong
	tst.l	d0
	bpl.b	song_check_ok
	rts
song_check_ok	move.l	moduleptr,a0
	moveq	#0,d0		* subsong
	bsr	EMS_init
	bsr	StartInt		;Start the player.
waitlbutton	move	$dff006,$dff180
	tst.l	end_song_bit
	bne.b	test_end_song
	btst	#6,$bfe001
	bne.b	waitlbutton
test_end_song	bsr	StopInt
	rts
	endif

CheckSong	cmp.l	#"E.M.",(a0)
	bne.b	check_failed
	cmp.l	#"S. V",4(a0)
	bne.b	check_failed
	move.l	8(a0),d1
	swap	d1
	cmp.w	#"6.",d1
	bne.b	check_failed
	moveq	#0,d0
	rts
check_failed	moveq	#-1,d0
	rts

	* EMS_init call
	* a0 pointer to the module
	* d0 subsong number (0-31)
InitSound	move.l	moduleptr,a0
	moveq	#0,d0
	move	dtg_SndNum(a5),d0
	bsr	EMS_init

	clr.l	uade_restart_cmd
	clr.l	uade_stop_cmd
	clr.l	end_song_bit

	rts

StartInt	push	all
	* d1 mixing mode (MONO, STEREO, ...)
	* d2 mixing rate
	* d3 volume boost (0-8)
	** "playmode" is one of the following:
	**	"STEREO14", "STEREO", "SURROUND", "REAL", "MONO".
	**
	** The maximum rate for the system is 28000 (28KHZ), and going above
	** or below this limit will cause either slowdown or skipping of the
	** sample mixing, so don't go above those limits.
	move.l	mixing_mode,d1		;Set the playmode to STANDARD STEREO.
	move.l	mixing_rate,d2		;Set the mixing rate to nnn Khz.
	move.l	volume_boost,d3		;Set volume boost up to 8.
	bsr	start_interrupt
	pull	all
	rts

StopInt	push	all
	bsr	stop_interrupt
	pull	all
	rts

uade_time_critical_on
	pushr	d0
	move.l	uadebase(pc),d0
	beq.b	no_uade_1
	push	all
	move.l	d0,a6
	moveq	#-1,d0
	jsr	-6(a6)
	pull	all
no_uade_1	pullr	d0
	rts

uade_time_critical_off
	pushr	d0
	move.l	uadebase(pc),d0
	beq.b	no_uade_2
	push	all
	move.l	d0,a6
	moveq	#0,d0
	jsr	-6(a6)
	pull	all
no_uade_2	pullr	d0
	rts

;PS3M Replay version 0.942/020+ / 30.10.1994
;Copyright (c) Jarno Paananen a.k.a. Guru / S2 1994-95

;Some portions based on STMIK 0.9? by Sami Tammilehto / PSI of Future Crew

;ASM-ONE 1.20 or newer is required unless disable020 is set to 1, when
;at least 1.09 (haven't tried older) is sufficient.

*****************************************************************************
** Contraption by K-P / HpD / iNS (14.12.1995)
** What's left: killermode, 000/020+ mixingroutines, all 5 playmodes, and
** the S3M replayer.
*****************************************************************************

;---- CIA Interrupt ----

mtS3M = 1

ENABLED = 0
DISABLED = 1

* Mixauspuskurin koko

disable020	=	0




mStart		equ	0	;(LONG) Start of sample.
mLength		equ	4	;(LONG) Length of sample.
mLStart		equ	8	;(LONG) Start of loop.
mLLength	equ	12	;(LONG) Length of loop.
mPeriod		equ	16	;(WORD) Period value.
mVolume		equ	18	;(WORD) Channel volume.
mFPos		equ	20	;(LONG) Fill position (clear it at start).
mLoop		equ	24	;(BYTE) Loop sound flag.
mOnOff		equ	25	;(BYTE) Channel mute on/off.
mPanning	equ	26	;(BYTE) Stereo panning value (0=off).
Filler		equ	27	;(BYTE) Sample filler flag.

mChanBlock_SIZE	equ	28	;Structure size.


;	/*
;	** Let's define the equates to allow the mixer parameters to access
;	** the data storage structure.
;	*/

vbrr		equ	0	;(LONG) *
olev4		equ	4	;(LONG) *
olev3		equ	8	;(LONG) *
vtabaddr	equ	12	;(LONG) *
playpos		equ	16	;(LONG) *
bufpos		equ	20	;(LONG) *
buffSize	equ	24	;(LONG) *
buffSizeMask	equ	28	;(LONG) *

bytesperframe	equ	32	;(WORD) *
bytes2do	equ	34	;(WORD) *
todobytes	equ	36	;(WORD) *
bytes2music	equ	38	;(WORD) *

mixad1		equ	40	;(LONG) *
mixad2		equ	44	;(LONG) *
cbufad		equ	48	;(LONG) *
opt020		equ	52	;(WORD) *

mixingrate	equ	54	;(LONG) *
mixingperiod	equ	58	;(LONG) *
vboost		equ	62	;(LONG) *
pmode		equ	66	;(WORD) *

PS3M_master	equ	68	;(WORD) *

audiorate	equ	70	;(LONG) *
mrate		equ	74	;(LONG) *
mrate50		equ	78	;(LONG) *

fformat		equ	82	;(WORD) *
tempo		equ	84	;(WORD) *
chans		equ	86	;(WORD) *
maxchan		equ	88	;(WORD) *
mtype		equ	90	;(WORD) *
clock		equ	92	;(LONG) *
globalVol	equ	96	;(WORD) *

tbuf		equ	98	;(LONG) *
tbuf2		equ	102	;(LONG) *
buff1		equ	106	;(LONG) *
buff2		equ	110	;(LONG) *
buff3		equ	114	;(LONG) *
buff4		equ	118	;(LONG) *
buff14		equ	122	;(LONG) *
vtab		equ	126	;(LONG) *
dtab		equ	130	;(LONG) *
dtabsize	equ	134	;(LONG) *
numchans	equ	138	;(WORD) *
vbpulse		equ	140	;(WORD) *
ciabasea	equ	142	;(LONG) *
ciabaseb	equ	146	;(LONG) *
ciabase		equ	150	;(LONG) *
timerhi		equ	154	;(BYTE) *
timerlo		equ	155	;(BYTE) *
ciaddr		equ	156	;(LONG) *
whichtimer	equ	160	;(BYTE) *

pushm	macro
	ifc	"\1","all"
	movem.l	d0-a6,-(sp)
	else
	movem.l	\1,-(sp)
	endc
	endm

popm	macro
	ifc	"\1","all"
	movem.l	(sp)+,d0-a6
	else
	movem.l	(sp)+,\1
	endc
	endm

pop	macro
	movem.l	(sp)+,\1
	endm

lob	macro
	jsr	_LVO\1(a6)
	endm

iword	macro
	ror	#8,\1
	endm

ilword	macro
	ror	#8,\1
	swap	\1
	ror	#8,\1
	endm

tlword	macro
	move.b	\1,\2
	ror.l	#8,\2
	move.b	\1,\2
	ror.l	#8,\2
	move.b	\1,\2
	ror.l	#8,\2
	move.b	\1,\2
	ror.l	#8,\2
	endm

tword	macro
	move.b	\1,\2
	ror	#8,\2
	move.b	\1,\2
	ror	#8,\2
	endm

	illegal
	bra.w	start_interrupt
	bra.w	stop_interrupt
	bra.w	toggle_channel
	bra.w	set_vbvalue
herepoint:
	dc.l	cha0-herepoint

set_vbvalue:
	movem.l	d0-a6,-(sp)		;Save these two registers.
	lea	data(pc),a5		;Pointer to data storage structure.
	and.l	#$0f,d0			;Limit to 0-15.
	move.l	d0,vboost(a5)		;Set up the volume boost.
	bsr	makedivtabs		;Make the division tables.
	movem.l	(sp)+,d0-a6		;Restore registers.
	rts

struct_size	equ	60
EMS_muteflag	equ	44

toggle_channel:
	movem.l	d0/a0,-(sp)		;Save D0 and A0 to stack.
	lea	EMS_structure(pc),a0	;Pointer to the base of structure.
	and.l	#$1f,d0			;Isolate channel info.
	mulu	#struct_size,d0		;* channel size.
	lea	(a0,d0.l),a0		;Index to channel base.
	eor.b	#1,EMS_muteflag(a0)	;Toggle the mute on/off flag.
	movem.l	(sp)+,d0/a0		;Restore D0 and A0 from stack.
	rts


start_interrupt	move.w	d1,-(sp)		;Store the playmode on the stack.
	move.l	d2,-(sp)		;Store the mixing rate on the stack.
	move.l	d3,-(sp)		;Store the volume boost on the stack.
;	/*
;	** Next, point to the data structure and initialize some of the
;	** audio mixer parameters and the desired play mode.
;	*/
	lea	data(pc),a5
	move.l	(sp)+,vboost(a5)	;Volume boost from 0-8.
	move.l	(sp)+,mixingrate(a5)	;Set the mixing rate.
	move.w	(sp)+,pmode(a5)		;Restore and set the playmode value.
	move	#64,PS3M_master(a5)	;Master volume level.
	move	#1,fformat(a5)		;Sample format is signed samples.

	move.l	#14317056/4,clock(a5)	;Clock constant
	move	#64,globalVol(a5)	;Set this global volume too.

*** Alloc mem

	move.l	#BUFFER,d0
	move.l	d0,buffSize(a5)
	subq.l	#1,d0
	move.l	d0,buffSizeMask(a5)
	lsl.l	#8,d0
	move.b	#$ff,d0
	lea	buffSizeMaskFF(pc),a3
	move.l	d0,(a3)

	move.l	4.w,a6
	move.l	#1024*4*2,d0
	move.l	#MEMF_PUBLIC!MEMF_CLEAR,d1
	lob	AllocMem
	move.l	d0,tbuf(a5)
	beq.w	_memerr
	add.l	#1024*4,d0
	move.l	d0,tbuf2(a5)	

	move.l	buffSize(a5),d0
	move.l	#MEMF_CHIP!MEMF_CLEAR,d1
	lob	AllocMem
	move.l	d0,buff1(a5)
	beq.w	_memerr

	move.l	buffSize(a5),d0
	move.l	#MEMF_CHIP!MEMF_CLEAR,d1
	lob	AllocMem
	move.l	d0,buff2(a5)
	beq.w	_memerr

	move.l	#66*256,d7			; Volume tab size

	cmp	#REAL,pmode(a5)
	beq.b	.varaa
	cmp	#STEREO14,pmode(a5)
	bne.b	.ala2

.varaa	move.l	buffSize(a5),d0
	move.l	#MEMF_CHIP!MEMF_CLEAR,d1
	lob	AllocMem
	move.l	d0,buff3(a5)
	beq.b	_memerr

	move.l	buffSize(a5),d0
	move.l	#MEMF_CHIP!MEMF_CLEAR,d1
	lob	AllocMem
	move.l	d0,buff4(a5)
	beq.b	_memerr

.ala2	cmp	#STEREO14,pmode(a5)
	beq.b	_bit14

	moveq	#0,d0
	move	maxchan(a5),d1
	move.l	#256,d2
	subq	#1,d1
_l	add.l	d2,d0
	add.l	#256,d2
	dbf	d1,_l

	move.l	d0,dtabsize(a5)
	moveq	#MEMF_PUBLIC,d1
	lob	AllocMem
	move.l	d0,dtab(a5)
	beq.b	_memerr	
	bra.b	_alavaraa

_bit14	move.l	#66*256*2,d7			; Volume tab size

	move.l	#64*1024,d0
	moveq	#MEMF_PUBLIC,d1
	lob	AllocMem
	move.l	d0,buff14(a5)
	bne.b	_alavaraa

_memerr	bsr.w	s3end

	moveq	#-1,d0			* ERROR: no mem!
	rts

_alavaraa
	move.l	d7,d0
	moveq	#MEMF_PUBLIC,d1
	lob	AllocMem
	move.l	d0,vtab(a5)
	beq.b	_memerr

	add.l	#255,d0
	and.l	#~$ff,d0
	move.l	d0,vtabaddr(a5)


	bsr.w	s3mPlay
	moveq	#0,d0			* All ok
	rts






** End music

s3end

	lea	data(pc),a5

	clr.l	vtabaddr(a5)
	move.l	4.w,a6
	move.l	tbuf(a5),d0
	beq.b	.eumg
	move.l	d0,a1
	move.l	#1024*4*2,d0
	lob	FreeMem
	clr.l	tbuf(a5)
	clr.l	tbuf2(a5)

.eumg	move.l	buff1(a5),d0
	beq.b	.eimem
	move.l	d0,a1
	move.l	buffSize(a5),d0
	lob	FreeMem
	clr.l	buff1(a5)

.eimem	move.l	buff2(a5),d0
	beq.b	.eimem1
	move.l	d0,a1
	move.l	buffSize(a5),d0
	lob	FreeMem
	clr.l	buff2(a5)

.eimem1	move.l	buff3(a5),d0
	beq.b	.eimem2
	move.l	d0,a1
	move.l	buffSize(a5),d0
	lob	FreeMem
	clr.l	buff3(a5)

.eimem2	move.l	buff4(a5),d0
	beq.b	.eimem3
	move.l	d0,a1
	move.l	buffSize(a5),d0
	lob	FreeMem
	clr.l	buff4(a5)

.eimem3	move.l	buff14(a5),d0
	beq.b	.eimem4
	move.l	d0,a1
	move.l	#64*1024,d0
	lob	FreeMem
	clr.l	buff14(a5)

.eimem4	move.l	vtab(a5),d0
	beq.b	.eimem5
	move.l	d0,a1
	move.l	#66*256,d0
	cmp	#STEREO14,pmode(a5)
	bne.b	.cd
	add.l	d0,d0
.cd	lob	FreeMem
	clr.l	vtab(a5)

.eimem5	move.l	dtab(a5),d0
	beq.b	.eimem6
	move.l	d0,a1
	move.l	dtabsize(a5),d0
	lob	FreeMem
	clr.l	dtab(a5)

.eimem6	rts


***********************************
* PS3M 0.959 Audio mixer routines *
*    ? 1994-95 Jarno Paananen	  *
*      All rights reserved	  *
***********************************

;	/*
;	** LEVEL 4 AUDIO IRQ HANDLER.
;	*/

lev4	move.l	a0,-(sp)
	lea	data+playpos(pc),a0
	clr.l	(a0)
	move.w	#$80,$dff09c
	move.l	(sp)+,a0
	nop
	rte

;	/*
;	** LEVEL 3 VERTICAL BLANK IRQ HANDLER.
;	*/


buffSizeMaskFF
	dc.l	(BUFFER-1)<<8!$ff


play:	movem.l	d0-d7/a0-a6,-(sp)
	lea	data(pc),a5
	move.l	mrate50(a5),d0
	add.l	d0,playpos(a5)
	move.l	buffSizeMaskFF(pc),d0
	and.l	d0,playpos(a5)
	bsr.s	play2
	movem.l	(sp)+,d0-d7/a0-a6
	rts

play2:	lea	data(pc),a5

	move.l	playpos(a5),d2
	lsr.l	#8,d2
	move.l	bufpos(a5),d0
	cmp.l	d2,d0
	ble.b	.norm
	sub.l	buffSize(a5),d0
.norm	move.l	mrate50(a5),d1
	lsr.l	#7,d1
	add.l	d0,d1

	sub.l	d1,d2
	bmi.s	.ei

	moveq	#1,d0
	and.l	d2,d0
	add	d0,d2

	cmp.l	#16,d2
	blt.s	.ei

	move	d2,todobytes(a5)

.mix	move	bytes2music(a5),d0
	cmp	todobytes(a5),d0
	bgt.b	.mixaa

	sub	d0,todobytes(a5)
	sub	d0,bytes2music(a5)
	move	d0,bytes2do(a5)
	beq.b	.q
	
	bsr.w	domix

.q	bsr	EMS_music
	lea	data(pc),a5

	move	bytesperframe(a5),d0
	add	d0,bytes2music(a5)
	bra.b	.mix

.mixaa	move	todobytes(a5),d0
	sub	d0,bytes2music(a5)
	move	d0,bytes2do(a5)
	beq.b	.q2

	bsr.w	domix

.q2	lea	data(pc),a5
.ei	moveq	#0,d7
	rts

scanpoint:
	dc.b	0
	even

FinalInit
	lea	data(pc),a5
	clr.l	bufpos(a5)
	clr.l	playpos(a5)

;	/*
;	** First, clear the circular audio buffers to 0 just incase there is
;	** some old data sitting there.
;	*/

	lea	data+buff1(pc),a0
	moveq	#3,d6
.clloop
	move.l	(a0)+,d0
	beq.b	.skip
	move.l	d0,a1

	move.l	buffSize(a5),d7
	lsr.l	#2,d7
	subq.l	#1,d7
.cl	clr.l	(a1)+
	dbf	d7,.cl
.skip	dbf	d6,.clloop

;	/*
;	** Clear the audio mixer structure too.
;	*/

.huu	lea	cha0(pc),a0
	move	#mChanBlock_SIZE*16-1,d7
.cl2	clr	(a0)+
	dbf	d7,.cl2

;	/*
;	** Initialize mixing rates/audio/clock periods.
;	*/

	moveq	#125,d0
	move.l	mrate(a5),d1
	move.l	d1,d2
	lsl.l	#2,d1
	add.l	d2,d1
	add	d0,d0
	divu	d0,d1

	addq	#1,d1
	and	#~1,d1

	move	d1,bytesperframe(a5)
	clr	bytes2do(a5)

	bset	#1,$bfe001

	bsr.w	makedivtabs
	bsr.w	Makevoltable

	ifeq	disable020
	
	move.l	4.w,a6
	btst	#1,297(a6)
	beq.b	.no020

; Processor is 020+!

	st	opt020(a5)
	
	cmp	#STEREO14,pmode(a5)
	beq.b	.s14_020

	lea	mix_020(pc),a2
	lea	mix2_020(pc),a3
	move.l	a2,mixad1(a5)
	move.l	a3,mixad2(a5)
	bra.b	.e

.s14_020
	lea	mix16_020(pc),a2
	lea	mix162_020(pc),a3
	move.l	a2,mixad1(a5)
	move.l	a3,mixad2(a5)
	bra.b	.e

	endc

; Processor is 000/010

.no020	clr	opt020(a5)

	cmp	#STEREO14,pmode(a5)
	beq.b	.s14_000

	lea	mix(pc),a2
	lea	mix2(pc),a3
	move.l	a2,mixad1(a5)
	move.l	a3,mixad2(a5)
	bra.b	.e

.s14_000
	lea	mix16(pc),a2
	lea	mix162(pc),a3
	move.l	a2,mixad1(a5)
	move.l	a3,mixad2(a5)

.e	cmp	#STEREO14,pmode(a5)
	bne.b	.nop

	lea	copybuf14(pc),a2
	move.l	a2,cbufad(a5)

	bsr.w	do14tab
	bra.b	.q

.nop	cmp	#REAL,pmode(a5)
	beq.b	.surr

	lea	copybuf(pc),a2
	move.l	a2,cbufad(a5)
	bra.b	.q

.surr	lea	copysurround(pc),a2
	move.l	a2,cbufad(a5)

.q	moveq	#0,d0
	rts

;;***** Mixing routines *********


domix	lea	cha0(pc),a4
	lea	pantab(pc),a0
	moveq	#31,d7
	move.l	mixad1(a5),a1
.loo	tst.b	(a0)+
	beq.b	.n
	bmi.b	.n

	move.l	tbuf(a5),a2
	push	a0/a1/d7
	jsr	(a1)				; Mix
	pull	a0/a1/d7
	move	#1,chans(a5)
	lea	mChanBlock_SIZE(a4),a4
	subq	#1,d7
	bra.b	.loo2

.n	lea	mChanBlock_SIZE(a4),a4
	dbf	d7,.loo
	bra.b	.ddq


.loo2	cmp	#1,maxchan(a5)
	beq.b	.ddq

	move.l	mixad2(a5),a1
.loka	tst.b	(a0)+
	beq.b	.n2
	bmi.b	.n2

	move.l	tbuf(a5),a2
	push	a0/a1/d7
	jsr	(a1)
	pull	a0/a1/d7

.n2	lea	mChanBlock_SIZE(a4),a4
	dbf	d7,.loka

.ddq	move.l	tbuf(a5),a0
	move.l	buff1(a5),a1
	move.l	buff3(a5),a4
	move.l	cbufad(a5),a2
	jsr	(a2)


right	lea	cha0(pc),a4
	lea	pantab(pc),a0
	move.l	mixad1(a5),a1
	moveq	#31,d7
.loo	tst.b	(a0)+
	bpl.b	.n

	move.l	tbuf2(a5),a2
	push	a0/a1/d7
	jsr	(a1)
	pull	a0/a1/d7
	move	#1,chans(a5)
	lea	mChanBlock_SIZE(a4),a4
	subq	#1,d7
	bra.b	.loo2

.n	lea	mChanBlock_SIZE(a4),a4
	dbf	d7,.loo
	bra.b	.ddq


.loo2	cmp	#1,maxchan(a5)
	beq.b	.ddq
	move.l	mixad2(a5),a1
.loka	tst.b	(a0)+
	bpl.b	.n2

	move.l	tbuf2(a5),a2
	push	a0/a1/d7
	jsr	(a1)
	pull	a0/a1/d7

.n2	lea	mChanBlock_SIZE(a4),a4
	dbf	d7,.loka

.ddq	move.l	tbuf2(a5),a0
	move.l	buff2(a5),a1
	move.l	buff4(a5),a4
	move.l	cbufad(a5),a2
	jsr	(a2)

	moveq	#0,d0
	move	bytes2do(a5),d0
	add.l	d0,bufpos(a5)
	move.l	buffSizeMask(a5),d0
	and.l	d0,bufpos(a5)
	clr	bytes2do(a5)
	rts


copybuf	move.l	bufpos(a5),d0
	move.l	d0,d1
	moveq	#0,d2
	move	bytes2do(a5),d2
	add.l	d2,d1
	cmp.l	buffSizeMask(a5),d1
	ble.b	.dd

	move.l	a1,a3

	move.l	buffSize(a5),d7
	sub.l	d0,d7
	lsr.l	#1,d7
	subq	#1,d7
	add.l	d0,a1
	lea	divtabs(pc),a2
	move	chans(a5),d0
	lsl	#2,d0
	move.l	-4(a2,d0),a2

.ldd	move	(a0)+,d2
	move.b	(a2,d2),(a1)+
	move	(a0)+,d2
	move.b	(a2,d2),(a1)+
	dbf	d7,.ldd

	move.l	a3,a1
	move.l	d1,d7
	sub.l	buffSize(a5),d7
	lsr.l	#1,d7
	subq	#1,d7
	bmi.b	.ddq
.ldd2	move	(a0)+,d2
	move.b	(a2,d2),(a1)+
	move	(a0)+,d2
	move.b	(a2,d2),(a1)+
	dbf	d7,.ldd2
.ddq	rts

.dd	add.l	d0,a1
	lea	divtabs(pc),a2
	move	chans(a5),d0
	lsl	#2,d0
	move.l	-4(a2,d0),a2
	move	bytes2do(a5),d7
	lsr	#1,d7
	subq	#1,d7
.ldd3	move	(a0)+,d1
	move.b	(a2,d1),(a1)+
	move	(a0)+,d1
	move.b	(a2,d1),(a1)+
	dbf	d7,.ldd3
	rts

copysurround
	move.l	bufpos(a5),d0
	move.l	d0,d1

	moveq	#0,d2
	move	bytes2do(a5),d2
	add.l	d2,d1

	cmp.l	buffSizeMask(a5),d1
	ble.b	.dd

	movem.l	a1/a4,-(sp)

	move.l	buffSize(a5),d7
	sub.l	d0,d7
	lsr.l	#1,d7
	subq	#1,d7
	add.l	d0,a1
	add.l	d0,a4
	lea	divtabs(pc),a2
	move	chans(a5),d0
	lsl	#2,d0
	move.l	-4(a2,d0),a2

.ldd	move	(a0)+,d2
	move.b	(a2,d2),d2
	move.b	d2,(a1)+
	not	d2
	move.b	d2,(a4)+

	move	(a0)+,d2
	move.b	(a2,d2),d2
	move.b	d2,(a1)+
	not	d2
	move.b	d2,(a4)+
	dbf	d7,.ldd

	movem.l	(sp)+,a1/a4

	move.l	d1,d7
	sub.l	buffSize(a5),d7
	lsr.l	#1,d7
	subq	#1,d7
	bmi.b	.ddq
.ldd2	move	(a0)+,d2
	move.b	(a2,d2),d2
	move.b	d2,(a1)+
	not	d2
	move.b	d2,(a4)+

	move	(a0)+,d2
	move.b	(a2,d2),d2
	move.b	d2,(a1)+
	not	d2
	move.b	d2,(a4)+
	dbf	d7,.ldd2
.ddq	rts

.dd	add.l	d0,a1
	add.l	d0,a4
	lea	divtabs(pc),a2
	move	chans(a5),d0
	lsl	#2,d0
	move.l	-4(a2,d0),a2
	move	bytes2do(a5),d7
	lsr	#1,d7
	subq	#1,d7
.ldd3	move	(a0)+,d2
	move.b	(a2,d2),d2
	move.b	d2,(a1)+
	not	d2
	move.b	d2,(a4)+

	move	(a0)+,d2
	move.b	(a2,d2),d2
	move.b	d2,(a1)+
	not	d2
	move.b	d2,(a4)+
	dbf	d7,.ldd3
	rts


copybuf14
	move.l	bufpos(a5),d0
	move.l	d0,d1
	moveq	#0,d2
	move	bytes2do(a5),d2
	add.l	d2,d1
	cmp.l	buffSizeMask(a5),d1
	ble.b	.dd

	movem.l	a1/a4,-(sp)

	move.l	buffSize(a5),d7
	sub.l	d0,d7
	subq	#1,d7
	add.l	d0,a1
	add.l	d0,a4
	moveq	#0,d2
	move.l	buff14(a5),a2
	moveq	#-2,d0
.ldd	move	(a0)+,d2
	and.l	d0,d2
	move.b	(a2,d2.l),(a1)+
	move.b	1(a2,d2.l),(a4)+
	dbf	d7,.ldd

.huu	movem.l	(sp)+,a1/a4
	move.l	d1,d7
	sub.l	buffSize(a5),d7
	subq	#1,d7
	bmi.b	.ddq

.ldd2	move	(a0)+,d2
	and.l	d0,d2
	move.b	(a2,d2.l),(a1)+
	move.b	1(a2,d2.l),(a4)+
	dbf	d7,.ldd2
.ddq	rts


.dd	add.l	d0,a1
	add.l	d0,a4
	move	bytes2do(a5),d7
	subq	#1,d7
	move.l	buff14(a5),a2
	moveq	#0,d2
	moveq	#-2,d0
.ldd3	move	(a0)+,d2
	and.l	d0,d2
	move.b	(a2,d2.l),(a1)+
	move.b	1(a2,d2.l),(a4)+
	dbf	d7,.ldd3
	rts


; 000/010 Mixing routines

; Mixing routine for the first channel (moves data)


mix	moveq	#0,d7
	move	bytes2do(a5),d7
	subq	#1,d7
	
	tst	mPeriod(a4)
	beq.w	.ty
	tst.b	mOnOff(a4)
	bne.w	.ty			;sound off

	tst	mVolume(a4)
	beq.w	.vol0

.dw	move.l	clock(a5),d4
	divu	mPeriod(a4),d4
	swap	d4
	clr	d4
	lsr.l	#2,d4

	move.l	mrate(a5),d0
	divu	d0,d4
	swap	d4
	clr	d4
	rol.l	#4,d4

	move.l	vtabaddr(a5),d2
	move	mVolume(a4),d0
	mulu	PS3M_master(a5),d0
	lsr	#6,d0
	lsl.l	#8,d0
	add.l	d0,d2				; Position in volume table

	move.l	(a4),a0				;mStart
	move.l	mFPos(a4),d0

	moveq	#0,d3
	moveq	#0,d5

	move.l	mLength(a4),d6
	bne.b	.2

	tst.b	mLoop(a4)
	bne.b	.q
	st	mOnOff(a4)
	bra.b	.qw

.2	cmp.l	#$ffff,d6
	bls.b	.leii
	move	#$ffff,d6

.leii	cmp	#32,d7
	blt.b	.lep
	move.l	d4,d1
	swap	d1
	lsl.l	#5,d1
	swap	d1
	add.l	d0,d1
	cmp	d6,d1
	bhs.b	.lep
	pea	.leii(pc)
	bra.w	.mix32

.lep	move.b	(a0,d0),d2
	move.l	d2,a1
	add.l	d4,d0
	move.b	(a1),d3
	addx	d5,d0
	move	d3,(a2)+

	cmp	d6,d0
	bhs.b	.ddwq
	dbf	d7,.lep
	bra.b	.qw

.ddwq	tst.b	mLoop(a4)
	bne.b	.q
	st	mOnOff(a4)
	dbf	d7,.ty
	bra.b	.qw

.q	move.l	mLStart(a4),a0
	moveq	#0,d1
	move	d0,d1
	sub.l	mLength(a4),d1
	add.l	d1,a0
	move.l	mLLength(a4),d6
	sub.l	d1,d6
	move.l	d6,mLength(a4)

	cmp.l	#$ffff,d6
	bls.b	.j
	move	#$ffff,d6
.j	clr	d0				;reset integer part
	dbf	d7,.leii

.qw	moveq	#0,d1
	move	d0,d1
	add.l	d1,a0
	clr	d0
	move.l	a0,(a4)				;mStart
	move.l	d0,mFPos(a4)

	sub.l	d1,mLength(a4)
	bpl.b	.u

	tst.b	mLoop(a4)
	bne.b	.q2
	st	mOnOff(a4)
	bra.b	.u

.q2	move.l	mLLength(a4),d6
	sub.l	(a4),a0
	add.l	mLStart(a4),a0
	sub.l	d6,a0
	add.l	d6,mLength(a4)
	move.l	a0,(a4)				; mStart
.u	rts

.ty	addq	#1,d7
	beq.b	.u

	move.l	#$800080,d0
	lsr	d7
	bcc.b	.sk
	move	d0,(a2)+
.sk	subq	#1,d7
	bmi.b	.u
.lk	move.l	d0,(a2)+
	dbf	d7,.lk
	rts

.mix32:
	rept	16
	move.b	(a0,d0),d2
	move.l	d2,a1
	move.b	(a1),d3
	add.l	d4,d0
	addx	d5,d0
	swap	d3
	move.b	(a0,d0),d2
	move.l	d2,a1
	move.b	(a1),d3
	move.l	d3,(a2)+
	add.l	d4,d0
	addx	d5,d0
	endr

	sub	#32,d7
	rts



.vol0	move.l	clock(a5),d4
	divu	mPeriod(a4),d4		;period
	swap	d4
	clr	d4
	lsr.l	#2,d4

	move.l	mrate(a5),d0
	divu	d0,d4
	swap	d4
	clr	d4
	rol.l	#4,d4
	swap	d4

	move.l	(a4),a0			;mStart
	move.l	mFPos(a4),d0

	addq	#1,d7

	movem.l	d0/d1,-(sp)
	move.l	d7,d1
	move.l	d4,d0
	bsr.w	mulu_32
	move.l	d0,d4
	movem.l	(sp)+,d0/d1

	subq	#1,d7

	swap	d0
	add.l	d4,d0			; Position after "mixing"
	swap	d0
	
	moveq	#0,d1
	move	d0,d1
	add.l	d1,a0
	clr	d0
	move.l	a0,(a4)
	move.l	d0,mFPos(a4)
	sub.l	d1,mLength(a4)
	bpl.w	.ty			; OK, Done!

; We're about to mix past the end of the sample

	tst.b	mLoop(a4)
	bne.b	.q3
	st	mOnOff(a4)
	bra.w	.ty

.q3	move.l	mLLength(a4),d6
.loop	sub.l	d6,a0
	add.l	d6,mLength(a4)
	bmi.b	.loop
	beq.b	.loop

	move.l	a0,(a4)
	bra.w	.ty



; Mixing routine for rest of the channels (adds data)

mix2	moveq	#0,d7
	move	bytes2do(a5),d7

	tst	mPeriod(a4)
	beq.w	.ty
	tst.b	mOnOff(a4)
	bne.w	.ty			;noloop

	tst	mVolume(a4)
	beq.w	.vol0

.dw	subq	#1,d7

	move.l	clock(a5),d4
	divu	mPeriod(a4),d4
	swap	d4
	clr	d4
	lsr.l	#2,d4

	move.l	mrate(a5),d0
	divu	d0,d4
	swap	d4
	clr	d4
	rol.l	#4,d4

	move.l	vtabaddr(a5),d2
	move	mVolume(a4),d0
	mulu	PS3M_master(a5),d0
	lsr	#6,d0
	lsl.l	#8,d0
	add.l	d0,d2

	move.l	(a4),a0			;mStart
	move.l	mFPos(a4),d0

	moveq	#0,d3
	moveq	#0,d5

	move.l	mLength(a4),d6
	bne.b	.2

	tst.b	mLoop(a4)
	bne.b	.q
	st	mOnOff(a4)
	bra.b	.qw

.2	cmp.l	#$ffff,d6
	bls.b	.leii
	move	#$ffff,d6

.leii	cmp	#32,d7
	blt.b	.lep
	move.l	d4,d1
	swap	d1
	lsl.l	#5,d1
	swap	d1
	add.l	d0,d1
	cmp	d6,d1
	bhs.b	.lep
	pea	.leii(pc)
	bra.w	.mix32

.lep	move.b	(a0,d0),d2
	move.l	d2,a1
	add.l	d4,d0
	move.b	(a1),d3
	addx	d5,d0
	add	d3,(a2)+

	cmp	d6,d0
	bhs.b	.ddwq
	dbf	d7,.lep
	bra.b	.qw

.ddwq	tst.b	mLoop(a4)
	bne.b	.q
	st	mOnOff(a4)
	dbf	d7,.tyy
	bra.b	.qw

.q	move.l	mLStart(a4),a0
	moveq	#0,d1
	move	d0,d1
	sub.l	mLength(a4),d1
	add.l	d1,a0
	move.l	mLLength(a4),d6
	sub.l	d1,d6
	move.l	d6,mLength(a4)
	cmp.l	#$ffff,d6
	bls.b	.j
	move	#$ffff,d6
.j	clr	d0			;reset integer part
	dbf	d7,.leii

.qw	moveq	#0,d1
	move	d0,d1
	add.l	d1,a0
	clr	d0
	move.l	a0,(a4)
	move.l	d0,mFPos(a4)

	sub.l	d1,mLength(a4)
	bpl.b	.u

	tst.b	mLoop(a4)
	bne.b	.q2
	st	mOnOff(a4)
	bra.b	.u

.q2	move.l	mLLength(a4),d6
	sub.l	(a4),a0
	add.l	mLStart(a4),a0
	sub.l	d6,a0
	add.l	d6,mLength(a4)
	move.l	a0,(a4)

.u	addq	#1,chans(a5)
.ty	rts

.tyy	addq	#1,d7
	beq.b	.u

	move.l	#$800080,d0
	lsr	d7
	bcc.b	.sk
	add	d0,(a2)+
.sk	subq	#1,d7
	bmi.b	.u
.lk	add.l	d0,(a2)+
	dbf	d7,.lk
	bra.b	.u

.mix32:
	rept	16
	move.b	(a0,d0),d2
	move.l	d2,a1
	move.b	(a1),d3
	add.l	d4,d0
	addx	d5,d0
	swap	d3
	move.b	(a0,d0),d2
	move.l	d2,a1
	move.b	(a1),d3
	add.l	d3,(a2)+
	add.l	d4,d0
	addx	d5,d0
	endr
	sub	#32,d7
	rts


.vol0	move.l	clock(a5),d4
	divu	mPeriod(a4),d4
	swap	d4
	clr	d4
	lsr.l	#2,d4

	move.l	mrate(a5),d0
	divu	d0,d4
	swap	d4
	clr	d4
	rol.l	#4,d4
	swap	d4

	move.l	(a4),a0			;pos (addr)
	move.l	mFPos(a4),d0

	addq	#1,d7
	movem.l	d0/d1,-(sp)
	move.l	d7,d1
	move.l	d4,d0
	bsr.w	mulu_32
	move.l	d0,d4
	movem.l	(sp)+,d0/d1

	subq	#1,d7
	swap	d0
	add.l	d4,d0			; Position after "mixing"
	swap	d0
	
	moveq	#0,d1
	move	d0,d1
	add.l	d1,a0
	clr	d0
	move.l	a0,(a4)
	move.l	d0,mFPos(a4)
	sub.l	d1,mLength(a4)
	bpl.w	.ty			; OK, Done!

; We're about to mix past the end of the sample

	tst.b	mLoop(a4)
	bne.b	.q3
	st	mOnOff(a4)
	bra.w	.ty

.q3	move.l	mLLength(a4),d6
.loop	sub.l	d6,a0
	add.l	d6,mLength(a4)
	bmi.b	.loop
	beq.b	.loop

	move.l	a0,(a4)
	bra.w	.ty


; 16-bit mixing routine for first channel (moves data)

mix16	moveq	#0,d7
	move	bytes2do(a5),d7
	subq	#1,d7

	tst	mPeriod(a4)
	beq.w	.ty
	tst.b	mOnOff(a4)
	bne.w	.ty

	tst	mVolume(a4)
	beq.w	.vol0

.dw	move.l	clock(a5),d4
	divu	mPeriod(a4),d4
	swap	d4
	clr	d4
	lsr.l	#2,d4

	move.l	mrate(a5),d0
	divu	d0,d4
	swap	d4
	clr	d4
	rol.l	#4,d4

	move.l	vtabaddr(a5),a3
	move	mVolume(a4),d0
	mulu	PS3M_master(a5),d0
	lsr	#6,d0
	add	d0,d0
	lsl.l	#8,d0
	add.l	d0,a3				; Position in volume table

	move.l	(a4),a0				;mStart
	move.l	mFPos(a4),d0

	moveq	#0,d3
	moveq	#0,d5

	move.l	mLength(a4),d6
	bne.b	.2

	tst.b	mLoop(a4)
	bne.b	.q
	st	mOnOff(a4)
	bra.b	.qw

.2	cmp.l	#$ffff,d6
	bls.b	.leii
	move	#$ffff,d6

.leii	cmp	#32,d7
	blt.b	.lep
	move.l	d4,d1
	swap	d1
	lsl.l	#5,d1
	swap	d1
	add.l	d0,d1
	cmp	d6,d1
	bhs.b	.lep
	pea	.leii(pc)
	bra.w	.mix32

.lep	moveq	#0,d2
	move.b	(a0,d0),d2
	add	d2,d2
	add.l	d4,d0
	move	(a3,d2),(a2)+
	addx	d5,d0

	cmp	d6,d0
	bhs.b	.ddwq
	dbf	d7,.lep
	bra.b	.qw

.ddwq	tst.b	mLoop(a4)
	bne.b	.q
	st	mOnOff(a4)
	dbf	d7,.ty
	bra.b	.qw

.q	move.l	mLStart(a4),a0
	moveq	#0,d1
	move	d0,d1
	sub.l	mLength(a4),d1
	add.l	d1,a0
	move.l	mLLength(a4),d6
	sub.l	d1,d6
	move.l	d6,mLength(a4)

	cmp.l	#$ffff,d6
	bls.b	.j
	move	#$ffff,d6
.j	clr	d0				;reset integer part
	dbf	d7,.leii

.qw	moveq	#0,d1
	move	d0,d1
	add.l	d1,a0
	clr	d0
	move.l	a0,(a4)				;mStart
	move.l	d0,mFPos(a4)

	sub.l	d1,mLength(a4)
	bpl.b	.u

	tst.b	mLoop(a4)
	bne.b	.q2
	st	mOnOff(a4)
	bra.b	.u

.q2	move.l	mLLength(a4),d6
	sub.l	(a4),a0
	add.l	mLStart(a4),a0
	sub.l	d6,a0
	add.l	d6,mLength(a4)
	move.l	a0,(a4)				; mStart
.u	rts

.ty	addq	#1,d7
	beq.b	.u

	moveq	#0,d0
	lsr	d7
	bcc.b	.sk
	move	d0,(a2)+
.sk	subq	#1,d7
	bmi.b	.u
.lk	move.l	d0,(a2)+
	dbf	d7,.lk
	rts

.mix32:
	rept	32

	moveq	#0,d2
	move.b	(a0,d0),d2
	add	d2,d2
	add.l	d4,d0
	move	(a3,d2),(a2)+
	addx	d5,d0

	endr

	sub	#32,d7
	rts


.vol0	move.l	clock(a5),d4
	divu	mPeriod(a4),d4		;period
	swap	d4
	clr	d4
	lsr.l	#2,d4

	move.l	mrate(a5),d0
	divu	d0,d4
	swap	d4
	clr	d4
	rol.l	#4,d4
	swap	d4

	move.l	(a4),a0			;mStart
	move.l	mFPos(a4),d0

	addq	#1,d7

	movem.l	d0/d1,-(sp)
	move.l	d7,d1
	move.l	d4,d0
	bsr.w	mulu_32
	move.l	d0,d4
	movem.l	(sp)+,d0/d1

	subq	#1,d7

	swap	d0
	add.l	d4,d0			; Position after "mixing"
	swap	d0
	
	moveq	#0,d1
	move	d0,d1
	add.l	d1,a0
	clr	d0
	move.l	a0,(a4)
	move.l	d0,mFPos(a4)
	sub.l	d1,mLength(a4)
	bpl.w	.ty			; OK, Done!

; We're about to mix past the end of the sample

	tst.b	mLoop(a4)
	bne.b	.q3
	st	mOnOff(a4)
	bra.w	.ty

.q3	move.l	mLLength(a4),d6
.loop	sub.l	d6,a0
	add.l	d6,mLength(a4)
	bmi.b	.loop
	beq.b	.loop

	move.l	a0,(a4)
	bra.w	.ty



; Mixing routine for rest of the channels (adds data)

mix162	moveq	#0,d7
	move	bytes2do(a5),d7

	tst	mPeriod(a4)
	beq.w	.ty
	tst.b	mOnOff(a4)
	bne.w	.ty

	tst	mVolume(a4)
	beq.w	.vol0

.dw	subq	#1,d7

	move.l	clock(a5),d4
	divu	mPeriod(a4),d4
	swap	d4
	clr	d4
	lsr.l	#2,d4

	move.l	mrate(a5),d0
	divu	d0,d4
	swap	d4
	clr	d4
	rol.l	#4,d4

	move.l	vtabaddr(a5),a3
	move	mVolume(a4),d0		;volu
	mulu	PS3M_master(a5),d0
	lsr	#6,d0
	add	d0,d0
	lsl.l	#8,d0
	add.l	d0,a3

	move.l	(a4),a0			;mStart
	move.l	mFPos(a4),d0

	moveq	#0,d3
	moveq	#0,d5

	move.l	mLength(a4),d6
	bne.b	.2

	tst.b	mLoop(a4)
	bne.b	.q
	st	mOnOff(a4)
	bra.b	.qw

.2	cmp.l	#$ffff,d6
	bls.b	.leii
	move	#$ffff,d6

.leii	cmp	#32,d7
	blt.b	.lep
	move.l	d4,d1
	swap	d1
	lsl.l	#5,d1
	swap	d1
	add.l	d0,d1
	cmp	d6,d1
	bhs.b	.lep
	pea	.leii(pc)
	bra.w	.mix32

.lep	moveq	#0,d2
	move.b	(a0,d0),d2
	add	d2,d2
	add.l	d4,d0
	move	(a3,d2),d3
	addx	d5,d0
	add	d3,(a2)+

	cmp	d6,d0
	bhs.b	.ddwq
	dbf	d7,.lep
	bra.b	.qw

.ddwq	tst.b	mLoop(a4)
	bne.b	.q
	st	mOnOff(a4)
	dbf	d7,.tyy
	bra.b	.qw

.q	move.l	mLStart(a4),a0
	moveq	#0,d1
	move	d0,d1
	sub.l	mLength(a4),d1
	add.l	d1,a0
	move.l	mLLength(a4),d6
	sub.l	d1,d6
	move.l	d6,mLength(a4)
	cmp.l	#$ffff,d6
	bls.b	.j
	move	#$ffff,d6
.j	clr	d0			;reset integer part
	dbf	d7,.leii

.qw	moveq	#0,d1
	move	d0,d1
	add.l	d1,a0
	clr	d0
	move.l	a0,(a4)
	move.l	d0,mFPos(a4)

	sub.l	d1,mLength(a4)
	bpl.b	.u

	tst.b	mLoop(a4)
	bne.b	.q2
	st	mOnOff(a4)
	bra.b	.u

.q2	move.l	mLLength(a4),d6
	sub.l	(a4),a0
	add.l	mLStart(a4),a0
	sub.l	d6,a0
	add.l	d6,mLength(a4)
	move.l	a0,(a4)

.u
.ty
.tyy
	rts


.mix32:
	rept	32
	moveq	#0,d2
	move.b	(a0,d0),d2
	add	d2,d2
	move	(a3,d2),d3
	add	d3,(a2)+
	add.l	d4,d0
	addx	d5,d0
	endr
	sub	#32,d7
	rts

.vol0	move.l	clock(a5),d4
	divu	mPeriod(a4),d4
	swap	d4
	clr	d4
	lsr.l	#2,d4

	move.l	mrate(a5),d0
	divu	d0,d4
	swap	d4
	clr	d4
	rol.l	#4,d4
	swap	d4

	move.l	(a4),a0			;pos (addr)
	move.l	mFPos(a4),d0

	addq	#1,d7
	movem.l	d0/d1,-(sp)
	move.l	d7,d1
	move.l	d4,d0
	bsr.w	mulu_32
	move.l	d0,d4
	movem.l	(sp)+,d0/d1

	subq	#1,d7
	swap	d0
	add.l	d4,d0			; Position after "mixing"
	swap	d0
	
	moveq	#0,d1
	move	d0,d1
	add.l	d1,a0
	clr	d0
	move.l	a0,(a4)
	move.l	d0,mFPos(a4)
	sub.l	d1,mLength(a4)
	bpl.w	.ty			; OK, Done!

; We're about to mix past the end of the sample

	tst.b	mLoop(a4)
	bne.b	.q3
	st	mOnOff(a4)
	bra.w	.ty

.q3	move.l	mLLength(a4),d6
.loop	sub.l	d6,a0
	add.l	d6,mLength(a4)
	bmi.b	.loop
	beq.b	.loop

	move.l	a0,(a4)
	bra.w	.ty




	ifeq	disable020

; 020+ Optimized versions!

; Mixing routine for the first channel (moves data)


mix_020	moveq	#0,d7
	move	bytes2do(a5),d7
	tst	mPeriod(a4)
	beq.w	.ty
	tst.b	mOnOff(a4)
	bne.w	.ty

	tst	mVolume(a4)
	beq.w	.vol0

.dw	move.l	clock(a5),d4
	moveq	#0,d0
	move	mPeriod(a4),d0

	divu.l	d0,d4

	lsl.l	#8,d4
	lsl.l	#6,d4

	move.l	mrate(a5),d0
	lsr.l	#4,d0

	divu.l	d0,d4
	swap	d4

	move.l	vtabaddr(a5),d2
	move	mVolume(a4),d0
	mulu	PS3M_master(a5),d0
	lsr	#6,d0
	lsl.l	#8,d0
	add.l	d0,d2			; Position in volume table

	move.l	(a4),a0			;pos (addr)
	move.l	mFPos(a4),d0		;fpos

	move.l	mLength(a4),d6		;len
	beq.w	.resloop

	cmp.l	#$ffff,d6
	bls.b	.restart
	move	#$ffff,d6
.restart
	swap	d6
	swap	d0
	sub.l	d0,d6
	swap	d0
	move.l	d4,d5
	swap	d5

	divul.l	d5,d5:d6		; bytes left to loop end
	tst.l	d5
	beq.b	.e
	addq.l	#1,d6
.e
	moveq	#0,d3
	moveq	#0,d5
.mixloop
	moveq	#8,d1
	cmp	d1,d7
	bhs.b	.ok
	move	d7,d1
.ok	cmp.l	d1,d6
	bhs.b	.ok2
	move.l	d6,d1
.ok2	sub	d1,d7
	sub.l	d1,d6

	jmp	.jtab1(pc,d1*2)

.a set 0
.jtab1
	rept	8
	bra.b	.mend-.a
.a set .a+14				; (mend - dmix) / 8
	endr

.dmix	rept	8
	move.b	(a0,d0),d2
	move.l	d2,a1
	move.b	(a1),d3
	add.l	d4,d0
	move	d3,(a2)+
	addx	d5,d0
	endr
.mend	tst	d7
	beq.b	.done
	tst.l	d6
	bne.w	.mixloop

.resloop
	tst.b	mLoop(a4)
	bne.b	.q
	st	mOnOff(a4)
	bra.b	.ty

.q	moveq	#0,d1
	move	d0,d1
	sub.l	mLength(a4),d1
	move.l	mLStart(a4),a0
	add.l	d1,a0
	move.l	mLLength(a4),d6
	sub.l	d1,d6
	move.l	d6,mLength(a4)
	cmp.l	#$ffff,d6
	bls.b	.j
	move	#$ffff,d6
.j	clr	d0			;reset integer part
	bra.w	.restart

.done	moveq	#0,d1
	move	d0,d1
	add.l	d1,a0
	clr	d0
	move.l	a0,(a4)
	move.l	d0,mFPos(a4)
	sub.l	d1,mLength(a4)
	bpl.b	.u

	tst.b	mLoop(a4)
	bne.b	.q2
	st	mOnOff(a4)
	bra.b	.u

.q2	move.l	mLLength(a4),d6
	sub.l	(a4),a0
	add.l	mLStart(a4),a0
	sub.l	d6,a0
	add.l	d6,mLength(a4)
	move.l	a0,(a4)
.u	rts

.ty	move.l	#$800080,d0
	lsr	d7
	bcc.b	.sk
	move	d0,(a2)+
.sk	subq	#1,d7
	bmi.b	.u
.lk	move.l	d0,(a2)+
	dbf	d7,.lk
	rts


.vol0	move.l	clock(a5),d4
	moveq	#0,d0
	move	mPeriod(a4),d0

	divu.l	d0,d4

	lsl.l	#8,d4
	lsl.l	#6,d4

	move.l	mrate(a5),d0
	lsr.l	#4,d0

	divu.l	d0,d4

	move.l	(a4),a0
	move.l	mFPos(a4),d0

	mulu.l	d7,d4

	swap	d0
	add.l	d4,d0			; Position after "mixing"
	swap	d0
	
	moveq	#0,d1
	move	d0,d1
	add.l	d1,a0
	clr	d0
	move.l	a0,(a4)
	move.l	d0,mFPos(a4)
	sub.l	d1,mLength(a4)
	bpl.b	.ty			; OK, Done!

; We're about to mix past the end of the sample

	tst.b	mLoop(a4)
	bne.b	.q3
	st	mOnOff(a4)
	bra.b	.ty

.q3	move.l	mLLength(a4),d6
.loop	sub.l	d6,a0
	add.l	d6,mLength(a4)
	bmi.b	.loop
	beq.b	.loop

	move.l	a0,(a4)
	bra.b	.ty


; Mixing routine for rest of the channels (adds data)

mix2_020
	moveq	#0,d7
	move	bytes2do(a5),d7
	tst	mPeriod(a4)
	beq.w	.ty
	tst.b	mOnOff(a4)
	bne.w	.ty

	tst	mVolume(a4)
	beq.w	.vol0

.dw	move.l	clock(a5),d4
	moveq	#0,d0
	move	mPeriod(a4),d0

	divu.l	d0,d4

	lsl.l	#8,d4
	lsl.l	#6,d4

	move.l	mrate(a5),d0
	lsr.l	#4,d0

	divu.l	d0,d4

	swap	d4

	move.l	vtabaddr(a5),d2
	move	mVolume(a4),d0
	mulu	PS3M_master(a5),d0
	lsr	#6,d0
	lsl.l	#8,d0
	add.l	d0,d2			; Position in volume table

	move.l	(a4),a0
	move.l	mFPos(a4),d0

	move.l	mLength(a4),d6
	beq.w	.resloop

	cmp.l	#$ffff,d6
	bls.b	.restart
	move	#$ffff,d6
.restart
	swap	d6
	swap	d0
	sub.l	d0,d6
	swap	d0

	move.l	d4,d5
	swap	d5

	divul.l	d5,d5:d6		; bytes left to loop end
	tst.l	d5
	beq.b	.e
	addq.l	#1,d6
.e	moveq	#0,d3
	moveq	#0,d5
.mixloop
	moveq	#8,d1
	cmp	d1,d7
	bhi.b	.ok
	move	d7,d1
.ok	cmp.l	d1,d6
	bhi.b	.ok2
	move	d6,d1
.ok2	sub	d1,d7
	sub.l	d1,d6
	jmp	.jtab1(pc,d1*2)

.a set 0
.jtab1
	rept	8
	bra.b	.mend-.a
.a set .a+14				; (mend - dmix) / 8
	endr

.dmix	rept	8
	move.b	(a0,d0),d2
	move.l	d2,a1
	move.b	(a1),d3
	add	d3,(a2)+
	add.l	d4,d0
	addx	d5,d0
	endr
.mend	tst	d7
	beq.b	.done
	tst.l	d6
	bne.w	.mixloop

.resloop
	tst.b	mLoop(a4)
	bne.b	.q
	st	mOnOff(a4)
	bra.b	.tyy

.q	moveq	#0,d1
	move	d0,d1
	sub.l	mLength(a4),d1
	move.l	mLStart(a4),a0
	add.l	d1,a0
	move.l	mLLength(a4),d6
	sub.l	d1,d6
	move.l	d6,mLength(a4)
	cmp.l	#$ffff,d6
	bls.b	.j
	move	#$ffff,d6
.j	clr	d0			;reset integer part
	bra.w	.restart

.done	moveq	#0,d1
	move	d0,d1
	add.l	d1,a0
	clr	d0
	move.l	a0,(a4)
	move.l	d0,mFPos(a4)
	sub.l	d1,mLength(a4)
	bpl.b	.u

	tst.b	mLoop(a4)
	bne.b	.q2
	st	mOnOff(a4)
	bra.b	.u

.q2	move.l	mLLength(a4),d6
	sub.l	(a4),a0
	add.l	mLStart(a4),a0
	sub.l	d6,a0
	add.l	d6,mLength(a4)
	move.l	a0,(a4)

.u	addq	#1,chans(a5)
.ty	rts

.tyy	move.l	#$800080,d0
	lsr	d7
	bcc.b	.sk
	add	d0,(a2)+
.sk	subq	#1,d7
	bmi.b	.u
.lk	add.l	d0,(a2)+
	dbf	d7,.lk
	bra.b	.u


.vol0	move.l	clock(a5),d4
	moveq	#0,d0
	move	mPeriod(a4),d0

	divu.l	d0,d4

	lsl.l	#8,d4
	lsl.l	#6,d4

	move.l	mrate(a5),d0
	lsr.l	#4,d0

	divu.l	d0,d4

	move.l	(a4),a0
	move.l	mFPos(a4),d0

	mulu.l	d7,d4

	swap	d0
	add.l	d4,d0			; Position after "mixing"
	swap	d0
	
	moveq	#0,d1
	move	d0,d1
	add.l	d1,a0
	clr	d0
	move.l	a0,(a4)
	move.l	d0,mFPos(a4)
	sub.l	d1,mLength(a4)
	bpl.b	.ty			; OK, Done!

; We're about to mix past the end of the sample

	tst.b	mLoop(a4)
	bne.b	.q3
	st	mOnOff(a4)
	bra.b	.ty

.q3	move.l	mLLength(a4),d6
.loop	sub.l	d6,a0
	add.l	d6,mLength(a4)
	bmi.b	.loop
	beq.b	.loop

	move.l	a0,(a4)
	bra.b	.ty



; Mixing routine for the first channel (moves data)


mix16_020
	moveq	#0,d7
	move	bytes2do(a5),d7
	tst	mPeriod(a4)
	beq.w	.ty
	tst.b	mOnOff(a4)
	bne.w	.ty

	tst	mVolume(a4)
	beq.w	.vol0

.dw	move.l	clock(a5),d4
	moveq	#0,d0
	move	mPeriod(a4),d0

	divu.l	d0,d4

	lsl.l	#8,d4
	lsl.l	#6,d4

	move.l	mrate(a5),d0
	lsr.l	#4,d0

	divu.l	d0,d4
	swap	d4

	move.l	vtabaddr(a5),a3
	move	mVolume(a4),d0
	mulu	PS3M_master(a5),d0
	lsr	#6,d0
	add	d0,d0
	lsl.l	#8,d0
	add.l	d0,a3			; Position in volume table

	move.l	(a4),a0			;pos (addr)
	move.l	mFPos(a4),d0		;fpos

	move.l	mLength(a4),d6		;len
	beq.w	.resloop

	cmp.l	#$ffff,d6
	bls.b	.restart
	move	#$ffff,d6
.restart
	swap	d6
	swap	d0
	sub.l	d0,d6
	swap	d0
	move.l	d4,d5
	swap	d5

	divul.l	d5,d5:d6		; bytes left to loop end
	tst.l	d5
	beq.b	.e
	addq.l	#1,d6
.e
	moveq	#0,d5
	moveq	#0,d2
.mixloop
	moveq	#8,d1
	cmp	d1,d7
	bhs.b	.ok
	move	d7,d1
.ok	cmp.l	d1,d6
	bhs.b	.ok2
	move.l	d6,d1
.ok2	sub	d1,d7
	sub.l	d1,d6

	jmp	.jtab1(pc,d1*2)

.a set 0
.jtab1
	rept	8
	bra.b	.mend-.a
.a set .a+12				; (mend - dmix) / 8
	endr

.dmix	rept	8
	move.b	(a0,d0),d2
	add.l	d4,d0
	move	(a3,d2*2),(a2)+
	addx	d5,d0
	endr

.mend	tst	d7
	beq.b	.done
	tst.l	d6
	bne.w	.mixloop

.resloop
	tst.b	mLoop(a4)
	bne.b	.q
	st	mOnOff(a4)
	bra.b	.ty

.q	moveq	#0,d1
	move	d0,d1
	sub.l	mLength(a4),d1
	move.l	mLStart(a4),a0
	add.l	d1,a0
	move.l	mLLength(a4),d6
	sub.l	d1,d6
	move.l	d6,mLength(a4)
	cmp.l	#$ffff,d6
	bls.b	.j
	move	#$ffff,d6
.j	clr	d0			;reset integer part
	bra.w	.restart

.done	moveq	#0,d1
	move	d0,d1
	add.l	d1,a0
	clr	d0
	move.l	a0,(a4)
	move.l	d0,mFPos(a4)
	sub.l	d1,mLength(a4)
	bpl.b	.u

	tst.b	mLoop(a4)
	bne.b	.q2
	st	mOnOff(a4)
	bra.b	.u

.q2	move.l	mLLength(a4),d6
	sub.l	(a4),a0
	add.l	mLStart(a4),a0
	sub.l	d6,a0
	add.l	d6,mLength(a4)
	move.l	a0,(a4)
.u	rts

.ty	addq	#1,d7
	beq.b	.u

	moveq	#0,d0
	lsr	d7
	bcc.b	.sk
	move	d0,(a2)+
.sk	subq	#1,d7
	bmi.b	.u
.lk	move.l	d0,(a2)+
	dbf	d7,.lk
	rts

.vol0	move.l	clock(a5),d4
	moveq	#0,d0
	move	mPeriod(a4),d0

	divu.l	d0,d4

	lsl.l	#8,d4
	lsl.l	#6,d4

	move.l	mrate(a5),d0
	lsr.l	#4,d0

	divu.l	d0,d4

	move.l	(a4),a0
	move.l	mFPos(a4),d0

	mulu.l	d7,d4

	swap	d0
	add.l	d4,d0			; Position after "mixing"
	swap	d0
	
	moveq	#0,d1
	move	d0,d1
	add.l	d1,a0
	clr	d0
	move.l	a0,(a4)
	move.l	d0,mFPos(a4)
	sub.l	d1,mLength(a4)
	bpl.b	.ty			; OK, Done!

; We're about to mix past the end of the sample

	tst.b	mLoop(a4)
	bne.b	.q3
	st	mOnOff(a4)
	bra.b	.ty

.q3	move.l	mLLength(a4),d6
.loop	sub.l	d6,a0
	add.l	d6,mLength(a4)
	bmi.b	.loop
	beq.b	.loop

	move.l	a0,(a4)
	bra.b	.ty


; Mixing routine for rest of the channels (adds data)

mix162_020
	moveq	#0,d7
	move	bytes2do(a5),d7
	tst	mPeriod(a4)
	beq.w	.ty
	tst.b	mOnOff(a4)
	bne.w	.ty

	tst	mVolume(a4)
	beq.w	.vol0

.dw	move.l	clock(a5),d4
	moveq	#0,d0
	move	mPeriod(a4),d0

	divu.l	d0,d4

	lsl.l	#8,d4
	lsl.l	#6,d4

	move.l	mrate(a5),d0
	lsr.l	#4,d0

	divu.l	d0,d4

	swap	d4

	move.l	vtabaddr(a5),a3
	move	mVolume(a4),d0
	mulu	PS3M_master(a5),d0
	lsr	#6,d0
	add	d0,d0
	lsl.l	#8,d0
	add.l	d0,a3			; Position in volume table

	move.l	(a4),a0
	move.l	mFPos(a4),d0

	move.l	mLength(a4),d6
	beq.w	.resloop

	cmp.l	#$ffff,d6
	bls.b	.restart
	move	#$ffff,d6
.restart
	swap	d6
	swap	d0
	sub.l	d0,d6
	swap	d0

	move.l	d4,d5
	swap	d5

	divul.l	d5,d5:d6		; bytes left to loop end
	tst.l	d5
	beq.b	.e
	addq.l	#1,d6
.e	moveq	#0,d2
	moveq	#0,d5
.mixloop
	moveq	#8,d1
	cmp	d1,d7
	bhi.b	.ok
	move	d7,d1
.ok	cmp.l	d1,d6
	bhi.b	.ok2
	move	d6,d1
.ok2	sub	d1,d7
	sub.l	d1,d6
	jmp	.jtab1(pc,d1*2)

.a set 0
.jtab1
	rept	8
	bra.b	.mend-.a
.a set .a+14				; (mend - dmix) / 8
	endr

.dmix	rept	8
	move.b	(a0,d0),d2
	add.l	d4,d0
	move	(a3,d2*2),d3
	addx	d5,d0
	add	d3,(a2)+
	endr

.mend	tst	d7
	beq.b	.done
	tst.l	d6
	bne.w	.mixloop

.resloop
	tst.b	mLoop(a4)
	bne.b	.q
	st	mOnOff(a4)
	bra.b	.tyy

.q	moveq	#0,d1
	move	d0,d1
	sub.l	mLength(a4),d1
	move.l	mLStart(a4),a0
	add.l	d1,a0
	move.l	mLLength(a4),d6
	sub.l	d1,d6
	move.l	d6,mLength(a4)
	cmp.l	#$ffff,d6
	bls.b	.j
	move	#$ffff,d6
.j	clr	d0			;reset integer part
	bra.w	.restart

.done	moveq	#0,d1
	move	d0,d1
	add.l	d1,a0
	clr	d0
	move.l	a0,(a4)
	move.l	d0,mFPos(a4)
	sub.l	d1,mLength(a4)
	bpl.b	.u

	tst.b	mLoop(a4)
	bne.b	.q2
	st	mOnOff(a4)
	bra.b	.u

.q2	move.l	mLLength(a4),d6
	sub.l	(a4),a0
	add.l	mLStart(a4),a0
	sub.l	d6,a0
	add.l	d6,mLength(a4)
	move.l	a0,(a4)
.u
.ty
.tyy	rts


.vol0	move.l	clock(a5),d4
	moveq	#0,d0
	move	mPeriod(a4),d0

	divu.l	d0,d4

	lsl.l	#8,d4
	lsl.l	#6,d4

	move.l	mrate(a5),d0
	lsr.l	#4,d0

	divu.l	d0,d4

	move.l	(a4),a0
	move.l	mFPos(a4),d0

	mulu.l	d7,d4

	swap	d0
	add.l	d4,d0			; Position after "mixing"
	swap	d0
	
	moveq	#0,d1
	move	d0,d1
	add.l	d1,a0
	clr	d0
	move.l	a0,(a4)
	move.l	d0,mFPos(a4)
	sub.l	d1,mLength(a4)
	bpl.b	.ty			; OK, Done!

; We're about to mix past the end of the sample

	tst.b	mLoop(a4)
	bne.b	.q3
	st	mOnOff(a4)
	bra.b	.ty

.q3	move.l	mLLength(a4),d6
.loop	sub.l	d6,a0
	add.l	d6,mLength(a4)
	bmi.b	.loop
	beq.b	.loop

	move.l	a0,(a4)
	bra.b	.ty

	endc


* mulu_32 --- d0 = d0*d1
mulu_32	movem.l	d2/d3,-(sp)
	move.l	d0,d2
	move.l	d1,d3
	swap	d2
	swap	d3
	mulu	d1,d2
	mulu	d0,d3
	mulu	d1,d0
	add	d3,d2
	swap	d2
	clr	d2
	add.l	d2,d0
	movem.l	(sp)+,d2/d3
	rts	

* divu_32 --- d0 = d0/d1, d1=jakoj??nn?s
divu_32	move.l	d3,-(a7)
	swap	d1
	tst	d1
	bne.b	lb_5f8c
	swap	d1
	move.l	d1,d3
	swap	d0
	move	d0,d3
	beq.b	lb_5f7c
	divu	d1,d3
	move	d3,d0
lb_5f7c	swap	d0
	move	d0,d3
	divu	d1,d3
	move	d3,d0
	swap	d3
	move	d3,d1
	move.l	(a7)+,d3
	rts	

lb_5f8c	swap	d1
	move	d2,-(a7)
	moveq	#16-1,d3
	move	d3,d2
	move.l	d1,d3
	move.l	d0,d1
	clr	d1
	swap	d1
	swap	d0
	clr	d0
lb_5fa0	add.l	d0,d0
	addx.l	d1,d1
	cmp.l	d1,d3
	bhi.b	lb_5fac
	sub.l	d3,d1
	addq	#1,d0
lb_5fac	dbf	d2,lb_5fa0
	move	(a7)+,d2
	move.l	(a7)+,d3
	rts	


;;******** Init routines ***********


makedivtabs
	lea	data(pc),a5
	move.l	vtabaddr(a5),d0			;Get address.
	tst.l	d0				;Is it 0?
	bne.s	making_tables			;>0 then make tables (Sean).
	rts
making_tables:
	cmp	#STEREO14,pmode(a5)
	beq.b	ret

	lea	divtabs(pc),a1
	move.l	dtab(a5),a0

	move	#255,d6
	moveq	#0,d5
	move	maxchan(a5),d5
	move.l	d5,d3
	move.l	d5,d2

	subq	#1,d5
	move	d5,d4
	lsl.l	#7,d5

	lsl.l	#7,d2

	sub.l	vboost(a5),d3
	cmp	#1,d3
	bge.b	.laa
	moveq	#1,d3

.laa	moveq	#0,d0
	move	d6,d7
	move.l	a0,(a1)+
.al	move.l	d0,d1
	add.l	d5,d1
	sub.l	d2,d1
	divs	d3,d1
	cmp	#$7f,d1
	ble.b	.d
	move	#$7f,d1
.d	cmp	#$ff80,d1
	bge.b	.d2
	move	#$80,d1
.d2	move.b	d1,(a0)+
	addq.l	#1,d0
	dbf	d7,.al

	add	#256,d6
	sub.l	#$80,d5
	dbf	d4,.laa
ret:	rts


Makevoltable
	move.l	vtabaddr(a5),a0
	move.l	a0,d0				;Address of table.
	tst.l	d0				;Is there a table yet?
	bne.s	mvt2				;Yes. (Sean).
	rts

mvt2:	cmp	#STEREO14,pmode(a5)
	beq.b	bit16

	moveq	#0,d3		;volume
	cmp	#1,fformat(a5)
	beq.b	signed

.lop	moveq	#0,d4		;data
.lap	move	d4,d5
	sub	#$80,d5
	mulu	d3,d5
	asr.l	#6,d5
	add	#$80,d5
	move.b	d5,(a0)+
	addq	#1,d4
	cmp	#256,d4
	bne.b	.lap
	addq	#1,d3
	cmp	#65,d3
	bne.b	.lop
	rts

signed
.lop	moveq	#0,d4		;data
.lap	move.b	d4,d5
	ext	d5
	mulu	d3,d5
	asr.l	#6,d5
	add	#$80,d5
	move.b	d5,(a0)+
	addq	#1,d4
	cmp	#256,d4
	bne.b	.lap
	addq	#1,d3
	cmp	#65,d3
	bne.b	.lop
	rts


bit16	move	maxchan(a5),d3
	moveq	#0,d7			; "index"
	cmp	#1,fformat(a5)
	beq.b	signed2

.lop	move	d7,d6
	tst.b	d7
	bmi.b	.above

	and	#127,d6
	move	#128,d5
	sub	d6,d5
	lsl	#8,d5
	move	d7,d6
	lsr	#8,d6
	mulu	d6,d5
	divu	#63,d5
	swap	d5
	clr	d5
	swap	d5
	divu	d3,d5
.ska1	neg	d5
	move	d5,(a0)+
	addq	#1,d7
	cmp	#256*65,d7
	bne.b	.lop
	rts

.above	and	#127,d6
	lsl	#8,d6

	move	d7,d5
	lsr	#8,d5
	mulu	d6,d5
	divu	#63,d5
	swap	d5
	clr	d5
	swap	d5
	divu	d3,d5
.ska2	move	d5,(a0)+
	addq	#1,d7
	cmp	#256*65,d7
	bne.b	.lop
	rts

signed2
.lop	move	d7,d6
	tst.b	d7
	bpl.b	.above

	and	#127,d6
	move	#128,d5
	sub	d6,d5
	lsl	#8,d5
	move	d7,d6
	lsr	#8,d6
	mulu	d6,d5
	divu	#63,d5
	swap	d5
	clr	d5
	swap	d5
	divu	d3,d5
.ska3	neg	d5
	move	d5,(a0)+
	addq	#1,d7
	cmp	#256*65,d7
	bne.b	.lop
	rts

.above	and	#127,d6
	lsl	#8,d6

	move	d7,d5
	lsr	#8,d5
	mulu	d6,d5
	divu	#63,d5
	swap	d5
	clr	d5
	swap	d5
	divu	d3,d5
.ska4	move	d5,(a0)+
	addq	#1,d7
	cmp	#256*65,d7
	bne.b	.lop
	rts


do14tab	move.l	buff14(a5),a0
	moveq	#0,d7
.loo	move	d7,d2
	bpl.b	.plus

	neg	d2
	move	d2,d3
	lsr	#8,d2
	neg.b	d2

	lsr.b	#2,d3
	neg	d3

	move.b	d2,(a0)+
	move.b	d3,(a0)+
	addq.l	#2,d7
	cmp.l	#$10000,d7
	bne.b	.loo
	rts

.plus	move	d2,d3
	lsr	#8,d2
	lsr.b	#2,d3
	move.b	d2,(a0)+
	move.b	d3,(a0)+
	addq.l	#2,d7
	cmp.l	#$10000,d7
	bne.b	.loo
	rts







******************************************************************************
******************************************************************************
******************************************************************************
* Soittolooppi


; PLAYING PROCESSES: HALF-FRIENDLY mode.
; ??????????????????????????????????????


s3mPlay	lea	data(pc),a5
	move.w	#$0f,$dff096		;Clear audio DMA.

	move.l	4.w,a6
	move.b	PowerSupplyFrequency(a6),d0
	cmp.b	#60,d0
	beq.b	.NTSC
	move.l	#3546895,audiorate(a5)
	bra.b	.qw
.NTSC
	move.l	#3579545,audiorate(a5)
.qw
	move.l	audiorate(a5),d0
	move.l	mixingrate(a5),d1
	divu	d1,d0
	move.l	audiorate(a5),d1
	divu	d0,d1
	swap	d1
	clr	d1
	swap	d1
	move.l	d1,mrate(a5)

	move.l	audiorate(a5),d0
	divu	d1,d0

	swap	d0
	clr	d0
	swap	d0
	move.l	d0,mixingperiod(a5)

	lsl.l	#8,d1				; 8-bit fraction
	move.l	d1,d0
	move.l	4.w,a6
	moveq	#0,d1
	move.b	VBlankFrequency(a6),d1
	bsr.w	divu_32
	move.l	d0,mrate50(a5)			;In fact vblank frequency

	movem.l	buff1(a5),a0-a3
	move.l	mixingperiod(a5),d0

	lea	$dff000,a6
	move.l	buffSize(a5),d1
	lsr.l	#1,d1
	move	d1,$a4(a6)
	move	d1,$b4(a6)
	move	d1,$c4(a6)
	move	d1,$d4(a6)
	move	d0,$a6(a6)
	move	d0,$b6(a6)
	move	d0,$c6(a6)
	move	d0,$d6(a6)

	moveq	#64,d1

	move	pmode(a5),d0	
	cmp.w	#SURROUND,d0
	bne.b	.nosurround

	moveq	#32,d2

	move.l	a0,$a0(a6)
	move.l	a1,$b0(a6)
	move.l	a0,$c0(a6)
	move.l	a1,$d0(a6)
	move	d1,$a8(a6)
	move	d1,$b8(a6)
	move	d2,$c8(a6)
	move	d2,$d8(a6)
	bra.w	.ohiis

.nosurround
	cmp.w	#STEREO,d0
	bne.b	.nostereo

	move.l	a0,$a0(a6)
	move.l	a1,$b0(a6)
	move.l	a1,$c0(a6)
	move.l	a0,$d0(a6)
	move	d1,$a8(a6)
	move	d1,$b8(a6)
	move	d1,$c8(a6)
	move	d1,$d8(a6)
	bra.b	.ohiis

.nostereo
	cmp.w	#MONO,d0
	bne.b	.nomono

	move.l	a0,$a0(a6)
	move.l	a1,$b0(a6)
	move.l	a0,$c0(a6)
	move.l	a1,$d0(a6)
	move	d1,$a8(a6)
	move	d1,$b8(a6)
	move	d1,$c8(a6)
	move	d1,$d8(a6)
	bra.b	.ohiis

.nomono

; REAL SURROUND!

	cmp.w	#REAL,d0
	bne.b	.bit14

	move.l	a0,$a0(a6)
	move.l	a1,$b0(a6)
	move.l	a2,$c0(a6)
	move.l	a3,$d0(a6)
	move	d1,$a8(a6)
	move	d1,$b8(a6)
	move	d1,$c8(a6)
	move	d1,$d8(a6)
	bra.b	.ohiis


; 14-BIT STEREO

.bit14	moveq	#1,d2

	move.l	a0,$a0(a6)
	move.l	a1,$b0(a6)
	move.l	a3,$c0(a6)
	move.l	a2,$d0(a6)
	move	d1,$a8(a6)
	move	d1,$b8(a6)
	move	d2,$c8(a6)
	move	d2,$d8(a6)

.ohiis	move.l	4.w,a6
	moveq	#0,d0
	btst	d0,AttnFlags+1(a6)
	beq.b	.no68010

	push	a5
	lea	liko(pc),a5
	call	_LVOSupervisor
	pull	a5
.no68010
	move.l	d0,vbrr(a5)

	push	a5
	bsr	FinalInit
	pull	a5

	lea	$dff000,a6
	move.l	vbrr(a5),a0
	move.l	$70(a0),olev4(a5)
	lea	lev4(pc),a3
	move.l	a3,$70(a0)
	move.w	#$800f,$96(a6)
	move.w	#$c080,$9a(a6)
StartModule:
	bsr	SetCIAInt
	rts
** You don't have to call play within regular intervals. The routine just 
** swallows cpu as it sees fit, but probably some 50Hz is the best.


stop_interrupt	lea	data(pc),a5
	bsr	RemCIAInt
	move.l	vbrr(a5),a0
	move.l	olev4(a5),$70(a0)
	lea	$dff000,a6
	clr	$a8(a6)			;Volumes down...
	clr	$b8(a6)
	clr	$c8(a6)
	clr	$d8(a6)
	move.w	#$80,$9a(a6)
	bsr	s3end
	moveq.l	#0,d0
	rts

liko
	ifeq	disable020
	MOVEC	VBR,d0
	endc
	rte


	IFNE	fforwrd
EMS_fastforward:
	btst	#10,$dff016		;Is right button being pressed?
	bne.s	no_fastforwards		;No.
	moveq.l	#$0f,d7			;Fastforward by 16 frames.
ffloop:	bsr	EMS_music		;Call the player.
	dbf	d7,ffloop		;Do the fastforward.
no_fastforwards:
	rts				;End of fastforward.
	ENDC

;	/*
;	** Routines to setup/stop the interrupt servers.
;	*/

****************************************************************************
*
* A system friendly way to use the CIA timer interrupts
*
* By K-P Koljonen 7.8.1996
*
* E-mail: k-p@kalahari.ton.tut.fi
*         kpk@pcuf.fi
*
* ---
* 
* Call init_ciaint() to initialize interrupt and rem_ciaint()
* to remove interrupt.
*
****************************************************************************





SetCIAInt	lea	icause(pc),a0
	lea	ciainterrupt(pc),a1
	move.l	a1,(a0)
	lea	sptr1(pc),a0
	lea	softserver(pc),a1
	move.l	a1,(a0)
	lea	sint(pc),a0
	lea	softint(pc),a1
	move.l	a1,(a0)
	bsr.b	init_ciaint
	rts

init_ciaint	lea	data(pc),a5			;Pointer to data structure.
	lea	cianame(pc),a1			;Pointer to CIA name.
	move.l	a1,-(sp)			;Save address.
	move.b	#'a',3(a1)			;Set up CIA-A first.
	move.l	$4.w,a6				;Execbase address.
	moveq.l	#0,d0				;Clear D0.
	jsr	_LVOOpenResource(a6)		;Open CIA resources.
	move.l	d0,ciabasea(a5)			;Store CIA pointer.
	move.l	(sp)+,a1			;Restore CIA name pointer.
	move.b	#'b',3(a1)			;Setup CIA-B second.
	moveq.l	#0,d0				;Clear D0.
	jsr	_LVOOpenResource(a6)		;Open CIA resources.
	move.l	d0,ciabaseb(a5)			;Store CIA pointer.

	movem.l	d1-a6,-(sp)			;Save registers.

	move.w	#28419/2,timerhi(a5)		;50 hz timer interval.
** CIAA
	lea	_ciaa,a3			;Pointer to CIA-A base.
	lea	ciaserver(pc),a4		;Pointer to CIA server.
	moveq.l	#0,d6				;Clear D6.
	move.l	ciabasea(a5),a6			;Pointer to CIA base address.
	lea	(a4),a1				;Get address.
	moveq.l	#0,d0				;Timer A.
	move.l	d0,d6				;Setup D6.
	jsr	_LVOAddICRVector(a6)		;Set ICR vector.
	tst.l	d0				;OK?
	beq.s	gottimer			;Yes.

	lea	(a4),a1				;Address to A1.
	moveq.l	#1,d0				;Timer B.
	move.l	d0,d6				;Timer B to d6.
	jsr	_LVOAddICRVector(a6)		;Set ICR vector.
	tst.l	d0				;OK?
	beq.s	gottimer			;Yes.

** CIAB
	lea	_ciab,a3			;Pointer to CIA-B base.
	lea	ciaserver(pc),a4		;Pointer to CIA server.
	moveq.l	#0,d6				;Clear D6.
	move.l	ciabaseb(a5),a6			;Get pointer.
	lea	(a4),a1				;Address to A1.
	moveq.l	#0,d0				;Timer a
	move.l	d0,d6				;Clear D6.
	jsr	_LVOAddICRVector(a6)		;Set ICR vector.
	tst.l	d0				;OK?
	beq.s	gottimer			;Yes.

	lea	(a4),a1				;Address to A1.
	moveq.l	#1,d0				;Timer B.
	move.l	d0,d6				;D6=1.
	jsr	_LVOAddICRVector(a6)		;Add interrupt server.
	tst.l	d0				;Is it OK?
	beq.s	gottimer			;Yes.

	movem.l	(sp)+,d1-a6			;Restore regs.
	moveq.l	#-1,d0				;ERROR! No timer available!
	rts

gottimer
	move.l	a3,ciaddr(a5)			;Address set up.
	move.l	a6,ciabase(a5)			;Address set up.
	move.b	d6,whichtimer(a5)		;0: timer a, 1:timer b.

** Set up timer registers

	lea	ciatalo(a3),a2			;Address to A2.
	tst.b	d6				;Is it timer A?
	beq.b	timera				;Yes.
	lea	ciatblo(a3),a2			;Timer B low address.
timera	move.b	timerlo(a5),(a2)		;Timer low byte.
	move.b	timerhi(a5),$100(a2)		;High byte.

	lea	ciacra(a3),a2			;Address to A2.
	tst.b	d6				;Is it timer A?
	beq.b	tima				;Yes.
	lea	ciacrb(a3),a2			;Address to A2.
tima

** timer control register
wraster:
	cmp.b	#$c0,$dff006
	bne.s	wraster
	move.b	#%00010001,(a2)			;Continuous, force load.
	movem.l	(sp)+,d1-a6			;Restore regs.
	moveq.l	#0,d0				;OK message.
	rts					;End.



RemCIAInt:
	movem.l	d0-a6,-(sp)			;Save regs.
	move.l	ciaddr(a5),a3			;Address to A3.

	moveq.l	#0,d0				;Clear D0.
	move.b	whichtimer(a5),d0		;Get timer value.
	bne.b	tb				;1=Timer B.
	move.b	#%00000000,ciacra(a3)		;Clear timer A.
	bra.b	ta				;Skip next command.
tb	move.b	#%00000000,ciacrb(a3)		;Clear timer B.
ta	move.l	ciabase(a5),a6			;CIA address to A6.
	lea	ciaserver(pc),a1		;Pointer to server.
	jsr	_LVORemICRVector(a6)		;Remove ICR vector.
	movem.l	(sp)+,d0-a6			;Restore regs.
	rts



ciaserver:
	dc.l	0,0
	dc.b	2
	dc.b	0		* interrupt priority
nptr1:	dc.l	0		* node name
sptr1:	dc.l	0		* IS_DATA
icause:	dc.l	0		* IS_CODE

intname2:
	dc.b	"EMSV6-CIA Interrupt",0
	even
cianame:
	dc.b	"ciaa.resource",0
	even

* Cause() a level 1 software interrupt to avoid executing code in high 
* priority interrupts (CIAA = lev 2, CIAB = lev 6). Lev 6 easily
* interferes with serial transfers.

ciainterrupt
* a6 = execbase
* a1 = softserver address
	move.l	4.w,a6
	jsr	_LVOCause(a6)
	moveq	#0,d0
	rts

softserver	dc.l	0,0
	dc.b	2
	dc.b	0		* interrupt priority
	dc.l	0		* node name
	dc.l	$bfe001		* IS_DATA
sint	dc.l	0		* IS_CODE

interrupt_mutex		dc.l	0
uade_restart_cmd	dc.l	0
uade_stop_cmd		dc.l	0
uade_active_channels	dc.l	0

softint	tst.l	interrupt_mutex
	bne.b	no_softint
	st	interrupt_mutex

	movem.l	d2-d7/a0/a2-a4/a6,-(sp)
	bsr	play
	movem.l	(sp)+,d2-d7/a0/a2-a4/a6

	move.l	uade_restart_cmd(pc),d0
	or.l	uade_stop_cmd(pc),d0
	cmp.l	#-1,d0
	bne.b	not_song_end
	bsr	report_song_end
not_song_end
	clr.l	interrupt_mutex
no_softint	moveq	#0,d0
	rts

;	/*
;	** Time to declare the S3M audio mixer structure space.
;	*/

;*** Datas ***

data:		dcb.b	162,0		;1 byte extra evens out struct.

divtabs		ds.l	16

cha0		ds.b	mChanBlock_SIZE*32

pantab		ds.b	32			;channel panning infos

dosname	dc.b	"dos.library",0
	even
dosbase	dc.l	0

	include	ems_player_dis.asm
	even

	if asmone=1
Module
;	incbin	nfs:deli/ems/EMSV6.Stormlord
	incbin	nfs:deli/ems/EMSV6.SynthTest
;	include	"A sporting chance.s"	;Module file here.
;	include	"Perception test.s"
;	include	"Tropical Islands.s"
;	include	"Stormlord.s"
;	include	"testfile.s"
;	include	"blank-data.s"
	endif
