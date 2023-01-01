const std = @import("std");


// Program Context 
pub const Ctx = struct {
    pub const Data = struct {
        type,
        source: type,
        action: type,
    };

    current: usize,
    stack: []const Data,

    threadlocal var runtime_stack_buffer:[2024]u8 = .{0}**2024;
    threadlocal var runtime_size: usize = 0;

    pub fn push(comptime ctx: *Ctx, comptime data: Data) void {
        ctx.current = ctx.current + 1;
        ctx.stack = ctx.stack ++ .{data};
    }

    pub fn call(comptime ctx: *Ctx, comptime action: type, comptime source: type, source_data: source) void {
        action.exec(ctx, source);
    } 
};

pub const Source = union(enum) {
    static,
    field: struct {type, []const u8},
    dynamic,
};

pub const State = enum {
    undefined,
    initialized,
};

const Test = Seq(.{
    A,
    B,
    C,
});

test {
    comptime var ctx: Ctx = Ctx.init(.{Test, .static});
    ctx.run(Init);

    var t = ctx.get(*Test);
    while(t.running) {
        ctx.run(Tick);
    }

    ctx.run(Deinit);
}

pub const Tick = struct {

    pub fn exec(comptime ctx: *Ctx) void {
        const T = ctx.getTopType();
        if(comptime @hasDecl(T, "tick")) {
            ctx.call(T.init);
        }
    }
};