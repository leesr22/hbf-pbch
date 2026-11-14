`default_nettype none
// Bit-exact implementation of the frozen xorshift-derived mask matrix.
// This changes only its hardware representation, not the selected code.
module pbch_unmask_rec_directload (
    input wire clk, reset_n, start_i, load_i,
    input wire [12:0] selector_i,
    input wire [63:0] in_bits_i,
    input wire [6:0] in_count_i,
    input wire in_valid_i,
    output wire in_ready_o,
    output wire [63:0] out_bits_o,
    output wire [6:0] out_count_o,
    output wire out_valid_o,
    input wire out_ready_i
);
    reg [5:0] beat_q;
    reg [31:0] state_q;
    wire [31:0] initial_state;
    wire [31:0] state_now = state_q;
    wire [95:0] extended;
    assign in_ready_o = out_ready_i;
    assign out_valid_o = in_valid_i;
    assign out_count_o = in_count_i;
    assign initial_state[0] = selector_i[0] ^ selector_i[2] ^ selector_i[3] ^ selector_i[4] ^ selector_i[7] ^ selector_i[8] ^ selector_i[9] ^ selector_i[10];
    assign initial_state[1] = selector_i[0] ^ selector_i[1] ^ selector_i[3] ^ selector_i[4] ^ selector_i[5] ^ selector_i[6] ^ selector_i[7] ^ selector_i[11];
    assign initial_state[2] = selector_i[0] ^ selector_i[1] ^ selector_i[4] ^ selector_i[6] ^ selector_i[7] ^ selector_i[10] ^ selector_i[12];
    assign initial_state[3] = selector_i[1] ^ selector_i[2] ^ selector_i[4] ^ selector_i[11];
    assign initial_state[4] = selector_i[0] ^ selector_i[2] ^ selector_i[4] ^ selector_i[7] ^ selector_i[9] ^ selector_i[11];
    assign initial_state[5] = selector_i[0] ^ selector_i[2] ^ selector_i[4] ^ selector_i[6] ^ selector_i[7] ^ selector_i[9] ^ selector_i[10] ^ selector_i[12];
    assign initial_state[6] = selector_i[0] ^ selector_i[1] ^ selector_i[2] ^ selector_i[5] ^ selector_i[7] ^ selector_i[8] ^ selector_i[9] ^ selector_i[10] ^ selector_i[11] ^ selector_i[12];
    assign initial_state[7] = selector_i[1] ^ selector_i[2] ^ selector_i[3] ^ selector_i[6] ^ selector_i[9] ^ selector_i[12];
    assign initial_state[8] = selector_i[0] ^ selector_i[1];
    assign initial_state[9] = selector_i[1] ^ selector_i[2] ^ selector_i[4] ^ selector_i[6] ^ selector_i[8] ^ selector_i[11];
    assign initial_state[10] = selector_i[0] ^ selector_i[2] ^ selector_i[4] ^ selector_i[6] ^ selector_i[9] ^ selector_i[11];
    assign initial_state[11] = selector_i[2] ^ selector_i[3] ^ selector_i[5] ^ selector_i[7] ^ selector_i[12];
    assign initial_state[12] = selector_i[1] ^ selector_i[2] ^ selector_i[5] ^ selector_i[8] ^ selector_i[9] ^ selector_i[10] ^ selector_i[11];
    assign initial_state[13] = selector_i[0] ^ selector_i[1] ^ selector_i[2] ^ selector_i[4] ^ selector_i[5] ^ selector_i[8] ^ selector_i[12];
    assign initial_state[14] = selector_i[0] ^ selector_i[2] ^ selector_i[4] ^ selector_i[6] ^ selector_i[9];
    assign initial_state[15] = selector_i[0] ^ selector_i[1] ^ selector_i[3] ^ selector_i[7] ^ selector_i[9] ^ selector_i[11];
    assign initial_state[16] = selector_i[1] ^ selector_i[4] ^ selector_i[9];
    assign initial_state[17] = selector_i[3] ^ selector_i[4] ^ selector_i[6] ^ selector_i[7] ^ selector_i[9];
    assign initial_state[18] = selector_i[1] ^ selector_i[2] ^ selector_i[3] ^ selector_i[4] ^ selector_i[5] ^ selector_i[7] ^ selector_i[8] ^ selector_i[10] ^ selector_i[11] ^ selector_i[12];
    assign initial_state[19] = selector_i[1] ^ selector_i[2] ^ selector_i[6] ^ selector_i[7] ^ selector_i[11] ^ selector_i[12];
    assign initial_state[20] = selector_i[0] ^ selector_i[1] ^ selector_i[2] ^ selector_i[3] ^ selector_i[9] ^ selector_i[11] ^ selector_i[12];
    assign initial_state[21] = selector_i[1] ^ selector_i[2] ^ selector_i[5] ^ selector_i[6] ^ selector_i[8] ^ selector_i[9] ^ selector_i[11] ^ selector_i[12];
    assign initial_state[22] = selector_i[0] ^ selector_i[2] ^ selector_i[3] ^ selector_i[5] ^ selector_i[6] ^ selector_i[7] ^ selector_i[8] ^ selector_i[11] ^ selector_i[12];
    assign initial_state[23] = selector_i[0] ^ selector_i[1] ^ selector_i[3] ^ selector_i[4] ^ selector_i[6] ^ selector_i[8] ^ selector_i[9] ^ selector_i[12];
    assign initial_state[24] = selector_i[0] ^ selector_i[1] ^ selector_i[8] ^ selector_i[9] ^ selector_i[11] ^ selector_i[12];
    assign initial_state[25] = selector_i[2] ^ selector_i[3];
    assign initial_state[26] = selector_i[3] ^ selector_i[5] ^ selector_i[6] ^ selector_i[9] ^ selector_i[10] ^ selector_i[11] ^ selector_i[12];
    assign initial_state[27] = selector_i[0] ^ selector_i[1] ^ selector_i[3] ^ selector_i[4] ^ selector_i[8] ^ selector_i[11] ^ selector_i[12];
    assign initial_state[28] = selector_i[1] ^ selector_i[3] ^ selector_i[4] ^ selector_i[5] ^ selector_i[7] ^ selector_i[8] ^ selector_i[9];
    assign initial_state[29] = selector_i[0] ^ selector_i[2] ^ selector_i[3] ^ selector_i[4] ^ selector_i[5] ^ selector_i[6] ^ selector_i[7] ^ selector_i[8] ^ selector_i[10] ^ selector_i[12];
    assign initial_state[30] = selector_i[1] ^ selector_i[4] ^ selector_i[5] ^ selector_i[6] ^ selector_i[7] ^ selector_i[8] ^ selector_i[11];
    assign initial_state[31] = selector_i[0] ^ selector_i[1] ^ selector_i[2] ^ selector_i[4] ^ selector_i[5] ^ selector_i[9] ^ selector_i[11] ^ selector_i[12];
    assign extended[0] = state_now[0];
    assign extended[1] = state_now[1];
    assign extended[2] = state_now[2];
    assign extended[3] = state_now[3];
    assign extended[4] = state_now[4];
    assign extended[5] = state_now[5];
    assign extended[6] = state_now[6];
    assign extended[7] = state_now[7];
    assign extended[8] = state_now[8];
    assign extended[9] = state_now[9];
    assign extended[10] = state_now[10];
    assign extended[11] = state_now[11];
    assign extended[12] = state_now[12];
    assign extended[13] = state_now[13];
    assign extended[14] = state_now[14];
    assign extended[15] = state_now[15];
    assign extended[16] = state_now[16];
    assign extended[17] = state_now[17];
    assign extended[18] = state_now[18];
    assign extended[19] = state_now[19];
    assign extended[20] = state_now[20];
    assign extended[21] = state_now[21];
    assign extended[22] = state_now[22];
    assign extended[23] = state_now[23];
    assign extended[24] = state_now[24];
    assign extended[25] = state_now[25];
    assign extended[26] = state_now[26];
    assign extended[27] = state_now[27];
    assign extended[28] = state_now[28];
    assign extended[29] = state_now[29];
    assign extended[30] = state_now[30];
    assign extended[31] = state_now[31];
    assign extended[32] = state_now[0] ^ state_now[6] ^ state_now[9] ^ state_now[14] ^ state_now[15] ^ state_now[17] ^ state_now[18] ^ state_now[19] ^ state_now[20] ^ state_now[21];
    assign extended[33] = state_now[1] ^ state_now[7] ^ state_now[10] ^ state_now[15] ^ state_now[16] ^ state_now[18] ^ state_now[19] ^ state_now[20] ^ state_now[21] ^ state_now[22];
    assign extended[34] = state_now[2] ^ state_now[8] ^ state_now[11] ^ state_now[16] ^ state_now[17] ^ state_now[19] ^ state_now[20] ^ state_now[21] ^ state_now[22] ^ state_now[23];
    assign extended[35] = state_now[3] ^ state_now[9] ^ state_now[12] ^ state_now[17] ^ state_now[18] ^ state_now[20] ^ state_now[21] ^ state_now[22] ^ state_now[23] ^ state_now[24];
    assign extended[36] = state_now[4] ^ state_now[10] ^ state_now[13] ^ state_now[18] ^ state_now[19] ^ state_now[21] ^ state_now[22] ^ state_now[23] ^ state_now[24] ^ state_now[25];
    assign extended[37] = state_now[5] ^ state_now[11] ^ state_now[14] ^ state_now[19] ^ state_now[20] ^ state_now[22] ^ state_now[23] ^ state_now[24] ^ state_now[25] ^ state_now[26];
    assign extended[38] = state_now[6] ^ state_now[12] ^ state_now[15] ^ state_now[20] ^ state_now[21] ^ state_now[23] ^ state_now[24] ^ state_now[25] ^ state_now[26] ^ state_now[27];
    assign extended[39] = state_now[7] ^ state_now[13] ^ state_now[16] ^ state_now[21] ^ state_now[22] ^ state_now[24] ^ state_now[25] ^ state_now[26] ^ state_now[27] ^ state_now[28];
    assign extended[40] = state_now[8] ^ state_now[14] ^ state_now[17] ^ state_now[22] ^ state_now[23] ^ state_now[25] ^ state_now[26] ^ state_now[27] ^ state_now[28] ^ state_now[29];
    assign extended[41] = state_now[9] ^ state_now[15] ^ state_now[18] ^ state_now[23] ^ state_now[24] ^ state_now[26] ^ state_now[27] ^ state_now[28] ^ state_now[29] ^ state_now[30];
    assign extended[42] = state_now[10] ^ state_now[16] ^ state_now[19] ^ state_now[24] ^ state_now[25] ^ state_now[27] ^ state_now[28] ^ state_now[29] ^ state_now[30] ^ state_now[31];
    assign extended[43] = state_now[0] ^ state_now[6] ^ state_now[9] ^ state_now[11] ^ state_now[14] ^ state_now[15] ^ state_now[18] ^ state_now[19] ^ state_now[21] ^ state_now[25] ^ state_now[26] ^ state_now[28] ^ state_now[29] ^ state_now[30] ^ state_now[31];
    assign extended[44] = state_now[0] ^ state_now[1] ^ state_now[6] ^ state_now[7] ^ state_now[9] ^ state_now[10] ^ state_now[12] ^ state_now[14] ^ state_now[16] ^ state_now[17] ^ state_now[18] ^ state_now[21] ^ state_now[22] ^ state_now[26] ^ state_now[27] ^ state_now[29] ^ state_now[30] ^ state_now[31];
    assign extended[45] = state_now[0] ^ state_now[1] ^ state_now[2] ^ state_now[6] ^ state_now[7] ^ state_now[8] ^ state_now[9] ^ state_now[10] ^ state_now[11] ^ state_now[13] ^ state_now[14] ^ state_now[20] ^ state_now[21] ^ state_now[22] ^ state_now[23] ^ state_now[27] ^ state_now[28] ^ state_now[30] ^ state_now[31];
    assign extended[46] = state_now[0] ^ state_now[1] ^ state_now[2] ^ state_now[3] ^ state_now[6] ^ state_now[7] ^ state_now[8] ^ state_now[10] ^ state_now[11] ^ state_now[12] ^ state_now[17] ^ state_now[18] ^ state_now[19] ^ state_now[20] ^ state_now[22] ^ state_now[23] ^ state_now[24] ^ state_now[28] ^ state_now[29] ^ state_now[31];
    assign extended[47] = state_now[0] ^ state_now[1] ^ state_now[2] ^ state_now[3] ^ state_now[4] ^ state_now[6] ^ state_now[7] ^ state_now[8] ^ state_now[11] ^ state_now[12] ^ state_now[13] ^ state_now[14] ^ state_now[15] ^ state_now[17] ^ state_now[23] ^ state_now[24] ^ state_now[25] ^ state_now[29] ^ state_now[30];
    assign extended[48] = state_now[1] ^ state_now[2] ^ state_now[3] ^ state_now[4] ^ state_now[5] ^ state_now[7] ^ state_now[8] ^ state_now[9] ^ state_now[12] ^ state_now[13] ^ state_now[14] ^ state_now[15] ^ state_now[16] ^ state_now[18] ^ state_now[24] ^ state_now[25] ^ state_now[26] ^ state_now[30] ^ state_now[31];
    assign extended[49] = state_now[0] ^ state_now[2] ^ state_now[3] ^ state_now[4] ^ state_now[5] ^ state_now[8] ^ state_now[10] ^ state_now[13] ^ state_now[16] ^ state_now[18] ^ state_now[20] ^ state_now[21] ^ state_now[25] ^ state_now[26] ^ state_now[27] ^ state_now[31];
    assign extended[50] = state_now[0] ^ state_now[1] ^ state_now[3] ^ state_now[4] ^ state_now[5] ^ state_now[11] ^ state_now[15] ^ state_now[18] ^ state_now[20] ^ state_now[22] ^ state_now[26] ^ state_now[27] ^ state_now[28];
    assign extended[51] = state_now[1] ^ state_now[2] ^ state_now[4] ^ state_now[5] ^ state_now[6] ^ state_now[12] ^ state_now[16] ^ state_now[19] ^ state_now[21] ^ state_now[23] ^ state_now[27] ^ state_now[28] ^ state_now[29];
    assign extended[52] = state_now[2] ^ state_now[3] ^ state_now[5] ^ state_now[6] ^ state_now[7] ^ state_now[13] ^ state_now[17] ^ state_now[20] ^ state_now[22] ^ state_now[24] ^ state_now[28] ^ state_now[29] ^ state_now[30];
    assign extended[53] = state_now[3] ^ state_now[4] ^ state_now[6] ^ state_now[7] ^ state_now[8] ^ state_now[14] ^ state_now[18] ^ state_now[21] ^ state_now[23] ^ state_now[25] ^ state_now[29] ^ state_now[30] ^ state_now[31];
    assign extended[54] = state_now[0] ^ state_now[4] ^ state_now[5] ^ state_now[6] ^ state_now[7] ^ state_now[8] ^ state_now[14] ^ state_now[17] ^ state_now[18] ^ state_now[20] ^ state_now[21] ^ state_now[22] ^ state_now[24] ^ state_now[26] ^ state_now[30] ^ state_now[31];
    assign extended[55] = state_now[0] ^ state_now[1] ^ state_now[5] ^ state_now[7] ^ state_now[8] ^ state_now[14] ^ state_now[17] ^ state_now[20] ^ state_now[22] ^ state_now[23] ^ state_now[25] ^ state_now[27] ^ state_now[31];
    assign extended[56] = state_now[0] ^ state_now[1] ^ state_now[2] ^ state_now[8] ^ state_now[14] ^ state_now[17] ^ state_now[19] ^ state_now[20] ^ state_now[23] ^ state_now[24] ^ state_now[26] ^ state_now[28];
    assign extended[57] = state_now[1] ^ state_now[2] ^ state_now[3] ^ state_now[9] ^ state_now[15] ^ state_now[18] ^ state_now[20] ^ state_now[21] ^ state_now[24] ^ state_now[25] ^ state_now[27] ^ state_now[29];
    assign extended[58] = state_now[2] ^ state_now[3] ^ state_now[4] ^ state_now[10] ^ state_now[16] ^ state_now[19] ^ state_now[21] ^ state_now[22] ^ state_now[25] ^ state_now[26] ^ state_now[28] ^ state_now[30];
    assign extended[59] = state_now[3] ^ state_now[4] ^ state_now[5] ^ state_now[11] ^ state_now[17] ^ state_now[20] ^ state_now[22] ^ state_now[23] ^ state_now[26] ^ state_now[27] ^ state_now[29] ^ state_now[31];
    assign extended[60] = state_now[0] ^ state_now[4] ^ state_now[5] ^ state_now[9] ^ state_now[12] ^ state_now[14] ^ state_now[15] ^ state_now[17] ^ state_now[19] ^ state_now[20] ^ state_now[23] ^ state_now[24] ^ state_now[27] ^ state_now[28] ^ state_now[30];
    assign extended[61] = state_now[1] ^ state_now[5] ^ state_now[6] ^ state_now[10] ^ state_now[13] ^ state_now[15] ^ state_now[16] ^ state_now[18] ^ state_now[20] ^ state_now[21] ^ state_now[24] ^ state_now[25] ^ state_now[28] ^ state_now[29] ^ state_now[31];
    assign extended[62] = state_now[0] ^ state_now[2] ^ state_now[7] ^ state_now[9] ^ state_now[11] ^ state_now[15] ^ state_now[16] ^ state_now[18] ^ state_now[20] ^ state_now[22] ^ state_now[25] ^ state_now[26] ^ state_now[29] ^ state_now[30];
    assign extended[63] = state_now[1] ^ state_now[3] ^ state_now[8] ^ state_now[10] ^ state_now[12] ^ state_now[16] ^ state_now[17] ^ state_now[19] ^ state_now[21] ^ state_now[23] ^ state_now[26] ^ state_now[27] ^ state_now[30] ^ state_now[31];
    assign extended[64] = state_now[0] ^ state_now[2] ^ state_now[4] ^ state_now[6] ^ state_now[11] ^ state_now[13] ^ state_now[14] ^ state_now[15] ^ state_now[19] ^ state_now[21] ^ state_now[22] ^ state_now[24] ^ state_now[27] ^ state_now[28] ^ state_now[31];
    assign extended[65] = state_now[0] ^ state_now[1] ^ state_now[3] ^ state_now[5] ^ state_now[6] ^ state_now[7] ^ state_now[9] ^ state_now[12] ^ state_now[16] ^ state_now[17] ^ state_now[18] ^ state_now[19] ^ state_now[21] ^ state_now[22] ^ state_now[23] ^ state_now[25] ^ state_now[28] ^ state_now[29];
    assign extended[66] = state_now[1] ^ state_now[2] ^ state_now[4] ^ state_now[6] ^ state_now[7] ^ state_now[8] ^ state_now[10] ^ state_now[13] ^ state_now[17] ^ state_now[18] ^ state_now[19] ^ state_now[20] ^ state_now[22] ^ state_now[23] ^ state_now[24] ^ state_now[26] ^ state_now[29] ^ state_now[30];
    assign extended[67] = state_now[2] ^ state_now[3] ^ state_now[5] ^ state_now[7] ^ state_now[8] ^ state_now[9] ^ state_now[11] ^ state_now[14] ^ state_now[18] ^ state_now[19] ^ state_now[20] ^ state_now[21] ^ state_now[23] ^ state_now[24] ^ state_now[25] ^ state_now[27] ^ state_now[30] ^ state_now[31];
    assign extended[68] = state_now[0] ^ state_now[3] ^ state_now[4] ^ state_now[8] ^ state_now[10] ^ state_now[12] ^ state_now[14] ^ state_now[17] ^ state_now[18] ^ state_now[22] ^ state_now[24] ^ state_now[25] ^ state_now[26] ^ state_now[28] ^ state_now[31];
    assign extended[69] = state_now[0] ^ state_now[1] ^ state_now[4] ^ state_now[5] ^ state_now[6] ^ state_now[11] ^ state_now[13] ^ state_now[14] ^ state_now[17] ^ state_now[20] ^ state_now[21] ^ state_now[23] ^ state_now[25] ^ state_now[26] ^ state_now[27] ^ state_now[29];
    assign extended[70] = state_now[1] ^ state_now[2] ^ state_now[5] ^ state_now[6] ^ state_now[7] ^ state_now[12] ^ state_now[14] ^ state_now[15] ^ state_now[18] ^ state_now[21] ^ state_now[22] ^ state_now[24] ^ state_now[26] ^ state_now[27] ^ state_now[28] ^ state_now[30];
    assign extended[71] = state_now[2] ^ state_now[3] ^ state_now[6] ^ state_now[7] ^ state_now[8] ^ state_now[13] ^ state_now[15] ^ state_now[16] ^ state_now[19] ^ state_now[22] ^ state_now[23] ^ state_now[25] ^ state_now[27] ^ state_now[28] ^ state_now[29] ^ state_now[31];
    assign extended[72] = state_now[0] ^ state_now[3] ^ state_now[4] ^ state_now[6] ^ state_now[7] ^ state_now[8] ^ state_now[15] ^ state_now[16] ^ state_now[18] ^ state_now[19] ^ state_now[21] ^ state_now[23] ^ state_now[24] ^ state_now[26] ^ state_now[28] ^ state_now[29] ^ state_now[30];
    assign extended[73] = state_now[1] ^ state_now[4] ^ state_now[5] ^ state_now[7] ^ state_now[8] ^ state_now[9] ^ state_now[16] ^ state_now[17] ^ state_now[19] ^ state_now[20] ^ state_now[22] ^ state_now[24] ^ state_now[25] ^ state_now[27] ^ state_now[29] ^ state_now[30] ^ state_now[31];
    assign extended[74] = state_now[0] ^ state_now[2] ^ state_now[5] ^ state_now[8] ^ state_now[10] ^ state_now[14] ^ state_now[15] ^ state_now[19] ^ state_now[23] ^ state_now[25] ^ state_now[26] ^ state_now[28] ^ state_now[30] ^ state_now[31];
    assign extended[75] = state_now[0] ^ state_now[1] ^ state_now[3] ^ state_now[11] ^ state_now[14] ^ state_now[16] ^ state_now[17] ^ state_now[18] ^ state_now[19] ^ state_now[21] ^ state_now[24] ^ state_now[26] ^ state_now[27] ^ state_now[29] ^ state_now[31];
    assign extended[76] = state_now[0] ^ state_now[1] ^ state_now[2] ^ state_now[4] ^ state_now[6] ^ state_now[9] ^ state_now[12] ^ state_now[14] ^ state_now[21] ^ state_now[22] ^ state_now[25] ^ state_now[27] ^ state_now[28] ^ state_now[30];
    assign extended[77] = state_now[1] ^ state_now[2] ^ state_now[3] ^ state_now[5] ^ state_now[7] ^ state_now[10] ^ state_now[13] ^ state_now[15] ^ state_now[22] ^ state_now[23] ^ state_now[26] ^ state_now[28] ^ state_now[29] ^ state_now[31];
    assign extended[78] = state_now[0] ^ state_now[2] ^ state_now[3] ^ state_now[4] ^ state_now[8] ^ state_now[9] ^ state_now[11] ^ state_now[15] ^ state_now[16] ^ state_now[17] ^ state_now[18] ^ state_now[19] ^ state_now[20] ^ state_now[21] ^ state_now[23] ^ state_now[24] ^ state_now[27] ^ state_now[29] ^ state_now[30];
    assign extended[79] = state_now[1] ^ state_now[3] ^ state_now[4] ^ state_now[5] ^ state_now[9] ^ state_now[10] ^ state_now[12] ^ state_now[16] ^ state_now[17] ^ state_now[18] ^ state_now[19] ^ state_now[20] ^ state_now[21] ^ state_now[22] ^ state_now[24] ^ state_now[25] ^ state_now[28] ^ state_now[30] ^ state_now[31];
    assign extended[80] = state_now[0] ^ state_now[2] ^ state_now[4] ^ state_now[5] ^ state_now[9] ^ state_now[10] ^ state_now[11] ^ state_now[13] ^ state_now[14] ^ state_now[15] ^ state_now[22] ^ state_now[23] ^ state_now[25] ^ state_now[26] ^ state_now[29] ^ state_now[31];
    assign extended[81] = state_now[0] ^ state_now[1] ^ state_now[3] ^ state_now[5] ^ state_now[9] ^ state_now[10] ^ state_now[11] ^ state_now[12] ^ state_now[16] ^ state_now[17] ^ state_now[18] ^ state_now[19] ^ state_now[20] ^ state_now[21] ^ state_now[23] ^ state_now[24] ^ state_now[26] ^ state_now[27] ^ state_now[30];
    assign extended[82] = state_now[1] ^ state_now[2] ^ state_now[4] ^ state_now[6] ^ state_now[10] ^ state_now[11] ^ state_now[12] ^ state_now[13] ^ state_now[17] ^ state_now[18] ^ state_now[19] ^ state_now[20] ^ state_now[21] ^ state_now[22] ^ state_now[24] ^ state_now[25] ^ state_now[27] ^ state_now[28] ^ state_now[31];
    assign extended[83] = state_now[0] ^ state_now[2] ^ state_now[3] ^ state_now[5] ^ state_now[6] ^ state_now[7] ^ state_now[9] ^ state_now[11] ^ state_now[12] ^ state_now[13] ^ state_now[15] ^ state_now[17] ^ state_now[22] ^ state_now[23] ^ state_now[25] ^ state_now[26] ^ state_now[28] ^ state_now[29];
    assign extended[84] = state_now[1] ^ state_now[3] ^ state_now[4] ^ state_now[6] ^ state_now[7] ^ state_now[8] ^ state_now[10] ^ state_now[12] ^ state_now[13] ^ state_now[14] ^ state_now[16] ^ state_now[18] ^ state_now[23] ^ state_now[24] ^ state_now[26] ^ state_now[27] ^ state_now[29] ^ state_now[30];
    assign extended[85] = state_now[2] ^ state_now[4] ^ state_now[5] ^ state_now[7] ^ state_now[8] ^ state_now[9] ^ state_now[11] ^ state_now[13] ^ state_now[14] ^ state_now[15] ^ state_now[17] ^ state_now[19] ^ state_now[24] ^ state_now[25] ^ state_now[27] ^ state_now[28] ^ state_now[30] ^ state_now[31];
    assign extended[86] = state_now[0] ^ state_now[3] ^ state_now[5] ^ state_now[8] ^ state_now[10] ^ state_now[12] ^ state_now[16] ^ state_now[17] ^ state_now[19] ^ state_now[21] ^ state_now[25] ^ state_now[26] ^ state_now[28] ^ state_now[29] ^ state_now[31];
    assign extended[87] = state_now[0] ^ state_now[1] ^ state_now[4] ^ state_now[11] ^ state_now[13] ^ state_now[14] ^ state_now[15] ^ state_now[19] ^ state_now[21] ^ state_now[22] ^ state_now[26] ^ state_now[27] ^ state_now[29] ^ state_now[30];
    assign extended[88] = state_now[1] ^ state_now[2] ^ state_now[5] ^ state_now[12] ^ state_now[14] ^ state_now[15] ^ state_now[16] ^ state_now[20] ^ state_now[22] ^ state_now[23] ^ state_now[27] ^ state_now[28] ^ state_now[30] ^ state_now[31];
    assign extended[89] = state_now[0] ^ state_now[2] ^ state_now[3] ^ state_now[9] ^ state_now[13] ^ state_now[14] ^ state_now[16] ^ state_now[18] ^ state_now[19] ^ state_now[20] ^ state_now[23] ^ state_now[24] ^ state_now[28] ^ state_now[29] ^ state_now[31];
    assign extended[90] = state_now[0] ^ state_now[1] ^ state_now[3] ^ state_now[4] ^ state_now[6] ^ state_now[9] ^ state_now[10] ^ state_now[18] ^ state_now[24] ^ state_now[25] ^ state_now[29] ^ state_now[30];
    assign extended[91] = state_now[1] ^ state_now[2] ^ state_now[4] ^ state_now[5] ^ state_now[7] ^ state_now[10] ^ state_now[11] ^ state_now[19] ^ state_now[25] ^ state_now[26] ^ state_now[30] ^ state_now[31];
    assign extended[92] = state_now[0] ^ state_now[2] ^ state_now[3] ^ state_now[5] ^ state_now[8] ^ state_now[9] ^ state_now[11] ^ state_now[12] ^ state_now[14] ^ state_now[15] ^ state_now[17] ^ state_now[18] ^ state_now[19] ^ state_now[21] ^ state_now[26] ^ state_now[27] ^ state_now[31];
    assign extended[93] = state_now[0] ^ state_now[1] ^ state_now[3] ^ state_now[4] ^ state_now[10] ^ state_now[12] ^ state_now[13] ^ state_now[14] ^ state_now[16] ^ state_now[17] ^ state_now[21] ^ state_now[22] ^ state_now[27] ^ state_now[28];
    assign extended[94] = state_now[1] ^ state_now[2] ^ state_now[4] ^ state_now[5] ^ state_now[11] ^ state_now[13] ^ state_now[14] ^ state_now[15] ^ state_now[17] ^ state_now[18] ^ state_now[22] ^ state_now[23] ^ state_now[28] ^ state_now[29];
    assign extended[95] = state_now[2] ^ state_now[3] ^ state_now[5] ^ state_now[6] ^ state_now[12] ^ state_now[14] ^ state_now[15] ^ state_now[16] ^ state_now[18] ^ state_now[19] ^ state_now[23] ^ state_now[24] ^ state_now[29] ^ state_now[30];
    assign out_bits_o[63] = in_bits_i[63] ^ extended[0];
    assign out_bits_o[62] = in_bits_i[62] ^ extended[1];
    assign out_bits_o[61] = in_bits_i[61] ^ extended[2];
    assign out_bits_o[60] = in_bits_i[60] ^ extended[3];
    assign out_bits_o[59] = in_bits_i[59] ^ extended[4];
    assign out_bits_o[58] = in_bits_i[58] ^ extended[5];
    assign out_bits_o[57] = in_bits_i[57] ^ extended[6];
    assign out_bits_o[56] = in_bits_i[56] ^ extended[7];
    assign out_bits_o[55] = in_bits_i[55] ^ extended[8];
    assign out_bits_o[54] = in_bits_i[54] ^ extended[9];
    assign out_bits_o[53] = in_bits_i[53] ^ extended[10];
    assign out_bits_o[52] = in_bits_i[52] ^ extended[11];
    assign out_bits_o[51] = in_bits_i[51] ^ extended[12];
    assign out_bits_o[50] = in_bits_i[50] ^ extended[13];
    assign out_bits_o[49] = in_bits_i[49] ^ extended[14];
    assign out_bits_o[48] = in_bits_i[48] ^ extended[15];
    assign out_bits_o[47] = in_bits_i[47] ^ extended[16];
    assign out_bits_o[46] = in_bits_i[46] ^ extended[17];
    assign out_bits_o[45] = in_bits_i[45] ^ extended[18];
    assign out_bits_o[44] = in_bits_i[44] ^ extended[19];
    assign out_bits_o[43] = in_bits_i[43] ^ extended[20];
    assign out_bits_o[42] = in_bits_i[42] ^ extended[21];
    assign out_bits_o[41] = in_bits_i[41] ^ extended[22];
    assign out_bits_o[40] = in_bits_i[40] ^ extended[23];
    assign out_bits_o[39] = in_bits_i[39] ^ extended[24];
    assign out_bits_o[38] = in_bits_i[38] ^ extended[25];
    assign out_bits_o[37] = in_bits_i[37] ^ extended[26];
    assign out_bits_o[36] = in_bits_i[36] ^ extended[27];
    assign out_bits_o[35] = in_bits_i[35] ^ extended[28];
    assign out_bits_o[34] = in_bits_i[34] ^ extended[29];
    assign out_bits_o[33] = in_bits_i[33] ^ extended[30];
    assign out_bits_o[32] = in_bits_i[32] ^ extended[31];
    assign out_bits_o[31] = in_bits_i[31] ^ extended[32];
    assign out_bits_o[30] = in_bits_i[30] ^ extended[33];
    assign out_bits_o[29] = in_bits_i[29] ^ extended[34];
    assign out_bits_o[28] = in_bits_i[28] ^ extended[35];
    assign out_bits_o[27] = in_bits_i[27] ^ extended[36];
    assign out_bits_o[26] = in_bits_i[26] ^ extended[37];
    assign out_bits_o[25] = in_bits_i[25] ^ extended[38];
    assign out_bits_o[24] = in_bits_i[24] ^ extended[39];
    assign out_bits_o[23] = in_bits_i[23] ^ extended[40];
    assign out_bits_o[22] = in_bits_i[22] ^ extended[41];
    assign out_bits_o[21] = in_bits_i[21] ^ extended[42];
    assign out_bits_o[20] = in_bits_i[20] ^ extended[43];
    assign out_bits_o[19] = in_bits_i[19] ^ extended[44];
    assign out_bits_o[18] = in_bits_i[18] ^ extended[45];
    assign out_bits_o[17] = in_bits_i[17] ^ extended[46];
    assign out_bits_o[16] = in_bits_i[16] ^ extended[47];
    assign out_bits_o[15] = in_bits_i[15] ^ extended[48];
    assign out_bits_o[14] = in_bits_i[14] ^ extended[49];
    assign out_bits_o[13] = in_bits_i[13] ^ extended[50];
    assign out_bits_o[12] = in_bits_i[12] ^ extended[51];
    assign out_bits_o[11] = in_bits_i[11] ^ extended[52];
    assign out_bits_o[10] = in_bits_i[10] ^ extended[53];
    assign out_bits_o[9] = in_bits_i[9] ^ extended[54];
    assign out_bits_o[8] = in_bits_i[8] ^ extended[55];
    assign out_bits_o[7] = in_bits_i[7] ^ extended[56];
    assign out_bits_o[6] = in_bits_i[6] ^ extended[57];
    assign out_bits_o[5] = in_bits_i[5] ^ extended[58];
    assign out_bits_o[4] = in_bits_i[4] ^ extended[59];
    assign out_bits_o[3] = in_bits_i[3] ^ extended[60];
    assign out_bits_o[2] = in_bits_i[2] ^ extended[61];
    assign out_bits_o[1] = in_bits_i[1] ^ extended[62];
    assign out_bits_o[0] = in_bits_i[0] ^ extended[63];
    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            beat_q <= 0;
            state_q <= 0;
        end else if (start_i) begin
            beat_q <= 0;
        end else if (load_i) begin
            state_q <= initial_state;
        end else if (in_valid_i && in_ready_o) begin
            beat_q <= beat_q + 1'b1;
            state_q <= extended[95:64];
        end
    end
endmodule
`default_nettype wire
