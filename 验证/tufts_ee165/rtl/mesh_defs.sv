package mesh_defs;

parameter RING_DATA_WIDTH=4,	// 4-bit data packets
	  MESH_ADDR_BITS=2;	// max 4x4 mesh size.

typedef struct packed {
    logic [RING_DATA_WIDTH-1:0] data;	// the actual data!
    logic valid;			// is this slot being used?
    logic reserved;			// to avoid a mesh stop being starved
    logic[1:0] unused;			// so that valid & reserved make an even
					// byte for easier debug.
    logic[MESH_ADDR_BITS-1:0] src_y, src_x,	// source stop (just for debug)
			      dst_y, dst_x;	// destination mesh stop
} Ring_slot;
parameter Ring_slot EMPTY_RING_SLOT = '{0, 0, 0, 0, 0, 0, 0, 0};

// Debug-print function.
function string print_RS (Ring_slot RS);
    string s;
    s = $sformatf ("Data=%d, valid=%0d, from y,x=(%0d,%0d) -> (%0d,%0d)",
		RS.data, RS.valid, RS.src_y, RS.src_x, RS.dst_y, RS.dst_x);
    return (s);
endfunction: print_RS

endpackage : mesh_defs
