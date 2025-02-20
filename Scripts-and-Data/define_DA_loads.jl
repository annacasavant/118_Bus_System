using PowerSystems
using CSV
using DataFrames
using Dates
using InfrastructureSystems

# Defining all the loads and adding them to lists
# adding loads and time series into system

partfact = sort!(CSV.read("Scripts-and-Data/partfact.csv", DataFrame));

for row in eachrow(partfact)
    num = lpad(rownumber(row), 3, '0')
    i = parse(Int, row[2][2])
    DAdf = CSV.read("Scripts-and-Data/TimeSeries/DA/Load/LoadR$(i)DA.csv", DataFrame);
    max = maximum(DAdf[:, 2])
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

for i in 1:3 
    local loaddf = CSV.read("Scripts-and-Data/TimeSeries/DA/Load/LoadR$(i)DA.csv", DataFrame)
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
