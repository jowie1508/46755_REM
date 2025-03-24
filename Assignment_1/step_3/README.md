# Step 3: Market Clearing with Network Constraints

This module extends the electricity market simulation to incorporate **network constraints** using a 24-bus transmission system. It introduces **nodal and zonal pricing**, performs **sensitivity analysis** (line congestion and outages), and investigates the **feasibility of zonal clearing outcomes**.

Implemented in Julia using [`JuMP`](https://jump.dev) and the [`Gurobi`](https://www.gurobi.com/) solver.

---

## Overview

- Models **power flows and congestion** in a 24-bus network  
- Derives **nodal market clearing prices** (LMPs)  
- Evaluates **zonal pricing outcomes** under inter-zonal ATC limits  
- Performs **sensitivity analysis** on:
  - Line capacities
  - Line outages  
- Verifies **feasibility of zonal solutions** with respect to physical line constraints  

---

## File Descriptions

### `task3_1_network_constraints.jl`

**Purpose:**  
Implements the DC-OPF-based market-clearing model with **nodal pricing**.

**Key Features:**
- Models DC power flows using reactance & susceptance matrices
- Enforces transmission line limits
- Solves for nodal prices (LMPs)
- Detects and reports **congested lines** (≥90% capacity)
- Exports:
  - Nodal prices
  - Line utilization
  - Social welfare

---

### `task3_2_line_capacity.jl`

**Purpose:**  
Performs **sensitivity analysis** on a specific line (14→16) by varying its capacity.

**Key Features:**
- Runs the nodal market model for multiple capacity levels (e.g., 50, 150, 200, 500 MW)
- Tracks how congestion and LMPs respond
- Saves results to: `sensitivity_analysis_results.csv`

---

### `task3_2_line_outage.jl`

**Purpose:**  
Performs **location-based congestion analysis** by introducing partial or full line outages.

**Key Features:**
- Tests 3 selected lines with varying capacity scenarios (including full outage)
- Captures:
  - Impact on LMPs at each bus
  - Total social welfare losses
  - Congestion severity and location
- Results saved to: `locational_congestion_impact.csv`

---

### `task3_3_zonal.jl`

**Purpose:**  
Simulates **zonal market clearing** by dividing the 24-bus system into North and South zones.

**Key Features:**
- Aggregates demand/generation at the zone level
- Enforces zonal power balance and inter-zonal transfer limits (ATC)
- Computes:
  - Zonal market prices
  - Inter-zonal power flow
  - Zone-wise generation and consumption
- Parameter: `ATC_factor` controls the available transfer capacity between zones

---

### `task3_4_zonal_feasability.jl`

**Purpose:**  
Analyzes whether zonal dispatch results are **feasible** at the nodal level.

**Key Features:**
- Applies the zonal solution to the nodal network
- Computes **net power injections** at each bus
- Checks if intra-zonal lines are congested or overloaded
- Flags buses or lines needing **ex-post redispatch**

---

### `task3_plots.ipynb`

**Purpose:**  
Used to create the visuals of the results for the sensitivity analysis. 

---

## Output Files

- `sensitivity_analysis_results.csv`:  
  LMPs and social welfare for different line capacities

- `locational_congestion_impact.csv`:  
  Impact of specific line outages on LMPs and social welfare

---

## How to Run

1. Ensure Gurobi license is set up and JuMP packages are installed  
2. Run each script individually from a Julia REPL or editor  

---

## Notes

- Slack bus is fixed at **Bus 13**  
- ATC can be modified in `task3_3_zonal.jl` by changing the `ATC_factor`  
- All analyses assume **1-hour market clearing**, no storage, and static demand/generation bids
