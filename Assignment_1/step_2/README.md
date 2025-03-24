#  Electricity Market Optimization with and without Battery Storage

This repository contains a full-featured simulation of a **24-hour electricity market**, implemented using Julia's [`JuMP`](https://jump.dev) optimization package and the [`Gurobi`](https://www.gurobi.com/) solver.

It includes two optimization models:
- `task2_WITHOUT_storage.jl`: base market simulation
- `task2_WITH_storage.jl`: enhanced model with a grid-connected battery
- `task2_plots.jl`: helper script for generating plots of results from Task 2

---

## Overview

The models simulate energy generation, demand satisfaction, and storage behavior in a electricity market. The goal is to **maximize social welfare** 
### Key Features:


## File Descriptions

### `task2_WITHOUT_storage.jl`

#### Purpose:
Simulates a basic day-ahead electricity market where generators are dispatched to meet hourly demand based on bid prices and generator offer costs.

#### Key Model Components:
- **Objective:** Maximize social welfare
- **Constraints:** Generator capacity, demand limits, hourly balance
- **Output:**
  - Market clearing prices per hour
  - Generator-wise profit
  - Total social welfare

---

### `task2_WITH_storage.jl`

#### Purpose:
Enhances the base market model by adding a **Li-ion battery** that charges/discharges based on price arbitrage.

#### New Components:
- Battery charging/discharging power limits
- Charging/discharging efficiencies
- Energy storage capacity (state-of-charge)
- Time-coupled state-of-charge constraints

#### Output:
- Hourly market prices (with battery)
- Generator and wind profits
- Battery  profit
- Total social welfare


### `task2_plots.jl`

#### Purpose:
Post-processes Task 2 outputs and generates plots.

#### Generates:
- Market prices with and without storage (€/MWh vs hour)
- Battery state of charge (SOC) over 24h


#### Usage:
Make sure you run `task2_WITH_storage.jl` and `task2_WITHOUT_storage.jl` first to generate required variables.


