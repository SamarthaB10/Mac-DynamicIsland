//! Event-driven island state. The UI owns the pointer on its main thread.
//! No threads, polling, network requests, or heap caches are used here.

#[derive(Default)]
pub struct Island {
    expanded: bool,
    hidden: bool,
    pinned: bool,
    hovered: bool,
    suppressed: bool,
    choosing: bool,
    dropping: bool,
    deadline: u64,
}

#[repr(C)]
#[derive(Default)]
pub struct Snapshot {
    pub expanded: u32,
    pub pinned: u32,
    pub visible: u32,
    pub deadline_ms: u64,
}

impl Island {
    fn schedule(&mut self, now: u64, delay: u64) {
        self.deadline =
            if self.expanded && !self.pinned && !self.hovered && !self.choosing && !self.dropping {
                now.saturating_add(delay)
            } else {
                0
            };
    }

    fn event(&mut self, event: u32, now: u64) {
        if self.hidden && event != 12 {
            return;
        }
        match event {
            0 => {
                self.expanded = true;
                self.schedule(now, 3000);
            }
            1 if !self.hovered => {
                self.hovered = true;
                self.deadline = 0;
                if !self.suppressed {
                    self.expanded = true;
                }
            }
            2 if self.hovered => {
                self.hovered = false;
                self.suppressed = false;
                self.schedule(now, 700);
            }
            3 => {
                self.pinned = !self.pinned;
                if self.pinned {
                    self.expanded = true;
                }
                self.schedule(now, 700);
            }
            4 => {
                self.pinned = false;
                self.expanded = false;
                self.deadline = 0;
                self.suppressed = self.hovered;
            }
            5 => {
                self.choosing = true;
                self.deadline = 0;
            }
            6 => {
                self.choosing = false;
                self.schedule(now, 3000);
            }
            7 => {
                self.dropping = true;
                self.expanded = true;
                self.deadline = 0;
            }
            8 => {
                self.dropping = false;
                self.schedule(now, 700);
            }
            9 if !self.pinned && !self.choosing && !self.dropping => {
                self.expanded = false;
                self.deadline = 0;
            }
            10 if self.deadline != 0 && now >= self.deadline => {
                self.deadline = 0;
                if !self.pinned && !self.hovered && !self.choosing && !self.dropping {
                    self.expanded = false;
                }
            }
            11 => {
                self.hidden = true;
                self.expanded = false;
                self.pinned = false;
                self.hovered = false;
                self.deadline = 0;
            }
            12 => {
                self.hidden = false;
            }
            _ => {}
        }
    }

    fn snapshot(&self) -> Snapshot {
        Snapshot {
            expanded: self.expanded as u32,
            pinned: self.pinned as u32,
            visible: (!self.hidden) as u32,
            deadline_ms: self.deadline,
        }
    }
}

#[no_mangle]
pub extern "C" fn island_create() -> *mut Island {
    Box::into_raw(Box::default())
}

/// # Safety
/// `island` must be a live pointer from island_create, used by one UI thread.
#[no_mangle]
pub unsafe extern "C" fn island_event(island: *mut Island, event: u32, now_ms: u64) -> Snapshot {
    if let Some(island) = island.as_mut() {
        island.event(event, now_ms);
        island.snapshot()
    } else {
        Snapshot::default()
    }
}

/// # Safety
/// Call exactly once with a pointer from island_create, after cancelling UI callbacks that use it.
#[no_mangle]
pub unsafe extern "C" fn island_destroy(island: *mut Island) {
    if !island.is_null() {
        drop(Box::from_raw(island));
    }
}
