module fifo #(parameter type DATA_TYPE=logic[1:0], parameter N_ADDR_BITS=2)
	(input logic reset, rd_en, wr_en, clk,
	 input DATA_TYPE wr_data,
	 output logic empty, full,
	 output DATA_TYPE rd_data);
    parameter FIFO_DEPTH = 1 << N_ADDR_BITS;

    DATA_TYPE fifo_mem[FIFO_DEPTH-1:0];	// The actual memory
    // Our rd and wr pointers include an extra MSB bit to distinguish between
    // Empty vs. Full.
    logic [N_ADDR_BITS:0] rd_ptr, wr_ptr;

    always_ff @(posedge clk) begin
	// Clear the read and write pointers synchronously if reset is asserted.
	...

        // The write pointer is the location where we will write into *next*.
        // It typically does not yet have valid data (but it may have valid data
        // from a while ago once the FIFO fills and we circle around).
	... handle FIFO writes ...

        // The read pointer is the location of data ready to read *now*.
        // It always has valid data (unless the FIFO is empty).
	... handle FIFO reads ...
    end

    always_comb begin
	// Create the full and empty signals, based on the read and
	// write pointers
        empty = ...;
        full = ...

	// Drive read data out.
        rd_data = ...
    end
endmodule
