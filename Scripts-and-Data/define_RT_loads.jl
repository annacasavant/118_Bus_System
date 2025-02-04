using PowerSystems
using CSV
using DataFrames
using Dates
using InfrastructureSystems

# duplicating DA to get RT system, since this is where the systems begin to differ

sys_RT = deepcopy(sys_DA)

# Defining all the loads and adding them to lists
# adding loads and time series into system

partfact = sort!(CSV.read("Scripts-and-Data/partfact.csv", DataFrame));
loads_R1_RT = []
loads_R2_RT = []
loads_R3_RT = []

for row in eachrow(partfact)
    num = lpad(rownumber(row), 3, '0')
    i = parse(Int, row[2][2])
    RTdf = CSV.read("Scripts-and-Data/TimeSeries/RT/Load/LoadR$(i)RT.csv", DataFrame);
    max = maximum(RTdf[:, 2])
    load = PowerLoad(;
        name = "load$num",
        available = true,
        bus = get_bus(sys_RT, i),
        active_power = 0.0, #per-unitized by device base_power
        reactive_power = 0.0, #per-unitized by device base_power
        base_power = 100.0, # MVA, for loads match system
        max_active_power = (max)*(row[3])/100, #per-unitized by device base_power?
        max_reactive_power = 0.0,
    );
    add_component!(sys_RT, load);
    if i == 1
        push!(loads_R1_RT, load)
    elseif i == 2
        push!(loads_R2_RT, load)
    else i == 3
        push!(loads_R3_RT, load)
    end
end

loads_RT = [loads_R1_RT, loads_R2_RT, loads_R3_RT]

for i in 1:3
    associations = (
    InfrastructureSystems.TimeSeriesAssociation(
        load,
        load_RT_TS[i],)
        for load in loads_RT[i]
    );
    bulk_add_time_series!(sys_RT, associations);
end
