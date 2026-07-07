// Auto-generated SystemVerilog file with register file changes
package reg_changes_pkg;
	typedef struct packed {
	    logic [4:0] name;
	    logic [31:0] val;
	} reg_change_t;

	// Array of register changes
	reg_change_t changes[7] = '{
		'{5'd2, 32'h10000000},
		'{5'd11, 32'h000000aa},
		'{5'd12, 32'h000000bb},
		'{5'd13, 32'h000000cc},
		'{5'd14, 32'h000000dd},
		'{5'd15, 32'hddccbbaa},
		'{5'd10, 32'h0000000a}
	};
endpackage
