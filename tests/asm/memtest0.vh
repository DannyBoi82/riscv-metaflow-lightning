// Auto-generated SystemVerilog file with register file changes
package reg_changes_pkg;
	typedef struct packed {
	    logic [4:0] name;
	    logic [31:0] val;
	} reg_change_t;

	// Array of register changes
	reg_change_t changes[23] = '{
		'{5'd1, 32'h10000000},
		'{5'd5, 32'h000000ff},
		'{5'd6, 32'h000001fe},
		'{5'd7, 32'h000003fc},
		'{5'd8, 32'h00000bcc},
		'{5'd9, 32'h000000ff},
		'{5'd10, 32'h000001fe},
		'{5'd11, 32'h000003fc},
		'{5'd12, 32'h00000bcc},
		'{5'd1, 32'h10000004},
		'{5'd13, 32'h000000ff},
		'{5'd14, 32'h000000ff},
		'{5'd15, 32'h000001fe},
		'{5'd16, 32'h000003fc},
		'{5'd17, 32'h000000ff},
		'{5'd17, 32'h000002fd},
		'{5'd17, 32'h000006f9},
		'{5'd17, 32'h000012c5},
		'{5'd17, 32'h000013c4},
		'{5'd17, 32'h000014c3},
		'{5'd17, 32'h000016c1},
		'{5'd17, 32'h00001abd},
		'{5'd10, 32'h0000000a}
	};
endpackage
