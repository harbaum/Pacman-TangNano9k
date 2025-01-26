module pacman_6j 
(
 input	          clk,
 input	          re,
 input [11:0]     addr,
 output reg [7:0] rdata_a
);

   reg [7:0]  pacman_6j_rom [4096];
   initial begin
      $readmemh("pacman_6j.mem", pacman_6j_rom);
   end

   always @(posedge clk)
     if(re)
       rdata_a <= pacman_6j_rom[addr];
   
endmodule // pacman_6j
