using PowerSystems
using CSV
using DataFrames
using Dates
using InfrastructureSystems

# duplicating DA to get RT system, since this is where the systems begin to differ

sys_RT = deepcopy(sys_DA)

# adding loads and time series into system

partfact = sort!(CSV.read("Scripts-and-Data/partfact.csv", DataFrame));

for row in eachrow(partfact)
    num = lpad(rownumber(row), 3, '0')
    i = parse(Int, row[2][2])
    RTdf = CSV.read("Scripts-and-Data/TimeSeries/RT/Load/LoadR$(i)RT.csv", DataFrame);
    max = maximum(RTdf[:, 2])
    load = PowerLoad(;
        name = "load$num",
        available = true,
        bus = get_bus(sys_RT, rownumber(row)),
        active_power = 0.0, #per-unitized by device base_power
        reactive_power = 0.0, #per-unitized by device base_power
        base_power = 100.0, # MVA, for loads match system
        max_active_power = (max)*(row[3])/100, #per-unitized by device base_power?
        max_reactive_power = 0.0,
    );
    add_component!(sys_RT, load);
end

for i in 1:3 
    local loaddf = CSV.read("Scripts-and-Data/TimeSeries/RT/Load/LoadR$(i)RT.csv", DataFrame)
    local load_array = TimeArray(timestamps, (loaddf[:, 2]./maximum(loaddf[:, 2])))
    local load_TS = SingleTimeSeries(;
           name = "max_active_power",
           data = load_array,
           scaling_factor_multiplier = get_max_active_power, #assumption?
       );  
    region = get_component(Area, sys_RT, "R$i")
    begin_time_series_update(sys_RT) do
        for component in get_components_in_aggregation_topology(PowerLoad, sys_RT, region)
            add_time_series!(sys_RT, component, load_TS)
        end
    end
end
