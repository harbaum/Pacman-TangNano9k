/*
    video.v

    Simple verilog implementation of the Pacman Arcade video logic.
 */

// `define DEBUG

module video #(
    parameter int VIDEO_WIDE = 0
) (
	input clk, resetn,

    // CPU interface
    input mem_en,
    input mem_spr_en,
    input [11:0] mem_addr,
    input [7:0] mem_din,
    output [7:0] mem_dout,
    input mem_wr_n,
    output reg vbi,

	input [10:0] x,  // 0..2047
	input [9:0] y,   // 0..1023
    output reg [7:0] r,
    output reg [7:0] g,
    output reg [7:0] b
);

    // differentiate between X and Y (11 bits vs 10 bits)
    `define XBITS 11
    `define YBITS 10

    // make sure the game area is centered. 
    // (768 - 448) / 2 =  160
    // (1024 - 448) / 2 =  288
    localparam XSTART = (VIDEO_WIDE == 0)?`XBITS'd160:`XBITS'd288;

    // --------------------------- sprites ------------------------------
    localparam SPRITES = 8;

    // Handle CPU writes to sprite related ram
    reg [7:0] spriteram1 [(2*SPRITES)-1:0], spriteram2 [(2*SPRITES)-1:0];
 	always @(posedge clk) begin
        // CPU writes one of the 16 spriteram1 bytes.
        // These are part of the 4k main RAM at 0xff0 - 0xfff.
        // These are mirrored here for easier processing.
        if(mem_en && !mem_wr_n && mem_addr[11:4] == 8'hff) spriteram1[mem_addr[3:0]] <= mem_din;       

        // CPU writes one of the 16 spriteram2 bytes.
        // These are outside the 4k main RAM.
        if(mem_spr_en) spriteram2[mem_addr[3:0]] <= mem_din;       
    end

    // prefetching the sprites consists of three steps:
    // 1. address sprite graphic rom
    // 2. map pixel index to color index
    // 3. mask by y coordinate as sprite is only visible in some lines and write to linebuffer

    // the type of sprite and the sprite color are stored in spriteram1
    wire [5:0] sprite_code = spriteram1[{x[6:4], 1'b0}][7:2];
    wire sprite_flip_y = spriteram1[{x[6:4], 1'b0}][0];
    wire sprite_flip_x = spriteram1[{x[6:4], 1'b0}][1];
    wire [5:0] sprite_palette = spriteram1[{x[6:4], 1'b1}][5:0];
    reg [5:0] sprite_palette_d; // register for palette delay

    // the x and y coordinates of the sprite are stored in spriteram2
    // wire [7:0] sprite_x = spriteram2[{x[6:4], 1'b0}];
    // remap x coordinate to y and mirror (due to the rotated screen)
    wire [8:0] sprite_y = (9'd16 + 9'd256) - { 1'b0, spriteram2[{x[6:4], 1'b1}] };
    reg [8:0] sprite_y_d;
    reg [8:0] sprite_y_d2;

    // calculate which sprite line is being displayed in the current screen line
    wire [3:0] sy = (y[4:1] - sprite_y[3:0]) ^ {4{sprite_flip_y}};
    wire [3:0] sx = x[3:0] ^ {4{sprite_flip_x}};

    // The x and y bits that form the address are somewhat shuffled around.
    // This is due the mapping of the graphic data inside the rom and more
    // importantly due to the fact that we draw the screen upright unlike
    // the original hardware.
    wire [11:0] sprite_addr = { sprite_code, ~sx[3], sy[3:2] + 2'd1, ~sx[2:0] };
    wire [3:0] sprite_pixel_hi, sprite_pixel_lo;
    wire [1:0] sprite_pixel = { sprite_pixel_hi[~sy[1:0]], sprite_pixel_lo[~sy[1:0]] };

    // We need to determine all the sprite pixels that may appear on one line beforehand.
    // Since a sprite is 16 pixels wide with 2 bits per pixel this is 32 bits per sprite.
    // For max 8 sprites this is a total of 256 bits.

    // buffer to store all sprite pixels for one line
    // 8 sprites with 16 pixels each are 128 pixels
    reg [3:0] sprite_linebuffer [127:0];

    // collect all sprite pixels into the line buffer
    // data and color rom access has one clock delay each, thus x-2
    wire [`XBITS-1:0] xs = x - `XBITS'd2;

    always @(posedge clk) begin
        // sprite palette is delayed by one pixel as the palette is not
        // needed during the data read phase but one cycle later for the
        // color mapping
        sprite_palette_d <= sprite_palette;
        // sprite y coordinate is delayed 2 pixels as it's being used after
        // the data has been read _and_ after the color has been mapped
        sprite_y_d <= sprite_y;
        sprite_y_d2 <= sprite_y_d;

        // fetch sprite data during the first 128 pixels (bits 0000xxxxxx)
        if(xs[`XBITS-1:7] == 0) begin
            // check if sprite is visible within this line
            if(y[`YBITS-1:1] >= sprite_y_d2 && y[`YBITS-1:1] <  sprite_y_d2 + 16)
                sprite_linebuffer[xs[6:0]] <= color;
            else
                sprite_linebuffer[xs[6:0]] <= 4'h0;
        end
    end
        
    // ------------------------ background tiles ------------------------
    // x pixel position is three clocks ahead to compensate
    // for rom read delay in tilemap, colortable and palette
    wire [`XBITS-1:0] xd = x + `XBITS'd3 - XSTART;

    // tile x/y coordinates used for memory access. The X coordinate
    // is delayed by one, so the tile is fetched one clock ahead of time
    wire [4:0] tx = xd[8:4]+5'd1;  // x: 0..27
    wire [5:0] ty = y[9:4];        // y: 0..35

    // map from screen coordinates to memory address.
    wire [11:0] ram_addr = ((xd[3:0] == 4'd14)?12'h000:12'h400) + (
        (ty ==  0)?( 12'd989-tx):   // row 0:    989 ... 962
        (ty ==  1)?(12'd1021-tx):   // row 1:   1032 ... 994
        (ty == 34)?(  12'd29-tx):   // row 34:    29 ...   2
        (ty == 35)?(  12'd61-tx):   // row 35:    61 ...  34
        12'd928 + (ty-12'd2) - { tx, 5'b00000 } ); 

    wire [7:0] ram_dout;

    // tile address: The lower bits address one of the 16 bytes a tile consists of and
    // the upper bits address the tile
    wire [11:0] tile_addr = { tile_index , { ~y[3], ~xd[3:1] } };

    reg [5:0] tile_palette;

    wire [5:0] palette = (x<130)?sprite_palette_d:tile_palette;

    wire [3:0] tile_pixel_lo, tile_pixel_hi;
    wire [1:0] tile_pixel = { tile_pixel_hi[~y[2:1]], tile_pixel_lo[~y[2:1]] };

    // process sprite colors during sprite prefetch, else tile pixels
    wire [1:0] pixel = (x<130)?sprite_pixel:tile_pixel;
    wire [3:0] color;
    wire [7:0] bgr233;
  
    // latch ram output on last two pixels of previous cell
    reg [7:0] tile_index;
 	always @(posedge clk) begin
        // tile_index is latched in last pixel of previous tile, so
        // it's valid over all pixels of current tile
        if(xd[3:0] == 4'd15) tile_index <= ram_dout;

        // the tile_palette is latched in first pixel
        if(xd[3:0] == 4'd0)  tile_palette <= ram_dout[5:0];
    end

    // Instantiate 4k main ram. This also includes the 1k tile
    // ram and the 1k tile color ram
	ram ram (
        // port a: CPU interface (RW)
		.clka(clk),
		.reseta(!resetn),
        .cea(mem_en),
        .ocea(1'b1),
        .wrea(!mem_wr_n),
        .ada(mem_addr),
        .dina(mem_din),
        .douta(mem_dout),

        // port B: video interface (read only)
		.clkb(clk),
		.resetb(!resetn),
        .ceb(1'b1),
        .oceb(1'b1),
        .wreb(1'b0),      // never write
        .dinb(8'h00),
        .adb(ram_addr),
        .doutb(ram_dout)
    );

    // rom pacman.5f contains the graphics data for the 
    // 16x16 sprites. For each pixel two bits are
    // stored.
	pacman_5f pacman_5f_inst (
		.clk(clk),
		.reset(!resetn),
        .oce(1'b1),
        .ce(1'b1),
        .ad( sprite_addr ),
        .dout({sprite_pixel_hi, sprite_pixel_lo})
    );

    // rom pacman.5e contains the graphics data for the
    // 256 8x8 background tiles. For each pixel two bits are
    // stored which are then used to address the tile color
    // map which returns a color index
	pacman_5e pacman_5e_inst (
		.clk(clk),
		.reset(!resetn),
        .oce(1'b1),
        .ce(1'b1),
        .ad( tile_addr ),
        .dout({tile_pixel_hi, tile_pixel_lo})
    );

    // prom 82s126.4a contains the tile color map
    // The pixels of each tile can have one of four colors and
    // each tile has a palette_index. The tile color map contains
    // 64 palette entries with four colors each.
	prom_82s126_4a prom_82s126_4a_inst (
		.clk(clk),
		.reset(!resetn),
        .oce(1'b1),
        .ce(1'b1),
        .ad( { palette, pixel } ),
        .dout(color)
    );

    // Calculate x position of current screen pixel relative to sprite x position
    // These are offset by two to give one cycle to latch the data and
    // one cycle to run the data through the palette.
    // Sprite 1 and 2 are offset one extra pixel to the left. It may be possible 
    // that sprite 0 needs to be offset as well. But Pacman never uses that.
    localparam SPRITE_BASE_OFFSET = 10'(XSTART>>1) - 10'd1 + 10'd255 - 10'd16;
    wire [`XBITS-2:0] sx0 = x[`XBITS-1:1] - (SPRITE_BASE_OFFSET       - {1'b0, spriteram2[ 0]});
    wire [`XBITS-2:0] sx1 = x[`XBITS-1:1] - (SPRITE_BASE_OFFSET-10'd1 - {1'b0, spriteram2[ 2]});
    wire [`XBITS-2:0] sx2 = x[`XBITS-1:1] - (SPRITE_BASE_OFFSET-10'd1 - {1'b0, spriteram2[ 4]});
    wire [`XBITS-2:0] sx3 = x[`XBITS-1:1] - (SPRITE_BASE_OFFSET       - {1'b0, spriteram2[ 6]});
    wire [`XBITS-2:0] sx4 = x[`XBITS-1:1] - (SPRITE_BASE_OFFSET       - {1'b0, spriteram2[ 8]});
    wire [`XBITS-2:0] sx5 = x[`XBITS-1:1] - (SPRITE_BASE_OFFSET       - {1'b0, spriteram2[10]});
    wire [`XBITS-2:0] sx6 = x[`XBITS-1:1] - (SPRITE_BASE_OFFSET       - {1'b0, spriteram2[12]});
    wire [`XBITS-2:0] sx7 = x[`XBITS-1:1] - (SPRITE_BASE_OFFSET       - {1'b0, spriteram2[14]});

    // latch pixel data of current pixel of each sprite if this pixel is within the
    // horizontal position of the sprite. Otherwise latch 0
    reg [3:0] p0, p1, p2, p3, p4, p5, p6, p7;
	always @(posedge clk) begin
        p0 <= (sx0 < 16)?sprite_linebuffer[  7'd0 + sx0]:4'h0; // sprite 0 = line buffer 0..15
        p1 <= (sx1 < 16)?sprite_linebuffer[ 7'd16 + sx1]:4'h0;
        p2 <= (sx2 < 16)?sprite_linebuffer[ 7'd32 + sx2]:4'h0;
        p3 <= (sx3 < 16)?sprite_linebuffer[ 7'd48 + sx3]:4'h0;
        p4 <= (sx4 < 16)?sprite_linebuffer[ 7'd64 + sx4]:4'h0;
        p5 <= (sx5 < 16)?sprite_linebuffer[ 7'd80 + sx5]:4'h0;
        p6 <= (sx6 < 16)?sprite_linebuffer[ 7'd96 + sx6]:4'h0;
        p7 <= (sx7 < 16)?sprite_linebuffer[7'd112 + sx7]:4'h0; // sprite 7 = line buffer 112..127
    end

    // determine final color. sprite 0 has highest priority.
    wire [3:0] final_color = p0?p0: p1?p1: p2?p2: p3?p3: p4?p4: p5?p5: p6?p6: p7?p7: color;

    // prom 82s123.7f contains the color table
	prom_82s123_7f prom_82s123_7f_inst (
		.clk(clk),
		.reset(!resetn),
        .oce(1'b1),
        .ce(1'b1),
`ifdef DEBUG
        .ad( { 1'b0, (x < XSTART+448+16-1)?final_color:sprite_linebuffer[x-(XSTART+448+16-1)] } ),
`else
        .ad( { 1'b0, final_color } ),
`endif
        .dout(bgr233)
    );

`ifdef DEBUG
    integer i;
`endif

	always @(posedge clk) begin
		if (!resetn) begin
		end else begin
            vbi <= 1'b0;

            if (x == 0 && y == 576)
                vbi <= 1'b1;  // trigger vertical blank interrupt

            // default background dark blue
            r = 0; g = 0;
            if(y[0]) b = 64;
            else     b = 32;

`ifdef DEBUG
            if(x >= XSTART+448+16 && x < XSTART+448+16+128) begin
                if(sprite_linebuffer[x-(XSTART+448+16)] != 0) begin
                    b = { bgr233[7:6], 6'b000000 };
                    g = { bgr233[5:3],  5'b00000 };
                    r = { bgr233[2:0],  5'b00000 };
                end else begin
                    b = x[4]?8'hc0:8'hff;
                    g = x[4]?8'hc0:8'hff;
                    r = x[4]?8'hc0:8'hff;
                end
            end
`endif

            // draw game area
            // center on screen: 224 * 2 = 448 pixels game area
            if( x >= XSTART && x < XSTART+10'd448 ) begin
                if(y[0]) begin
                    b = { bgr233[7:6], 6'b000000 };
                    g = { bgr233[5:3],  5'b00000 };
                    r = { bgr233[2:0],  5'b00000 }; 
                end else begin
                    b = { 1'b0, bgr233[7:6], 5'b00000 };
                    g = { 1'b0, bgr233[5:3],  4'b0000 };
                    r = { 1'b0, bgr233[2:0],  4'b0000 }; 
                end
            end

`ifdef DEBUG
            // draw sprite marker
            for ( i = 0; i < 8; i = i + 1) begin
                if( x[`XBITS-1:1] >= ((XSTART>>1) + 255 - 16 - spriteram2[2*i] ) &&
                    x[`XBITS-1:1] <  ((XSTART>>1) + 255 - 16 - spriteram2[2*i] + 16 ) &&
                    y[`YBITS-1:1] >= (16 + 256 - spriteram2[2*i+1]) &&
                    y[`YBITS-1:1] <  (16 + 256 - spriteram2[2*i+1] +16 )) begin

                    if( x >= XSTART && x < XSTART+448 ) begin
                        b = { (i&1)?1'b1:1'b0, bgr233[7:6], 5'b00000 };
                        g = { (i&2)?1'b1:1'b0, bgr233[5:3],  4'b0000 };
                        r = { (i&4)?1'b1:1'b0, bgr233[2:0],  4'b0000 };                            
                    end
                end
             end
`endif
        end
    end
endmodule
