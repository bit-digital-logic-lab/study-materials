// Interface signals between the mesh and DUT. Note that it does not include
// the rings -- they're not visible outside of the DUT and are hence not part
// of the interface.
interface If_mesh();
    logic clk;
    logic reset;

    logic data_avail_for_venv[MESH_SIZE][MESH_SIZE];
    logic venv_taking_data[MESH_SIZE][MESH_SIZE];
    Ring_slot data_to_venv[MESH_SIZE][MESH_SIZE];

    logic can_accept_data_from_env[MESH_SIZE][MESH_SIZE];
    Ring_slot data_from_venv [MESH_SIZE][MESH_SIZE];

    modport TEST (output clk, reset, 
			input  data_avail_for_venv, data_to_venv,
			output venv_taking_data, can_accept_data_from_env,
			data_from_venv);
    modport DUT  (input  clk, reset,
			output data_avail_for_venv, venv_taking_data,
			input  data_to_venv, can_accept_data_from_env,
			data_from_venv);
endinterface
