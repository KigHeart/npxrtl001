# Run from the repo root:  .\sim\run_all.ps1
# Step 1 (native Windows): Rust golden tests + vector generation.
# Step 2: RTL simulation under Verilator. Uses a native `verilator` on PATH if present (e.g. OSS CAD Suite shell),
#         otherwise falls back to WSL2 (Ubuntu) running sim/run_all.sh.
$ErrorActionPreference = "Stop"
Push-Location golden
cargo test --release -q
cargo run --release -q --bin gen_vectors -- ../sim/vec ../rtl
Pop-Location

if (Get-Command verilator -ErrorAction SilentlyContinue) {
  foreach ($m in @(@("alloc","kv_page_alloc"),@("cim","cim_tile"),@("softmax","softmax_q15"),@("decode","cmd_decode"))) {
    $tb = $m[0]; $top = $m[1]
    verilator --binary --timing -CFLAGS "-std=c++20 -fcoroutines" -Wno-fatal -Wno-lint -Wno-style -Irtl `
      --top-module "tb_$tb" -Mdir "sim/obj_$tb" "tb/tb_$tb.sv" "rtl/$top.sv" | Out-Null
    & "./sim/obj_$tb/Vtb_$tb.exe" "+vec=sim/vec"
  }
} elseif (Get-Command wsl -ErrorAction SilentlyContinue) {
  Write-Host "No native verilator found; running the simulation in WSL (needs: sudo apt install verilator g++ make)"
  wsl bash ./sim/run_all.sh
} else {
  Write-Host "Golden model + vectors done. Install WSL2 or the OSS CAD Suite to run the RTL simulation." -ForegroundColor Yellow
}
