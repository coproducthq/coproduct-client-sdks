use std::io;
use std::path::PathBuf;

fn snapshot_path(cache_dir: &str) -> PathBuf {
    PathBuf::from(cache_dir)
        .join("coproduct")
        .join("snapshot.json")
}

pub fn read_snapshot(cache_dir: &str) -> io::Result<Option<Vec<u8>>> {
    match std::fs::read(snapshot_path(cache_dir)) {
        Ok(bytes) => Ok(Some(bytes)),
        Err(error) if error.kind() == io::ErrorKind::NotFound => Ok(None),
        Err(error) => Err(error),
    }
}

pub fn write_snapshot(cache_dir: &str, bytes: &[u8]) -> io::Result<()> {
    let path = snapshot_path(cache_dir);
    if let Some(parent) = path.parent() {
        std::fs::create_dir_all(parent)?;
    }

    let temp = path.with_extension("json.tmp");
    std::fs::write(&temp, bytes)?;
    std::fs::rename(&temp, &path)
}
