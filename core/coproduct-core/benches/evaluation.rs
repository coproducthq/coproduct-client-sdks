use std::hint::black_box;

use coproduct_core::bucketing::{bucket_for_seed, bucket_for_vectors};
use criterion::{Criterion, criterion_group, criterion_main};

fn bench_bucket_for_seed(c: &mut Criterion) {
    let seed = "abc12345-6789-4abc-9def-0123456789ab.alice.rollout";
    c.bench_function("bucket_for_seed", |b| {
        b.iter(|| {
            let result = bucket_for_seed(black_box(seed));
            black_box(result);
        });
    });
}

fn bench_bucket_for_vectors(c: &mut Criterion) {
    c.bench_function("bucket_for_vectors", |b| {
        b.iter(|| {
            let result = bucket_for_vectors(
                black_box("abc12345-6789-4abc-9def-0123456789ab"),
                black_box("alice"),
                black_box("rollout"),
            );
            black_box(result);
        });
    });
}

criterion_group!(benches, bench_bucket_for_seed, bench_bucket_for_vectors);
criterion_main!(benches);
