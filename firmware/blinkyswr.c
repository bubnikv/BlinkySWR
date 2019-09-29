#define F_CPU 4800000

#include <avr/io.h>
#include <avr/interrupt.h>
#include <avr/wdt.h>
#include <util/delay.h>

#define REF_AVCC (0<<REFS0) // reference = AVCC
#define REF_INT  (1<<REFS0) // internal reference 1.1 V 

// Macros for bitwise operations
#define set_bit(address,bit)	(address |= (1<<bit))	//sets bit to high
#define clear_bit(address,bit)	(address &= ~(1<<bit))	//sets bit to low
#define toggle_bit(address,bit)	(address ^= (1<<bit))	//toggles bit opposite of what it is

#define LINE_A 4 //Pin 3 (PB4) on ATtiny13A
#define LINE_B 0 //Pin 5 (PB0) on ATtiny13A
#define LINE_C 1 //Pin 6 (PB1) on ATtiny13A
#define ALL_LEDS ((1<<LINE_A) | (1<<LINE_B) | (1<<LINE_C))

#define ADC_PWR (1<<MUX0 | 1<<MUX1) // Pin 2 (PB3/ADC3) on ATtiny13A
#define ADC_REF (1<<MUX0) 			// Pin 7 (PB2/ADC1) on ATtiny13A

//DDRB direction config for each LED (1 = output)
const unsigned char led_dir[6] = {
  ( 1<<LINE_A | 1<<LINE_B ), //LED 0
  ( 1<<LINE_A | 1<<LINE_B ), //LED 1
  ( 1<<LINE_A | 1<<LINE_C ), //LED 2
  ( 1<<LINE_A | 1<<LINE_C ), //LED 3
  ( 1<<LINE_B | 1<<LINE_C ), //LED 4
  ( 1<<LINE_B | 1<<LINE_C ), //LED 5
};

//PORTB output config for each LED (1 = High, 0 = Low)
const unsigned char led_out[6] = {
  ( 1<<LINE_B ), //LED 0
  ( 1<<LINE_A ), //LED 1
  ( 1<<LINE_A ), //LED 2
  ( 1<<LINE_C ), //LED 3
  ( 1<<LINE_C ), //LED 4
  ( 1<<LINE_B ), //LED 5
};

static unsigned char led1_dir;
static unsigned char led1_out;
static unsigned char led2_dir;
static unsigned char led2_out;

ISR(TIM0_COMPA_vect)
{
	DDRB = led1_dir;
	PORTB = led1_out;
}

ISR(TIM0_OVF_vect)
{
	DDRB = led2_dir;
	PORTB = led2_out;
}

inline __attribute__((always_inline)) void leds_off()
{
	// Stop the timer.
	TCCR0B = 0;
	// Set all LED pins to outputs, set all LED values to zeros. This switches all charlieplexed LEDs off
	// with a defined state.
	DDRB = ALL_LEDS;
	PORTB = 0;
}

void interpolate_baragraph(unsigned char led_idx, unsigned char led_value)
{
	if (led_idx >= 6) {
		led_idx = 6;
		led_value = 0;
	} else if (led_value == 255) {
		led_value = 0;
		++ led_idx;
	}
	// Stop the timer.
	TCCR0B = 0;
	if (led_idx == 0) {
		led1_dir = 0;
		led1_out = 0;
	} else {
		led1_dir = led_dir[led_idx - 1];
		led1_out = led_out[led_idx - 1];
	}
	if (led_idx == 6) {
		led2_dir = 0;
		led2_out = 0;
	} else {
		led2_dir = led_dir[led_idx];
		led2_out = led_out[led_idx];
	}
	if (led_value == 0) {
		DDRB  = led1_dir;
		PORTB = led1_out;
	} else {
		TCNT0 = 0;
		OCR0A = led_value;
		// Counting from 0, and when OCR0A is reached, led1_dir / led1_out are activated. Therefore activate the other now.
		DDRB  = led2_dir;
		PORTB = led2_out;
		// Enable the timer.
		// Clock select, prescaler.
		TCCR0B = 1<<CS00; // clk_io
		TCCR0B = 1<<CS01; // clk_io / 8: 4.8MHz / 8 / 256 = 2.34kHz PWM period
	//	TCCR0B = 1<<CS02; // clk_io / 256
	//	TCCR0B = 1<<CS02 | 1 <<CS00; // clck_io / 1024
	}
}

// Value is from 0 to 6 * 256 = 1536
inline __attribute__((always_inline)) void set_baragraph_value(unsigned long value)
{
	interpolate_baragraph((unsigned char)(value >> 8), (unsigned char)(value & 0x0FF));
}

void show_swr(unsigned int pwr_in, unsigned int ref_in)
{
	// Show SWR infinity by default.
	unsigned char led_idx   = 6;
	unsigned char led_value = 0;
	// Correct for the shottky diode drop (0.3V * 2k2 / (2k2+39k)) * 1024 / 1.1V = 15
	pwr_in += 15;
	ref_in += 15;
	// Calculate SWR value
	if (pwr_in > ref_in) {
		// SWR calculated with 5 bits resolution right of the decimal point.
		unsigned int swr = ((pwr_in + ref_in) << 5) / (pwr_in - ref_in);
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

int main(void)
{
	cli();

	wdt_reset();
	// Clear WDRF in MCUSR
	MCUSR &= ~(1<<WDRF);
	// Write logical one to WDCE and WDE, keep old prescaler setting to prevent unintentional time-out.
	WDTCR |= (1<<WDCE) | (1<<WDE);
	// Turn off WDT.
	WDTCR = 0x00;
	
	leds_off();
	// Disable all digital input buffers for lower current consumption, as we are using two analog inputs
	// and three tri-stated output pins.
	DIDR0 = 0x3f;

	//Initialize Timer/Counter 0, normal mode.
	TCCR0A = 0;
	// Stop the timer.
	TCCR0B = 0;
	// Interrupt on overflow and compare A.
	TIMSK0 = 1<<TOIE0 | 1<<OCIE0A;
	
	// Force prescaler to zero on startup (starts with /8).
	CLKPR = _BV(CLKPCE);
	CLKPR = 0;

	//Power Savings
//	set_bit(PRR, PRADC);  		// Disable ADC in power reduction register
//	set_bit(ACSR, ACD);			// Disable Comparitor 
//	DIDR0 = 0xFF;
//	clear_bit(ADCSRA, ADEN);	// Disable ADC
//	set_bit(MCUCR, PUD);		// Disable pullups
//	clear_bit(MCUSR, WDRF);	
	
	// Enable ADC, set clock prescaler.
    ADCSRA = (1<<ADEN)|(1<<ADPS1)|(1<<ADPS0);
    ADCSRA = (1<<ADEN)|(1<<ADPS2)|(1<<ADPS1)|(1<<ADPS0);

	sei();

#if 1
{
	char no_input_power_cnt = 100;
	unsigned int off_cntr = 0;
	unsigned int vfwd_history[8];
	unsigned char vfwd_history_ptr = 0;
	for (;;) {
		ADMUX = REF_INT | ADC_PWR;    // set reference and channel
		ADCSRA |= 1<<ADSC;            // start conversion  
		while(ADCSRA & (1<<ADSC)) ;   // wait for conversion complete
		// A/D readout of 233.6 corresponds to 1W input power at 2k2 / 39k divider and 10bit A/D conversion with 1.1V voltage reference.
		unsigned int vfwd = ADC;
		if (vfwd < 104) {
			// input power lower than 0.2W
			if (++ no_input_power_cnt > 100) {
				no_input_power_cnt = 100;
				if (++ off_cntr == 150) {
					// Sum the oldest 4 vfwd samples captured.
					unsigned char i;
					vfwd = 0;
					for (i = 0; i < 4; ++ i) {
						vfwd += vfwd_history[vfwd_history_ptr ++] + 15;
						vfwd_history_ptr &= 0x07;
					}
					// Divide by 16, round to closest. Now vfwd has resolution of 8 bits, so the power will fit 16 bits.
					vfwd = (vfwd + 7) >> 4;
					// 3860.87 corresponds to 1W of input power.
					set_baragraph_value((vfwd * vfwd) / 15); //FIXME divide by 15.08!
				} else if (off_cntr >= 300) {
					off_cntr = 300;
					// Switch off the baragraph as we are losing power and
					// we don't want to let the LEDs die slowly.
					leds_off();
				}
				_delay_ms(1);
			} else {
				leds_off();
			}
		} else if (-- no_input_power_cnt < 0) {
			no_input_power_cnt = 0;
			ADMUX = REF_INT | ADC_REF;    // set reference and channel
			ADCSRA |= 1<<ADSC;            // start conversion  
			while(ADCSRA & (1<<ADSC)) ;   // wait for conversion complete
			unsigned long vref = ADC;
			show_swr(vfwd, vref);
			vfwd_history[vfwd_history_ptr ++] = vfwd;
			vfwd_history_ptr &= 0x07;
			_delay_ms(1);
		} else {
			off_cntr = 0;
			leds_off();
		}
	}
}
#endif

#if 0
	for (;;) {
		unsigned long i;
		unsigned long delay = 3;
		delay = 15;
		for (i = 0; i < 1536; ++ i) {
			set_baragraph_value(i);
			_delay_ms(delay);			
		}
		_delay_ms(500);
		for (i = 0; i < 1536; ++ i) {
			set_baragraph_value(1536 - i);
			_delay_ms(delay);
		}
		_delay_ms(500);
	}
#endif

	for (;;) {
		DDRB = led_dir[4];
		PORTB = led_out[4];
		DDRB = led_dir[0];
		PORTB = led_out[0];
	}

	for (;;) {
		unsigned char i;
		for (i = 0; i < 6; ++ i) {
			DDRB = led_dir[i];
			PORTB = led_out[i];
			_delay_ms(500);
		}
	}
}
