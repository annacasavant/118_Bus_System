using PowerSystems
using CSV
using DataFrames
using Dates
using InfrastructureSystems

# ============================================================================
# Define Loads: Add demand points to the power system
# ============================================================================
# This script creates load (demand) components at specific buses and assigns
# time series profiles showing how demand varies over the 24-hour period.

# Read participation factors that determine load distribution across buses
partfact = sort!(CSV.read("Scripts-and-Data/partfact.csv", DataFrame));

# Create loads at each bus using participation factors
# Participation factors distribute total regional load proportionally across buses
for row in eachrow(partfact)
    num = lpad(rownumber(row), 3, '0')
    i = parse(Int, row[2][2])  # Identify which region this load belongs to
    
    # Read hourly load profile data for this region
    DAdf = CSV.read("Scripts-and-Data/TimeSeries/DA/Load/LoadR$(i)DA.csv", DataFrame);
    max = maximum(DAdf[:, 2])
    
    # Create the load with its base power and maximum capacity
    load = PowerLoad(;
        name = "load$num",
        available = true,
        bus = get_bus(sys_DA, rownumber(row)),
        active_power = 0.0, #per-unitized by device base_power
        reactive_power = 0.0, #per-unitized by device base_power
        base_power = 100.0, # MVA, for loads match system
        max_active_power = (max)*(row[3])/100, #per-unitized by device base_power?
        max_reactive_power = 0.0,
    );
    add_component!(sys_DA, load);
end

# Add time series data to loads
# This defines how regional demand changes hour by hour
for i in 1:3 
    local loaddf = CSV.read("Scripts-and-Data/TimeSeries/DA/Load/LoadR$(i)DA.csv", DataFrame)
    # Normalize load profile to 0-1 range (will be scaled by max_active_power)
    local load_array = TimeArray(timestamps, (loaddf[:, 2]./maximum(loaddf[:, 2])))
    local load_TS = SingleTimeSeries(;
           name = "max_active_power",
           data = load_array,
           scaling_factor_multiplier = get_max_active_power, #assumption?
       );  
    region = get_component(Area, sys_DA, "R$i")
    begin_time_series_update(sys_DA) do
        for component in get_components_in_aggregation_topology(PowerLoad, sys_DA, region)
            add_time_series!(sys_DA, component, load_TS)
        end
    end
end
