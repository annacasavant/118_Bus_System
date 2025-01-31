# Building a System with Real Time and Forecast

### Dependencies
```@hide
using PowerSystems 
using CSV
using DataFrames
```

### Build the base of the system with appropriate base power. 
Begin by building the base system using the base power. 

```@repl system 
sys = System(100)
```

### Read in all component data 
Read in the CSV files that contain the data for building the system. In this example, the line, bus and generator data are found in the following CSV files. 

```@repl system 
line_params = CSV.read("Scripts-and-Data/Lines.csv", DataFrame)
bus_params = CSV.read("Scripts-and-Data/Buses.csv", DataFrame)
gen_params = CSV.read("Scripts-and-Data/gen.csv", DataFrame) 
```

### Build the buses - parsing data from `bus_params`
The first building block are the buses in the system. We can define variables describing the buses using columns found in the `bus_params.csv` file. 

```@repl system 
min_voltage_col_name = "Voltage-Min (pu)"
max_voltage_col_name = "Voltage-Max (pu)"
base_voltage_col_name = "Base Voltage"
```

```@repl system
buses = []
for row in eachrow(bus_params)
    num =  lpad(string(row, 3, '0'))
    min_volt = row[:min_voltage_col_name]     
    max_volt = row[:max_voltage_col_name]
    base_volt = row[:base_voltage_col_name]
    bus = ACBus(;
           number = row[:number],
           name = "bus$num",
           bustype = ACBusTypes.PQ,
           angle = 0.0,
           magnitude = 1.0,
           voltage_limits = (min = min_volt, max = max_volt),
           base_voltage = base_volt,
       )
    add_component!(sys, bus)
end
buses = sort!(get_buses(sys_DA, Set(1:length(bus_params[:, 1]))), by = n -> n.name);
```

### Build the lines and transformers - parsing data from `line_params`

```@repl system
bus_from_col = "Bus from "
bus_to_col = "Bus to" 
resistance_col = "Resistance (p.u.)"
reactance_col = "Reactance (p.u.)"
max_flow_col = "Max Flow (MW)"

for i in length(lines)
	num =  lpad(string(row, 3, '0'))
	bus_from = parse(Int, row[bus_from_col][4:6])
    bus_to = parse(Int, row[bus_to_col][4:6])	
    if # voltage at connecting ends is the same - build a line
        local line = Line(;
            name = "branch$num"
            available = true,
            active_power_flow = # parsed data,
            reactive_power_flow = # parsed data,
            arc = Arc(; from = get_bus(sys_DA, bus_from), to = get_bus(sys_DA, bus_to)),
            r = row[resistance_col],
            x = row[reactance_col],
            b = # parsed data,
            rating = row[max_flow_col]/100,
            angle_limits = # parsed data,
        );
        add_component!(sys, line)
    else # voltage at connecting ends is different - build a transformer
        local tline = Transformer2W(;
            name = "branch$num"
            available = true,
            active_power_flow = # parsed data,
            reactive_power_flow = # parsed data,
            arc = Arc(; from = get_bus(sys_DA, bus_from), to = get_bus(sys_DA, bus_to)),
            r = row[resistance_col],
            x = row[reactance_col],
            primary_shunt = # parsed data,
            rating = row[max_flow_col]/100,
        );
        add_component!(sys, tline)
    end
end
```

# Reading in Time Series Data

### Establishing resolution of time series

```@repl system
resolution = Dates.Hour(1);
timestamps = range(DateTime("2023-01-01T00:00:00"); step = resolution, length = 8784);
gendata = CSV.read("Scripts-and-Data/Generators.csv", DataFrame)
```

The following time series are hourly for the year 2023, meaning there are 8784 data points, or one
time stamp for each hour, the resolution, of the year. The following steps are how to add these time
series data to renewable generators. 

### Reading in Solar Time Series

```@repl system 
solar_RT_TS = []
file_path = "Scripts-and-Data/TimeSeries/RT/Solar"

for i in length(solar_generator)
	solardf = CSV.read("$file_path/Solar$(i)RT.csv", DataFrame) # read in data 
	norm = maximum(solardf[:, 2])
	solar_array = TimeArray(timestamps, (solardf[:, 2]./norm)/100) # normalize and per-unitize data 
	solar_TS = SingleTimeSeries(;
           name = "max_active_power",
           data = solar_array,
		   scaling_factor_multiplier = get_max_active_power, # max active power
       );
	push!(solar_RT_TS, solar_TS);
end
```

### Reading in Wind Time Series

```@repl system 
wind_RT_TS = []
file_path = "Scripts-and-Data/TimeSeries/RT/Wind"

for i in length(wind_generator)
	winddf = CSV.read("$file_path/Wind$(i)RT.csv", DataFrame) # read in data 
	norm = maximum(winddf[:, 2])
	wind_array = TimeArray(timestamps, (winddf[:, 2]./norm)/100) # normalize and per-unitize data 
	wind_TS = SingleTimeSeries(;
           name = "max_active_power",
           data = wind_array,
		   scaling_factor_multiplier = # max active power 
       );
	push!(wind_RT_TS, wind_TS);
end
```

### Reading in Hydro Time Series 

```@repl system 
hydro_RT_TS = []
file_path = "Scripts-and-Data/TimeSeries/RT/Hydro"

for i in length(hydro_generator)
	hydrodf = CSV.read("$file_path/Hydro$(i)RT.csv", DataFrame) # read in data 
	norm = maximum(hydrodf[:, 2])
	hydro_array = TimeArray(timestamps, (hydrodf[:, 2]./norm)/100) # normalize and per-unitize data 
	hydro_TS = SingleTimeSeries(;
           name = "max_active_power",
           data = hydro_array,
		   scaling_factor_multiplier = get_max_active_power, # max active power
       );
	push!(hydro_RT_TS, hydro_TS);
end
```

### Reading in Load Time Series
If your time series data is defined by region as opposed to component, here is how you would create 
those time series objects.

```@repl system
load_RT_TS = []

for i in 1:3
    local loaddf = CSV.read("Scripts-and-Data/TimeSeries/RT/Load/LoadR$(i)RT.csv", DataFrame)
    local load_array = TimeArray(timestamps, (loaddf[:, 2]./maximum(loaddf[:, 2])))
    local load_TS = SingleTimeSeries(;
           name = "max_active_power",
           data = load_array,
           scaling_factor_multiplier = get_max_active_power, #assumption?
       );
    push!(load_RT_TS, load_TS);
end
```

# Building Generator Components
### Build thermal generators - parsing data from `gen_params`

```@repl system 
for i in length(thermal_generators)
        thermal = ThermalStandard(;
            name = # name,  
            available = true,
            status = true,
            bus = # parsed data,
            active_power = # parsed data,
            reactive_power = # parsed data,
            rating = # parsed data,
            active_power_limits = # parsed data,
            reactive_power_limits = # parsed data,
            ramp_limits = # parsed data,
            operation_cost = ThermalGenerationCost(nothing), 
            base_power = 100,
            time_limits = # parsed data,
            prime_mover_type = # parsed data,
            fuel = # parsed data,
        )
    add_component!(sys, thermal)
end
``` 

### Build solar generators - parsing data from `gen_params`
```@repl system
for i in length(solar_generators)
    local solar = RenewableDispatch(;
        name = # name
        available = true,
        bus = # bus of connection
        active_power = # active power
        reactive_power = # reactive power
        rating = # generator rating 
        prime_mover_type = PrimeMovers.PVe,
        reactive_power_limits = # reactive power limits
        power_factor = # power factor
        operation_cost = RenewableGenerationCost(nothing),
        base_power = 100
        )
    add_component!(sys, solar)
	add_time_series!(sys, solar, solar_RT_TS[i])
```

### Build wind generators - parsing data from `gen_params`

```@repl system

for i in length(wind_generators)
    wind = RenewableDispatch(;
        name = # name
        available = true,
        bus = # bus of connection
        active_power = # initial active power
        reactive_power = # initial reactive power
        rating = # generator rating 
        prime_mover_type = PrimeMovers.WT,
        reactive_power_limits = # reactive power limits
        power_factor = # power factor
        operation_cost = RenewableGenerationCost(nothing),
        base_power = 100
        )
    add_component!(sys, wind)
	add_time_series!(sys, wind, wind_RT_TS[i])
end
```
### Build hydro generators - parsing data from `gen_params` 
```@repl system 

for i in length(hydro_generation)
    local hydro = HydroDispatch(;
        name = "hydro$num",
        available = true,
        bus = buses[bus_hydro],
        active_power = 0.0,
        reactive_power = 0,
        rating = 0.0,
        prime_mover_type = PrimeMovers.HA,
        active_power_limits = (min = hydro_gens[i, "Min Stable Level (MW)"]/100, max = hydro_gens[i, "Max Capacity (MW)"]/100),
        reactive_power_limits = (min = 0.0, max = 0.0),
        ramp_limits = (up = hydro_gens[i, "Max Ramp Up (MW/min)"], down = hydro_gens[i, "Max Ramp Down (MW/min)"]),
        time_limits = (up = hydro_gens[i,"Min Up Time (h)" ], down = hydro_gens[i, "Min Down Time (h)"]),
        base_power = 100,
        operation_cost = HydroGenerationCost(nothing)
        )
    add_component!(sys, hydro)
	add_time_series!(sys, hydro, hydro_RT_TS[i])
end
```

### Build hydro generators - parsing data from `gen_params` 

This is how you would build loads if those loads were defined by region and not by generator.

```@repl system
file_path = "Scripts-and-Data/TimeSeries/RT/Load"

R1RTdf = CSV.read("$file_path/LoadR1RT.csv", DataFrame);
R2RTdf = CSV.read("$file_path/LoadR2RT.csv", DataFrame);
R3RTdf = CSV.read("$file_path/LoadR3RT.csv", DataFrame);
load_data = sort!(CSV.read("Scripts-and-Data/partfact.csv", DataFrame));

load_region = "Region"
factor = "Load Participation Factor"

for i in 1:118
    num = lpad(i, 3, '0')
    if load_data[i, load_region] == 1
        local max1 = maximum(R1RTdf[:, 2])
        local load = PowerLoad(;
            name = "load$num",
            available = true,
            bus = buses[i],
            active_power = 0.0, #per-unitized by device base_power
            reactive_power = 0.0, #per-unitized by device base_power
            base_power = 100.0, # MVA, for loads match system
            max_active_power = (max1)*(load_data[i, "factor"])/100, #per-unitized by device base_power
            max_reactive_power = 0.0,
        );
        add_component!(sys, load)
    elseif load_data[i, load_region] == 2
        local max2 = maximum(R2RTdf[:, 2])
        local load = PowerLoad(;
            name = "load$num",
            available = true,
            bus = buses[i],
            active_power = 0.0, #per-unitized by device base_power
            reactive_power = 0.0, #per-unitized by device base_power
            base_power = 100.0, # MVA, for loads match system
            max_active_power = (max2)*(load_data[i, "factor"])/100, #per-unitized by device base_power
            max_reactive_power = 0.0,
        );
        add_component!(sys, load)
    else load_data[i, "load_region"] == 3
        local max3 = maximum(R3RTdf[:, 2])
        local load = PowerLoad(;
            name = "load$num",
            available = true,
            bus = buses[i],
            active_power = 0.0, #per-unitized by device base_power
            reactive_power = 0.0, #per-unitized by device base_power
            base_power = 100.0, # MVA, for loads match system
            max_active_power = (max3)*(load_data[i, "factor"])/100, #per-unitized by device base_power
            max_reactive_power = 0.0,
        );
        add_component!(sys, load)
    end
end

associations1 = (
    InfrastructureSystems.TimeSeriesAssociation(
        load,
        load_RT_TS[1],)
    for load in loads_RT_R1
)
bulk_add_time_series!(sys, associations1)

associations2 = (
    InfrastructureSystems.TimeSeriesAssociation(
        load,
        load_RT_TS[2],)
    for load in loads_RT_R2
)
bulk_add_time_series!(sys, associations2)

associations3 = (
    InfrastructureSystems.TimeSeriesAssociation(
        load,
        load_RT_TS[3],)
    for load in loads_RT_R3
)
bulk_add_time_series!(sys, associations3)
```

# Building `RenewableGenerationCost`, `HydroGenerationCost` and `ThermalGenerationCost` functions

### `RenewableGenerationCost`
```@repl system 
ren_gens = collect(get_components(RenewableDispatch, sys)) #collect the renewable generators
for i in length(renewable_generation)
    cost_curve = zero(CostCurve) 
    cost_ren = RenewableGenerationCost(cost_curve)
    ren_gen = ren_gens[i] 
    set_operation_cost!(ren_gen, cost_ren)
end
``` 
For more information regarding renewable cost function please visit [RenewableGenerationCost](https://nrel-sienna.github.io/PowerSystems.jl/stable/model_library/renewable_generation_cost/#RenewableGenerationCost).
### `HydroGenerationCost`
```@repl system 
hydrogens = collect(get_components(HydroDispatch, sys)) #collect hydro generators
for i in length(hydro_generators)
    curve = LinearCurve(0.0)
    value_curve = # FuelCurve(curve) or CostCurve(curve)
    fixed = # fixed cost 
    cost_hydro = HydroGenerationCost(;variable = value_curve, fixed)
    hydrogen = hydrogens[i]
    set_operation_cost!(hydrogens[i], cost_hydro)
end
```
For more information regarding hydro cost functions please visit [HydroGenerationCost](https://nrel-sienna.github.io/PowerSystems.jl/stable/model_library/hydro_generation_cost/). 
### `ThermalGenerationCost`
```@repl system 
thermals = collect(get_components(ThermalStandard, sys)) # collect thermal generators 
for i in length(thermals)
   fuel_cost = # fuel prices
   heat_rate_base = # heat rate base
   heat_rate = # heat rates
   load_point = # load points 
   heat_rate_curve = PieceWiseIncrementalCurve(heat_rate_base[i], load_point[i], heat_rate[i])
   fuel_curve FuelCurve(; value_curve = heat_rate_curve, fuel_cost = fuel_prices[i])
   cost_thermal = ThermalGenerationCost(;
            variable = fuel_curve,
            fixed = # fixed cost 
            start_up = # start up cost
            shut_down = # shut down cost
        )
        set_operation_cost!(thermals[i], cost_thermal)
end
```
For more information regarding thermal cost functions please visit [ThermalGenerationCost](https://nrel-sienna.github.io/PowerSystems.jl/stable/model_library/thermal_generation_cost/). 



### 




