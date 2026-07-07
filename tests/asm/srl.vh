// Auto-generated SystemVerilog file with register file changes
package reg_changes_pkg;
	typedef struct packed {
	    logic [4:0] name;
	    logic [31:0] val;
	} reg_change_t;

	// Array of register changes
	reg_change_t changes[15] = '{
		'{5'd8, 32'hccccd000},
		'{5'd8, 32'hcccccccc},
		'{5'd9, 32'h00000001},
		'{5'd11, 32'h0000000a},
		'{5'd13, 32'hccccd000},
		'{5'd13, 32'hcccccccc},
		'{5'd14, 32'h00000020},
		'{5'd16, 32'hccccd000},
		'{5'd16, 32'hcccccccc},
		'{5'd17, 32'h00000028},
		'{5'd2, 32'h66666666},
		'{5'd12, 32'h00333333},
		'{5'd15, 32'hcccccccc},
		'{5'd18, 32'h00cccccc},
		'{5'd10, 32'h0000000a}
	};
endpackage
