module test;
  reg [7:0] mem [0:1048575]; // 1MB
  initial begin
    $display("OK");
    $finish;
  end
endmodule
