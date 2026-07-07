// Auto-generated SystemVerilog file with register file changes
package reg_changes_pkg;
	typedef struct packed {
	    logic [4:0] name;
	    logic [31:0] val;
	} reg_change_t;

	// Array of register changes
	reg_change_t changes[9] = '{
		'{5'd2, 32'h10000000},
		'{5'd2, 32'h10000000},
		'{5'd11, 32'h12345000},
		'{5'd11, 32'h123456ff},
		'{5'd12, 32'hffffffff},
		'{5'd13, 32'h00000056},
		'{5'd14, 32'h00000034},
		'{5'd15, 32'h00000012},
		'{5'd10, 32'h0000000a}
	};
endpackage
