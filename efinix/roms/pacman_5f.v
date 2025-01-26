module pacman_5f 
(
 input	          clk,
 input	          re,
 input [11:0]     addr,
 output reg [7:0] rdata_a
);

   reg [7:0]  pacman_5f_rom [4096];
   initial begin
      $readmemh("pacman_5f.mem", pacman_5f_rom);
   end

   always @(posedge clk)
     if(re)
       rdata_a <= pacman_5f_rom[addr];
   
endmodule // pacman_5f
