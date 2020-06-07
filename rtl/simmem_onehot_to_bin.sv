module simmem_onehot_to_bin #(
  parameter int OneHotWidth
) ( 
  input logic [OneHotWidth-1:0] data_i,
  output logic [$clog(BinaryWidth)-1:0] data_o
);

  always_comb begin
    for (genvar logic [$clog(OneHotWidth)-1:0] i=0; i<OneHotWidth; i=i+1)
      if (data_i[i]) begin
        data_o = data_o | i;
      end
    end
  end
  
endmodule