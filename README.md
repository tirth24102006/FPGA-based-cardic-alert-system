# FPGA-based-cardic-alert-system
FPGA-ready Verilog pipeline implementing Pan-Tompkins QRS detection with adaptive thresholding and RR-interval based arrhythmia classification (Normal/Tachy/Brady/Irregular). Multi-patient MIT-BIH ECG simulation with LED and buzzer alerts.
 
# ❤️ Real-Time ECG Arrhythmia Detection using Pan-Tompkins Algorithm (Verilog / FPGA)

A hardware implementation of the **Pan-Tompkins QRS detection algorithm** for real-time R-peak (heartbeat) detection and arrhythmia classification (Tachycardia / Bradycardia / Irregular Rhythm / Normal), written in Verilog and targeted at FPGA boards (e.g. Xilinx Nexys/Basys series).

The system reads pre-recorded ECG waveforms from on-chip memory, runs them through a 4-stage DSP pipeline (Low-Pass Filter → Derivative → Squaring → Moving Window Integration), detects R-peaks using an adaptive thresholding scheme, and classifies the heart rhythm based on beat-to-beat timing — all in real hardware, with switches to select the ECG pattern and LEDs/buzzer to display the diagnosis.
 
--- 
 
## Table of Contents

1. [Overview](#overview)
2. [Features](#features)
3. [System Architecture](#system-architecture)
4. [File Hierarchy](#file-hierarchy)
5. [Module-by-Module Description](#module-by-module-description)
   - [1. top_pt_system](#1-top_pt_system-top-level-module)
   - [2. sim_bram](#2-sim_bram-ecg-data-memory)
   - [3. pan_tompkins_processor](#3-pan_tompkins_processor-dsp-front-end)
   - [4. adaptive_threshold](#4-adaptive_threshold-r-peak-detection)
   - [5. arrhythmia_classifier](#5-arrhythmia_classifier-diagnosis)
6. [Key Design Parameters](#key-design-parameters)
7. [Hardware I/O Mapping](#hardware-io-mapping)
8. [How to Simulate (Icarus Verilog)](#how-to-simulate-icarus-verilog)
9. [How to Run on FPGA Hardware](#how-to-run-on-fpga-hardware)
10. [Design Notes & Hardware-Efficiency Tricks](#design-notes--hardware-efficiency-tricks)
11. [Limitations / Future Work](#limitations--future-work)
12. [References](#references)

---

## Overview

Real-time ECG (electrocardiogram) monitoring requires detecting the **QRS complex** (the sharp spike corresponding to ventricular depolarization, i.e. one heartbeat) and using the time between consecutive beats to determine heart rate and rhythm regularity.

This project implements the classic **Pan-Tompkins algorithm** (Pan & Tompkins, 1985) entirely in synthesizable Verilog, without using any multipliers/dividers where avoidable — all scaling is done using arithmetic bit-shifts (`<<<`, `>>>`) for hardware efficiency. The design is self-contained: it includes its own simulated ECG memory (ROM) so it can be demoed on an FPGA board without needing a live ECG sensor.

---

## Features

- Full 4-stage Pan-Tompkins signal conditioning pipeline (LPF, Derivative, Squaring, Moving Window Integration)
- Adaptive dual-threshold R-peak detector (signal-peak / noise-peak tracking, per the original 1985 paper)
- Real-time arrhythmia classification: **Tachycardia**, **Bradycardia**, **Irregular Rhythm**, **Normal**
- On-board demo mode: 4 pre-recorded ECG patterns selectable via switches, no external hardware required
- Clock-divided sample-rate generator producing an accurate 360 Hz sampling clock enable from a 100 MHz board clock
- Button-latched LED output (stable diagnosis snapshot instead of flickering display)
- Buzzer alert on any abnormal rhythm
- Separate `SIMULATION` build path for fast testbench simulation vs. real hardware timing

---

## System Architecture

```
                         ┌───────────────────────────┐
   sw1, sw0  ─────────▶ │   Base Address Selector   │
                         │ (choose ECG pattern quad) │
                         └─────────────┬─────────────┘
                                       │
                         ┌─────────────▼──────────────┐
   100 MHz clk ────────▶│  Sample-Rate Generator     │  (360 Hz sample_en)
                         │  (clock divider, /277778)  │
                         └─────────────┬──────────────┘
                                       │ paces every stage below
                         ┌─────────────▼──────────────┐
                         │   sim_bram (ECG ROM)       │  raw ecg_in
                         └─────────────┬──────────────┘
                                       ▼
                         ┌─────────────────────────────┐
                         │   pan_tompkins_processor    │
                         │  LPF → Derivative → Squaring│
                         │      → Moving Window Integ. │
                         └─────────────┬───────────────┘
                                       │ mwi_out
                         ┌─────────────▼───────────────┐
                         │   adaptive_threshold        │
                         │ (SPKI / NPKI adaptive levels│
                         └─────────────┬───────────────┘
                                       │ r_peak_pulse (1 beat event)
                         ┌─────────────▼──────────────-─┐
                         │   arrhythmia_classifier      │
                         │ (RR-interval stopwatch logic)│
                         └──────┬───────────┬───────────┘
                                │           │
                     led_normal/tachy/    buzzer
                     brady/irregular
                                │
                         ┌──────▼──────┐
   btnc  ──────────────▶│ Latch on    │──▶ Physical LEDs
                         │ button press│
                         └─────────────┘
```

---

## File Hierarchy

> Adjust file names below to match your actual repository layout.

```
ecg-pan-tompkins-fpga/
│
├── README.md                        # This file
├── pan_tompkins_paper.pdf            # 📄 Reference paper: Pan & Tompkins,
│                                      #   "A Real-Time QRS Detection Algorithm", IEEE, 1985
│
├── top_pt_system.v                  # Top-level module, board I/O, instantiation
├── sim_bram.v                        # ECG waveform memory (ROM)
├── pan_tompkins_processor.v          # LPF + Derivative + Squaring + MWI pipeline
├── adaptive_threshold.v              # Adaptive R-peak threshold detector
├── arrhythmia_classifier.v           # RR-interval based rhythm classifier
├── tb_top_pt_system.v                # Testbench: clock gen, reset, monitors outputs
│
├── all_mit_data_101.coe             # ECG waveform data (MIT-BIH record 101), loaded
│                                      #   into sim_bram via $readmemh (4 quadrants:
│                                      #   Tachy / Brady / Irregular / Normal)
├── pins.xdc                          # Xilinx constraints file (clk, sw, btn, led, buzzer)
└── dump.vcd                          # 🌊 Waveform dump generated after simulation,
                                       #   viewable in GTKWave
```

---

## Module-by-Module Description

### 1. `top_pt_system` (Top-Level Module)

The top module wires every other module together and connects the design to physical board I/O.

**Responsibilities:**
- Generates the system's **360 Hz sample-enable pulse** from the board clock using a clock-divider counter (see [Key Design Parameters](#key-design-parameters))
- Decodes `sw1`, `sw0` into a `base_address`, selecting which of 4 pre-recorded ECG patterns (Tachycardia / Bradycardia / Irregular / Normal) to play back from ROM
- Runs an inner counter (0–685) to step through the selected 686-sample waveform, looping continuously
- Delays `sample_en` by one clock cycle (`sample_en_d1`) to correctly align with the ROM's one-cycle synchronous read latency
- Instantiates and connects: `sim_bram` → `pan_tompkins_processor` → `adaptive_threshold` → `arrhythmia_classifier`
- Latches the classifier's live output into the physical LEDs **only while the center button (`btnc`) is held**, so the display shows a stable snapshot rather than constantly flickering

**Ports:** `clk`, `rst_n`, `btnc`, `sw0`, `sw1` → `led_normal`, `led_tachy`, `led_brady`, `led_irregular`, `buzzer`

---

### 2. `sim_bram` (ECG Data Memory)

A simple synchronous ROM that stores pre-recorded ECG samples, loaded at simulation/synthesis time using `$readmemh` from a hex data file.

**Responsibilities:**
- **Write/load operation:** reads the ECG dataset from a `.mem` hex file into internal memory via `$readmemh`
- **Read operation:** on every positive clock edge, outputs the memory value stored at the given `addr`, registered (one-cycle read latency — this is why the top module needs `sample_en_d1`)

The single memory is split into **4 quadrants** of 686 samples each, one per heart condition, selected by `base_address` from the top module.

---

### 3. `pan_tompkins_processor` (DSP Front-End)

Implements the 4-stage signal-conditioning pipeline from the original Pan-Tompkins paper, converting raw ECG into a smoothed "QRS energy" signal.

| Stage | Purpose | Implementation |
|---|---|---|
| **Low-Pass Filter** | Removes high-frequency/muscle noise | 13-tap delay line + feedback, realizes `H(z) = (1−z⁻⁶)² / (1−z⁻¹)²` |
| **Derivative** | Highlights the steep slope characteristic of a QRS complex | 5-tap delay line, standard 5-point derivative filter |
| **Squaring** | Makes all values positive; nonlinearly amplifies large (QRS) values more than small (noise) values | Simple `x × x` |
| **Moving Window Integration (MWI)** | Smooths the sharp squared-derivative spike into a solid "hump" whose width/height reflects real QRS energy | 30-sample sliding-window running sum ÷ 30 |

All scaling by powers of two (×2, ÷8) is done using bit-shifts (`<<<`, `>>>`) instead of multipliers/dividers, except the final `÷30` averaging step, which is not a power of two and uses a true divider.

**Ports:** `clk`, `rst_n`, `ecg_in`, `valid_in` → `mwi_out`, `valid_out`

---

### 4. `adaptive_threshold` (R-Peak Detection)

Takes the smoothed `mwi_out` signal and decides, sample by sample, whether it represents a genuine heartbeat.

**Responsibilities:**
- Maintains two adaptive running-average levels:
  - `spki` — expected signal (QRS) peak level
  - `npki` — expected noise peak level
- Computes a dynamic threshold: `threshold = npki + 0.25 × (spki − npki)` (the exact formula from the 1985 Pan-Tompkins paper)
- If the input exceeds the threshold **and** a 72-sample refractory period has elapsed since the last detected beat, fires a single-cycle `r_peak_pulse` and updates `spki`
- If the input stays below threshold, updates `npki` instead
- The refractory period (72 samples at 360 Hz ≈ 200 ms) prevents double-counting the same beat (e.g. from a T-wave)

All averaging weights (7/8, 1/8, 1/4) are implemented with `>>>3` and `>>>2` bit-shifts.

**Ports:** `clk`, `rst_n`, `mwi_in`, `valid_in` → `r_peak_pulse`

---

### 5. `arrhythmia_classifier` (Diagnosis)

Converts individual beat pulses into a rhythm diagnosis by measuring the time between consecutive beats (the **RR interval**).

**Responsibilities:**
- Clean rising-edge detection on `r_peak_pulse` (`r_peak_edge`) to guarantee exactly one trigger per beat
- Runs a **sample-based stopwatch** (`sample_counter`), incrementing once per `sample_en` pulse (i.e. at 360 Hz), reset to zero on every detected beat
- Stores the two most recent RR intervals (`current_rr`, `previous_rr`) for comparison; the first two beats are used only to seed these registers (no diagnosis yet)
- From the third beat onward, on every beat edge:
  - `sample_counter < 216` → **Tachycardia** (heart rate > 100 BPM)
  - `sample_counter > 360` → **Bradycardia** (heart rate < 60 BPM)
  - RR interval changed by more than **12.5%** from the previous beat → **Irregular Rhythm**
  - Otherwise → **Normal**
- Drives `buzzer` combinationally high whenever any abnormal condition (Tachy/Brady/Irregular) is flagged

**Ports:** `clk`, `rst_n`, `sample_en`, `r_peak_pulse` → `led_normal`, `led_tachy`, `led_brady`, `led_irregular`, `buzzer`

---

## Key Design Parameters

| Parameter | Value | Derivation |
|---|---|---|
| Sampling frequency (Fs) | 360 Hz | Matches the MIT-BIH Arrhythmia Database standard sample rate |
| Sample-rate clock divider | 277,778 cycles | `100,000,000 Hz / 360 Hz ≈ 277,777.78` → counts 0 to 277777 |
| Refractory period | 72 samples (≈200 ms) | `72 / 360 Hz = 0.2 s`, the physiological minimum gap between real heartbeats |
| Threshold blend factor | 25% | `threshold = npki + (spki − npki) >>> 2`, per Pan-Tompkins (1985) |
| Tachycardia cutoff | 216 samples (100 BPM) | `samples_per_beat = 60 × Fs / BPM = 60 × 360 / 100 = 216` |
| Bradycardia cutoff | 360 samples (60 BPM) | `60 × 360 / 60 = 360` |
| Irregularity tolerance | 12.5% RR-interval change | `previous_rr >>> 3` = divide by 8 (hardware-friendly; tunable design choice, not a fixed medical constant) |
| ECG waveform length per condition | 686 samples | 4 conditions × 686 samples stored contiguously in ROM |

---

## Hardware I/O Mapping

| Signal | Direction | Function |
|---|---|---|
| `clk` | in | 100 MHz board clock |
| `rst_n` | in | Active-low reset |
| `sw0`, `sw1` | in | Select ECG pattern: `00`=Tachy, `01`=Brady, `10`=Irregular, `11`=Normal |
| `btnc` | in | Hold to latch and display the current diagnosis on LEDs |
| `led_normal` | out | Lit when rhythm is classified as Normal |
| `led_tachy` | out | Lit when Tachycardia is detected |
| `led_brady` | out | Lit when Bradycardia is detected |
| `led_irregular` | out | Lit when an irregular rhythm is detected |
| `buzzer` | out | Sounds for any abnormal rhythm (Tachy/Brady/Irregular) |

---

## How to Simulate (Icarus Verilog)

This project defines a `` `SIMULATION `` macro that speeds up the sample-rate generator for fast testbench runs (4-cycle divider instead of 277,778).

**1. Compile all source + testbench with the SIMULATION macro defined:** ⚙️

```bash
iverilog -o design.out -D SIMULATION \
    top_pt_system.v \
    sim_bram.v \
    pan_tompkins_processor.v \
    adaptive_threshold.v \
    arrhythmia_classifier.v \
    tb_top_pt_system.v
```

**2. Run the compiled simulation:**

```bash
vvp design.out
```

This executes the simulation and prints monitored signals (heartbeat pulses, RR intervals, LED/buzzer states) to the terminal (TCL console if run inside Vivado, or plain terminal if run standalone). If the testbench includes `$dumpfile`/`$dumpvars`, this step also generates `dump.vcd`.

**3. View waveforms in GTKWave:** 🌊

```bash
gtkwave dump.vcd
```

> **Note:** Make sure the ECG data file (`all_mit_data_101.coe`) path referenced inside `sim_bram.v`'s `$readmemh` call is correct relative to where you invoke `vvp` from, or use an absolute path.

---

## How to Run on FPGA Hardware

1. Create a new project in your FPGA vendor toolchain (e.g. Xilinx Vivado).
2. Add all `.v` source files and `all_mit_data_101.coe` to the project.
3. **Do not** define `SIMULATION` for the synthesis run — leave it undefined so the design uses the real 277,778-cycle divider for accurate 360 Hz timing on hardware.
4. Add `pins.xdc` to map `clk`, `sw0`/`sw1`, `btnc`, `led_*`, and `buzzer` to the correct physical pins for your board.
5. Synthesize, implement, and generate the bitstream.
6. Program the FPGA board. 🔌
7. Use `sw0`/`sw1` to select an ECG pattern, and hold `btnc` to view the live diagnosis on the LEDs; the buzzer will sound automatically for any abnormal rhythm.

---

## Design Notes & Hardware-Efficiency Tricks

- **No multipliers/dividers where avoidable:** every filter coefficient and averaging weight (×2, ÷8, ÷4) is implemented using arithmetic shift operators (`<<<`, `>>>`), which cost nothing in FPGA fabric compared to real multiplier/divider hardware. The only true divider in the design is the `÷30` in the moving window integrator, since 30 is not a power of two.
- **Single-cycle pulse discipline:** both `r_peak_pulse` and `r_peak_edge` are guaranteed one-clock-wide pulses (achieved by resetting to 0 every cycle by default, or explicit edge detection), avoiding double-counting of the same event.
- **Enable-driven design, not multiple clock domains:** rather than generating a physically slower clock, the design keeps one fast clock and uses a `sample_en` enable signal — the standard, FPGA-recommended way to implement a slower effective sample rate.
- **Pipeline latency awareness:** `sample_en_d1` exists specifically to compensate for the ROM's one-cycle synchronous read latency, ensuring the DSP pipeline is fed correctly time-aligned data.

---

## Limitations / Future Work

- The design plays back **pre-recorded ECG patterns** from ROM rather than accepting a live ADC input; adding a real-time ECG front-end (ADC + interface) would make this a fully live monitor.
- No "search-back" mechanism (present in the original Pan-Tompkins paper) to retroactively lower the threshold if no beat is found for too long — could be added to reduce missed-beat rate.
- The 12.5% irregularity threshold is a fixed, hardware-friendly design choice (`>>>3`) rather than one calibrated against a labeled arrhythmia dataset — could be tuned/validated against MIT-BIH annotations for improved clinical accuracy.
- LED output only updates while a button is held; a future revision could add a hold/latch toggle or a small display for continuous readout.

---

## References

- 📄 J. Pan and W. J. Tompkins, **"A Real-Time QRS Detection Algorithm,"** *IEEE Transactions on Biomedical Engineering*, vol. BME-32, no. 3, pp. 230–236, 1985. (Included in this repo as `pan_tompkins_paper.pdf`)
- MIT-BIH Arrhythmia Database — standard reference ECG dataset (360 Hz sampling rate), used to inform this design's timing parameters and as the source of `all_mit_data_101.coe`.
