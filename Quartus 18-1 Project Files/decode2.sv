// File: decode2.sv
// Description: A 2-to-4 decoder. Controls the digit to be displayed.
// Author: Marcus Fu
// Date: 2025/01/17



module decode2 ( input logic [1:0] digit, // digit counter
					  output logic [3:0] ct ); // active low digit enable

	always_comb
		case (digit)
			2'b00 : ct = 4'b1110;
			2'b01 : ct = 4'b1101;
			2'b10 : ct = 4'b1011;
			2'b11 : ct = 4'b0111;
		endcase


endmodule	