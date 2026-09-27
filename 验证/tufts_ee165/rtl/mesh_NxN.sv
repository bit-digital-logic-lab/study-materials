import mesh_defs::*;

module mesh_NxN #(parameter N=2) (If_mesh if_mesh);

  // ALL INDICES IN THIS FILE ARE TREATED AS Y,X LOCATIONS (I.E., ROW,COLUMN),
  // WHICH IS HOW MATRICES AND 2D ARRAYS USUALLY WORK.
  // BUT IT IS NOT HOW COORDINATES ARE USUALLY GIVEN IN GEOMETRY.

  ////////////////////////////////////////////
  // Declare the ring signals.
  ////////////////////////////////////////////
  Ring_slot vert_ring[N][N],
	    hori_ring[N][N];

  ////////////////////////////////////////////
  // Instantiantiate the NxN array of mesh stops
  ////////////////////////////////////////////

  // See https://stackoverflow.com/questions/12504837/
  // verilog-generate-genvar-in-an-always-block
  generate
    genvar x, y;
    for (y=0; y<N; ++y) begin : yloop
	for (x=0; x<N; ++x) begin: xloop
	    // We're building the instance, e.g., yloop[2].xloop[1].MS
	    mesh_stop #(.MY_Y(y), .MY_X(x)) MS (
		.reset(if_mesh.reset), .clk(if_mesh.clk),
		.data_from_venv(if_mesh.data_from_venv[y][x]),
		.data_to_venv(if_mesh.data_to_venv[y][x]),
		.data_avail_for_venv(if_mesh.data_avail_for_venv[y][x]),
		.venv_taking_data(if_mesh.venv_taking_data[y][x]),
		.can_accept_data_from_env(if_mesh.can_accept_data_from_env[y][x]),
		.vert_ring_in (vert_ring[(y+N-1)%N][x]),
		.vert_ring_out(vert_ring[y][x]),
		.hori_ring_in (hori_ring[y][(x+N-1)%N]),
		.hori_ring_out(hori_ring[y][x%N]));
	end // for x
    end // for y
  endgenerate
endmodule
