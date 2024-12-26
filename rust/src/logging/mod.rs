use byondapi::global_call::call_global;
use byondapi::prelude::ByondValue;
use byondapi::threadsync::thread_sync;
use eyre;

/// Call stack trace dm method with message.
pub(crate) fn dm_call_stack_trace(msg: String) -> eyre::Result<()> {
    call_global("stack_trace", &[ByondValue::new_str(msg)?])?;

    Ok(())
}

/// Panic handler, called on unhandled errors.
/// Writes panic info to a text file, and calls dm stack trace proc as well.
pub(crate) fn setup_panic_handler() {
    std::panic::set_hook(Box::new(|info| {
        let msg = format!("Panic \n {:#?}", info);
        let msg_copy = msg.clone();
        let _ = thread_sync(|| -> ByondValue {
            if let Err(error) = dm_call_stack_trace(msg_copy) {
                let second_msg = format!("BYOND error \n {:#?}", error);
                let _ = std::fs::write("./rustlibs_cant_tell_byond.txt", second_msg.clone());
            }
            Default::default()
        }, true);
        let _ = std::fs::write("./rustlibs_panic.txt", msg.clone());
    }))
}
