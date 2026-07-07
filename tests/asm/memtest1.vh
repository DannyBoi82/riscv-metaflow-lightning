// Auto-generated SystemVerilog file with register file changes
package reg_changes_pkg;
	typedef struct packed {
	    logic [4:0] name;
	    logic [31:0] val;
	} reg_change_t;

	// Array of register changes
	reg_change_t changes[23] = '{
		'{5'd5, 32'h000007de},
		'{5'd6, 32'h000005ca},
		'{5'd7, 32'h0000033f},
		'{5'd8, 32'h0000d000},
		'{5'd8, 32'h0000cafe},
		'{5'd9, 32'h000000de},
		'{5'd10, 32'h000000ca},
		'{5'd11, 32'h0000003f},
		'{5'd12, 32'hfffffffe},
		'{5'd3, 32'h10000004},
		'{5'd13, 32'h000007de},
		'{5'd14, 32'h0000cafe},
		'{5'd15, 32'h0000033f},
		'{5'd16, 32'hffffcafe},
		'{5'd17, 32'h000000de},
		'{5'd17, 32'h000001a8},
		'{5'd17, 32'h000001e7},
		'{5'd17, 32'h000001e5},
		'{5'd17, 32'h000009c3},
		'{5'd17, 32'h0000d4c1},
		'{5'd17, 32'h0000d800},
		'{5'd17, 32'h0000a2fe},
		'{5'd10, 32'h0000000a}
	};
endpackage
