// This is the first testbench version.
// It:	instantiates the FIFO (which is meant to be fifo_1.sv)
//	drives it with random data every cycle
//	reads the FIFO data every cycle
//	never checks empty or full
//	has no ref model or scoreboard; you must examine waveforms to know
//	if the FIFO works.
module tb_fifo;

  // Declare top-level wires.
  parameter N_ADDR_BITS=2, FIFO_WIDTH=4;
  logic reset, rd_en, wr_en, clk, fifo_empty, fifo_full;
  logic[FIFO_WIDTH-1:0] wr_data, fifo_rd_data;

  // Instantiate the FIFO.
  ... instantiate it here and call your instance "F"...

  // Drive the main clock
  initial begin
      $dumpfile("dump.vcd");
      $dumpvars();

      // The clock starts at 0 and toggles every 10 time units.
      clk = 0;
      forever begin	// eventually "tester" will call $stop to end the sim.
	  ... pause 10 time units and toggle the clock ...
      end
  end

  // A function to choose & return random FIFO-input data.
  function logic[FIFO_WIDTH-1:0] get_data();
      return $random;
  endfunction: get_data

  // The top-level tester routine.
  //	- Drive reset on & off.
  //	- Many loops of (pick operands; drive them; check results).
  initial begin : tester
      // Reset the system
      $display ("Starting the sim!");
      reset = 1'b1;
      @(negedge clk);
      @(negedge clk);
      reset = 1'b0;

      // Drive the simulation with 10 cycles of driving wr_data with new
      // random data. This simple testbench both reads and writes every cycle.
      repeat (10) begin
	  ... drive the enables, and drive wr_data with random data ...
          $display ("T=%0t: driving wr_data=%0x", $time, wr_data);

          // Advance the clock.
	  ... Advance the clock at the right time ...
      end

      // The $stop is not to stop *this* block (which would just run to its end
      // and finish), but rather to stop the "always" blocks above.
      $stop;
  end : tester
endmodule : tb_fifo
