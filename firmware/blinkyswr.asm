
blinkyswr.bin:     file format elf32-avr

Sections:
Idx Name          Size      VMA       LMA       File off  Algn
  0 .text         00000370  00000000  00000000  00000074  2**1
                  CONTENTS, ALLOC, LOAD, READONLY, CODE
  1 .data         00000000  00800060  00000370  000003e4  2**0
                  CONTENTS, ALLOC, LOAD, DATA
  2 .comment      00000030  00000000  00000000  000003e4  2**0
                  CONTENTS, READONLY
  3 .debug_aranges 00000030  00000000  00000000  00000414  2**0
                  CONTENTS, READONLY, DEBUGGING
  4 .debug_info   000005df  00000000  00000000  00000444  2**0
                  CONTENTS, READONLY, DEBUGGING
  5 .debug_abbrev 0000020d  00000000  00000000  00000a23  2**0
                  CONTENTS, READONLY, DEBUGGING
  6 .debug_line   0000045f  00000000  00000000  00000c30  2**0
                  CONTENTS, READONLY, DEBUGGING
  7 .debug_frame  00000064  00000000  00000000  00001090  2**2
                  CONTENTS, READONLY, DEBUGGING
  8 .debug_str    000001ff  00000000  00000000  000010f4  2**0
                  CONTENTS, READONLY, DEBUGGING
  9 .debug_loc    0000092f  00000000  00000000  000012f3  2**0
                  CONTENTS, READONLY, DEBUGGING
 10 .debug_ranges 00000038  00000000  00000000  00001c22  2**0
                  CONTENTS, READONLY, DEBUGGING

Disassembly of section .text:

00000000 <start>:

// We are saving couple of bytes by avoiding the standard start files and interrupt tables and
// providing custom substitutes.
__attribute__((naked,section(".vectors"))) void start(void)
{
    asm volatile(
   0:	21 c0       	rjmp	.+66     	; 0x44 <__onreset>
   2:	18 95       	reti
   4:	18 95       	reti
   6:	1c c1       	rjmp	.+568    	; 0x240 <__vector_3>
   8:	18 95       	reti
   a:	18 95       	reti
   c:	12 c1       	rjmp	.+548    	; 0x232 <__vector_6>
   e:	18 95       	reti
  10:	18 95       	reti
  12:	18 95       	reti

00000014 <__trampolines_end>:
  14:	13 00       	.word	0x0013	; ????
  16:	11 01       	movw	r2, r2
  18:	11 10       	cpse	r1, r1
  1a:	12 10       	cpse	r1, r2
  1c:	12 02       	muls	r17, r18
  1e:	03 02       	muls	r16, r19
  20:	03 01       	movw	r0, r6
  22:	03 01       	movw	r0, r6

00000024 <diode_correction_table_rough>:
  24:	20 00 e8 00 3d 01 9a 01 eb 01 39 02 82 02 ca 02      ...=.....9.....
  34:	10 03 55 03 99 03 db 03 1d 04 5e 04 9e 04 dd 04     ..U.......^.....

00000044 <__onreset>:

void __onreset(void)
{
	// Naked start function requires us to set the stack and R1 to zero.
    asm volatile ( ".set __stack, %0" :: "i" (RAMEND) );
    asm volatile ( "clr __zero_reg__" );        // R1 set to 0 (GCC expects the R1 register to be set to zero at program start)
  44:	11 24       	eor	r1, r1

	// Interrupts are disabled after reset.
	
	// Disable watch dog.
	wdt_reset();
  46:	a8 95       	wdr
	// Clear WDRF in MCUSR
	MCUSR &= ~(1<<WDRF);
  48:	84 b7       	in	r24, 0x34	; 52
  4a:	87 7f       	andi	r24, 0xF7	; 247
  4c:	84 bf       	out	0x34, r24	; 52
	// Write logical one to WDCE and WDE, keep old prescaler setting to prevent unintentional time-out.
	WDTCR |= (1<<WDCE) | (1<<WDE);
  4e:	81 b5       	in	r24, 0x21	; 33
  50:	88 61       	ori	r24, 0x18	; 24
  52:	81 bd       	out	0x21, r24	; 33
	// Turn off WDT.
	WDTCR = 0x00;
  54:	11 bc       	out	0x21, r1	; 33
	//Initialize Timer/Counter 0, normal mode.
//	TCCR0A = 0; // No need to set it, it is the initial value after reset.
	// Stop the timer.
//	TCCR0B = 0; // No need to set it, it is the initial value after reset.
	// Interrupt on overflow.
	TIMSK0 = 1<<TOIE0;
  56:	82 e0       	ldi	r24, 0x02	; 2
  58:	89 bf       	out	0x39, r24	; 57

#ifdef DEBUG_SPI
//	correct_diode_test();
#endif /* DEBUG_SPI */

	sei();
  5a:	78 94       	sei
	// Wait a bit.
//	vfwd = 0xffff;
//	do {
		// Disable all digital input buffers for lower current consumption, as we are using two analog inputs
		// and three tri-stated output pins.
		DIDR0 = 0x3f;
  5c:	8f e3       	ldi	r24, 0x3F	; 63
  5e:	84 bb       	out	0x14, r24	; 20

	sei();
	
	uint16_t vfwd, vref;
	uint8_t i;
	unsigned char no_input_power_cnt = 0;
  60:	a0 e0       	ldi	r26, 0x00	; 0
		// Enable ADC, set clock prescaler to 1/16 of the main clock 
		// (that is with main clock 9.6MHz/8 = 1.2MHz, the ADC sample rate is 1.2MHz / 16 / 13 = 5.77kHz
		// Enable ADC and Timer0 in power reduction register.
		PRR = 0;
		// Enable ADC interrupts.
		ADCSRA = (1<<ADEN)|(1<<ADIE)|(1<<ADPS2);
  62:	bc e8       	ldi	r27, 0x8C	; 140
  64:	ab 2e       	mov	r10, r27
		ADMUX = REF_INT | ADC_PWR;    // set reference and channel
  66:	c3 e4       	ldi	r28, 0x43	; 67
  68:	9c 2e       	mov	r9, r28

		// Enter Sleep Mode To Trigger ADC Measurement. CPU Will Wake Up From ADC Interrupt.
		// The first measurement will be thrown away after enabling the ADC.
		// Instead of calling set_sleep_mode(SLEEP_MODE_ADC) which reads the state of MCUCR, modifies it and writes it back,
		// just write a constant into MCUCR, as we shall know the state of the MCUCR already.
		MCUCR = (1 << SM0) | PUD_VALUE;
  6a:	18 e4       	ldi	r17, 0x48	; 72
		// sleep_mode();
		MCUCR = (1 << SM0) | (1 << SE) | PUD_VALUE;
  6c:	08 e6       	ldi	r16, 0x68	; 104

no_power:
		// Disable ADC until the next 75Hz cycle.
		ADCSRA = 0;
		// Disable ADC in power reduction register, enable Timer0.
		PRR = (1<<PRADC);
  6e:	dd 24       	eor	r13, r13
  70:	d3 94       	inc	r13
		// Process the "no input power" state. Input power lower than 0.2W.
		// Start the timer to measure the 73.24Hz cycle and modulate the LEDs.
		TCNT0 = 13; // This is the time the A/D capture will take.
  72:	dd e0       	ldi	r29, 0x0D	; 13
  74:	8d 2e       	mov	r8, r29
		TCCR0B = (1<<CS01)|(1 <<CS00); // clck_io / 64: 73.24Hz period.
  76:	83 e0       	ldi	r24, 0x03	; 3
  78:	c8 2e       	mov	r12, r24
				goto no_power;
#endif /* DEBUG_SPI */
			vfwd += vadc;
		} while (-- i);

		ADMUX = REF_INT | ADC_REF;    // set reference and channel
  7a:	91 e4       	ldi	r25, 0x41	; 65
  7c:	79 2e       	mov	r7, r25
			// Wait until the timer overflows.
			// Two interrupts may wake up the micro from the sleep: Timer0 compare A event and Timer0 overflow.
			// The Timer0 overflow event handler resets TCCR0B to stop the timer and let us know to exit the sleep loop.
			// Instead of calling set_sleep_mode(SLEEP_MODE_IDLE) which reads the state of MCUCR, modifies it and writes it back,
			// just write a constant into MCUCR, as we shall know the state of the MCUCR already.
			MCUCR = PUD_VALUE;
  7e:	40 e4       	ldi	r20, 0x40	; 64
  80:	b4 2e       	mov	r11, r20
			do {
				// sleep_mode();
				MCUCR = (1 << SE) | PUD_VALUE;
  82:	50 e6       	ldi	r21, 0x60	; 96
  84:	65 2e       	mov	r6, r21
	// Main loop, forever:
	for (;;) {
		// Enable ADC, set clock prescaler to 1/16 of the main clock 
		// (that is with main clock 9.6MHz/8 = 1.2MHz, the ADC sample rate is 1.2MHz / 16 / 13 = 5.77kHz
		// Enable ADC and Timer0 in power reduction register.
		PRR = 0;
  86:	15 bc       	out	0x25, r1	; 37
		// Enable ADC interrupts.
		ADCSRA = (1<<ADEN)|(1<<ADIE)|(1<<ADPS2);
  88:	a6 b8       	out	0x06, r10	; 6
		ADMUX = REF_INT | ADC_PWR;    // set reference and channel
  8a:	97 b8       	out	0x07, r9	; 7

		// Enter Sleep Mode To Trigger ADC Measurement. CPU Will Wake Up From ADC Interrupt.
		// The first measurement will be thrown away after enabling the ADC.
		// Instead of calling set_sleep_mode(SLEEP_MODE_ADC) which reads the state of MCUCR, modifies it and writes it back,
		// just write a constant into MCUCR, as we shall know the state of the MCUCR already.
		MCUCR = (1 << SM0) | PUD_VALUE;
  8c:	15 bf       	out	0x35, r17	; 53
		// sleep_mode();
		MCUCR = (1 << SM0) | (1 << SE) | PUD_VALUE;
  8e:	05 bf       	out	0x35, r16	; 53
		sleep_cpu();
  90:	88 95       	sleep
		MCUCR = (1 << SM0) | PUD_VALUE;
  92:	15 bf       	out	0x35, r17	; 53
  94:	48 e0       	ldi	r20, 0x08	; 8
		// Enable ADC interrupts.
		ADCSRA = (1<<ADEN)|(1<<ADIE)|(1<<ADPS2);
		ADMUX = REF_INT | ADC_PWR;    // set reference and channel
		
		// Reset the accumulators.
		vfwd = 0;
  96:	80 e0       	ldi	r24, 0x00	; 0
  98:	90 e0       	ldi	r25, 0x00	; 0
		i = 8;
		do {
			// Enter Sleep Mode To Trigger ADC Measurement. CPU Will Wake Up From ADC Interrupt.
			// Instead of calling sleep_mode() which reads the state of MCUCR, modifies it and writes it back,
			// just write a constant into MCUCR, as we shall know the state of the MCUCR already.
			MCUCR = (1 << SM0) | (1 << SE) | PUD_VALUE;
  9a:	05 bf       	out	0x35, r16	; 53
			sleep_cpu();
  9c:	88 95       	sleep
			MCUCR = (1 << SM0) | PUD_VALUE;
  9e:	15 bf       	out	0x35, r17	; 53
			unsigned long vadc = ADC;
  a0:	64 b1       	in	r22, 0x04	; 4
  a2:	75 b1       	in	r23, 0x05	; 5
#ifndef DEBUG_SPI
			if (vadc < 104)
  a4:	68 36       	cpi	r22, 0x68	; 104
  a6:	71 05       	cpc	r23, r1
  a8:	08 f4       	brcc	.+2      	; 0xac <__stack+0xd>
  aa:	6d c0       	rjmp	.+218    	; 0x186 <__stack+0xe7>
				// input power lower than 0.2W
				goto no_power;
#endif /* DEBUG_SPI */
			vfwd += vadc;
  ac:	86 0f       	add	r24, r22
  ae:	97 1f       	adc	r25, r23
  b0:	41 50       	subi	r20, 0x01	; 1
		} while (-- i);
  b2:	99 f7       	brne	.-26     	; 0x9a <__onreset+0x56>

		ADMUX = REF_INT | ADC_REF;    // set reference and channel
  b4:	77 b8       	out	0x07, r7	; 7
  b6:	28 e0       	ldi	r18, 0x08	; 8
		ADCSRA = (1<<ADEN)|(1<<ADIE)|(1<<ADPS2);
		ADMUX = REF_INT | ADC_PWR;    // set reference and channel
		
		// Reset the accumulators.
		vfwd = 0;
		vref = 0;
  b8:	e1 2c       	mov	r14, r1
  ba:	f1 2c       	mov	r15, r1
		i = 8;
		do {
			// Enter Sleep Mode To Trigger ADC Measurement. CPU Will Wake Up From ADC Interrupt.
			// Instead of calling sleep_mode() which reads the state of MCUCR, modifies it and writes it back,
			// just write a constant into MCUCR, as we shall know the state of the MCUCR already.
			MCUCR = (1 << SM0) | (1 << SE) | PUD_VALUE;
  bc:	05 bf       	out	0x35, r16	; 53
			sleep_cpu();
  be:	88 95       	sleep
			MCUCR = (1 << SM0) | PUD_VALUE;
  c0:	15 bf       	out	0x35, r17	; 53
			unsigned long vadc = ADC;
  c2:	44 b1       	in	r20, 0x04	; 4
  c4:	55 b1       	in	r21, 0x05	; 5
			vref += vadc;
  c6:	e4 0e       	add	r14, r20
  c8:	f5 1e       	adc	r15, r21
  ca:	21 50       	subi	r18, 0x01	; 1
		} while (-- i);
  cc:	b9 f7       	brne	.-18     	; 0xbc <__stack+0x1d>
		
		// Input power is above 0.2W. Show SWR.
		// Start the timer to measure the 73.24Hz cycle and modulate the LEDs.
		TCNT0 = 72; // This is the time the A/D capture will take.
  ce:	28 e4       	ldi	r18, 0x48	; 72
  d0:	22 bf       	out	0x32, r18	; 50
		TCCR0B = (1<<CS01)|(1 <<CS00); // clck_io / 64: 73.24Hz period.
  d2:	c3 be       	out	0x33, r12	; 51
		// Disable ADC until the next 75Hz cycle.
		ADCSRA = 0;
  d4:	16 b8       	out	0x06, r1	; 6
		// Disable ADC in power reduction register, enable Timer0.
		PRR = (1<<PRADC);
  d6:	d5 bc       	out	0x25, r13	; 37
		no_input_power_cnt = 0;
		vfwd = correct_diode(vfwd);
  d8:	b8 d0       	rcall	.+368    	; 0x24a <correct_diode>
  da:	ec 01       	movw	r28, r24
		vref = correct_diode(vref);
  dc:	c7 01       	movw	r24, r14
  de:	b5 d0       	rcall	.+362    	; 0x24a <correct_diode>
	// Show SWR infinity by default.
	unsigned char led_idx   = 6;
	// No need to initialize led_value, any value with led_idx will fully light the last LED.
	unsigned char led_value = 0;
	// Calculate SWR value
	if (pwr_in > ref_in) {
  e0:	8c 17       	cp	r24, r28
  e2:	9d 07       	cpc	r25, r29
  e4:	08 f0       	brcs	.+2      	; 0xe8 <__stack+0x49>
  e6:	41 c0       	rjmp	.+130    	; 0x16a <__stack+0xcb>
		// SWR calculated with 5 bits resolution right of the decimal point.
		unsigned int swr;
		{
			unsigned int num   = pwr_in + ref_in;
			unsigned int denom = (pwr_in - ref_in + 0x0f) >> 5;
  e8:	be 01       	movw	r22, r28
  ea:	61 5f       	subi	r22, 0xF1	; 241
  ec:	7f 4f       	sbci	r23, 0xFF	; 255
  ee:	68 1b       	sub	r22, r24
  f0:	79 0b       	sbc	r23, r25
  f2:	e5 e0       	ldi	r30, 0x05	; 5
  f4:	76 95       	lsr	r23
  f6:	67 95       	ror	r22
  f8:	ea 95       	dec	r30
  fa:	e1 f7       	brne	.-8      	; 0xf4 <__stack+0x55>
			swr = (num + (denom >> 1)) / denom;
  fc:	8c 0f       	add	r24, r28
  fe:	9d 1f       	adc	r25, r29
 100:	9b 01       	movw	r18, r22
 102:	36 95       	lsr	r19
 104:	27 95       	ror	r18
 106:	82 0f       	add	r24, r18
 108:	93 1f       	adc	r25, r19
 10a:	1e d1       	rcall	.+572    	; 0x348 <__udivmodhi4>
 10c:	cb 01       	movw	r24, r22
		}
		// SWR must be above 1:1
		// assert(swr >= 32);
		if (swr < 48) {
 10e:	60 33       	cpi	r22, 0x30	; 48
 110:	71 05       	cpc	r23, r1
 112:	20 f4       	brcc	.+8      	; 0x11c <__stack+0x7d>
			// SWR from 1:1 to 1:1.5
			led_idx = 1;
			led_value = (unsigned char)((swr - 32) << 4);
 114:	82 95       	swap	r24
 116:	80 7f       	andi	r24, 0xF0	; 240
		}
		// SWR must be above 1:1
		// assert(swr >= 32);
		if (swr < 48) {
			// SWR from 1:1 to 1:1.5
			led_idx = 1;
 118:	21 e0       	ldi	r18, 0x01	; 1
 11a:	2c c0       	rjmp	.+88     	; 0x174 <__stack+0xd5>
			led_value = (unsigned char)((swr - 32) << 4);
		} else if (swr < 64) {
 11c:	60 34       	cpi	r22, 0x40	; 64
 11e:	71 05       	cpc	r23, r1
 120:	20 f4       	brcc	.+8      	; 0x12a <__stack+0x8b>
			// SWR from 1:1.5 to 1:2.0
			led_idx = 2;
			led_value = (unsigned char)((swr - 48) << 4);
 122:	82 95       	swap	r24
 124:	80 7f       	andi	r24, 0xF0	; 240
			// SWR from 1:1 to 1:1.5
			led_idx = 1;
			led_value = (unsigned char)((swr - 32) << 4);
		} else if (swr < 64) {
			// SWR from 1:1.5 to 1:2.0
			led_idx = 2;
 126:	22 e0       	ldi	r18, 0x02	; 2
 128:	25 c0       	rjmp	.+74     	; 0x174 <__stack+0xd5>
			led_value = (unsigned char)((swr - 48) << 4);
		} else if (swr < 96) {
 12a:	60 36       	cpi	r22, 0x60	; 96
 12c:	71 05       	cpc	r23, r1
 12e:	28 f4       	brcc	.+10     	; 0x13a <__stack+0x9b>
			// SWR from 1:2.0 to 1:3.0
			led_idx = 3;
			led_value = (unsigned char)((swr - 64) << 3);
 130:	88 0f       	add	r24, r24
 132:	88 0f       	add	r24, r24
 134:	88 0f       	add	r24, r24
			// SWR from 1:1.5 to 1:2.0
			led_idx = 2;
			led_value = (unsigned char)((swr - 48) << 4);
		} else if (swr < 96) {
			// SWR from 1:2.0 to 1:3.0
			led_idx = 3;
 136:	23 e0       	ldi	r18, 0x03	; 3
 138:	1d c0       	rjmp	.+58     	; 0x174 <__stack+0xd5>
			led_value = (unsigned char)((swr - 64) << 3);
		} else if (swr < 160) {
 13a:	60 3a       	cpi	r22, 0xA0	; 160
 13c:	71 05       	cpc	r23, r1
 13e:	28 f4       	brcc	.+10     	; 0x14a <__stack+0xab>
			// SWR from 1:3.0 to 1:5.0
			led_idx = 4;
			led_value = (unsigned char)((swr - 96) << 2);
 140:	80 56       	subi	r24, 0x60	; 96
 142:	88 0f       	add	r24, r24
 144:	88 0f       	add	r24, r24
			// SWR from 1:2.0 to 1:3.0
			led_idx = 3;
			led_value = (unsigned char)((swr - 64) << 3);
		} else if (swr < 160) {
			// SWR from 1:3.0 to 1:5.0
			led_idx = 4;
 146:	24 e0       	ldi	r18, 0x04	; 4
 148:	15 c0       	rjmp	.+42     	; 0x174 <__stack+0xd5>
			led_value = (unsigned char)((swr - 96) << 2);
		} else if (swr < 256) {
 14a:	6f 3f       	cpi	r22, 0xFF	; 255
 14c:	71 05       	cpc	r23, r1
 14e:	09 f0       	breq	.+2      	; 0x152 <__stack+0xb3>
 150:	78 f4       	brcc	.+30     	; 0x170 <__stack+0xd1>
			// SWR from 1:5.0 to 1:8.0
			led_idx = 5;
			// swr * 256 / 96 = approximately floor((swr * 341 + 63) / 128)
			led_value = (unsigned char)(((swr - 160) * 341 + 63) >> 7);
 152:	65 e5       	ldi	r22, 0x55	; 85
 154:	71 e0       	ldi	r23, 0x01	; 1
 156:	e7 d0       	rcall	.+462    	; 0x326 <__mulhi3>
 158:	81 5e       	subi	r24, 0xE1	; 225
 15a:	94 4d       	sbci	r25, 0xD4	; 212
 15c:	88 0f       	add	r24, r24
 15e:	89 2f       	mov	r24, r25
 160:	88 1f       	adc	r24, r24
 162:	99 0b       	sbc	r25, r25
 164:	91 95       	neg	r25
			// SWR from 1:3.0 to 1:5.0
			led_idx = 4;
			led_value = (unsigned char)((swr - 96) << 2);
		} else if (swr < 256) {
			// SWR from 1:5.0 to 1:8.0
			led_idx = 5;
 166:	25 e0       	ldi	r18, 0x05	; 5
 168:	05 c0       	rjmp	.+10     	; 0x174 <__stack+0xd5>
inline __attribute__((always_inline)) unsigned int swr_to_baragraph(unsigned int pwr_in, unsigned int ref_in)
{
	// Show SWR infinity by default.
	unsigned char led_idx   = 6;
	// No need to initialize led_value, any value with led_idx will fully light the last LED.
	unsigned char led_value = 0;
 16a:	80 e0       	ldi	r24, 0x00	; 0
}

inline __attribute__((always_inline)) unsigned int swr_to_baragraph(unsigned int pwr_in, unsigned int ref_in)
{
	// Show SWR infinity by default.
	unsigned char led_idx   = 6;
 16c:	26 e0       	ldi	r18, 0x06	; 6
 16e:	02 c0       	rjmp	.+4      	; 0x174 <__stack+0xd5>
	// No need to initialize led_value, any value with led_idx will fully light the last LED.
	unsigned char led_value = 0;
 170:	80 e0       	ldi	r24, 0x00	; 0
}

inline __attribute__((always_inline)) unsigned int swr_to_baragraph(unsigned int pwr_in, unsigned int ref_in)
{
	// Show SWR infinity by default.
	unsigned char led_idx   = 6;
 172:	26 e0       	ldi	r18, 0x06	; 6
	spi_byte(led_value);
	PORTB = (1 << SPI_EN);
#else /* DEBUG_SPI */
//	interpolate_baragraph(led_idx, led_value);
#endif /* DEBUG_SPI */
	return ((unsigned int)(led_idx) << 8) | led_value;
 174:	90 e0       	ldi	r25, 0x00	; 0
 176:	92 2b       	or	r25, r18
		PRR = (1<<PRADC);
		no_input_power_cnt = 0;
		vfwd = correct_diode(vfwd);
		vref = correct_diode(vref);

		vfwd0 = vfwd1;
 178:	25 2d       	mov	r18, r5
 17a:	34 2d       	mov	r19, r4
		vfwd1 = vfwd2;
 17c:	21 01       	movw	r4, r2
		// Disable ADC until the next 75Hz cycle.
		ADCSRA = 0;
		// Disable ADC in power reduction register, enable Timer0.
		PRR = (1<<PRADC);
		no_input_power_cnt = 0;
		vfwd = correct_diode(vfwd);
 17e:	3c 2e       	mov	r3, r28
 180:	2d 2e       	mov	r2, r29
		TCCR0B = (1<<CS01)|(1 <<CS00); // clck_io / 64: 73.24Hz period.
		// Disable ADC until the next 75Hz cycle.
		ADCSRA = 0;
		// Disable ADC in power reduction register, enable Timer0.
		PRR = (1<<PRADC);
		no_input_power_cnt = 0;
 182:	a0 e0       	ldi	r26, 0x00	; 0
		spi_byte(vref & 0x0ff);
//		PORTB = (1 << SPI_EN);
#else /* DEBUG_SPI */
		vfwd = swr_to_baragraph(vfwd, vref);
#endif /* DEBUG_SPI */
		goto wait_end;
 184:	1f c0       	rjmp	.+62     	; 0x1c4 <__stack+0x125>

no_power:
		// Disable ADC until the next 75Hz cycle.
		ADCSRA = 0;
 186:	16 b8       	out	0x06, r1	; 6
		// Disable ADC in power reduction register, enable Timer0.
		PRR = (1<<PRADC);
 188:	d5 bc       	out	0x25, r13	; 37
		// Process the "no input power" state. Input power lower than 0.2W.
		// Start the timer to measure the 73.24Hz cycle and modulate the LEDs.
		TCNT0 = 13; // This is the time the A/D capture will take.
 18a:	82 be       	out	0x32, r8	; 50
		TCCR0B = (1<<CS01)|(1 <<CS00); // clck_io / 64: 73.24Hz period.
 18c:	c3 be       	out	0x33, r12	; 51
		// By default, switch off the LEDs.
		vfwd = 0;
		if (no_input_power_cnt < 74) {
 18e:	aa 34       	cpi	r26, 0x4A	; 74
 190:	a0 f4       	brcc	.+40     	; 0x1ba <__stack+0x11b>
			// Less than 1 seconds.
			if (++ no_input_power_cnt > 37) {
 192:	af 5f       	subi	r26, 0xFF	; 255
 194:	a6 32       	cpi	r26, 0x26	; 38
 196:	a0 f0       	brcs	.+40     	; 0x1c0 <__stack+0x121>
				// More than 0.5 second.
				// Round to a byte. 
				vfwd = (vfwd0 + 0x03f) >> 7;
 198:	b9 01       	movw	r22, r18
 19a:	61 5c       	subi	r22, 0xC1	; 193
 19c:	7f 4f       	sbci	r23, 0xFF	; 255
 19e:	66 0f       	add	r22, r22
 1a0:	67 2f       	mov	r22, r23
 1a2:	66 1f       	adc	r22, r22
 1a4:	77 0b       	sbc	r23, r23
 1a6:	71 95       	neg	r23
				// Now vfwd0 == 256 corresponds to input power of 16 watts,
				// vfwd0 * vfwd0 == 65536 corresponds to input power of 16 watts,
				vfwd = (vfwd * vfwd + 0x07) >> 4;
 1a8:	cb 01       	movw	r24, r22
 1aa:	bd d0       	rcall	.+378    	; 0x326 <__mulhi3>
 1ac:	07 96       	adiw	r24, 0x07	; 7
 1ae:	54 e0       	ldi	r21, 0x04	; 4
 1b0:	96 95       	lsr	r25
 1b2:	87 95       	ror	r24
 1b4:	5a 95       	dec	r21
 1b6:	e1 f7       	brne	.-8      	; 0x1b0 <__stack+0x111>
 1b8:	05 c0       	rjmp	.+10     	; 0x1c4 <__stack+0x125>
		// Process the "no input power" state. Input power lower than 0.2W.
		// Start the timer to measure the 73.24Hz cycle and modulate the LEDs.
		TCNT0 = 13; // This is the time the A/D capture will take.
		TCCR0B = (1<<CS01)|(1 <<CS00); // clck_io / 64: 73.24Hz period.
		// By default, switch off the LEDs.
		vfwd = 0;
 1ba:	80 e0       	ldi	r24, 0x00	; 0
 1bc:	90 e0       	ldi	r25, 0x00	; 0
 1be:	02 c0       	rjmp	.+4      	; 0x1c4 <__stack+0x125>
 1c0:	80 e0       	ldi	r24, 0x00	; 0
 1c2:	90 e0       	ldi	r25, 0x00	; 0
		// Fall through to wait_end.

wait_end:
		{
			struct LedState led_state;
			interpolate_baragraph((unsigned char)(vfwd >> 8), (unsigned char)(vfwd & 0x0FF), &led_state);
 1c4:	68 2f       	mov	r22, r24
inline __attribute__((always_inline)) void interpolate_baragraph(unsigned char led_idx, unsigned char led_value, struct LedState *led_state)
{
	uint16_t addr;
	if (led_idx > 6)
		led_idx = 6;
	addr = (uint16_t)led_table + (led_idx << 1);
 1c6:	49 2f       	mov	r20, r25
 1c8:	97 30       	cpi	r25, 0x07	; 7
 1ca:	08 f0       	brcs	.+2      	; 0x1ce <__stack+0x12f>
 1cc:	46 e0       	ldi	r20, 0x06	; 6
 1ce:	50 e0       	ldi	r21, 0x00	; 0
 1d0:	44 0f       	add	r20, r20
 1d2:	55 1f       	adc	r21, r21
 1d4:	4c 5e       	subi	r20, 0xEC	; 236
 1d6:	5f 4f       	sbci	r21, 0xFF	; 255
	led_state->dir1 = __LPM(addr ++);
 1d8:	fa 01       	movw	r30, r20
 1da:	b4 91       	lpm	r27, Z
	led_state->out1 = __LPM(addr ++);
 1dc:	31 96       	adiw	r30, 0x01	; 1
 1de:	94 91       	lpm	r25, Z
	led_state->dir2 = __LPM(addr ++);
 1e0:	31 96       	adiw	r30, 0x01	; 1
 1e2:	74 91       	lpm	r23, Z
 1e4:	c7 2f       	mov	r28, r23
	led_state->out2 = __LPM(addr);
 1e6:	31 96       	adiw	r30, 0x01	; 1
 1e8:	e4 91       	lpm	r30, Z
 1ea:	4e 2f       	mov	r20, r30
	if (led_value < 128) {
 1ec:	87 fd       	sbrc	r24, 7
 1ee:	05 c0       	rjmp	.+10     	; 0x1fa <__stack+0x15b>
		// Invert the timer value.
		led_value = 255 - led_value;
 1f0:	60 95       	com	r22
	uint16_t addr;
	if (led_idx > 6)
		led_idx = 6;
	addr = (uint16_t)led_table + (led_idx << 1);
	led_state->dir1 = __LPM(addr ++);
	led_state->out1 = __LPM(addr ++);
 1f2:	e9 2f       	mov	r30, r25
	led_state->dir2 = __LPM(addr ++);
	led_state->out2 = __LPM(addr);
 1f4:	94 2f       	mov	r25, r20
{
	uint16_t addr;
	if (led_idx > 6)
		led_idx = 6;
	addr = (uint16_t)led_table + (led_idx << 1);
	led_state->dir1 = __LPM(addr ++);
 1f6:	7b 2f       	mov	r23, r27
	led_state->out1 = __LPM(addr ++);
	led_state->dir2 = __LPM(addr ++);
 1f8:	bc 2f       	mov	r27, r28
#else
	// Round the LED value to 4 levels per LED interval.
	// Full intensity (the other LED fully off) will become zero.
	// 3/4 intensity will be increased to make it more pronounced from 1/2 intensity
	// due to logarithmic sensitivity of the human eye.
	led_value = (led_value + 32) & 0x0c0;
 1fa:	60 5e       	subi	r22, 0xE0	; 224
 1fc:	60 7c       	andi	r22, 0xC0	; 192
	led_state->timer_capture = (led_value == 192) ? 256 - 32 : led_value;
 1fe:	60 3c       	cpi	r22, 0xC0	; 192
 200:	09 f0       	breq	.+2      	; 0x204 <__stack+0x165>
 202:	01 c0       	rjmp	.+2      	; 0x206 <__stack+0x167>
 204:	60 ee       	ldi	r22, 0xE0	; 224
			// Wait until the timer overflows.
			// Two interrupts may wake up the micro from the sleep: Timer0 compare A event and Timer0 overflow.
			// The Timer0 overflow event handler resets TCCR0B to stop the timer and let us know to exit the sleep loop.
			// Instead of calling set_sleep_mode(SLEEP_MODE_IDLE) which reads the state of MCUCR, modifies it and writes it back,
			// just write a constant into MCUCR, as we shall know the state of the MCUCR already.
			MCUCR = PUD_VALUE;
 206:	b5 be       	out	0x35, r11	; 53
			do {
				// sleep_mode();
				MCUCR = (1 << SE) | PUD_VALUE;
 208:	65 be       	out	0x35, r6	; 53
				sleep_cpu();
 20a:	88 95       	sleep
				MCUCR = PUD_VALUE;
 20c:	b5 be       	out	0x35, r11	; 53
			} while (TCCR0B);
 20e:	83 b7       	in	r24, 0x33	; 51
 210:	81 11       	cpse	r24, r1
 212:	fa cf       	rjmp	.-12     	; 0x208 <__stack+0x169>
			// Set the LED for the next long interval.
	#ifdef DEBUG_SPI
	#else
			DDRB  = led_state.dir1;
 214:	77 bb       	out	0x17, r23	; 23
			PORTB = led_state.out1;
 216:	e8 bb       	out	0x18, r30	; 24
	#endif
			// Use PCMSK and OCR0B to communicate with the Timer0 Cature A interrupt.
			// led_state.dir2use = led_state.dir2;
			OCR0B = led_state.dir2;
 218:	b9 bd       	out	0x29, r27	; 41
			// led_state.out2use = led_state.out2;
			PCMSK = led_state.out2;
 21a:	95 bb       	out	0x15, r25	; 21
			// Clear the Timer 0 Compare A interrupt flag. The flag is normally cleared on Timer 0 Capture A interrupt, 
			// but the following line disables the Timer 0 Compare A interrupt if the timer capture value is close to overflow.
			TIFR0 |= 1<<OCF0A;
 21c:	88 b7       	in	r24, 0x38	; 56
 21e:	84 60       	ori	r24, 0x04	; 4
 220:	88 bf       	out	0x38, r24	; 56
			// Next timer run will interrupt on overflow and on compare A if the timer_capture value is not close to full period.
			TIMSK0 = led_state.timer_capture ? (1<<TOIE0) | (1<<OCIE0A) : (1<<TOIE0);
 222:	61 11       	cpse	r22, r1
 224:	02 c0       	rjmp	.+4      	; 0x22a <__stack+0x18b>
 226:	82 e0       	ldi	r24, 0x02	; 2
 228:	01 c0       	rjmp	.+2      	; 0x22c <__stack+0x18d>
 22a:	86 e0       	ldi	r24, 0x06	; 6
 22c:	89 bf       	out	0x39, r24	; 57
			OCR0A = led_state.timer_capture;
 22e:	66 bf       	out	0x36, r22	; 54
		}
		// and continue the next 75Hz cycle starting with ADC sampling.
	}
 230:	2a cf       	rjmp	.-428    	; 0x86 <__onreset+0x42>

00000232 <__vector_6>:
	// correspond to LED bits and that are powered and steady while the bit in PCMSK is set to 1, therefore
	// the bit shall not have any effect on power consumption.
	// DDRB  = led_state.dir2use;
	// PORTB = led_state.out2use;

    asm volatile(
 232:	0f 92       	push	r0
 234:	09 b4       	in	r0, 0x29	; 41
 236:	07 ba       	out	0x17, r0	; 23
 238:	05 b2       	in	r0, 0x15	; 21
 23a:	08 ba       	out	0x18, r0	; 24
 23c:	0f 90       	pop	r0
		: :
		"I" (_SFR_IO_ADDR(OCR0B)), "I" (_SFR_IO_ADDR(DDRB)),
		"I" (_SFR_IO_ADDR(PCMSK)), "I" (_SFR_IO_ADDR(PORTB)));
#endif /* DEBUG_SPI */

	asm volatile("reti");
 23e:	18 95       	reti

00000240 <__vector_3>:
	// Create a "zero" register. Actually AVRGCC expects the R1 register to always contain zero,
	// so the push / pull and resetting R1 may not be needed.
	// Using R16 - the first "upper" register, which may be filled with "ldi" instruction to set it to zero,
	// as "ldi 0" does not change change status register, while the usual "eor r1, r1" does, requiring saving 
	// and restoring the stack register.
    asm volatile(
 240:	0f 93       	push	r16
 242:	00 e0       	ldi	r16, 0x00	; 0
 244:	03 bf       	out	0x33, r16	; 51
 246:	0f 91       	pop	r16
 248:	18 95       	reti

0000024a <correct_diode>:
// Input value has 13 bits of resolution (10 bit ADC, 8 samples summed).
// Output value has 15 bits resolution, where the 0x8000 value corresponds to 16 Watts of input power.
uint16_t correct_diode(uint16_t v)
{
	uint16_t corr1, corr2;
	if (v < 256) {
 24a:	8f 3f       	cpi	r24, 0xFF	; 255
 24c:	91 05       	cpc	r25, r1
 24e:	11 f0       	breq	.+4      	; 0x254 <correct_diode+0xa>
 250:	08 f0       	brcs	.+2      	; 0x254 <correct_diode+0xa>
 252:	36 c0       	rjmp	.+108    	; 0x2c0 <correct_diode+0x76>
		// Interpolating a knee of the diode curve, table is 16 items long.
		uint16_t addr = (uint16_t)diode_correction_table_rough + ((v & 0x0f0) >> 3);
 254:	bc 01       	movw	r22, r24
 256:	60 7f       	andi	r22, 0xF0	; 240
 258:	77 27       	eor	r23, r23
 25a:	e3 e0       	ldi	r30, 0x03	; 3
 25c:	76 95       	lsr	r23
 25e:	67 95       	ror	r22
 260:	ea 95       	dec	r30
 262:	e1 f7       	brne	.-8      	; 0x25c <correct_diode+0x12>
 264:	6c 5d       	subi	r22, 0xDC	; 220
 266:	7f 4f       	sbci	r23, 0xFF	; 255
		corr1 = __LPM(addr ++);
 268:	fb 01       	movw	r30, r22
 26a:	24 91       	lpm	r18, Z
 26c:	30 e0       	ldi	r19, 0x00	; 0
		corr1 |= __LPM(addr ++) << 8;
 26e:	31 96       	adiw	r30, 0x01	; 1
 270:	e4 91       	lpm	r30, Z
 272:	3e 2b       	or	r19, r30
		if (v < 240) {
 274:	80 3f       	cpi	r24, 0xF0	; 240
 276:	91 05       	cpc	r25, r1
 278:	50 f4       	brcc	.+20     	; 0x28e <correct_diode+0x44>
			// Read two items from the "rough" table.
			corr2 = __LPM(addr ++);
 27a:	fb 01       	movw	r30, r22
 27c:	32 96       	adiw	r30, 0x02	; 2
 27e:	44 91       	lpm	r20, Z
 280:	50 e0       	ldi	r21, 0x00	; 0
			corr2 |= __LPM(addr) << 8;
 282:	31 96       	adiw	r30, 0x01	; 1
 284:	e4 91       	lpm	r30, Z
 286:	ba 01       	movw	r22, r20
 288:	7e 2b       	or	r23, r30
 28a:	fb 01       	movw	r30, r22
 28c:	0a c0       	rjmp	.+20     	; 0x2a2 <correct_diode+0x58>
		} else {
			// Read the first item from the EEPROM.
			EEARL = 0;
 28e:	1e ba       	out	0x1e, r1	; 30
			EECR |= 1<<EERE;
 290:	e0 9a       	sbi	0x1c, 0	; 28
			corr2 = EEDR;
 292:	ed b3       	in	r30, 0x1d	; 29
			++ EEARL;
 294:	4e b3       	in	r20, 0x1e	; 30
 296:	4f 5f       	subi	r20, 0xFF	; 255
 298:	4e bb       	out	0x1e, r20	; 30
			EECR |= 1<<EERE;
 29a:	e0 9a       	sbi	0x1c, 0	; 28
			corr2 |= EEDR << 8;
 29c:	4d b3       	in	r20, 0x1d	; 29
 29e:	f0 e0       	ldi	r31, 0x00	; 0
 2a0:	f4 2b       	or	r31, r20
		}
		// Now use the lowest 8 bits of the measurement value to interpolate linearly.
		return corr1 + ((((v & 0x0f) * (corr2 - corr1)) + 0x7) >> 4);
 2a2:	bf 01       	movw	r22, r30
 2a4:	62 1b       	sub	r22, r18
 2a6:	73 0b       	sbc	r23, r19
 2a8:	8f 70       	andi	r24, 0x0F	; 15
 2aa:	99 27       	eor	r25, r25
 2ac:	3c d0       	rcall	.+120    	; 0x326 <__mulhi3>
 2ae:	07 96       	adiw	r24, 0x07	; 7
 2b0:	74 e0       	ldi	r23, 0x04	; 4
 2b2:	96 95       	lsr	r25
 2b4:	87 95       	ror	r24
 2b6:	7a 95       	dec	r23
 2b8:	e1 f7       	brne	.-8      	; 0x2b2 <correct_diode+0x68>
 2ba:	82 0f       	add	r24, r18
 2bc:	93 1f       	adc	r25, r19
 2be:	08 95       	ret
	} else {
		// Read two successive entries of the diode correction table from EEPROM, table is 32 items long.
		// Address of the correction value in the EEPROM.
		EEARL = (unsigned char)(((v >> (13 - 5 - 1)) & 0x0fe) - 2);
 2c0:	9c 01       	movw	r18, r24
 2c2:	22 0f       	add	r18, r18
 2c4:	23 2f       	mov	r18, r19
 2c6:	22 1f       	adc	r18, r18
 2c8:	33 0b       	sbc	r19, r19
 2ca:	31 95       	neg	r19
 2cc:	2e 7f       	andi	r18, 0xFE	; 254
 2ce:	22 50       	subi	r18, 0x02	; 2
 2d0:	2e bb       	out	0x1e, r18	; 30
		// Start eeprom read by writing EERE
		EECR |= 1<<EERE;
 2d2:	e0 9a       	sbi	0x1c, 0	; 28
		corr1 = EEDR;
 2d4:	ed b3       	in	r30, 0x1d	; 29
		++ EEARL;
 2d6:	2e b3       	in	r18, 0x1e	; 30
 2d8:	2f 5f       	subi	r18, 0xFF	; 255
 2da:	2e bb       	out	0x1e, r18	; 30
		EECR |= 1<<EERE;
 2dc:	e0 9a       	sbi	0x1c, 0	; 28
		corr1 |= EEDR << 8;
 2de:	2d b3       	in	r18, 0x1d	; 29
 2e0:	f0 e0       	ldi	r31, 0x00	; 0
 2e2:	f2 2b       	or	r31, r18
		++ EEARL;
 2e4:	2e b3       	in	r18, 0x1e	; 30
 2e6:	2f 5f       	subi	r18, 0xFF	; 255
 2e8:	2e bb       	out	0x1e, r18	; 30
		EECR |= 1<<EERE;
 2ea:	e0 9a       	sbi	0x1c, 0	; 28
		corr2 = EEDR;
 2ec:	2d b3       	in	r18, 0x1d	; 29
		++ EEARL;
 2ee:	3e b3       	in	r19, 0x1e	; 30
 2f0:	3f 5f       	subi	r19, 0xFF	; 255
 2f2:	3e bb       	out	0x1e, r19	; 30
		EECR |= 1<<EERE;
 2f4:	e0 9a       	sbi	0x1c, 0	; 28
		corr2 |= EEDR << 8;
 2f6:	4d b3       	in	r20, 0x1d	; 29
		// Now use the lowest 8 bits of the measurement value to interpolate linearly.
		// max(corr2-corr1) = 982, which is tad smaller than 1024, therefore
		// the difference is first divided by 4 and rounded before multiplication 
		return corr1 + (((v & 0x0ff) * (((corr2 - corr1) + 0x01) >> 2) + 0x1f) >> 6);
 2f8:	30 e0       	ldi	r19, 0x00	; 0
 2fa:	34 2b       	or	r19, r20
 2fc:	2f 5f       	subi	r18, 0xFF	; 255
 2fe:	3f 4f       	sbci	r19, 0xFF	; 255
 300:	2e 1b       	sub	r18, r30
 302:	3f 0b       	sbc	r19, r31
 304:	bc 01       	movw	r22, r24
 306:	77 27       	eor	r23, r23
 308:	c9 01       	movw	r24, r18
 30a:	96 95       	lsr	r25
 30c:	87 95       	ror	r24
 30e:	96 95       	lsr	r25
 310:	87 95       	ror	r24
 312:	09 d0       	rcall	.+18     	; 0x326 <__mulhi3>
 314:	4f 96       	adiw	r24, 0x1f	; 31
 316:	66 e0       	ldi	r22, 0x06	; 6
 318:	96 95       	lsr	r25
 31a:	87 95       	ror	r24
 31c:	6a 95       	dec	r22
 31e:	e1 f7       	brne	.-8      	; 0x318 <correct_diode+0xce>
 320:	8e 0f       	add	r24, r30
 322:	9f 1f       	adc	r25, r31
	}
}
 324:	08 95       	ret

00000326 <__mulhi3>:
 326:	00 24       	eor	r0, r0
 328:	55 27       	eor	r21, r21
 32a:	04 c0       	rjmp	.+8      	; 0x334 <__mulhi3+0xe>
 32c:	08 0e       	add	r0, r24
 32e:	59 1f       	adc	r21, r25
 330:	88 0f       	add	r24, r24
 332:	99 1f       	adc	r25, r25
 334:	00 97       	sbiw	r24, 0x00	; 0
 336:	29 f0       	breq	.+10     	; 0x342 <__mulhi3+0x1c>
 338:	76 95       	lsr	r23
 33a:	67 95       	ror	r22
 33c:	b8 f3       	brcs	.-18     	; 0x32c <__mulhi3+0x6>
 33e:	71 05       	cpc	r23, r1
 340:	b9 f7       	brne	.-18     	; 0x330 <__mulhi3+0xa>
 342:	80 2d       	mov	r24, r0
 344:	95 2f       	mov	r25, r21
 346:	08 95       	ret

00000348 <__udivmodhi4>:
 348:	aa 1b       	sub	r26, r26
 34a:	bb 1b       	sub	r27, r27
 34c:	51 e1       	ldi	r21, 0x11	; 17
 34e:	07 c0       	rjmp	.+14     	; 0x35e <__udivmodhi4_ep>

00000350 <__udivmodhi4_loop>:
 350:	aa 1f       	adc	r26, r26
 352:	bb 1f       	adc	r27, r27
 354:	a6 17       	cp	r26, r22
 356:	b7 07       	cpc	r27, r23
 358:	10 f0       	brcs	.+4      	; 0x35e <__udivmodhi4_ep>
 35a:	a6 1b       	sub	r26, r22
 35c:	b7 0b       	sbc	r27, r23

0000035e <__udivmodhi4_ep>:
 35e:	88 1f       	adc	r24, r24
 360:	99 1f       	adc	r25, r25
 362:	5a 95       	dec	r21
 364:	a9 f7       	brne	.-22     	; 0x350 <__udivmodhi4_loop>
 366:	80 95       	com	r24
 368:	90 95       	com	r25
 36a:	bc 01       	movw	r22, r24
 36c:	cd 01       	movw	r24, r26
 36e:	08 95       	ret
