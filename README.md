# Renewables in Electricity Markets

This repository contains the code of **Assignment 1**  and **Assignment 2** for the course _Renewables in Electricity Markets_ (46755, DTU).


# Assignment 1

The assignment is based on a step-by-step system modeling and market-clearing approach across different scenarios in electricity markets. The objective is to understand the effects of renewables, storage, transmission constraints, reserve and balancing mechanisms through mathematical modeling and optimization.

The full task description can be found in the course assignment document.

## Tools & Methods

- Language: [Julia](https://julialang.org/)
- Optimization: [`JuMP.jl`](https://jump.dev/) + [`Gurobi`](https://www.gurobi.com/)
- Visualization: `Plots.jl`
- Data and logic are structured following the steps defined in the assignment.

## Documentation and Explanations

Each task contains a seperate README and each julia script contains documented code, trying to make reading it easy and accessible. As for the interpretation of the results, please refer to the written report. 

# Assignment 2 

Assignment2/Task2.ipynb contains the analysis and optimization code for determining optimal reserve capacity bids for stochastic flexible loads in the FCR-D UP market. The notebook implements two solution techniques: ALSO-X and CVaR.
To ensure reproducibility, all dependencies are listed in requirements.txt. Follow these steps to set up your Python environment and run the notebook:

    # 1. Clone the repository or download the project folder
    git clone <your-repo-url>
    cd <project-folder>

    # 2. Create and activate a virtual environment
    python -m venv venv
    source venv/bin/activate   # On Windows: venv\Scripts\activate

    # 3. Install all required packages
    pip install -r requirements.txt

Note: This project uses gurobipy, which requires a valid Gurobi installation and license. Alternatively the highs solver can be used.
