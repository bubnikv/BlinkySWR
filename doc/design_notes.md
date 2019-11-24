# BlinkySWR design notes

The BlinkySWR is an ATtiny SWR and power meter, basically a smarter
replacement of the famous Tayloe SWR bridge. It will be a 1W to 5W (maybe a
bit higher, up to 10W) QRP resistive bridge with 6 LEDs analog-like
baragraph, with the intensity being interpolated between two successive
LEDs enhancing the baragraph resolution to at least 4x6 levels (I can
easily recognize 1 LED illuminated from 2 LEDs equally illuminated and 1
LED illuminated significantly stronger than the other). I have the
baragraph electronics and code prototyped, it works quite nicely.

The electronics (ATtiny13A driving the 6 LEDs) will be powered from a 3V
low drop low low quiescent current 16V max input linear regulator, and the
linear regulator will be powered with a 1:2 or 1:3 transformer from the
radio RF power, rectified by a single 1n5711 shottky diode (the diodes will
be used in the bridge anyway, so to reduce the BOM complexity). Look ma, no
batteries.

There will be a larger capacitor at the input side of the regulator, so the
microprocessor will have couple of seconds to perform additional tasks
after key up, that is to show the input power with quite a high accuracy.
So there will be no button: SWR will be shown during key down, and power
will be shown after a second or so after key up.

I feel quite confident with digital design and programming, but I am not
quite sure about the RF
side. Namely, what transformer should I use to feed the linear regulator?

These are my back of the envelope calculations:

On the transceiver output, when loaded with an open resistive bridge (all
three resistors 50 Ohm), the SWR is 2:1 and the voltage at the transceiver
output is 1.3333 * of Vpeak (assuming 50 Ohm output impedance of the
transceiver). Likely the maximum voltage will be lower as the output
impedance of the transceiver PA is not resistive. These are the maxima:
10W -> 42.16V Vpeak at SWR 2:1
7W -> 35.28V Vpeak at SWR 2:1
6W -> 32.65V Vpeak at SWR 2:1
5W -> 29.81V Vpeak at SWR 2:1

The minimum Vpeak at 1W transceiver output with the resistive bridge
shorted (again producing SWR 2:1 at the transceiver) will be minimum 8V
assuming the transceiver PA output is resistive. If not, the output voltage
will be closer to 10V peak.

Now the digital circuit requires a minimum 3.1V at 1.5mA DC before the
linear stabilizer, and the power will be rectified with a single diode, but
the micro will likely work happily down to 2V even if the linear regulator
just passes the voltage unregulated, as the micro may use its internal 1.1V
voltage reference for measurements. Operating the micro unregulated sounds
unusual, but it may be a viable option if tested, especially if the input
voltage will be stable enough due to the large capacitor before the
regulator.

Now my question is:
1) Should I use a 1:2 or 1:3 transformer? Using the 1:2 transformer may
require additional zener diode and likely a resistor before the linear
stabilizer if the input voltage could exceed 16V peak.
2) What will be the tiniest / cheapest ferrite and how many widings will be
optimal? I suppose this decision will be strongly dependent on the bands
supported. My personal goal is a 40m-20m EFHW tuner.

And also:

Will there be an interest for a kit?
Through hole or SMD? It may be a nice "introduction to SMD" kit as the
number of parts will be pretty low.
What bands?
What power range?
Should it contain an EFHW tuner? My personal preference would be a "NJQRP
Rainbow Tuner" like setup covering 40m-20m with a T50-6 transformer, mica
compression capacitor trimmer, jumpers to select the primary winding with
another jumper to add a capacitance for 40m coverage.

Thanks and 73,
Vojtech OK1IAK (former AB2ZA)

By kb1gmx

I pondered the idea an using a QRP radio or even a 20W radio where 
some larger chunk of power out goes to SWR/power meter tp power it
seems wrong.   Even if the suggested electronics uses a watt on a 5W 
radio that's a lot of power not going to the antenna.

Also Tayloe bridge SWR meters are a source of some 6-10db of 
insertion loss.  This is good while tuning the antenna as it 
protects the transmitter from a bad swr but unacceptable 
for inline use.   So the SWR detector (directional coupler) for inline
use should be of the Tandem match type or similar and even 
that sampler eats a little transmitter power.  The only point 
for it is now reflected power so a simple display works fine.
For power a meter will be far higher resolution.

Why not just use power from the radios  9-15V battery or an internal one? 
 Saves a lot of extra electronics and doesn't hurt the power out of the TX.
For intermittent use the battery would be small.

As to the EFHW antenna matching unit make it outboard in case 
you use a different antenna.  For 40-202m a T50-2 or T68-2 should 
do the job there are lots of schemes on the net for doing this.

Allison


Vojtech Bubnik
Even if the suggested electronics uses a watt on a 5W radio that's a lot of power not going to the antenna.
The suggested SWR meter shall draw roughly 1.5mA using a 1:2 or 1:3 transformer from the transceiver. Using a 1:2 transformer, with the assumption that only the positive polarity peak will be rectified, to source a 1.5mA voltage regulator, the circuit will draw 3mA from the source at the positive voltage peaks. Transformed by the 1:2 transformer, the current requirement will be halved, that is 1.5mA. 

At 5W the maximum peak voltage at the transmitter terminals when loaded with an open resistive bridge will be 29.81V. That corresponds to a 45mW power loss mostly in the linear regulator, that is roughly 1% of the input power.
At 10W it will be 63mW.
At 1W the power drawn to source the SWR meter electronics will be 10V * 1.5mA = 15mW, that is still 1.5% of the input power, that corresponds to -18dB power lost.

The SWR bridge current requirements may likely be even a bit lower, the 1.5mA is quite a conservative estimate using lower CPU speed and highest efficiency LED diodes.

I would be thankful if you correct my thoughs if I am wrong. I am more a software engineer than an electronics engineer.

Vojtech

kb1gmx

If your running a micro 1.5ma seems very low and LEDs you can see in 
daylight want a few ma to themselves.

Also don't forget the transformer and rectifier is a load ont he transmitter and 
that is in parallel with the antenna or dummy load which contributes to
SWR .  That whole DC recovery has an impedance and what is that?
How will the transmitter behave with that addded (loss in power 
and stability with a mismatched load).

There is no something for nothing in RF if your using power from the 
transmitter you also contributing load and possible reactance to the 
transmitters total load.  Also the transformer, rectifier and power 
converter do not deliver efficiency as components have loss.

That and the spec for the MPU used may hit low power but 
soon as the IO and A/D does something that goes up.

If the power needed is so low a few coin cells would power 
it for a very long time.  A CR3020  cell is about 225mah. 
That would save messing with RF and dealing with 
inefficiencies of power conversion.  You already have a 
battery to run the transmitter why suffer the cost in 
efficiency and losses (transfomer loss, rectifier loss, 
regulator loss) to convert DC to RF and then back to 
DC.  Keep in mind that a CW rig running class E might 
be 90% efficient but if it s class C its only 70% and 
it can easily be lower. If SSB those linear amps are maybe 
55% at full power and at less than half power 25% would 
be good.  So converting precious battery to RF then back 
to DC is at best inefficient.

You are correct save for your also incomplete in your loss projections.
Transformers are not 100% efficient, same for diodes (.2V at 1.5ma is 
0.3 mw of loss per diode).  Since the diodes are switches they generate 
harmonic waveforms that will be contributed to the output of the 
transmitter.  That's harder to predict as it varies with power in and 
load power needs.  In any case it needs to sty below the requirent
but the telecommunications rehulatory (FCC, PTT, other) 
agencies as well as good engineering practice.

In the end you get pecked to death a little at a time by ducks.

I do hardware, software, as well as RF for the last 50 years.

Allison
-- 


Vojtech Bubnik
There are two reasons to try it: First, it is challenge therefore fun. Second, it shall be an external box and it is great to not to worry about flat batteries.

1 mA flowing through a clear high intensity red LED makes my eyes hurt indoors.

Since the diodes are switches they generate 
harmonic waveforms that will be contributed to the output of the 
transmitter.

I will draw the current before the resistive bridge, therefore the harmonics will be attenuated. And the harmonics will be generated during the tune procedure only. I suppose that at 1.5% power consumed by the rectifier these harmonics will be quite weak.

I think it is time to test it. If I fail, at least I will learn something. Going shopping for the linear regulators.

Vojtech

I have a prototype working, see the attached photos showing the infinite SWR with open antenna terminals by lighting up the last LED, and showing a SWR roughly 1:1.1 with a 50 Ohm load. The bridge is powered with around 1.5W input power at 40m.

The six orange LEDs are interpolated by PWM, showing smooth transitions between levels. The SWR scale is following:
1st LED - 1:1
2nd LED - 1:1.5
3rd LED - 1:2
4th LED - 1:3
5th LED - 1:5
6th LED - 1:8 and higher

therefore the 1st LED being illuminated significantly more than the 2nd LED indicates SWR somwhere between 1:1 and 1:125.

On key up, the SWR meter is powered from a large 1000uF capacitor for around 1 second to blink the power detected on the 6 LED scale. I think that is all the functionality I can manage to squeeze into the 1kB of FLASH of this tiny $1 micro.

The device works somehow, but it is far from optimal. The micro is powered by a full wave rectifier with an artificial ground in the middle of the resistive bridge. As long as the current drawn is low, such arrangement should not cause significant read out errors or harmonics generated. I plan to do simulations of harmonic content in ltspice. The SWR bridge electronics is grounded to the virtual ground with a low impedance wire, therefore it shall be physically as tiny as possible to produce as little as possible capacitance against the other poles of the bridge, and this capacitance shall be balanced. The other three connections from the electronics to the SWR bridge are high impedance (1kOhm for power, 39kOhm for the forward and reflected power read outs).
 I do not consider myself an expert in RF electronics, though I have a feeling that such a setup will be less than optimal above 20m due to the low impedance path between the electronics ground and the virtual ground at the bridge, but with today's tiny SMD circuitry the capacity may be lower than expected.

There is a lot of work to be done on fine tuning the firmware and possibly the circuit. The firmware should utilize power saving features of the micro to a full extent, it should run the A/D conversion with all the processing disabled to lower the noise, it should use averaging to improve read out SNR, the diode detector read out shall be linearised. Currently the electronics draws around 2.5mA from the transceiver with 1mA flowing through the LEDs. To lower the micro current below the planned 1.5mA, as low as possible Vcc shall be used, likely around 2.2 to 2.5V. The micro would work from 1.8V, but a little bit higher voltag is required to have enough of current regulation on the resistors powering the low voltage red LEDs. The CPU shall be operated at as low as possible CPU frequency.

It is an interesting engineering optimization task, it is a lot of fun, and it is manageable due to the simplicity of the circuit and the ATtiny13A micro. As always, I will be thankful for constructive criticism of my endeavors.

----------------------

I ran some simulation of the power recovery circuit in ltspice. With the assumption, that the controller driving the LED baragraph draws 1.2mA at 2.4V, the following peak currents of the power recovery diodes were simulated, and the following harmonic distortion values were simulated as well. Only 3rd harmonic levels below the carrier are shown as they are most pronounced. Long story short, the worst harmonic simulation was 3rd harmonic at -34dB below the carrier. I would say this is a pretty harmless value for a circuit, that is inserted between the transceiver and antenna only during antenna adjustment.

1.2mA at 2.4V is a realistic value if all the AtTiny13A power saving features are used and LED current is limited to 1mA.

At 1W input power:
At SWR 1:1, the diode peak current is 7.4mA, which is 3.7% of 200mA input peak current, and 3rd harmonic introduced by the power recovery circuit is -36dB below the carrier.
When antenna open, the diode peak current is 8,3mA, which is 6.1% of 135mA input peak current, and 3rd harmonic introduced by the power recovery circuit is -34dB below the carrier. This is the worst distortion value.
When antenna shorted, the diode peak current is 7mA, which is 2.9% of 240mA input peak current, and 3rd harmonic introduced by the power recovery circuit is -39dB below the carrier.

At 10W input power:
At SWR 1:1, the diode peak current is 11.5mA, which is 1.8% of 636mA input peak current, and 3rd harmonic introduced by the power recovery circuit is -36dB below the carrier.
When antenna open, the diode peak current is 13mA, which is 3% of 427mA input peak current, and 3rd harmonic introduced by the power recovery circuit is -35dB below the carrier.
When antenna shorted, the diode peak current is 11mA, which is 1.4% of 764mA input peak current, and 3rd harmonic introduced by the power recovery circuit is -36dB below the carrier.

-----------------------------

* Zdokumentovat spotřebu při max SWR (svítí jedna LED): 940 mA
* Zdokumentovat proud přez tu poslední LED: 1.17V na 1.5kOhm = 0.78mA -> 160mA na procesoru
* Znovu ověřit převodní tabulku.
* Ověřit simulaci SWR trimrem pro různé úrovně vstupního výkonu.
* Naladit svítivost méně nasvětlené LEDky z páru. Moc málo?
Programovátko + naprogramovat nějaký kusy? (krajní piny na jedné straně, všechy piny na druhé).

Zdokumentovat UI a omezení:
* nefunguje na SSB, potřebuje steady signál, nefunguje na CW tečky a čárky (ověř): Funguje na pomalejší CW, ale při key off glitches
* pro měření výkonu filtruje poslední 3 samply, spočítej spoždění, jak pozvolné může být CW shaping. (4 poslední samply nad 0.2W), 3x14ms=40ms.


