// Auto-generated SystemVerilog file with register file changes
package reg_changes_pkg;
	typedef struct packed {
	    logic [4:0] name;
	    logic [31:0] val;
	} reg_change_t;

	// Array of register changes
	reg_change_t changes[11] = '{
		'{5'd8, 32'h0000000a},
		'{5'd9, 32'h00000014},
		'{5'd2, 32'hfffffff6},
		'{5'd11, 32'hffffffec},
		'{5'd12, 32'h00000001},
		'{5'd13, 32'h00000000},
		'{5'd14, 32'h00000001},
		'{5'd15, 32'h00000000},
		'{5'd16, 32'h00000000},
		'{5'd17, 32'h00000001},
		'{5'd10, 32'h0000000a}
	};
endpackage
