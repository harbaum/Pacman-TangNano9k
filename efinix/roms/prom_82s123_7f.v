module prom_82s123_7f 
(
 input	          clk,
 input	          re,
 input [4:0]      addr,
 output reg [7:0] rdata_a
);

   reg [7:0]  prom_82s123_7f_rom [32];
   initial begin
      $readmemh("82s123_7f.mem", prom_82s123_7f_rom);
   end

   always @(posedge clk)
     if(re)
       rdata_a <= prom_82s123_7f_rom[addr];
   
endmodule // prom_82s123_7f
