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
// seems to fit into roughly 1/3 of the 75kHz period.

// Input resistive divider 10k / 150k provides the required 10k input impedance to the ADC converter (see AtTiny13A datasheet).
// At 7W input power, the peak voltage at SWR 2:1 with the resistive bridge open is maximum 35.28V peak with the assumption,
// that the transceiver output impedance is purely resistive. As the transceiver output impedance is far from resistive and the transceiver is conjugate matched to the antenna, the transceiver peak voltage at 2:1 SWR will likely be lower, allowing the SWR meter likely to work up to 10W.

// At the maximum 35.28V peak voltage at the resistive bridge input, the ADC voltage at 10k / 150k resistive divider will be
// 1.1025 V, which matches the 1.1V ADC reference voltage (the voltage will be lower for the diode drop, which will be corrected
// for in the firmware).
// If the input voltage is higher, the current flowing through the 150k resistor into the micro substrate diodes will be negligible.

#include <avr/interrupt.h>
#include <avr/io.h>
#include <avr/pgmspace.h>
#include <avr/sleep.h>
#include <avr/wdt.h>

const uint16_t diode_correction_table_rough[] PROGMEM = {
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

// DDRB direction config for each LED (1 = output)
// PORTB output config for each LED (1 = High, 0 = Low)
const unsigned char led_table[] PROGMEM = {
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
	unsigned char dir1;
	// Output state of PORTB pins at the 1st part of the 75 Hz period, to be loaded at the timer overflow event.
	unsigned char out1;
	// Direction of PORTB pins at the 2nd part of the 75 Hz period, calculated.
	unsigned char dir2;
	// Output state of PORTB pins at the 2nd part of the 75 Hz period, calculated.
	unsigned char out2;
	// Direction of PORTB pins at the 2nd part of the 75 Hz period, to be loaded by the timer capture A.
	unsigned char dir2use;
	// Output state of PORTB pins at the 2nd part of the 75 Hz period, calculated, to be loaded by the timer capture A.
	unsigned char out2use;
	// New value of timer capture A to use the dir2 / out2.
	unsigned char timer_capture;
};

static struct LedState led_state;

// Switch the charlieplexed LEDs to the 2nd state of the period.
// The CPU will also wake up from the sleep state.
ISR(TIM0_COMPA_vect)
{
	DDRB  = led_state.dir2use;
	PORTB = led_state.out2use;
}

// Timer overflow is used to wake up CPU from sleep mode.
// Disable timer, so that the main thread could differentiate between the wake up after TIM0_COMPA from wake up after TIM0_OVF.
ISR(TIM0_OVF_vect)
{
	// Stop the timer.
	TCCR0B = 0;
}

// ADC overflow is used to wake up CPU from sleep mode.
EMPTY_INTERRUPT(ADC_vect);

// Interpolate baragraph from off state (no LED is lit, led_idx == 0, led_value == 0)
// to the first LED fully lit (led_idx == 1, led_value == 0),
// to the 6th LED fully lit (led_idx == 6, led_value == 0).
// Values over (led_idx == 6, led_value == 0) are clamped to the 6th LED fully lit.
void interpolate_baragraph(unsigned char led_idx, unsigned char led_value)
{
	uint16_t addr;
	if (led_idx > 6)
		led_idx = 6;
	addr = (uint16_t)led_table + (led_idx << 1);
	led_state.dir1 = __LPM(addr ++);
	led_state.out1 = __LPM(addr ++);
	led_state.dir2 = __LPM(addr ++);
	led_state.out2 = __LPM(addr);
	if (led_value < 128) {
		// Swap led1_dir/out with led2_dir/out, so that the 1st part of the 75 Hz period will be longer
		// than the second one
		unsigned char tmp = led_state.dir1;
		led_state.dir1 = led_state.dir2;
		led_state.dir2 = tmp;
		tmp = led_state.out1;
		led_state.out1 = led_state.out2;
		led_state.out2 = tmp;
		// and invert the timer value.
		led_value = 255 - led_value;
	}
	led_state.timer_capture = led_value;
}

// The expected input value is from 0 to 6 * 256 = 1536.
// Value above 6 * 256 is clamped to 6 * 256.
inline __attribute__((always_inline)) void set_baragraph_value(unsigned long value)
{
	interpolate_baragraph((unsigned char)(value >> 8), (unsigned char)(value & 0x0FF));
}

inline __attribute__((always_inline)) void show_swr(unsigned int pwr_in, unsigned int ref_in)
{
	// Show SWR infinity by default.
	unsigned char led_idx   = 6;
	unsigned char led_value = 0;
	// Calculate SWR value
	if (pwr_in > ref_in) {
		// SWR calculated with 5 bits resolution right of the decimal point.
		unsigned int swr = (pwr_in + ref_in) / ((pwr_in - ref_in) >> 5);
		// SWR must be above 1:1
		// assert(swr >= 32);
		if (swr < 48) {
			// SWR from 1:1 to 1:1.5
			led_idx = 1;
			led_value = (unsigned char)((swr - 32) << 4);
		} else if (swr < 64) {
			// SWR from 1:1.5 to 1:2.0
			led_idx = 2;
			led_value = (unsigned char)((swr - 48) << 4);
		} else if (swr < 96) {
			// SWR from 1:2.0 to 1:3.0
			led_idx = 3;
			led_value = (unsigned char)((swr - 64) << 3);
		} else if (swr < 160) {
			// SWR from 1:3.0 to 1:5.0
			led_idx = 4;
			led_value = (unsigned char)((swr - 96) << 2);
		} else if (swr < 256) {
			// SWR from 1:5.0 to 1:8.0
			led_idx = 4;
			// swr * 256 / 96 = approximately floor((swr * 341 + 63) / 128)
			swr *= 341;
			swr += 63;
			swr >>= 7;
			led_value = (unsigned char)(swr);
		} else {
			// SWR above 1:8.0
			// Infinity SWR is shown by default.
		}
	}
	interpolate_baragraph(led_idx, led_value);
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
		uint16_t addr;
		addr = (uint16_t)diode_correction_table_rough + ((v & 0x0f0) >> 3);
		corr1 = __LPM(addr ++);
		corr1 |= __LPM(addr ++) << 8;
		if (v < 240) {
			// Read two items from the "rough" table.
			corr2 = __LPM(addr ++);
			corr2 |= __LPM(addr) << 8;
		} else {
			// Read the first item from the EEPROM.
			EEARL = 0;
			EECR |= 1<<EERE;
			corr2 = EEDR;
			++ EEARL;
			EECR |= 1<<EERE;
			corr2 |= EEDR << 8;
		}
		// Now use the lowest 8 bits of the measurement value to interpolate linearly.
		return corr1 + ((((v & 0x0f) * (corr2 - corr1)) + 0x7) >> 4);
	} else {
		// Read the two successive entries of the diode correction table from EEPROM.
		// Address of the correction value in the EEPROM.
		EEARL = (unsigned char)(((v >> (13 - 5 - 1)) & 0x0fe) - 2);
		// Start eeprom read by writing EERE
		EECR |= 1<<EERE;
		corr1 = EEDR;
		++ EEARL;
		EECR |= 1<<EERE;
		corr1 |= EEDR << 8;
		EECR |= 1<<EERE;
		corr2 = EEDR;
		++ EEARL;
		EECR |= 1<<EERE;
		corr2 |= EEDR << 8;
		// Now use the lowest 8 bits of the measurement value to interpolate linearly.
		return corr1 + (((v & 0x0ff) * (((corr2 - corr1) + 0x07) >> 2) + 0x1f) >> 6);
	}
}

int main(void)
{
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
	DDRB = ALL_LEDS;
	PORTB = 0;
	// Disable all digital input buffers for lower current consumption, as we are using two analog inputs
	// and three tri-stated output pins.
	DIDR0 = 0x3f;

	//Initialize Timer/Counter 0, normal mode.
//	TCCR0A = 0; // No need to set it, it is the initial value after reset.
	// Stop the timer.
//	TCCR0B = 0; // No need to set it, it is the initial value after reset.
	// Interrupt on overflow.
	TIMSK0 = 1<<TOIE0;

	// Power Savings
//	set_bit(MCUCR, PUD);		// Disable pullups

	sei();

	uint16_t vfwd, vref;
	uint8_t i;
	char no_input_power_cnt = 0;
	// History of forward power for showing the transmit power after key off.
	// We want to show a power measurement before the input power started to fall off.
	uint16_t vfwd0, vfwd1, vfwd2;

	// Main loop, forever:
	for (;;) {
		// Enable ADC, set clock prescaler to 1/16 of the main clock 
		// (that is with main clock 9.6MHz/8 = 1.2MHz, the ADC sample rate is 1.2MHz / 16 / 13 = 5.77kHz
		// Enable ADC in power reduction register
		PRR &= ~(1<<PRADC);
		// Enable ADC interrupts.
		ADCSRA = (1<<ADEN)|(1<<ADIE)|(1<<ADPS2);
		ADMUX = REF_INT | ADC_PWR;    // set reference and channel
		
		// Reset the accumulators.
		vfwd = 0;
		vref = 0;

		// Enter Sleep Mode To Trigger ADC Measurement. CPU Will Wake Up From ADC Interrupt.
		// The first measurement will be thrown away after enabling the ADC.
		set_sleep_mode(SLEEP_MODE_ADC);
		sleep_mode();

		i = 8;
		do {
			// Enter Sleep Mode To Trigger ADC Measurement. CPU Will Wake Up From ADC Interrupt.
			sleep_mode();
			unsigned long vadc = ADC;
			if (vadc < 104)
				// input power lower than 0.2W
				goto no_power;
			vfwd += vadc;
		} while (-- i);

		ADMUX = REF_INT | ADC_REF;    // set reference and channel
		i = 8;
		do {
			// Enter Sleep Mode To Trigger ADC Measurement. CPU Will Wake Up From ADC Interrupt.
			sleep_mode();
			unsigned long vadc = ADC;
			vref += vadc;
		} while (-- i);
		
		// Input power is above 0.2W. Show SWR.
		// Start the timer to measure the 73.24Hz cycle and modulate the LEDs.
		TCNT0 = 72; // This is the time the A/D capture will take.
		TCCR0B = (1<<CS01)|(1 <<CS00); // clck_io / 64: 73.24Hz period.
		// Disable ADC until the next 75Hz cycle.
		ADCSRA = 0;
		// Disable ADC in power reduction register
		PRR |= (1<<PRADC);
		no_input_power_cnt = 0;
		vfwd = correct_diode(vfwd);
		vref = correct_diode(vref);
		show_swr(vfwd, vref);
		vfwd0 = vfwd1;
		vfwd1 = vfwd2;
		vfwd2 = vfwd;
		goto wait_end;

no_power:
		// Disable ADC until the next 75Hz cycle.
		ADCSRA = 0;
		// Disable ADC in power reduction register
		PRR |= (1<<PRADC);
		// Process the "no input power" state. Input power lower than 0.2W.
		// Start the timer to measure the 73.24Hz cycle and modulate the LEDs.
		TCNT0 = 13; // This is the time the A/D capture will take.
		TCCR0B = (1<<CS01)|(1 <<CS00); // clck_io / 64: 73.24Hz period.
		// By default, switch off the LEDs.
		led_state.dir1 = ALL_LEDS;
		led_state.out1 = 0;
		led_state.timer_capture = 255;
		if (no_input_power_cnt < 111) {
			// Less than 1.5 seconds.
			if (++ no_input_power_cnt > 37) {
				// More than 0.5 second.
				// Round to a byte. 
				vfwd0 = (vfwd0 + 0x03f) >> 7;
				// Now vfwd0 == 256 corresponds to input power of 16 watts,
				// vfwd0 * vfwd0 == 65536 corresponds to input power of 16 watts,
				set_baragraph_value((vfwd0 * vfwd0 + 0x07) >> 4);
			}
		}
		// Fall through to wait_end.

wait_end:
		// Wait until the timer overflows.
		// Two interrupts may wake up the micro from the sleep: Timer0 compare A event and Timer0 overflow.
		// The Timer0 overflow event handler resets TCCR0B to stop the timer and let us know to exit the sleep loop.
		do {
			set_sleep_mode(SLEEP_MODE_IDLE);
			sleep_mode();
		} while (TCCR0B);
		// Set the LED for the next long interval.
		DDRB  = led_state.dir1;
		PORTB = led_state.out1;
		led_state.dir2use = led_state.dir2;
		led_state.out2use = led_state.out2;
		// Next timer run will interrupt on overflow and on compare A if the timer_capture value is not close to full period.
		TIMSK0 = (led_state.timer_capture < 250) ? ((1<<TOIE0) | (1<<OCIE0A)) : (1<<TOIE0);
		OCR0A = led_state.timer_capture;
		// and continue the next 75Hz cycle starting with ADC sampling.
	}
}
