
using PowerSystems
using PowerSimulations
using Dates
using CSV
using HydroPowerSimulations
using DataFrames
using Logging
using TimeSeries
using HiGHS #solver
using PowerNetworkMatrices
using Xpress
using PowerGraphics
mip_gap = 0.01

## Transform DA into Deterministic from SingleTimeSeries
transform_single_time_series!(sys_DA, Hour(48), Day(1))
transform_single_time_series!(sys_RT, Hour(2), Hour(1))

optimizer = optimizer_with_attributes(
                Xpress.Optimizer,
                #"parallel" => "on",
                "MIPRELSTOP" => mip_gap)


# logger      = configure_logging(console_level=Logging.Info)
# data_dir    = "rdm"
# base_power  = 100.0
# descriptors = raw"user_descriptors 2.yaml"
# generator_mapping = raw"generator_mapping 3.yaml"
# timeseries_metadata_file = raw"rdm/timeseries_pointers.json"


                
template_uc = template_unit_commitment(;
network = NetworkModel(CopperPlatePowerModel; duals =[CopperPlateBalanceConstraint],  use_slacks = true))
set_device_model!(template_uc, ThermalStandard, ThermalBasicUnitCommitment)
set_device_model!(template_uc, RenewableDispatch, RenewableFullDispatch, ) 
set_device_model!(template_uc, PowerLoad, StaticPowerLoad)
set_device_model!(template_uc, DeviceModel(Line, 
                                        StaticBranch; 
                                        use_slacks = true))
set_device_model!(template_uc, DeviceModel(Transformer2W, 
                                        StaticBranch; 
                                        use_slacks = true))
#set_device_model!(template_uc, HydroDispatch, HydroDispatchRunOfRiver)


template_ed = template_economic_dispatch(;
    network = NetworkModel(CopperPlatePowerModel; duals =[CopperPlateBalanceConstraint],  use_slacks = true),
)



model_uc = DecisionModel(
    template_uc,
    sys_DA;
    name = "DA",
    optimizer = optimizer,
    system_to_file = false,
    initialize_model = true,
    check_numerical_bounds = false,
    optimizer_solve_log_print = true,
    direct_mode_optimizer = false,
    rebuild_model = false,
    store_variable_names = true,
    calculate_conflict = true,
)
model_ed = DecisionModel(
    template_ed,
    sys_RT;
    name = "RT",
    optimizer = optimizer,
    system_to_file = false,
    initialize_model = true,
    check_numerical_bounds = false,
    optimizer_solve_log_print = true,
    direct_mode_optimizer = false,
    rebuild_model = false,
    store_variable_names = true,
    calculate_conflict = true,
)

models = SimulationModels(; decision_models = [model_uc, model_ed])

feedforward = Dict(
    "RT" => [
        SemiContinuousFeedforward(;
            component_type = ThermalStandard,
            source = OnVariable,
            affected_values = [ActivePowerVariable],
        ),
    ],
)

DA_sequence = SimulationSequence(;
    models = models,
    ini_cond_chronology = InterProblemChronology(),
    feedforwards = feedforward,
)

initial_date = "2023-01-01"
steps_sim    = 100
current_date = string( today() )
sim = Simulation(
    name = current_date * "_DR-test" * "_" * string(steps_sim)* "steps",
    steps = steps_sim,
    models = models,
    initial_time = DateTime(string(initial_date,"T00:00:00")),
    sequence = DA_sequence,
    simulation_folder = tempdir()#".",
)

build!(sim)
execute!(sim)
#---------------------------------------------------------------------------
results = SimulationResults(sim)
# ed_results = get_decision_problem_results(results, "RT")
# uc_results = get_decision_problem_results(results, "DA")
# LMP_ed = read_realized_duals(ed_results)
# LMP_uc = read_realized_duals(uc_results)

# ed_LMP_data = LMP_ed["CopperPlateBalanceConstraint__System"]
# uc_LMP_data = LMP_uc["CopperPlateBalanceConstraint__System"]

# CSV.write("C:\\Users\\acasavan\\118 Bus Data\\ed_LMP.csv", ed_LMP_data)
# CSV.write("C:\\Users\\acasavan\\118 Bus Data\\uc_LMP.csv", uc_LMP_data)

# ## ED Saving all Renewable Active Power Variable to csvs
# results_hydro = SimulationResults(sim)
# ed = read_variables(ed_results)
# ed_ren_gen = ed["ActivePowerVariable__RenewableDispatch"]

# for (key, df) in ed_ren_gen 
#     formatted_key = replace(string(key), ":" => "-")
#     file_name = "C:\\Users\\acasavan\\118 Bus Data\\ed_ren_gen\\$(formatted_key).csv"
#     CSV.write(file_name, df)
# end


# ## ED Saving all power load variables
# ed = read_parameters(ed_results)
# ed_power_load = ed["ActivePowerTimeSeriesParameter__PowerLoad"]

# for (key, df) in ed_power_load
#     formatted_key = replace(string(key), ":" => "-")
#     file_name = "C:\\Users\\acasavan\\118 Bus Data\\ed_power_load\\$(formatted_key).csv"
#     CSV.write(file_name, df)
# end

# ## UC Saving all power load variables

# uc = read_parameters(uc_results)
# uc_power_load = uc["ActivePowerTimeSeriesParameter__PowerLoad"]
# for (key, df) in uc_power_load
#     formatted_key = replace(string(key), ":" => "-")
#     file_name = "C:\\Users\\acasavan\\118 Bus Data\\uc_power_load\\$(formatted_key).csv"
#     CSV.write(file_name, df)
# end

# # ## UC saving all ren_gen variables

# uc = read_parameters(uc_results)
# uc_ren_gen = uc["ActivePowerTimeSeriesParameter__RenewableDispatch"]
# for (key, df) in uc_ren_gen
#     formatted_key = replace(string(key), ":" => "-")
#     file_name = "C:\\Users\\acasavan\\118 Bus Data\\uc_ren_gen\\$(formatted_key).csv"
#     CSV.write(file_name, df)
# end

# ed = read_variables(ed_results)
# ed_thermal = ed["ActivePowerVariable__ThermalStandard"]
# for (key, df) in ed_thermal
#     formatted_key = replace(string(key), ":" => "-")
#     file_name = "C:\\Users\\acasavan\\118 Bus Data\\ed_thermal\\$(formatted_key).csv"
#     CSV.write(file_name, df)
# end

# ed = read_expressions(ed_results)
# ed_thermal_cost = ed["ProductionCostExpression__ThermalStandard"]
# for (key, df) in ed_thermal_cost
#     formatted_key = replace(string(key), ":" => "-")
#     file_name = "C:\\Users\\acasavan\\118 Bus Data\\ed_thermal_cost\\$(formatted_key).csv"
#     CSV.write(file_name, df)
# end

# ed = read_expressions(ed_results)
# ed_active_power_balance = ed["ActivePowerBalance__System"]
# for (key, df) in ed_active_power_balance
#     formatted_key = replace(string(key), ":" => "-")
#     file_name = "C:\\Users\\acasavan\\118 Bus Data\\ed_active_power_balance\\$(formatted_key).csv"
#     CSV.write(file_name, df)
# end


# uc = read_variables(uc_results)
# uc_thermal = uc["ActivePowerVariable__ThermalStandard"]
# for (key, df) in uc_thermal
#     formatted_key = replace(string(key), ":" => "-")
#     file_name = "C:\\Users\\acasavan\\118 Bus Data\\uc_thermal\\$(formatted_key).csv"
#     CSV.write(file_name, df)
# end

