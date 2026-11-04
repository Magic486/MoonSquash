///|
/// Report command failures to stderr and set a nonzero exit status.
fn main {
  run() catch {
    e => report_error(e.to_string())
  }
}
