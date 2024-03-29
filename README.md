# avrispm328p
AVR ISP (ATmega328P, Addr. auto inc., STK500v1 at 115.2 kbps)

## Description

This AVR ISP firmware turns your ATmega328P-based board (like an Arduino Nano, Uno, etc.) into an AVR ISP with adjustable SCK half-period, using the STK500v1 protocol.
(The pin assignment matches the already established practice, so this firmware can be used with existing rigs.)

## Set up your programmer board

In the examples below, the programmer board is assumed to be an Arduino board with an ATmega328P clocked at 16 MHz. Also it is assumed that `avrdude` is used.

Download the [avrispm328p.hex](https://raw.githubusercontent.com/imrehorvath/avrispm328p/main/avrispm328p.hex) file and flash it to the programmer.
```
avrdude -v -P /dev/cu.usbserial-A12345BA -p m328p -c arduino -U flash:w:avrispm328p.hex:i
```

**Note:** replace `/dev/cu.usbserial-A12345BA` with your actual device.

## Program- or set fuses on your targer

Hook up your target AVR as usual. Common GND, Vcc, RST and the SPI (MOSI, MISO and SCK). Optionally connect the status indicator LEDs through current limiting series resistors.

### Pin Assignments

| Function | ATmega328P Pin | Arduino Nano Pin |
| -------- | -------------- | ---------------- |
| RED      | PB0            | D8               |
| GREEN    | PB1            | D9               |
| RST      | PB2            | D10              |
| MOSI     | PB3            | D11              |
| MISO     | PB4            | D12              |
| SCK      | PB5            | D13              |

**Note:** Make sure you connect a 10 uF capacitor between the RESET and GND pins of your Arduino board when applicable to prevent it from going into the bootloader when you want to program your target.

### LED Status Indication (Optional)

Even though hooking up the status indicator LEDs is optional, it can provide you with some useful hints about what's going on.

The GREEN LED is lit, when the programmer enters Programming Mode and stays on during the entire duration while the programmer drives the target. It is turned off, when the programmer leaves Programming Mode, that is, when the programmer isolates itself from the target, letting it run in-system. To put it short, when the GREEN LED is lit, the programmer drives the target and when it is off, the programmer is isolated from the target.

The RED LED is lit, when various error conditions occure. For example, when an UNKNOWN command is received from the computer, or when the sync with the computer is lost, or when there is an attempt to set an unsupported parameter, or when trying to use an unsupported mem. type (protocol error), or when there is an attempt to set more bytes in EEPROM than available, or when trying to enter Programming Mode whitout setting the device parameters first. It is turned off, when a successful sync has been established, or when leaving Programming Mode.

### Examples

**Note:** please care to use the `-c stk500v1` option to indicate the programmer-id. (This firmware uses the STK500v1 protocol)

Read signature, calibration and lock bytes. As target an ATtiny85 is assumed. If you have another part, make sure to change the option.

```
avrdude -v -P /dev/cu.usbserial-A12345BA -p t85 -c stk500v1 -U signature:r:-:h
avrdude -v -P /dev/cu.usbserial-A12345BA -p t85 -c stk500v1 -U calibration:r:-:h
avrdude -v -P /dev/cu.usbserial-A12345BA -p t85 -c stk500v1 -U lock:r:-:h
```

Read the fuses

```
avrdude -v -P /dev/cu.usbserial-A12345BA -p t85 -c stk500v1 -U lfuse:r:-:h -U hfuse:r:-:h -U efuse:r:-:h
```

**Note:** for other uses, please refer to the manual of `avrdude`.

## Set sck programming param for slow targets (optional)

This firmware uses a 2 microseconds SCK half-period duration as default. This works with most recent parts with their factory default settings of using an internal 1 MHz clock.

There are cases, you might want to program a target -In System- clocked at much lower frequencies. (Like a clock application running at 32.768 kHz.) In such cases you need to set a longer SCK half-period duration. Otherwise you can skip this part.

### Set a longer SCK half-period duration

1. Run `avrdude` in Terminal Mode.

   ```
   avrdude -v -P /dev/cu.usbserial-A12345BA -p t85 -c stk500v1 -t
   ```

2. Set the SCK half-period duration with the `sck` interactive command in `avrdude` Terminal Mode. (Eg. for a 32.768 kHz clocked target.)

   ```
   sck 66.2
   ```

   ![sck 66.2 on scope](https://raw.githubusercontent.com/imrehorvath/avrispm328p/main/sck_66.2.jpeg "sck 66.2 half-period")

   **Note:** this sets a slightly more than 61 microseconds SCK half-period in the programmer. For caculation of this value, please see below.

3. Exit `avrdude`.

   ```
   q
   ```

4. Use `avrdude` as usual. (The programmer remembers the SCK half-period duration until reset or power-cycled.)

### SCK half-period calculation

`avrdude` assumes that the `sck` programming parameter represents the count of `8000000/f` microseconds, where `f` stands for the clock frequency of the programmer. `avrdude` further assumes that the programmer is clocked at 7.3728 MHz, so `f = 7372800`. However this firmware uses the same parameter `sck` for the SCK half-period as the count of 1 microseconds.

To calculate the minimum required SCK half-period from the target frequency `FOSC_t`, we can use the following formula.

```
sckhp = 1 ÷ IF(FOSC_t < 12000000, FOSC_t ÷ 4, FOSC_t ÷ 6) × 1000000 ÷ 2
```

To calculate the value we need to enter as the argument to the `sck` command in `avrdude` to achieve the desired SCK half-period duration, we can use the following formula.

```
v = ROUND(sckhp ÷ 0.9216, 1)
```

#### Pre-calculated sck values

| FOSC_t   | sckhp   | v    |
| -------: | ------: | ---: |
| 32768    | 61.0352 | 66.2 |
| 1000000  | 2       | 2.2  |

**Note:** The minimum SCK half-period duration is 1 microseconds.
