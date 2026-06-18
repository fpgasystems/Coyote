# Selected Feasible Candidates

Targets use 8-bit weights/activations, 50% weight pruning, and RF values `1,2,4,8,16,32`.

| Candidate | Source experiment | Source status | Target base | RF values |
| --- | --- | --- | --- | --- |
| `res128_layers6` | `res128_layers6_WfloatAfloat_P0_RFbase` | success | `res128_layers6_W8A8_P50_RFbase` | `1,2,4,8,16,32` |
| `res256_layers6` | `res256_layers6_WfloatAfloat_P0_RFbase` | success | `res256_layers6_W8A8_P50_RFbase` | `1,2,4,8,16,32` |
| `res256_layers7` | `res256_layers7_WfloatAfloat_P0_RFbase` | success | `res256_layers7_W8A8_P50_RFbase` | `1,2,4,8,16,32` |
| `res512_layers7` | `res512_layers7_WfloatAfloat_P0_RFbase` | success | `res512_layers7_W8A8_P50_RFbase` | `1,2,4,8,16,32` |
