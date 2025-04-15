// File: decode7.sv
// Description: Decodes the ID number sent in hexidecimal
// 				 to the segments displayed on the digits
// Author: Marcus Fu
// Date: 2025/01/17

module decode7 ( input logic [3:0] num, 	// num of bcitID
					output logic [7:0] leds );	// active high led segment enable


	always_comb
		case (num)
			4'h0 : leds = 8'h3F; // Disp: 0
			4'h1 : leds = 8'h06; // Disp: 1
			4'h2 : leds = 8'h5B; // Disp: 2
			4'h3 : leds = 8'h4F; // Disp: 3
			
			4'h4 : leds = 8'h66; // Disp: 4
			4'h5 : leds = 8'h6D; // Disp: 5
			4'h6 : leds = 8'h7D; // Disp: 6
			4'h7 : leds = 8'h07; // Disp: 7
			
			4'h8 : leds = 8'h7F; // Disp: 8
			4'h9 : leds = 8'h67; // Disp: 9
			4'hA : leds = 8'h77; // Disp: A
			4'hB : leds = 8'h7C; // Disp: b

			4'hC : leds = 8'h39; // Disp: C
			4'hD : leds = 8'h5E; // Disp: d
			4'hE : leds = 8'h79; // Disp: E
			4'hF : leds = 8'h71; // Disp: F
		endcase



endmodule