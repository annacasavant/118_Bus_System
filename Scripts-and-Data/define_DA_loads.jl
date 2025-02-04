using PowerSystems
using CSV
using DataFrames
using Dates
using InfrastructureSystems

# Defining all the loads and adding them to lists
# adding loads and time series into system

partfact = sort!(CSV.read("Scripts-and-Data/partfact.csv", DataFrame));
loads_R1_DA = []
loads_R2_DA = []
loads_R3_DA = []

for row in eachrow(partfact)
    num = lpad(rownumber(row), 3, '0')
    i = parse(Int, row[2][2])
    DAdf = CSV.read("Scripts-and-Data/TimeSeries/DA/Load/LoadR$(i)DA.csv", DataFrame);
    max = maximum(DAdf[:, 2])
    load = PowerLoad(;
        name = "load$num",
        available = true,
        bus = get_bus(sys_DA, i),
        active_power = 0.0, #per-unitized by device base_power
        reactive_power = 0.0, #per-unitized by device base_power
        base_power = 100.0, # MVA, for loads match system
        max_active_power = (max)*(row[3])/100, #per-unitized by device base_power?
        max_reactive_power = 0.0,
    );
    add_component!(sys_DA, load);
    if i == 1
        push!(loads_R1_DA, load)
    elseif i == 2
        push!(loads_R2_DA, load)
    else i == 3
        push!(loads_R3_DA, load)
    end
end

loads_DA = [loads_R1_DA, loads_R2_DA, loads_R3_DA]

for i in 1:3
    associations = (
    InfrastructureSystems.TimeSeriesAssociation(
        load,
        load_DA_TS[i],)
        for load in loads_DA[i]
    );
    bulk_add_time_series!(sys_DA, associations);
end
