#!/usr/bin/env julia

using PowerSystems
using CSV
using DataFrames

# ============================================================================
# Define Transmission Lines: Connect buses in the power system
# ============================================================================
# This script creates transmission line and transformer components that
# connect different buses, enabling power flow between system nodes.

# Read transmission line parameters from CSV file
line_params = CSV.read("Scripts-and-Data/Lines.csv", DataFrame)

# System base power (100 MVA) used to convert line ratings from MW to per-unit
sys_base_power = 100.0

# Create transmission lines and transformers from CSV data
for row in eachrow(line_params) 
    num = lpad(rownumber(row), 3, '0')
    # Extract bus numbers from the bus name (e.g., "bus069" -> 69)
    bus_from = parse(Int, row["Bus from "][4:6])
    bus_to = parse(Int, row["Bus to"][4:6])
    
    # Lines connect buses at the same voltage level
    # Transformers connect buses at different voltage levels
    # Rating data must be added in per-unit. For lines this is based on the system base power, for transformers it is based on the transformer's base power.
    # However, we use the system base power for transformers in this case too.
    if bus_params[bus_to, "Base Voltage kV"] == bus_params[bus_from, "Base Voltage kV"]
        local line = Line(;
            name = "line$num",
            available = true,
            active_power_flow = 0.0,
            reactive_power_flow = 0.0,
            arc = Arc(; from = get_bus(sys_DA, bus_from), to = get_bus(sys_DA, bus_to)),
            r = row["Resistance (p.u.)"],
            x = row["Reactance (p.u.)"],
            b = (from = 0.0, to = 0.0),
            rating = row["Max Flow (MW)"]/sys_base_power,
            angle_limits = (min = 0.0, max = 0.0),
        );
        add_component!(sys_DA, line)
    else
        local tline = Transformer2W(;
            name = "line$num",
            available = true,
            active_power_flow = 0.0,
            reactive_power_flow = 0.0,
            arc = Arc(; from = get_bus(sys_DA, bus_from), to = get_bus(sys_DA, bus_to)),
            r = row["Resistance (p.u.)"],
            x = row["Reactance (p.u.)"],
            primary_shunt = 0.0,
            rating = row["Max Flow (MW)"]/sys_base_power,
            base_power = sys_base_power,
        );
        add_component!(sys_DA, tline)
    end
end
