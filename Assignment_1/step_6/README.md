# Step 6: Reserve Market — Sequential (EU) vs. Joint (US) Market Clearing

This module simulates electricity market clearing **with reserve procurement**, comparing the **European-style sequential clearing** (reserves first, then energy) with the **U.S.-style joint clearing** approach. 

Implemented in Julia using [`JuMP`](https://jump.dev) and the [`Gurobi`](https://www.gurobi.com/) solver.

---

## Overview

- Procures upward/downward **reserves** based on total demand (15% up, 10% down)
- Compares **two market designs**:
  - 🇪🇺 **European style:** Sequential reserve and energy market clearing
  - 🇺🇸 **U.S. style:** Joint clearing of energy and reserves in one optimization
- Uses a **flexible subset of generators** for reserve provisioning
- Visualizes changes in supply due to reserve allocations

---

## File Descriptions

### `task6_european_style.jl`

**Purpose:**  
Implements the **European-style** reserve and day-ahead market clearing in sequence.

**Structure:**
1. **Reserve Market Clearing**
   - Objective: Minimize reserve procurement cost
   - Outputs:
     - Reserve clearing prices (€/MWh)
     - Generator reserve allocations (R<sub>up</sub>, R<sub>down</sub>)
2. **Day-Ahead Market Clearing**
   - Incorporates reduced generator capacity due to reserved capacity
   - Outputs:
     - Market clearing price for energy
     - Generator dispatch considering reserve constraints
3. **Plotting**
   - Adjusted supply curve based on reserve commitments

**Key Outputs:**
- Reserve market prices (λ<sub>up</sub>, λ<sub>down</sub>)
- Day-ahead market price
- Generator schedules
- Social welfare
- Visual: supply curve shift due to reserves

---

### `task6_us_style.jl`

**Purpose:**  
Implements the **U.S.-style** joint clearing of energy and reserves in a single optimization problem.

**Features:**
- Maximizes social welfare (consumer benefit – energy & reserve costs)
- Simultaneously solves for:
  - Generator dispatch
  - Reserve allocations
  - Market-clearing price for energy
- Enforces:
  - Reserve capacity bounds per generator
  - Total system reserve requirements

**Key Outputs:**
- Market clearing price for energy
- Reserve volumes per generator
- Generator dispatch
- Total social welfare
- Adjusted supply vs. demand curve

---

### `plot_demand_supply.jl`

**Purpose:**  
Helper script for plotting **adjusted supply curves** to visualize reserve impact.

**Used in:**
- `task6_european_style.jl`
- `task6_us_style.jl`

**Plots:**
- Original vs. adjusted generator capacities
- Demand curve vs. supply curve under reserve commitment

---

## How to Run

1. Make sure `Gurobi` is installed and licensed
2. Run either script from Julia REPL:
   ```julia
   include("task6_european_style.jl")
   include("task6_us_style.jl")
