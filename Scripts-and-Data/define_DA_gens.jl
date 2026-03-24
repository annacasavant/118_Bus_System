#!/usr/bin/env julia

using PowerSystems
using CSV
using DataFrames

# ============================================================================
# Define Generators: Add power supply to the system
# ============================================================================
# This script creates generator components of four types (thermal, hydro, solar,
# wind) at specific buses and assigns operating characteristics and time series.

# Read generator parameter data from CSV
gen_params = CSV.read("Scripts-and-Data/gen.csv", DataFrame)
# Separate generators by type for organized processing
thermal_gens = DataFrame()
hydro_gens = DataFrame()
solar_gens = DataFrame()
wind_gens = DataFrame()

# Categorize generators by their type
for row in eachrow(gen_params)
    if row["type"] == "Thermal "
        push!(thermal_gens, row, promote=true)
    elseif row["type"] == "Hydro"
        push!(hydro_gens, row, promote=true)
    elseif row["type"] == "Solar"
        push!(solar_gens, row, promote=true)
    elseif row["type"] == "Wind"
        push!(wind_gens, row, promote=true)
    end
end

# ============================================================================
# Solar Generators (RenewableDispatch)
# ============================================================================
# Solar PV generators produce electricity based on sunlight availability.
# They are modeled as RenewableDispatch, meaning they can be curtailed by the
# optimizer but cannot exceed the hourly generation profile in solar_DA_TS.
# There are 75 solar generators spread across the 118-bus system.
for i in 1:75
	num = lpad(i, 3, '0')  # Zero-padded name, e.g., "solar001"
    # Extract bus number from the string (e.g., "bus069" -> 69)
    local bus_solar = parse(Int, solar_gens[i, "bus of connection"][4:6])
    local rate = gen_params[i, "Max Capacity (MW)"]
    local solar = RenewableDispatch(;
        name = "solar$num",
        available = true,
        bus = get_bus(sys_DA, bus_solar),
        active_power = 0.0,       # Initial condition; solver determines dispatch
        reactive_power = 0.0,
        rating = rate,            # Nameplate capacity in MW
        prime_mover_type = PrimeMovers.PVe,  # PVe = photovoltaic
        reactive_power_limits = (min = 0.0, max = 0.0),
        power_factor = 1.0,       # Unity power factor (no reactive contribution)
        operation_cost = RenewableGenerationCost(nothing),  # Placeholder; set later
        base_power = solar_DA_max[i]          # device base (MVA)
        )
    add_component!(sys_DA, solar)
	# Attach the DA solar time series profile (normalized 0-1 hourly output)
	add_time_series!(sys_DA, solar, solar_DA_TS[i])
end

# ============================================================================
# Wind Generators (RenewableDispatch)
# ============================================================================
# Wind generators follow a similar pattern to solar but use wind speed profiles.
# They are also modeled as RenewableDispatch and can be curtailed.
# There are 17 wind generators in the system.
for i in 1:17
	num = lpad(i, 3, '0')  # Zero-padded name, e.g., "wind001"
    local bus_wind = parse(Int, wind_gens[i, "bus of connection"][4:6])
    rate = gen_params[i, "Max Capacity (MW)"]
    local wind = RenewableDispatch(;
        name = "wind$num",
        available = true,
        bus = get_bus(sys_DA, bus_wind),
        active_power = 0.0,
        reactive_power = 0.0,
        rating = rate,
        prime_mover_type = PrimeMovers.WT,  # WT = wind turbine
        reactive_power_limits = (min = 0.0, max = 0.0),
        power_factor = 1.0,
        operation_cost = RenewableGenerationCost(nothing),  # Placeholder; set below
        base_power = wind_DA_max[i]          # device base (MVA)
        )
    add_component!(sys_DA, wind)
	# Attach the DA wind time series profile (normalized 0-1 hourly output)
	add_time_series!(sys_DA, wind, wind_DA_TS[i])
end

# ============================================================================
# Renewable Generation Costs (Solar + Wind)
# ============================================================================
# Renewable generators have no fuel costs but may have a small curtailment
# penalty to discourage the optimizer from needlessly spilling available energy.
# Here, a zero variable cost curve is assigned. The curtailment_cost variable
# (LinearCurve(0, 0.275)) is defined but not applied — it can be activated to
# penalize curtailment if desired in future studies.
ren_gens = collect(get_components(RenewableDispatch, sys_DA))  # All 92 renewables (75 solar + 17 wind)
for i in 1:92
    cost_curve = zero(CostCurve)          # Zero variable generation cost
    value_curve = LinearCurve(0, .275)    # Optional curtailment cost ($/MWh)
    curtailment_cost = CostCurve(value_curve)
    cost_ren = RenewableGenerationCost(cost_curve)
    ren_gen = ren_gens[i]
    set_operation_cost!(ren_gen, cost_ren)
end

# ============================================================================
# Hydroelectric Generators (HydroDispatch)
# ============================================================================
# Hydro generators are dispatchable within the bounds set by available water
# resources. Unlike thermal or renewables, they have both power limits
# (min/max MW) and ramp rate constraints that limit how fast output can change.
# The time series attached here (hydro_DA_RT_TS) provides the hourly upper
# limit on generation, derived from monthly water budget data.
for i in 1:43
	local num = lpad(i, 3, '0')
    local bus_hydro = parse(Int, hydro_gens[i, "bus of connection"][4:6])
    local hydro = HydroDispatch(;
        name = "hydro$num",
        available = true,
        bus = get_bus(sys_DA, bus_hydro),
        active_power = 0.0,
        reactive_power = 0,
        rating = 0.0,
        prime_mover_type = PrimeMovers.HA,  # HA = hydraulic turbine
        # Power limits in per-unit (divide MW by base_power = 100 MVA)
        active_power_limits = (min = hydro_gens[i, "Min Stable Level (MW)"]/100, max = hydro_gens[i, "Max Capacity (MW)"]/100),
        reactive_power_limits = (min = 0.0, max = 0.0),
        # Ramp limits constrain how fast output can change between intervals (MW/min)
        ramp_limits = (up = hydro_gens[i, "Max Ramp Up (MW/min)"], down = hydro_gens[i, "Max Ramp Down (MW/min)"]),
        # Minimum up/down time limits (hours) prevent rapid cycling of the unit
        time_limits = (up = hydro_gens[i,"Min Up Time (h)" ], down = hydro_gens[i, "Min Down Time (h)"]),
        base_power = hydro_DA_RT_max[i],
        operation_cost = HydroGenerationCost(nothing)  # Placeholder; set below
        )
    add_component!(sys_DA, hydro)
	# Attach the shared DA/RT hydro time series (water availability profile)
	add_time_series!(sys_DA, hydro, hydro_DA_RT_TS[i])
end

# ============================================================================
# Hydro Generation Costs
# ============================================================================
# Hydroelectric generation has no fuel cost. A zero-cost linear curve is used
# so the optimizer can freely dispatch hydro within its water availability limits.
hydrogens = collect(get_components(HydroDispatch, sys_DA))
for i in 1:43
    cost_curve = LinearCurve(0.0)              # Zero variable cost ($/MWh)
    value_curve = CostCurve(cost_curve)
    fixed = 0.0                                # No fixed operating cost
    cost_hydro = HydroGenerationCost(;variable = value_curve, fixed)
    set_operation_cost!(hydrogens[i], cost_hydro)
end

# ============================================================================
# Thermal Generators (ThermalStandard)
# ============================================================================
# Thermal generators burn fuel (natural gas, coal, oil, etc.) to produce
# electricity. Their operating cost depends on heat rate (fuel efficiency)
# and fuel price, making them significantly more expensive than renewables.
# There are 192 thermal generators in this system.

# Map short prime mover codes (from CSV) to PowerSystems.jl PrimeMover types
# OT=Other, CC=Combined Cycle, CT=Combustion Turbine, ST=Steam Turbine
thermal_prime_mover_type = Dict{String, PrimeMovers}(
    "OT" => PrimeMovers.OT,
    "CC" => PrimeMovers.CC,
    "CT" => PrimeMovers.CT,
    "HA" => PrimeMovers.HA,
    "IC" => PrimeMovers.IC,
    "WT" => PrimeMovers.WT,
    "ST" => PrimeMovers.ST,
)

# Fuel prices in $/MMBTU — these scale the heat rate curves into $/MWh costs
ng_price = 5.4      # Natural gas
coal_price = 1.8    # Coal
oil_price = 21      # Distillate fuel oil
bm_price = 2.4      # Biomass (mapped to OTHER)
geo_price = 0       # Geothermal (no fuel cost)

# Assign fuel type and price to each thermal generator based on its name/type
# This determines the variable cost of electricity production for each unit
fuel_prices = []
fuel = []
for i in 1:192
    if thermal_gens[i, "PrimeMoveType"] == "OT"
        push!(fuel_prices, bm_price)
        push!(fuel, ThermalFuels.OTHER)
    elseif thermal_gens[i, "PrimeMoveType"] == "CC" || startswith(thermal_gens[i, "Generator Name"], "CT NG") || startswith(thermal_gens[i, "Generator Name"], "ICE NG") || startswith(thermal_gens[i, "Generator Name"], "ST NG")
        push!(fuel_prices, ng_price)
        push!(fuel, ThermalFuels.NATURAL_GAS)
    elseif startswith(thermal_gens[i, "Generator Name"], "CT Oil")
        push!(fuel_prices, oil_price)
        push!(fuel, ThermalFuels.DISTILLATE_FUEL_OIL)
    elseif startswith(thermal_gens[i, "Generator Name"], "ST Coal")
        push!(fuel_prices, coal_price)
        push!(fuel, ThermalFuels.COAL)
    elseif startswith(thermal_gens[i, "Generator Name"], "Geo")
        push!(fuel_prices, geo_price)
        push!(fuel, ThermalFuels.GEOTHERMAL)
    elseif startswith(thermal_gens[i, "Generator Name"], "ST Other 01")
        push!(fuel_prices, oil_price)
        push!(fuel, ThermalFuels.DISTILLATE_FUEL_OIL)
    elseif startswith(thermal_gens[i, "Generator Name"], "ST Other 02")
        push!(fuel_prices, ng_price)
        push!(fuel, ThermalFuels.NATURAL_GAS)
    end
end

# Parse generator ratings (MVA), defaulting to 1.0 per unit if missing from CSV
ratings = []
for i in 1:192
    if ismissing(thermal_gens[i, "Rating"]) || thermal_gens[i, "Rating"] == ""
        push!(ratings, 1.0)
    else
        push!(ratings, parse(Float64, thermal_gens[i, "Rating"]) / 100.0)  # Convert MW to per-unit by dividing by system base (100 MVA)
    end
end

# ============================================================================
# Thermal Heat Rate Curves
# ============================================================================
# Heat rate (BTU/kWh) measures how much fuel is burned per unit of electricity.
# Lower heat rate = more efficient generator. BTU/kWh is converted to MMBTU/MWh
# by dividing by 1000, which is the unit expected by PowerSystems.jl.
#
# Generators may have up to 5 piecewise incremental bands, capturing the fact
# that efficiency changes as output increases. Fewer bands = simpler cost curve.
heat_rate1 = thermal_gens[:, "Heat Rate Inc Band 1 (BTU/kWh)"] ./1000
heat_rate2 = thermal_gens[:, "Heat Rate Inc Band 2 (BTU/kWh)"] ./1000
heat_rate3 = thermal_gens[:, "Heat Rate Inc Band 3 (BTU/kWh)"] ./1000
heat_rate4 = thermal_gens[:, "Heat Rate Inc Band 4 (BTU/kWh)"] ./1000
heat_rate5 = thermal_gens[:, "Heat Rate Inc Band 5 (BTU/kWh)"] ./1000

# Combine all bands into a matrix for easy per-generator indexing
heat_rates = hcat(
    heat_rate1,
    heat_rate2,
    heat_rate3,
    heat_rate4,
    heat_rate5
)

# Load points (MW) define where each heat rate band applies.
# The piecewise curve spans from Min Stable Level to Max Capacity.
# Each band covers the range between two consecutive load points.
load_points = hcat(
    thermal_gens[:, "Min Stable Level (MW)"],
    thermal_gens[:, "Load Point Band 1 (MW)"],
    thermal_gens[:, "Load Point Band 2 (MW)"],
    thermal_gens[:, "Load Point Band 3 (MW)"],
    thermal_gens[:, "Load Point Band 4 (MW)"],
    thermal_gens[:, "Load Point Band 5 (MW)"]
)

# Base heat rate (MMBTU/hr): constant fuel consumption when the unit is online
# at minimum load, regardless of output level. Converted from MMBTU/hr to MMBTU/MWh.
heat_rate_base = (thermal_gens[:, "Heat Rate Base (MMBTU/hr)"])/1000

# ============================================================================
# Build Cost Function for Each Thermal Generator
# ============================================================================
# The cost function converts heat rate and fuel price into a generation cost
# ($/MWh). The number of piecewise bands varies by generator; missing bands
# mean the curve ends at that point and max_cap closes the last interval.
#
# LinearCurve is used for generators with only one heat rate band.
# PiecewiseIncrementalCurve is used for generators with 2-5 bands.
# FuelCurve wraps the heat rate curve and multiplies by fuel price ($/MMBTU)
# to produce the final variable cost in $/MWh.
thermal_cost_function = []
for i in 1:192
    max_cap = thermal_gens[i, "Max Capacity (MW)"]
    if ismissing(heat_rates[i,2])
        # Single-band: constant heat rate across all output levels
        heat_rate = heat_rate1[i]
        heat_rate_curve = LinearCurve(heat_rate, heat_rate_base[i])
        fuel_curve = FuelCurve(; value_curve = heat_rate_curve, fuel_cost = fuel_prices[i])
        cost = ThermalGenerationCost(;
            variable = fuel_curve,
            fixed = 0.00,
            start_up = thermal_gens[i, "Start Cost (dollar)"],
            shut_down = 0.0)
    elseif !ismissing(heat_rates[i,2]) && ismissing(heat_rates[i,3])
        # Two-band piecewise curve
        heat_rate = [heat_rate1[i], heat_rate2[i]]
        load_point = [load_points[i,1], load_points[i,2], max_cap]
        heat_rate_curve = PiecewiseIncrementalCurve(heat_rate_base[i], load_point, heat_rate)
        fuel_curve = FuelCurve(; value_curve = heat_rate_curve, fuel_cost = fuel_prices[i])
        cost = ThermalGenerationCost(;
            variable = fuel_curve,
            fixed = 0.0,
            start_up = thermal_gens[i, "Start Cost (dollar)"],
            shut_down = 0.0
        )
    elseif !ismissing(heat_rates[i,2]) && !ismissing(heat_rates[i,3]) && ismissing(heat_rates[i,4])
        # Three-band piecewise curve
        heat_rate = [heat_rate1[i], heat_rate2[i], heat_rate3[i]]
        load_point = [load_points[i,1], load_points[i,2], load_points[i,3], max_cap]
        heat_rate_curve = PiecewiseIncrementalCurve(heat_rate_base[i], load_point, heat_rate)
        fuel_curve = FuelCurve(; value_curve = heat_rate_curve, fuel_cost = fuel_prices[i])
        cost = ThermalGenerationCost(;
            variable = fuel_curve,
            fixed = 0.0,
            start_up = thermal_gens[i, "Start Cost (dollar)"],
            shut_down = 0.0
        )
    elseif !ismissing(heat_rates[i,2]) && !ismissing(heat_rates[i,3]) && !ismissing(heat_rates[i,4]) && ismissing(heat_rates[i,5])
        # Four-band piecewise curve
        heat_rate = [heat_rate1[i], heat_rate2[i], heat_rate3[i], heat_rate4[i]]
        load_point = [load_points[i,1], load_points[i,2], load_points[i,3], load_points[i,4], max_cap]
        heat_rate_curve = PiecewiseIncrementalCurve(heat_rate_base[i], load_point, heat_rate)
        fuel_curve = FuelCurve(; value_curve = heat_rate_curve, fuel_cost = fuel_prices[i])
        cost = ThermalGenerationCost(;
            variable = fuel_curve,
            fixed = 0.0,
            start_up = thermal_gens[i, "Start Cost (dollar)"],
            shut_down = 0.0
        )
    elseif !ismissing(heat_rates[i,2]) && !ismissing(heat_rates[i,3]) && !ismissing(heat_rates[i,4]) && !ismissing(heat_rates[i,5])
        # Five-band piecewise curve (most detailed cost representation)
        heat_rate = [heat_rate1[i], heat_rate2[i], heat_rate3[i], heat_rate4[i], heat_rate5[i]]
        load_point = [load_points[i,1], load_points[i,2], load_points[i,3], load_points[i,4], load_points[i,5], max_cap]
        heat_rate_curve = PiecewiseIncrementalCurve(heat_rate_base[i], load_point, heat_rate)
        fuel_curve = FuelCurve(; value_curve = heat_rate_curve, fuel_cost = fuel_prices[i])
        cost = ThermalGenerationCost(;
            variable = fuel_curve,
            fixed = 0.0,
            start_up = thermal_gens[i, "Start Cost (dollar)"],
            shut_down = 0.0
        )
    end
    push!(thermal_cost_function, cost)
end


# ============================================================================
# Create Thermal Generator Components
# ============================================================================
# Each ThermalStandard generator is added to the system with its operating
# parameters, then the pre-built cost function is applied. The cost function
# is set separately (via set_operation_cost!) because it depends on data
# computed in the heat rate loop above.
for i in 1:192
    prime_mover_str = thermal_gens[i, "PrimeMoveType"]
    prime_mover = thermal_prime_mover_type[prime_mover_str]  # Look up enum from string
    bus_thermal = parse(Int, thermal_gens[i, "bus of connection"][4:6])
    # Convert MW to per-unit by dividing by base_power (100 MVA
    # We will use the system base for thermal generators
    max_active_power = thermal_gens[i, "Max Capacity (MW)"]/100.0
    min_active_power = thermal_gens[i, "Min Stable Level (MW)"]/100.0
    thermal = ThermalStandard(;
        name = thermal_gens[i, "Generator Name"],
        available = true,
        status = true,   # Generator is initially online
        bus = get_bus(sys_DA, bus_thermal),
        active_power = 0.0,
        reactive_power = 0.0,
        rating = ratings[i],
        active_power_limits = (min = 0, max = max_active_power),
        reactive_power_limits = nothing,
        # Ramp limits in per-unit/min (MW/min divided by 100 MVA base)
        ramp_limits = (up = thermal_gens[i, "Max Ramp Up (MW/min)"]/100.0, down = thermal_gens[i, "Max Ramp Down (MW/min)"]/100.0),
        operation_cost = ThermalGenerationCost(nothing),  # Placeholder; set below
        base_power = 100.0,
        time_limits = (up = thermal_gens[i,"Min Up Time (h)" ], down = thermal_gens[i, "Min Down Time (h)"]),
        prime_mover_type = prime_mover,
        fuel = fuel[i],
    )
    add_component!(sys_DA, thermal)
    # Apply the piecewise heat rate cost function built in the previous loop
    set_operation_cost!(thermal, thermal_cost_function[i])
end
