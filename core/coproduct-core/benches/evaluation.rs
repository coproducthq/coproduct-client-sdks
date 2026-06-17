use criterion::{Criterion, criterion_group, criterion_main};

fn bucketing_bench(c: &mut Criterion) {
    c.bench_function("bucketing_seed_hash", |b| {
        b.iter(|| {
            coproduct_core::bucketing::compute_bucket(
                "abc12345-6789-4abc-9def-0123456789ab",
                "alice",
                "rollout",
            )
        })
    });
}

criterion_group!(benches, bucketing_bench);
criterion_main!(benches);
