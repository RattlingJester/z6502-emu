.segment "IO"

MONCOUT: 
	pha
	lda #$04
	sta $D013
	pla
	sta $D012
	rts
	
MONRDKEY:
	lda $D011
	bpl MONRDKEY
	lda $D010
	rts
