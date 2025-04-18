using PowerSystems
using CSV
using DataFrames
using Dates
using InfrastructureSystems
using TimeSeries

#=
Defining all the loads, which are located in three regions. Each region has one
unique time series, and every load in each region is assigned its region's
respective time series. Original time series files have first column
timestamps, second column values, but here I'm creating one dataframe from each
of the files' value columns. To name loads, using convention "load001", where
the number matches the number of the bus attached to the load.  
=#

# creating dataframes for load parameters and time series, and column name variables

load_params = sort!(CSV.read("Scripts-and-Data/partfact.csv", DataFrame));

REGION = "Region"
LOAD_BUS = "Bus Name"
FACT = "Load Participation Factor"

load_RT_TS = DataFrame()
for file in readdir("Scripts-and-Data/TimeSeries/RT/Load/", join=true)
    data = CSV.read(file, DataFrame)[:, 2]
    load_RT_TS[:, file[end-7:end-6]] = data
end

# building and adding loads to system

for row in eachrow(load_params)
    max = maximum(load_RT_TS[:, row[REGION]])
    load = PowerLoad(;
        name = "load$(row[LOAD_BUS][4:6])",
        available = true,
        bus = get_bus(sys_RT, row[LOAD_BUS]),
        active_power = 0.0, # per-unitized by device base_power
        reactive_power = 0.0, # per-unitized by device base_power
        base_power = system_base_power, # MVA, for loads match system
        max_active_power = (max) * (row[FACT]) / system_base_power,
        max_reactive_power = 0.0,
    );
    add_component!(sys_RT, load);
end

# bulk adding loads' time series by region

resolution = Dates.Hour(1);
timestamps = range(DateTime("2023-01-01T00:00:00"); step = resolution, length = 8784);

regions = unique(load_params[:, REGION]);

for reg in regions
    max = maximum(load_RT_TS[:, reg])
    local load_array = TimeArray(timestamps, (load_RT_TS[:, reg] ./ max))
    local load_TS = SingleTimeSeries(;
           name = "max_active_power",
           data = load_array,
           scaling_factor_multiplier = get_max_active_power, #assumption?
       );  
    region = get_component(Area, sys_RT, reg)
    begin_time_series_update(sys_RT) do
        for component in get_components_in_aggregation_topology(PowerLoad, sys_RT, region)
            add_time_series!(sys_RT, component, load_TS)
        end
    end
end
