// SWR / power meter powered by rectifying the transceiver output power.
// The firmware was fine tuned to draw as little current as possible, running from low VCC voltage,
// at relatively low CPU speed and sleeping as much as possible.
// The firmware fits the 1kB FLASH of the AtTiny13A tightly, and the firmware only fits if a newer GCC compiler tool chain is used.
// We have used the GCC tool chain provided by the chip vendor.

// The AtTiny13A is clocked by an internal RC oscillator running at approximately 9.6MHz. This oscillator is being calibrated at production & testing of the chips, the calibration value is written into a FLASH block not accessible to the firmware, and the calibration value is loaded at the reset.

// The CPU clock is set to 9.6 MHz / 8 = 1.2 MHz by setting the appropriate programming fuse.
// The ADC clock is set to 1.2 MHZ / 16 = 75 kHz.
// As each ADC conversion takes 13 cycles, the maximum ADC sampling rate is then 75 kHz / 13 = 5.77 kHz.

// The firmware runs a main loop, which first samples the forward & reflected voltage, then it calculates the SWR and power, and
// then it sleeps up to an and of the 75 Hz period, while the 6 LED charlieplexed baragraph is modulated at the same 
// 75 Hz repeat cycle to provide smooth interpolation of light intensity between two succeeding LEDs.
// A straightforward solution would be to use the 8 bit timer to PWM between the two neighboring LEDs at 75 Hz repeat cycle.
// However, the firmware puts the CPU to "noise reduction" sleep state during ADC conversion. During the "noise reduction"
// sleep state the 8 bit timer clock is suspended, therefore it is not so simple to use the timer for the timing
// of the baragraph PWM. Our solution is to measure the time needed for all the ADC conversion, then to restart the timer
// while setting the timer initial state to the time consumed already by the ADC conversion. As the ADC time conversion 
// is relatively lengthy, the LED configuration taking the longer time is activated first, while the other LED configuration
// is activated by the timer capture event, and the cycle is repeated at the timer overflow event.

// Sampling 2x16 samples per 75kHz period seems to fit the first half of the 75kHz period with some reserve,
// but that may be sensitive to a compiler optimizations. We rather chose a conservative approach of sampling
// just 2x6 samples, which also leads to lower current consumption, as the whole sampling & SWR processing
// seems to fit into roughly 1/3 of the 75 kHz period. The time spent by the sampling & SWR processing was verified with a logic
// analyser. As it only takes 1/3 of the 75 kHz period, there is a healthy buffer for situations, where the calculation
// takes longer due to different program paths being taken.

// Input resistive divider 10k / 150k provides the required 10k input impedance to the ADC converter (see AtTiny13A datasheet).
// At 7W input power, the peak voltage at SWR 2:1 with the resistive bridge open is maximum 35.28V peak with the assumption,
// that the transceiver output impedance is purely resistive. As the transceiver output impedance is far from resistive and the transceiver is conjugate matched to the antenna, the transceiver peak voltage at 2:1 SWR will likely be lower, allowing the SWR meter likely to work up to 10W.

// At the maximum 35.28V peak voltage at the resistive bridge input, the ADC voltage at 10k / 150k resistive divider will be
// 1.1025 V, which matches the 1.1V ADC reference voltage (the voltage will be lower for the diode drop, which will be corrected
// for in the firmware).
// If the input voltage is higher, the current flowing through the 150k resistor into the micro substrate diodes will be negligible.

#include <stdbool.h>
#include <avr/interrupt.h>
#include <avr/io.h>
#include <avr/pgmspace.h>
#include <avr/sleep.h>
#include <avr/wdt.h>

#define F_CPU 1000000UL  // 1 MHz
#include <util/delay.h>

const uint16_t diode_correction_table_rough[16] PROGMEM = {
	#include "table_fine.inc"
};

#define REF_AVCC (0<<REFS0) // reference = AVCC
#define REF_INT  (1<<REFS0) // internal reference 1.1 V 

#define LINE_A 4 //Pin 3 (PB4) on ATtiny13A
#define LINE_B 0 //Pin 5 (PB0) on ATtiny13A
#define LINE_C 1 //Pin 6 (PB1) on ATtiny13A
#define ALL_LEDS ((1<<LINE_A) | (1<<LINE_B) | (1<<LINE_C))

#define ADC_PWR (1<<MUX0 | 1<<MUX1) // Pin 2 (PB3/ADC3) on ATtiny13A
#define ADC_REF (1<<MUX0) 			// Pin 7 (PB2/ADC1) on ATtiny13A

// #define DISABLE_PULLUPS 
#ifdef DISABLE_PULLUPS
	#define PUD_VALUE 0
#else /* DISABLE_PULLUPS */
	#define PUD_VALUE (1 << PUD)
#endif /* DISABLE_PULLUPS */

// DDRB direction config for each LED (1 = output)
// PORTB output config for each LED (1 = High, 0 = Low)
const unsigned char led_table[16] PROGMEM = {
  ALL_LEDS, 					0, 				// all LEDs off
  ( 1<<LINE_A | 1<<LINE_B ), 	( 1<<LINE_B ), 	// LED 0
  ( 1<<LINE_A | 1<<LINE_B ), 	( 1<<LINE_A ), 	// LED 1
  ( 1<<LINE_A | 1<<LINE_C ), 	( 1<<LINE_A ),	// LED 2
  ( 1<<LINE_A | 1<<LINE_C ), 	( 1<<LINE_C ), 	// LED 3
  ( 1<<LINE_B | 1<<LINE_C ), 	( 1<<LINE_C ), 	// LED 4
  ( 1<<LINE_B | 1<<LINE_C ), 	( 1<<LINE_B ), 	// LED 5
  ( 1<<LINE_B | 1<<LINE_C ), 	( 1<<LINE_B ) 	// LED 5: Clamp to LED5
};

// Global data are packed into a commmon structure as recommended by Atmel, as the members of the global structure
// may be addressed effectively by using a common pointer register and fixed offsets.
struct LedState {
	// Direction of PORTB pins at the 1st part of the 75 Hz period, to be loaded at the timer overflow event.
	// Output state of PORTB pins at the 1st part of the 75 Hz period, to be loaded at the timer overflow event.
	// Two bytes are bundled into a single 16bit word, so we save some FLASH space when reading the word from FLASH
	// as the macro for reading two bytes is shorter than twice a macro for reading a single byte.
	uint16_t dir_and_out1;
	// Direction of PORTB pins at the 2nd part of the 75 Hz period.
	// Output state of PORTB pins at the 2nd part of the 75 Hz period.
	uint16_t dir_and_out2;
	// New value of timer capture A to use the dir2 / out2.
	unsigned char timer_capture;
};

// #define DEBUG_SPI
// sigrok-cli -d fx2lafw -c samplerate=500k --continuous -P spi:mosi=D5:clk=D7:cs=D6 --protocol-decoder-annotations spi=mosi-data
#ifdef DEBUG_SPI
#define SPI_MOSI	LINE_A
#define SPI_CLK 	LINE_B
#define SPI_EN		LINE_C

// Output one byte by software SPI, for debugging purposes.
// http://nerdralph.blogspot.com/2015/03/fastest-avr-software-spi-in-west.html
void spi_byte(uint8_t byte)
{
    uint8_t i = 8;
//    uint8_t portbits = PORTB & ~((1 << SPI_MOSI) | (1 << SPI_CLK));
    do {
		// CLK and MOSI are low in portbits.
//		PORTB = portbits;
		// All other pins are inputs, just set all outputs to zero.
		PORTB = 0;
        if (byte & 0x80)
			PINB = (1 << SPI_MOSI);
		// Toggle CLK - unusual optimization, see ATTiny13 datasheet, page 48:
		// "writing a logic one to a bit in the PINx Register, will result in a toggle 
		// in the corresponding bit in the Data Register"
        PINB = (1 << SPI_CLK);
        byte <<= 1;
    } while (-- i);
}
#endif /* DEBUG_SPI */

// Switch the charlieplexed LEDs to the 2nd state of the period.
// The CPU will also wake up from the sleep state.
ISR(TIM0_COMPA_vect, ISR_NAKED)
{
#ifdef DEBUG_SPI
#else
	// Using the OCR0B and PCMSK to communicate between the main thread and the TIM0_COMPA interrupt.
	// Using hardware registers instead of global variables is much cheaper, it saves a considerable number
	// of stack push / pull instructions inside this interrupt handler.
	// If PCIE is disabled (by default), PCIE should do nothing. Also we are setting only bits of PCMSK to 1 that
	// correspond to LED bits and that are powered and steady while the bit in PCMSK is set to 1, therefore
	// the bit shall not have any effect on power consumption.
    asm volatile(
		"push r16\n"
//	DDRB = OCR0B;
		"in  r16, %0\n"
		"out %1, r16\n"
//	PORTB = PCMSK;
		"in  r16, %2\n"
		"out %3, r16\n"
		"pop r16\n"
		: :
		"I" (_SFR_IO_ADDR(OCR0B)), "I" (_SFR_IO_ADDR(DDRB)),
		"I" (_SFR_IO_ADDR(PCMSK)), "I" (_SFR_IO_ADDR(PORTB)));
#endif /* DEBUG_SPI */

	asm volatile("reti");
}

// Timer overflow is used to wake up CPU from sleep mode.
// Disable timer, so that the main thread could differentiate between the wake up after TIM0_COMPA from wake up after TIM0_OVF.
ISR(TIM0_OVF_vect, ISR_NAKED)
{
	// Stop the timer. Using assembly as the AVRGCC creates an unnecessary prologue / epilogue.
	// Create a "zero" register. Actually AVRGCC expects the R1 register to always contain zero,
	// so the push / pull and resetting R1 may not be needed.
	// Using R16 - the first "upper" register, which may be filled with "ldi" instruction to set it to zero,
	// as "ldi 0" does not change change status register, while the usual "eor r1, r1" does, requiring saving 
	// and restoring the stack register.
    asm volatile(
		"push r16\n"
		"ldi r16, 0\n" 	// r1 = 0
		"out %0, r16\n"	// TCCR0B = 0
		"pop r16\n"
		"reti\n"
		: : "I" (_SFR_IO_ADDR(TCCR0B)));
}

// This macro is supposed to save a bit of flash due to the successive increment of the Z register.
// If two pgm_read_word() macros were to be used, the address would have to be incremented by 2 between
// the two pgm_read_word() calls.
#define pgm_read_two_successive_words(addr, data1, data2) \
	do {								\
		asm volatile( 					\
			"lpm %A0, Z+" 	"\n\t" 		\
			"lpm %B0, Z+" 	"\n\t" 		\
			: "=r" (data1), "=z" (addr) \
			: "1" (addr) 				\
		); 								\
		asm volatile( 					\
			"lpm %A0, Z+" 	"\n\t" 		\
			"lpm %B0, Z" 	"\n\t" 		\
			: "=r" (data2) 				\
			: : "r30", "r31"			\
		); 								\
	} while (0)

// Interpolate baragraph from off state (no LED is lit, led_idx == 0, led_value == 0)
// to the first LED fully lit (led_idx == 1, led_value == 0),
// to the 6th LED fully lit (led_idx == 6, led_value == 0).
// Values over (led_idx == 6, led_value == 0) are clamped to the 6th LED fully lit.
inline __attribute__((always_inline)) void interpolate_baragraph(unsigned char led_idx, unsigned char led_value, struct LedState *led_state)
{
	uint16_t addr;
	if (led_idx > 6)
		led_idx = 6;
	addr = (uint16_t)led_table + (led_idx << 1);
	pgm_read_two_successive_words(addr, led_state->dir_and_out1, led_state->dir_and_out2);
	if (led_value < 128) {
		// Invert the timer value.
		led_value = 255 - led_value;
	} else {
		// Swap led1_dir/out with led2_dir/out, so that the 1st part of the 75 Hz period will be longer
		// than the second one
		uint16_t tmp = led_state->dir_and_out1;
		led_state->dir_and_out1 = led_state->dir_and_out2;
		led_state->dir_and_out2 = tmp;
	}
	// Round the LED value to 4 levels per LED interval.
	// Full intensity (the other LED fully off) will become zero.
	// 3/4 intensity will be increased to make it more pronounced from 1/2 intensity
	// due to logarithmic sensitivity of the human eye.
	// Maximum level will be rounded to zero. For zero led_value, the timer capture timer must not trigger!
	led_value = (led_value + 32) & 0x0c0;
	if (led_value == 192)
		led_value = 256 - 20;
	led_state->timer_capture = led_value;
}

inline __attribute__((always_inline)) unsigned int swr_to_baragraph(unsigned int pwr_in, unsigned int ref_in)
{
	// Show SWR infinity by default.
	unsigned char led_idx   = 6;
	// No need to initialize led_value, any value with led_idx will fully light the last LED.
	unsigned char led_value = 0;
	// Calculate SWR value
	if (pwr_in > ref_in) {
		// SWR calculated with 5 bits resolution right of the decimal point.
		unsigned char swr;
		{
			unsigned int num   = pwr_in + ref_in;
			unsigned int denom = pwr_in - ref_in;
			unsigned int swrl;
			// Scale num and denum to full resolution to improve accuracy of the division below.
			// Scale denom to 5 bits right of the decimal point.
			unsigned char bits = 5;
			// Cannot allow the num to grow up to the highest bit, as the num would possibly
			// overflow below when calculating swrl = (num + (denom >> 1)) / denom.
			//FIXME here we are potentially losing 1 bit of resolution.
			while ((num & 0x0c000) == 0) {
				num <<= 1;
				if (-- bits == 0)
					break;
			}
			denom >>= bits;
			swrl = (num + (denom >> 1)) / denom;
			swr = (denom == 0 || swrl > 255) ? 255 : (unsigned char)swrl;
		}
		// SWR must be above 1:1
		// assert(swr >= 32);
		if (swr < 64) {
			// SWR from 1:1 to 1:1.5
			// SWR from 1:1.5 to 1:2.0
			led_idx = (swr < 48) ? 1 : 2;
			led_value = (unsigned char)(swr << 4);
		} else if (swr < 96) {
			// SWR from 1:2.0 to 1:3.0
			led_idx = 3;
			led_value = (unsigned char)(swr << 3);
		} else if (swr < 160) {
			// SWR from 1:3.0 to 1:5.0
			led_idx = 4;
			led_value = (unsigned char)((swr - 96) << 2);
		} else if (swr < 256) {
			// SWR from 1:5.0 to 1:8.0
			led_idx = 5;
			// swr * 256 / 96 = approximately floor((swr * 683 + 127) / 256)
			led_value = (unsigned char)(((swr - 160) * 683 + 127) >> 8);
		} else {
			// SWR above 1:8.0
			// Infinity SWR is shown by default.
		}
	}
#ifdef DEBUG_SPI
	spi_byte(led_idx);
	spi_byte(led_value);
	PORTB = (1 << SPI_EN);
#endif /* DEBUG_SPI */
	return ((unsigned int)(led_idx) << 8) | led_value;
}

// Correct the diode drop by linearly interpolating 
// a) 16 line table stored in FLASH (fine knee of the diode curve)
// b) 32 line table stored in 64 bytes of the EEPROM (slowly changing curve after the diode knee)
// Input value has 13 bits of resolution (10 bit ADC, 8 samples summed).
// Output value has 15 bits resolution, where the 0x8000 value corresponds to 16 Watts of input power.
uint16_t correct_diode(uint16_t v)
{
	uint16_t corr1, corr2;
	if (v < 256) {
		// Interpolating a knee of the diode curve, table is 16 items long.
		uint16_t addr = (uint16_t)diode_correction_table_rough + ((v & 0x0f0) >> 3);
		pgm_read_two_successive_words(addr, corr1, corr2);
		if (v >= 240) {
			// Read the first item from the EEPROM.
			EEARL = 0;
			EECR |= 1<<EERE;
			corr2 = EEDR;
			EEARL = 1;
			EECR |= 1<<EERE;
			corr2 |= EEDR << 8;
		}
		// Now use the lowest 8 bits of the measurement value to interpolate linearly.
		return corr1 + ((((v & 0x0f) * (corr2 - corr1)) + 0x7) >> 4);
	} else {
		// Read two successive entries of the diode correction table from EEPROM, table is 32 items long.
		// Address of the correction value in the EEPROM.
		unsigned char addr = (unsigned char)(((v >> (13 - 5 - 1)) & 0x0fe) - 2);
		EEARL = addr ++;
		// Start eeprom read by writing EERE
		EECR |= 1<<EERE;
		corr1 = EEDR;
		EEARL = addr ++;
		EECR |= 1<<EERE;
		corr1 |= EEDR << 8;
		EEARL = addr ++;
		EECR |= 1<<EERE;
		corr2 = EEDR;
		EEARL = addr ++;
		EECR |= 1<<EERE;
		corr2 |= EEDR << 8;
		// Now use the lowest 8 bits of the measurement value to interpolate linearly.
		// max(corr2-corr1) = 982, which is tad smaller than 1024, therefore
		// the difference is first divided by 4 and rounded before multiplication 
		return corr1 + (((v & 0x0ff) * (((corr2 - corr1) + 0x01) >> 2) + 0x1f) >> 6);
	}
}

#ifdef DEBUG_SPI
// Testing the correct_diode() interpolation:
// Send a sequence of i = <0, 1023*8> and correct_diode(i) to SPI bus
// to be captured by a logic analyzer and compared with the Octave tables.
void correct_diode_test()
{
	for (;;) {
		for (uint16_t i = 0; i <= 1023 * 8; ++ i) {
			uint16_t j = correct_diode(i);
			spi_byte(i >> 8);
			spi_byte(i & 0x0ff);
			spi_byte(j >> 8);
			spi_byte(j & 0x0ff);
			PORTB = (1 << SPI_EN);
//			_delay_ms(100);
		}
		for (uint16_t i = 0; i <= 1023 * 8; ++ i) {
			PORTB = 0;
			PORTB = (1 << SPI_EN);
		}
	}
}
#endif /* DEBUG_SPI */

void __onreset(void) __attribute__ ((naked)) __attribute__ ((section (".init9")));

// How many samples with valid SWR will be thrown away before the power supply capacitors charge enough
// to not influence the measurement visibly. One sample takes roughly 14ms.
// Lower time will be required with lower power supply capacitors or with lower current limiting resistor
// powering the controller.
#define TIME_TO_SIGNAL_STABLE	 			 3 // 5
// Blank for roughly half second after key up and before showing the detected power.
#define TIME_LED_BLANKED_BETWEEN_SWR_AND_PWR 37
// Switch off all LEDs roughly after a second after key up, so that the intensity of the LEDs when showing
// the detected power will not visibly decrease.
#define TIME_SWITCH_OFF_AFTER_KEY_UP 		 74

void __onreset(void)
{
	// Naked start function requires us to set the stack and R1 to zero.
    asm volatile ( ".set __stack, %0" :: "i" (RAMEND) );
    asm volatile ( "clr __zero_reg__" );        // R1 set to 0 (GCC expects the R1 register to be set to zero at program start)

	// Interrupts are disabled after reset.
	
	// Disable watch dog.
	wdt_reset();
	// Clear WDRF in MCUSR
	MCUSR &= ~(1<<WDRF);
	// Write logical one to WDCE and WDE, keep old prescaler setting to prevent unintentional time-out.
	WDTCR |= (1<<WDCE) | (1<<WDE);
	// Turn off WDT.
	WDTCR = 0x00;
	
	// Set all LED pins to outputs, set all LED values to zeros. This switches all charlieplexed LEDs off
	// with a defined state.
#ifdef DEBUG_SPI
	// Enable SPI outputs.
	DDRB = (1 << SPI_MOSI) | (1 << SPI_CLK) | (1 << SPI_EN);
	// Disable SPI
	PORTB = (1 << SPI_EN);
#else
	// No need to initialize DDRB and PORTB. DDRB is set to all inputs, therefore no LED is lit after reboot.
	// Enable LED outputs.
//	DDRB = ALL_LEDS;
	// Switch off all LEDs.
//	PORTB = 0;
#endif

	//Initialize Timer/Counter 0, normal mode.
//	TCCR0A = 0; // No need to set it, it is the initial value after reset.
	// Stop the timer.
//	TCCR0B = 0; // No need to set it, it is the initial value after reset.
	// Interrupt on overflow.
	TIMSK0 = 1<<TOIE0;

	// Power Savings
//	set_bit(MCUCR, PUD);		// Disable pullups

	// Disable all digital input buffers for lower current consumption, as we are using two analog inputs
	// and three tri-stated output pins.
	DIDR0 = 0x3f;

#ifdef DEBUG_SPI
//	correct_diode_test();
#endif /* DEBUG_SPI */

	sei();
	
	uint16_t 		vfwd, vref;
	uint8_t 		i;
	unsigned char 	no_input_power_cnt = 0;
	unsigned char 	signal_steady_cntr = TIME_TO_SIGNAL_STABLE;
	// History of forward power for showing the transmit power after key off.
	// We want to show a power measurement before the input power started to fall off.
	uint16_t 		vfwd0, vfwd1, vfwd2;
	// State machine for showing the range of the power reading after key up by scrolling the LEDs up or down.
	unsigned char 	power_scroll_cntr;
	bool 			power_scroll_down;

	// Main loop, forever:
	for (;;) {
		// Enable ADC, set clock prescaler to 1/16 of the main clock 
		// (that is with main clock 9.6MHz/8 = 1.2MHz, the ADC sample rate is 1.2MHz / 16 / 13 = 5.77kHz
		// Enable ADC and Timer0 in power reduction register.
		PRR = 0;
		// Enable ADC interrupts.
		ADCSRA = (1<<ADEN)|(1<<ADIE)|(1<<ADPS2);
		ADMUX = REF_INT | ADC_REF;    // set reference and channel
		
		// Reset the accumulators.
		vfwd = 0;
		vref = 0;

		// Enter Sleep Mode To Trigger ADC Measurement. CPU Will Wake Up From ADC Interrupt.
		// The first measurement will be thrown away after enabling the ADC.
		// Instead of calling set_sleep_mode(SLEEP_MODE_ADC) which reads the state of MCUCR, modifies it and writes it back,
		// just write a constant into MCUCR, as we shall know the state of the MCUCR already.
		MCUCR = (1 << SM0) | PUD_VALUE;
		// sleep_mode();
		MCUCR = (1 << SM0) | (1 << SE) | PUD_VALUE;
		sleep_cpu();
		MCUCR = (1 << SM0) | PUD_VALUE;

		i = 8;
		do {
			// Enter Sleep Mode To Trigger ADC Measurement. CPU Will Wake Up From ADC Interrupt.
			// Instead of calling sleep_mode() which reads the state of MCUCR, modifies it and writes it back,
			// just write a constant into MCUCR, as we shall know the state of the MCUCR already.
			MCUCR = (1 << SM0) | (1 << SE) | PUD_VALUE;
			sleep_cpu();
			MCUCR = (1 << SM0) | PUD_VALUE;
			unsigned long vadc = ADC;
			vref += vadc;
		} while (-- i);

		ADMUX = REF_INT | ADC_PWR;    // set reference and channel
		i = 8;
		do {
			// Enter Sleep Mode To Trigger ADC Measurement. CPU Will Wake Up From ADC Interrupt.
			// Instead of calling sleep_mode() which reads the state of MCUCR, modifies it and writes it back,
			// just write a constant into MCUCR, as we shall know the state of the MCUCR already.
			MCUCR = (1 << SM0) | (1 << SE) | PUD_VALUE;
			sleep_cpu();
			MCUCR = (1 << SM0) | PUD_VALUE;
			unsigned long vadc = ADC;
#ifndef DEBUG_SPI
			if (vadc < 104)
				// input power lower than 0.2W
				goto no_power;
#endif /* DEBUG_SPI */
			vfwd += vadc;
		} while (-- i);
		
		// Input power is above 0.2W. Show SWR.
		// Start the timer to measure the 73.24Hz cycle and modulate the LEDs.
		TCNT0 = 69; // This is the time the A/D capture will take.
		TCCR0B = (1<<CS01)|(1 <<CS00); // clck_io / 64: 73.24Hz period.
		// Disable ADC until the next 75Hz cycle.
		ADCSRA = 0;
		// Disable ADC in power reduction register, enable Timer0.
		PRR = (1<<PRADC);
		
		no_input_power_cnt = 0;

		if (signal_steady_cntr == 0) {
			// Signal available, steady state. Show SWR.
			vfwd = correct_diode(vfwd);
			vref = correct_diode(vref);

			vfwd0 = vfwd1;
			vfwd1 = vfwd2;
			vfwd2 = vfwd;

	#ifdef DEBUG_SPI
			spi_byte(vfwd >> 8);
			spi_byte(vfwd & 0x0ff);
			spi_byte(vref >> 8);
			spi_byte(vref & 0x0ff);
			PORTB = (1 << SPI_EN);
	#else /* DEBUG_SPI */
			vfwd = swr_to_baragraph(vfwd, vref);
	#endif /* DEBUG_SPI */
		} else {
			// Blank the display.
			vfwd = 0;
			if (-- signal_steady_cntr == 0) {
				// Ready to show SWR and power when the next valid fwd / ref values are measured.
				// Clear the power value history.
				vfwd0 = 0;
				vfwd1 = 0;
				vfwd2 = 0;
			}
		}

		goto wait_end;

no_power:
		// Disable ADC until the next 75Hz cycle.
		ADCSRA = 0;
		// Disable ADC in power reduction register, enable Timer0.
		PRR = (1<<PRADC);
		// Process the "no input power" state. Input power lower than 0.2W.
		// Start the timer to measure the 73.24Hz cycle and modulate the LEDs.
		TCNT0 = 42; // This is the time the A/D capture will take.
		TCCR0B = (1<<CS01)|(1 <<CS00); // clck_io / 64: 73.24Hz period.
		// By default, switch off the LEDs.
		vfwd = 0;
		if (no_input_power_cnt < TIME_SWITCH_OFF_AFTER_KEY_UP) {
			// Less than 1 seconds.
			// Update the "steady signal" counter.
			if (++ signal_steady_cntr > TIME_TO_SIGNAL_STABLE)
				signal_steady_cntr = TIME_TO_SIGNAL_STABLE;
			if (++ no_input_power_cnt == TIME_LED_BLANKED_BETWEEN_SWR_AND_PWR) {
				// More than 0.5 second.
				// Round to a byte. 
				vfwd0 = (vfwd0 + 0x03f) >> 7;
				// Now vfwd0 == 256 corresponds to input power of 16 watts,
				// vfwd0 * vfwd0 == 65536 corresponds to input power of 16 watts,
				vfwd0 *= vfwd0;
				power_scroll_cntr = 6;
				power_scroll_down = false;
				if (vfwd0 > 24576) {
					// Measured power is over 6 watts, show 2x scale (2 to 12 Watts).
					vfwd0 = (vfwd0 + 0x0f) >> 5;
				} else if (vfwd0 < 4096) {
					// Measured power is below 1 watt, show /4 scale (0.25 to 1.5 Watts).
					power_scroll_down = true;
					vfwd0 = (vfwd0 + 0x01) >> 2;
				} else {
					// Show 1x scale (1 to 6 Watts).
					power_scroll_cntr = 0;
					vfwd0 = (vfwd0 + 0x07) >> 4;
				}
			} else if (no_input_power_cnt > TIME_LED_BLANKED_BETWEEN_SWR_AND_PWR) {
				if (power_scroll_cntr > 0) {
					vfwd = (power_scroll_down ? power_scroll_cntr : 6 - power_scroll_cntr) << 8;
					-- power_scroll_cntr;
				} else
					vfwd = vfwd0;
			}
		}
		// Fall through to wait_end.

wait_end:
		{
			struct LedState led_state;
			interpolate_baragraph((unsigned char)(vfwd >> 8), (unsigned char)(vfwd & 0x0FF), &led_state);

			// Wait until the timer overflows.
			// Two interrupts may wake up the micro from the sleep: Timer0 compare A event and Timer0 overflow.
			// The Timer0 overflow event handler resets TCCR0B to stop the timer and let us know to exit the sleep loop.
			// Instead of calling set_sleep_mode(SLEEP_MODE_IDLE) which reads the state of MCUCR, modifies it and writes it back,
			// just write a constant into MCUCR, as we shall know the state of the MCUCR already.
			MCUCR = PUD_VALUE;
			do {
				// sleep_mode();
				MCUCR = (1 << SE) | PUD_VALUE;
				sleep_cpu();
				MCUCR = PUD_VALUE;
			} while (TCCR0B);
			// Set the LED for the next long interval.
	#ifdef DEBUG_SPI
	#else
			DDRB  = (unsigned char)led_state.dir_and_out1;
			PORTB = (unsigned char)(led_state.dir_and_out1 >> 8);
	#endif
			// Use PCMSK and OCR0B to communicate with the Timer0 Cature A interrupt.
			OCR0B = (unsigned char)led_state.dir_and_out2;
			PCMSK = (unsigned char)(led_state.dir_and_out2 >> 8);
			// Clear the Timer 0 Compare A interrupt flag. The flag is normally cleared on Timer 0 Capture A interrupt, 
			// but the following line disables the Timer 0 Compare A interrupt if the timer capture value is close to overflow.
			TIFR0 |= 1<<OCF0A;
			// Next timer run will interrupt on overflow and on compare A if the timer_capture value is not close to full period.
			TIMSK0 = led_state.timer_capture ? (1<<TOIE0) | (1<<OCIE0A) : (1<<TOIE0);
			OCR0A = led_state.timer_capture;
		}
		// and continue the next 75Hz cycle starting with ADC sampling.
	}
}

// We are saving couple of bytes by avoiding the standard start files and interrupt tables and
// providing custom substitutes.
__attribute__((naked,section(".vectors"))) void start(void)
{
    asm volatile(
		"rjmp __onreset\n"	// on reset
		"reti\n" 			// INT0 External Interrupt Request 0
		"reti\n" 			// PCINT0 Pin Change Interrupt Request 0
		"rjmp __vector_3\n" // TIM0_OVF Timer/Counter Overflow
		"reti\n" 			// EE_RDY EEPROM Ready
		"reti\n" 			// ANA_COMP Analog Comparator
		"rjmp __vector_6\n" // TIM0_COMPA Timer/Counter Compare Match A
		"reti\n" 			// TIM0_COMPB Timer/Counter Compare Match B
		"reti\n" 			// WDT Watchdog Time-out
		"reti\n" 			// ADC overflow is used to wake up CPU from sleep mode.
		);
}
