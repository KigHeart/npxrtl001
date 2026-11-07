//! Usage: gen_vectors <vec_dir> <rtl_dir>
//! Writes stimulus + expected results for each RTL testbench, and rtl/exp2_lut.svh.
use npx_golden::*;
use std::{env, fs, io::Write};

fn main() {
    let a: Vec<String> = env::args().collect();
    let (vd, rd) = (&a[1], &a[2]);
    fs::create_dir_all(vd).unwrap();
    fs::write(format!("{rd}/exp2_lut.svh"), lut::to_svh()).unwrap();

    // ---------------- allocator
    {
        let mut f = fs::File::create(format!("{vd}/alloc.txt")).unwrap();
        let mut m = alloc::Alloc::new();
        let mut r = Rng(0xA110C);
        let mut ops: Vec<(u8, usize, u8, usize)> = Vec::new();
        // directed: fill one sequence past MAXLP to hit FULLSEQ, cross-tenant, bad lookup
        ops.push((alloc::OP_OPEN, 0, 1, 0));
        ops.push((alloc::OP_OPEN, 0, 2, 0)); // EXISTS
        for _ in 0..17 { ops.push((alloc::OP_ALLOC, 0, 1, 0)); }
        ops.push((alloc::OP_ALLOC, 0, 3, 0)); // TENANT
        ops.push((alloc::OP_LOOKUP, 0, 2, 3)); // TENANT
        ops.push((alloc::OP_LOOKUP, 0, 1, 16)); // RANGE
        ops.push((alloc::OP_LOOKUP, 5, 1, 0)); // NOSEQ
        ops.push((alloc::OP_FREE, 0, 2, 0)); // TENANT
        ops.push((alloc::OP_FREE, 0, 1, 0)); // frees 16
        ops.push((alloc::OP_FREE, 0, 1, 0)); // NOSEQ
        // random phase biased to fill memory (NOMEM) then drain
        for i in 0..6000 {
            let seq = r.below(16) as usize;
            let t = if r.chance(85) { (seq % 4) as u8 } else { r.below(16) as u8 };
            let op = match r.below(100) {
                0..=14 => alloc::OP_OPEN,
                15..=64 => alloc::OP_ALLOC,
                65..=89 => alloc::OP_LOOKUP,
                _ => if (i / 1500) % 2 == 1 { alloc::OP_FREE } else if r.chance(30) { alloc::OP_FREE } else { alloc::OP_ALLOC },
            };
            ops.push((op, seq, t, r.below(18) as usize));
        }
        let mut seen = [0u32; 8];
        for (op, seq, t, lp) in ops.iter() {
            let (st, val) = m.step(*op, *seq, *t, *lp);
            seen[st as usize] += 1;
            writeln!(f, "{op} {seq} {t} {lp} {st} {val} {}", m.free_count()).unwrap();
        }
        eprintln!("alloc: {} ops, status histogram {:?}", ops.len(), seen);
        assert!(seen[1..=6].iter().all(|&c| c > 0), "every error status must be exercised");
    }

    // ---------------- CiM tile
    {
        let mut f = fs::File::create(format!("{vd}/cim.txt")).unwrap();
        let mut r = Rng(0xC1A);
        for t in 0..400 {
            let w: Vec<i8> = (0..cim::ROWS * cim::COLS).map(|_| match t % 7 { 0 => -128, 1 => 127, _ => r.next() as i8 }).collect();
            let x: Vec<i8> = (0..cim::ROWS).map(|_| match t % 5 { 0 => -128, 1 => 127, 2 => 0, _ => r.next() as i8 }).collect();
            let y = cim::dot(&w, &x);
            assert_eq!(y, cim::bit_serial(&w, &x));
            let mut s = String::new();
            for v in &w { s += &format!("{v} "); }
            for v in &x { s += &format!("{v} "); }
            for v in &y { s += &format!("{v} "); }
            writeln!(f, "{}", s.trim_end()).unwrap();
        }
    }

    // ---------------- softmax island
    {
        let mut f = fs::File::create(format!("{vd}/softmax.txt")).unwrap();
        let mut r = Rng(0x50F7);
        for t in 0..1000 {
            let mut s = [0i16; softmax::N];
            for v in s.iter_mut() {
                *v = match t % 10 {
                    0 => (r.below(65536) as i64 - 32768) as i16,      // full range: exercises shift cap
                    1 => 0,                                            // uniform
                    2 => i16::MIN,
                    _ => (r.below(3072) as i64 - 1536) as i16,
                };
            }
            if t % 10 == 3 { s[3] = i16::MAX; }
            let p = softmax::q15(&s);
            let mut l = String::new();
            for v in &s { l += &format!("{v} "); }
            for v in &p { l += &format!("{v} "); }
            writeln!(f, "{}", l.trim_end()).unwrap();
        }
    }

    // ---------------- command decoder
    {
        let mut f = fs::File::create(format!("{vd}/decode.txt")).unwrap();
        let mut r = Rng(0xDEC0DE);
        let mut hist = [0u32; 8];
        for _ in 0..6000 {
            let res: u128 = if r.chance(88) { r.below(3) as u128 } else { 3 };
            let prec: u128 = if r.chance(80) { r.below(4) as u128 } else { r.below(16) as u128 };
            let tenant = r.below(16) as u128;
            let kvseq = r.below(16) as u128;
            let kvvalid = r.chance(60) as u128;
            let rsv1 = if r.chance(95) { 0 } else { r.below(255) as u128 + 1 };
            let addr = if r.chance(85) { (r.below(1 << 20) as u128) << 5 } else { r.below(1 << 32) as u128 };
            let m = if r.chance(95) { r.below(65535) as u128 + 1 } else { 0 };
            let n = if r.chance(95) { r.below(65535) as u128 + 1 } else { 0 };
            let rsv2 = if r.chance(97) { 0 } else { r.below(4095) as u128 + 1 };
            let d: u128 = (r.below(256) as u128) | (res << 8) | (prec << 10) | (tenant << 14) | (kvseq << 18) | (kvvalid << 22)
                | (rsv1 << 24) | (addr << 32) | (m << 64) | (n << 80) | ((r.below(256) as u128) << 96)
                | ((r.below(256) as u128) << 104) | ((r.below(16) as u128) << 112) | (rsv2 << 116);
            let pen = r.chance(50);
            let open = r.below(65536) as u16 | if r.chance(50) { 0xFFFF } else { 0 };
            let mut kt = r.next();
            if r.chance(60) { kt = (0..16).fold(0u64, |acc, i| acc | (((tenant as u64) & 0xF) << (4 * i))); }
            let (st, disp) = decode::decode(d, pen, open, kt);
            hist[st as usize] += 1;
            writeln!(f, "{:032x} {} {:04x} {:016x} {} {}", d, pen as u8, open, kt, st, disp).unwrap();
        }
        eprintln!("decode: status histogram {:?}", hist);
        assert!(hist.iter().all(|&c| c > 0), "every decode status must be exercised");
    }
}
