module prom_82s126_3m 
(
 input	          clk,
 input	          re,
 input [7:0]      addr,
 output reg [7:0] rdata_a
);

   reg [7:0]  prom_82s126_3m_rom [256];
   initial begin
      $readmemh("82s126_3m.mem", prom_82s126_3m_rom);
   end

   always @(posedge clk)
     if(re)
       rdata_a <= prom_82s126_3m_rom[addr];
   
endmodule // prom_82s126_3m
