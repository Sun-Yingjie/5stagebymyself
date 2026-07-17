# Initial structural-synthesis constraints for rv32_core.
# These values are provisional and are not a performance claim.

set CORE_CLOCK_PERIOD_NS 10.000
set CORE_CLOCK_UNCERTAINTY_NS 0.100
set CORE_INPUT_DELAY_NS 1.000
set CORE_OUTPUT_DELAY_NS 1.000

create_clock \
    -name core_clk \
    -period $CORE_CLOCK_PERIOD_NS \
    [get_ports clk]

set_clock_uncertainty \
    $CORE_CLOCK_UNCERTAINTY_NS \
    [get_clocks core_clk]

set core_data_inputs [
    remove_from_collection \
        [all_inputs] \
        [get_ports clk]
]

set_input_delay \
    $CORE_INPUT_DELAY_NS \
    -clock [get_clocks core_clk] \
    $core_data_inputs

set_output_delay \
    $CORE_OUTPUT_DELAY_NS \
    -clock [get_clocks core_clk] \
    [all_outputs]

# rst is synchronous and intentionally remains timed as a data input.
# Driving cells, output loads and design-rule limits are added after the
# SMIC 28nm library and target corner have been identified.
