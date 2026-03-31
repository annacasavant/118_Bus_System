using PowerSystems
using CSV
using DataFrames
using TimeSeries

# ============================================================================
# Build a Day-Ahead (DA) Power System from CSV Data
# ============================================================================
# This script constructs a complete power system model by reading component
# data from CSV files and organizing them into PowerSystems.jl data structures.
# The workflow follows this order:
#   1. Define buses (nodes) and create regions
#   2. Define transmission lines connecting buses
#   3. Define time series profiles for renewable generators
#   4. Define loads and their time series data
#   5. Define generators and assign time series to each

include("Scripts-and-Data/define_buses.jl");
include("Scripts-and-Data/define_lines.jl");
include("Scripts-and-Data/define_time_series.jl");
include("Scripts-and-Data/define_DA_loads.jl");
include("Scripts-and-Data/define_DA_gens.jl");

# Return the completed system object
sys_DA