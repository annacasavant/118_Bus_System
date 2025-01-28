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

### Reading in Solar Time Series

```@repl system 
solar_RT_TS = []

for i in length(solar_generator)
	solardf = CSV.read("Scripts-and-Data/TimeSeries/RT/Solar/Solar$(i)RT.csv", DataFrame) # read in data 
	norm = maximum(solardf[:, 2])
	solar_array = TimeArray(timestamps, (solardf[:, 2]./norm)) # normalize data 
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

for i in length(wind_generator)
	winddf = CSV.read("Scripts-and-Data/TimeSeries/RT/Wind/Wind$(i)RT.csv", DataFrame) # read in data 
	norm = maximum(winddf[:, 2])
	wind_array = TimeArray(timestamps, (winddf[:, 2]./norm)) # normalize data 
	wind_TS = SingleTimeSeries(;
           name = "max_active_power",
           data = wind_array,
		   scaling_factor_multiplier = # max active power 
       );
	push!(wind_RT_TS, wind_TS);
end
```

### Reading in Load Time Series

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

### Reading in Hydro Time Series 

```@repl system 
hydro_RT_TS = []

for i in length(hydro_generator)
	hydrodf = CSV.read("Scripts-and-Data/TimeSeries/RT/Hydro/Hydro$(i)RT.csv", DataFrame) # read in data 
	norm = maximum(hydrodf[:, 2])
	hydro_array = TimeArray(timestamps, (hydrodf[:, 2]./norm)) # normalize data 
	hydro_TS = SingleTimeSeries(;
           name = "max_active_power",
           data = hydro_array,
		   scaling_factor_multiplier = get_max_active_power, # max active power
       );
	push!(hydro_RT_TS, hydro_TS);
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
    add_component!(sys_DA, hydro)
	push!(hydro_DA_RT_gens, hydro)
	add_time_series!(sys_DA, hydro, hydro_DA_RT_TS[i])
end
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




