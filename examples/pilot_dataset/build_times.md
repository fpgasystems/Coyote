# Pilot Dataset Build Times

## Shell Setup (one-time, in `make app`)
| Step | Elapsed |
|------|---------|
| opt_design | 5m 54s |
| place_design | 31m 33s |
| phys_opt_design | 9m 36s |
| route_design | 24m 07s |
| post-route phys_opt | 4m 00s |
| **Total** | **1h 15m** |

## Per-Config App Implementation (`make app`)
| Config | App | LUTs | opt | place | phys_opt | route | post_phys | **Total** |
|--------|-----|------|-----|-------|----------|-------|-----------|-----------|
| c0 | app1_euclidean (benign) | 20,799 | 6m54s | 37m50s | 9m36s | 16m55s | 0m26s | **1h12m** |
| c1 | app2_cosine (benign) | 20,833 | 6m26s | 36m46s | 0m47s | 11m08s | 0m26s | **56m** |
| c2 | app3_vadd (benign) | 20,307 | 7m01s | 46m49s | 0m50s | 13m49s | 0m29s | **1h09m** |
| c3 | app4_aes (benign) | 31,149 | 6m36s | 50m16s | 0m42s | 49m59s | 0m26s | **1h48m** |
| c4 | app1_euclidean (susp) | 20,847 | 6m06s | 34m48s | 0m50s | 11m11s | 0m27s | **53m** |
| c5 | app2_cosine (susp) | 20,881 | 5m53s | 31m58s | 0m49s | 15m46s | 0m34s | **55m** |
| c6 | app3_vadd (susp) | 20,355 | 6m30s | 35m36s | 0m48s | 15m59s | 0m27s | **59m** |
| c7 | app4_aes (susp) | 31,197 | 2m04s | 54m58s | 0m44s | 1h36m | 0m15s | **2h34m** |
| c8 | standalone_1 (5 ROs) | 8,387 | 1m55s | 33m16s | 0m40s | 13m45s | 0m22s | **50m** |
| c9 | standalone_2 (50 ROs) | 8,522 | 2m12s | 28m27s | 0m36s | 8m38s | 0m22s | **40m** |
| c10 | standalone_3 (500 ROs) | 9,872 | 2m05s | 28m53s | 0m38s | 10m14s | 0m23s | **42m** |
| c11 | standalone_4 (5000 ROs) | 23,372 | 2m10s | 32m31s | 0m37s | 9m26s | 0m22s | **45m** |
| | | | | | | | **App total** | **13h23m** |

## Per-Config Bitgen (`make bitgen`)
| Config | open_ckpt | write_r0 | write_r1 | **Total** |
|--------|-----------|----------|----------|-----------|
| c0 | 3m20s | 5m06s | 4m02s | **12m28s** |
| c1 | 3m17s | 3m55s | 4m18s | **11m30s** |
| c2 | 3m19s | 4m06s | 4m27s | **11m52s** |
| c3 | 3m45s | 4m17s | 4m23s | **12m25s** |
| c4 | 3m28s | 4m09s | 5m57s | **13m34s** |
| c5 | 3m46s | 5m46s | 5m26s | **14m58s** |
| c6 | 3m26s | 3m56s | 4m43s | **12m05s** |
| c7 | 3m19s | 4m11s | 5m03s | **12m33s** |
| c8 | 3m03s | 3m38s | 3m42s | **10m23s** |
| c9 | 3m08s | 3m38s | 7m57s | **14m43s** |
| c10 | 3m27s | 4m29s | 4m21s | **12m17s** |
| c11 | 3m42s | 3m53s | 6m29s | **14m04s** |
| | | | **Bitgen total** | **2h33m** |

## Grand Total
| Phase | Time |
|-------|------|
| Shell setup | 1h 15m |
| 12 configs (app) | 13h 23m |
| 12 configs (bitgen) | 2h 33m |
| **Total** | **~17h 11m** |

## Key Observations
- **c7 (app4_aes suspicious)** was by far the longest at **2h34m**, dominated by a 1h36m route — likely due to the dense AES logic + ROs creating congestion
- **c3 (app4_aes benign)** was second longest at **1h48m** with a 50m route — AES is consistently the hardest to route
- **Standalone configs (c8–c11)** were the fastest (~40–50m), since the passthrough base is minimal
- **c0's phys_opt was 9m36s** vs ~0m47s for all others — this appears to be a first-config artifact (possibly more aggressive optimization on the initial run)
