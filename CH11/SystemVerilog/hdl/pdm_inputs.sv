`timescale 1ns/10ps
module pdm_inputs
  #
  (
   parameter          CLK_FREQ    = 100,    // Mhz
   parameter          SAMPLE_RATE = 2400000 // Hz
   )
  (
   input wire         clk, // 100Mhz

   // Microphone interface
   output logic       m_clk,
   output logic       m_clk_en,
   input wire         m_data,

   // Amplitude outputs
   output logic [6:0] amplitude,
   output logic       amplitude_valid
   );

  localparam CLK_COUNT = int'((CLK_FREQ*1000000)/(SAMPLE_RATE*2));

  logic [1:0][7:0]                   counter;
  logic [1:0][7:0]                   sample_counter;
  logic [$clog2(CLK_COUNT)-1:0]      clk_counter;
  logic                              running;

  initial begin
    sample_counter = '0;
    counter        = '0;
    m_clk          = '0;
    clk_counter    = '0;
    running        = '0;
  end

  always @(posedge clk) begin
    amplitude_valid <= '0;
    m_clk_en        <= '0;

    if (clk_counter == CLK_COUNT - 1) begin
      clk_counter <= '0;
      m_clk       <= ~m_clk;
      m_clk_en    <= ~m_clk;
    end else begin
      clk_counter <= clk_counter + 1;
      //if (clk_counter == CLK_COUNT - 2) m_clk_en    <= ~m_clk;
    end

    if (m_clk_en) begin
      if (counter[0] == 199) counter[0] <= '0;
      else                   counter[0] <= counter[0] + 1'b1;

      if (~running) begin
        if (counter[0] == 100) begin
          running    = '1;
          counter[1] = '0;
        end
      end else begin
        if (counter[1] == 199) counter[1] <= '0;
        else                   counter[1] <= counter[1] + 1'b1;
      end

      if (counter[0] == 127) begin
        amplitude         <= (sample_counter[0] + m_data) <= 127 ? sample_counter[0] + m_data : '1;
        amplitude_valid   <= '1;
        sample_counter[0] <= '0;
      end else if (counter[0] < 127) begin
        sample_counter[0] <= sample_counter[0] + m_data;
      end
      if (counter[1] == 127) begin
        amplitude         <= sample_counter[1] + m_data <= 127 ? sample_counter[1] + m_data : '1;
        amplitude_valid   <= '1;
        sample_counter[1] <= '0;
      end else if (counter[1] < 127) begin
        sample_counter[1] <= sample_counter[1] + m_data;
      end
    end
  end // always @ (posedge clk)

endmodule // pdm_input
