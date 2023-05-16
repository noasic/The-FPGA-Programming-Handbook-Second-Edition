`ifndef NUM_SEGMENTS
`define NUM_SEGMENTS 8
`endif
`timescale 1ns/10ps
module calculator_top
  #
  (
   parameter BITS         = 32,
   parameter NUM_SEGMENTS = `NUM_SEGMENTS,
   parameter SM_TYPE      = "MEALY", // MEALY or MOORE
   parameter USE_PLL      = "TRUE"
   )
  (
   input wire                      clk,
   input wire [15:0]               SW,
   input wire [4:0]                buttons,
   input wire                      CPU_RESETN,

   output logic [NUM_SEGMENTS-1:0] anode,
   output logic [7:0]              cathode
   );

  import calculator_pkg::*;

  logic                               clk_50;
  logic                               reset;

  generate
    if (USE_PLL == "TRUE") begin : g_USE_PLL
      logic int_reset;
      (* ASYNC_REG = "TRUE" *) logic [1:0] reset_sync = '1;

      sys_pll u_sys_pll
        (
         .clk_in1  (clk),
         .clk_out1 (clk_50),
         .locked   (int_reset)
         );

      always_ff @(posedge clk_50) begin
        reset_sync <= {reset_sync[0], ~(int_reset & CPU_RESETN)};
      end
      assign reset = reset_sync[1];
    end else  begin : g_NO_PLL
      assign clk_50 = clk;
      assign reset = '0; // No reset necessary unless using external reset or PLL
    end
  endgenerate

  logic [31:0]                        accumulator;
  (* mark_debug = "true" *) logic [NUM_SEGMENTS-1:0][3:0]       encoded;
  logic [NUM_SEGMENTS-1:0]            digit_point;

  // Capture button events
  (* ASYNC_REG = "TRUE" *) logic [2:0] button_sync;
  logic                               counter_en;
  logic [7:0]                         counter;
  logic                               button_down;
  logic [4:0]                         button_capt;
  logic [15:0]                        sw_capt;

  seven_segment
    #
    (
     .NUM_SEGMENTS (NUM_SEGMENTS),
     .CLK_PER      (20)
     )
  u_seven_segment
    (
     .clk          (clk_50),
     .reset        (reset),
     .encoded      (encoded),
     .digit_point  (digit_point),
     .anode        (anode),
     .cathode      (cathode)
     );

  always @(posedge clk_50) begin
    button_down <= '0;
    button_capt <= '0;
    button_sync <= button_sync << 1 | (|buttons);
    if (button_sync[2:1] == 2'b01) counter_en <= '1;
    else if (~button_sync[1])      counter_en <= '0;

    if (counter_en) begin
      counter <= counter + 1'b1;
      if (&counter) begin
        counter_en  <= '0;
        counter     <= '0;
        button_down <= '1;
        button_capt <= buttons;
        sw_capt     <= SW;
      end
    end
    if (reset) begin
      counter_en  <= '0;
      counter     <= '0;
      button_down <= '0;
    end
  end

  generate
    if (SM_TYPE == "MOORE") begin : g_MOORE
      calculator_moore
        #
        (
         .BITS            (BITS)
         )
      u_sm
        (
         .clk             (clk_50),
         .reset           (reset),
         .start           (button_down),
         .buttons         (button_capt),
         .switch          (sw_capt),

         .accum           (accumulator)
         );
    end else begin : g_MEALY
      calculator_mealy
        #
        (
         .BITS            (BITS)
         )
      u_sm
        (
         .clk             (clk_50),
         .reset           (reset),
         .start           (button_down),
         .buttons         (button_capt),
         .switch          (sw_capt),

         .accum           (accumulator)
         );
    end
  endgenerate

  always @(posedge clk_50) begin
    encoded     <= bin_to_bcd(accumulator);
    digit_point <= '1;
  end

endmodule // calculator_top
