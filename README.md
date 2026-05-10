# Smart ISO Tank Container — FBG Sensor Software

EG5565 MEng Group Design Project — University of Aberdeen 2025/2026

## GUI

The following files make up the graphical interface and must all be placed in the same directory:

- `Smart_Tank_FBG_GUI.m` — Main entry point
- `LiveMode_Page.m` — Live Mode simulation
- `SHM_Panel.m` — Structural Health Monitoring panel
- `FBG_v7_Functions.m` — Core physics functions
- `fem_strain_data.csv` — FEA strain dataset (required)

Run in the MATLAB command window:

```matlab
Smart_Tank_FBG_GUI
```

## Standalone Simulation

`final.m` is a self-contained simulation script that runs independently of the GUI. It does not require any of the GUI files above.

```matlab
final
```

## Requirements

MATLAB R2021b or later. No additional toolboxes required.

## Authors

Khalid Suliman, Ibrahim Alkali, Nidhin Varughese, Thomas Barker, Rodin Akraminejad
