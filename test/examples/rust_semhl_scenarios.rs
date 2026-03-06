// semhl.nvim troubleshooting scenarios (Rust)
//
// Suggested actions:
// 1) Move function blocks and verify identifier highlight stability.
// 2) Comment/uncomment statements and verify highlights update immediately.
// 3) Rename identifiers and confirm old highlight spans are removed.

struct Session {
    session_id: String,
    retry_count: u32,
}

fn bump_retry_count(session: &mut Session) {
    session.retry_count += 1;
}

fn log_session(session: &Session) {
    println!("session={} retries={}", session.session_id, session.retry_count);
}

fn main() {
    let mut current_session = Session {
        session_id: String::from("s-100"),
        retry_count: 0,
    };

    bump_retry_count(&mut current_session);
    log_session(&current_session);

    // Scenario A: comment/uncomment this line.
    // bump_retry_count(&mut current_session);

    // Scenario B: rename `current_session` to `active_session`.
    // Scenario C: move `log_session` above `bump_retry_count`.
}
