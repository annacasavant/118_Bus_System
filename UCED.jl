using PowerSystems
using PowerSimulations
const PSI = PowerSimulations
using Dates
using CSV
using HydroPowerSimulations
using DataFrames
using Logging
using TimeSeries
using HiGHS #solver
using PowerNetworkMatrices
using Xpress


mip_gap = 0.01

## Transform DA into Deterministic from SingleTimeSeries
transform_single_time_series!(sys_DA, Hour(48), Day(1))
transform_single_time_series!(sys_RT, Hour(2), Hour(1))

optimizer = optimizer_with_attributes(
                Xpress.Optimizer,
                #"parallel" => "on",
                "mip_rel_gap" => mip_gap)


# logger      = configure_logging(console_level=Logging.Info)
# data_dir    = "rdm"
# base_power  = 100.0
# descriptors = raw"user_descriptors 2.yaml"
# generator_mapping = raw"generator_mapping 3.yaml"
# timeseries_metadata_file = raw"rdm/timeseries_pointers.json"


                
template_uc = template_unit_commitment()
set_device_model!(template_uc, ThermalStandard, ThermalStandardUnitCommitment)
set_device_model!(template_uc, RenewableDispatch, FixedOutput) 
set_device_model!(template_uc, PowerLoad, StaticPowerLoad)
set_device_model!(template_uc, HydroDispatch, HydroDispatchRunOfRiver)

template_ed = template_economic_dispatch(;
    network = NetworkModel(PTDFPowerModel; use_slacks = true),
)


models = SimulationModels(;
    decision_models = [
        DecisionModel(
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
 ,
        DecisionModel(template_ed,
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
        calculate_conflict = true,),
    ],
)


feedforward = Dict(
    "DA" => [
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
steps_sim    = 2
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