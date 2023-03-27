# avrispm328p
AVR ISP (ATmega328P, Addr. auto inc., STK500v1 at 115.2 kbps)

## Description

This AVR ISP firmware turns your ATmega328P-based board (like an Arduino Nano, Uno, etc.) into an AVR ISP with adjustable SCK half-period, using the STK500v1 protocol.

## Set up your programmer board

The programmer board is assumed to be an Arduino board with an ATmega328P clocked at 16 MHz. Also it is assumed that `avrdude` is used.

Download the [avrispm328p.hex](https://raw.githubusercontent.com/imrehorvath/avrispm328p/main/avrispm328p.hex) file and flash it to the programmer.
```
avrdude -v -P /dev/cu.usbserial-<whatever> -p m328p -c arduino -U flash:w:avrispm328p.hex:i
```

**Note:** replace `/dev/cu.usbserial-<whatever>` with wour actual device.

## Program- or set fuses on your targer

Hook up your target AVR as usual. Common GND, Vcc, RST and the SPI (MOSI, MISO and SCK). Optionally connect the status indicator LEDs through current limiting series resistors.

| Function | AVR Pin | Arduino Nano Pin |
| -------- | ------- | ---------------- |
| RST      | PB0     | D8               |
| MOSI     | PB3     | D11              |
| MISO     | PB4     | D12              |
| SCK      | PB5     | D13              |

| Indicator LED               | AVR Pin | Arduino Nano Pin |
| --------------------------- | ------- | ---------------- |
| In Programming Mode (Green) | PD7     | D7               |
| Error Indication (Red)      | PD6     | D6               |

**Note:** make sure you connect a 10 uF capacitor between the RESET and GND pins of your Arduino board when applicable to prevent it from going into the bootloader when you want to program your target.

### Examples

**Note:** please care to use the `-c stk500v1` option to indicate the programmer-id. (This firmware uses the STK500v1 protocol)

Read signature, calibration and lock bytes. As target an ATtiny85 is assumed. If you have another part, make sure to change the option.

```
avrdude -v -P /dev/cu.usbserial-<whatever> -p t85 -c stk500v1 -U signature:r:-:h
avrdude -v -P /dev/cu.usbserial-<whatever> -p t85 -c stk500v1 -U calibration:r:-:h
avrdude -v -P /dev/cu.usbserial-<whatever> -p t85 -c stk500v1 -U lock:r:-:h
```

Read the fuses

```
avrdude -v -P /dev/cu.usbserial-<whatever> -p t85 -c stk500v1 -U lfuse:r:-:h -U hfuse:r:-:h -U efuse:r:-:h
```

**Note:** for other uses, please refer to the manual of `avrdude`.

## Set sck programming param for slow targets

This firmware uses a 2 microseconds sck half-period duration as default. This works with most recent parts with their factory default settings of using an internal 1 MHz clock. (Actually 8 MHz divided by 8)

There are cases you might want to program In System a target clocked at a much slower frequency. Like a clock application running at 32768 Hz. In that case you need to set a longer sck half period duration.

### Set a longer sck half period duration

Run `avrdude` in Terminal Mode.

```
avrdude -v -P /dev/cu.usbserial-<whatever> -p t85 -c stk500v1 -t
```

Set the sck half period duration with. Eg. for a 32768 Hz clocked target.

```
sck 66.2
```

Exit `avrdude`.

```
q
```

Use `avrdude` as usual. The programmer remembers the sck half period duration until reset or power-cycled.

### Sck half period calculation

`avrdude` assumes that the `sck` programming parameter represents the count of `8000000/f` microseconds, where the `f` stands for the clock frequency of the programmer. `avrdude` further assumes that the programmer is clocked at 7.3728 MHz, so `f = 7372800`. However this firmware uses the same for the sck half period as the count of 1 microseconds.

To calculate the minimum required sck half period from the target frequency `FOSC_t`, we can use the formula.

```
sckhp = 1 ÷ IF(FOSC_t < 12000000, FOSC_t ÷ 4, FOSC_t ÷ 6) × 1000000 ÷ 2
```

To compensate the formula `avrdude` uses, we can use the following, to calculate the minumum number, which needs to be entered in the Terminal Mode.

```
sck = ROUND(sckhp ÷ 0.9216, 1)
```

### Example values

| FOSC_t   | sckhp   | sck  |
| -------: | ------: | ---: |
| 32768    | 61.0352 | 66.2 |
| 1000000  | 2       | 2.2  |
| 4000000  | 0.5     | 0.5  |
| 7372800  | 0.2713  | 0.3  |
| 8000000  | 0.25    | 0.3  |
| 12000000 | 0.25    | 0.3  |
| 16000000 | 0.1875  | 0.2  |
