const std = @import("std");
const Ctx = @import("ctx.zig").Ctx;

pub fn Seq(comptime sq_anytype: anytype) type {
    const sq_list = to_type_array(sq_anytype);
    return _Seq(sq_list);
}

pub fn _Seq(comptime sq_list: []const type) type {
    if(sq_list.len == 1) {
        return struct { 
            state: sq_list[0],

            pub fn init(comptime ctx: *Ctx, self: *@This()) void {
                ctx.call(.init, Field(@This(), .state), .{});
            }

            pub fn tick(comptime ctx: *Ctx, self: *@This()) void {
                ctx.call(.tick, Field(@This(), .state), .{});
            }

            pub fn deinit(comptime ctx: *Ctx, self: *@This()) void {
                ctx.call(.deinit, Field(@This(), .state), .{});
            }
        };
    } else {
        return struct {
            state: sq_list[0],
            cons: Seq(sq_list[1..]),

            pub fn init(comptime ctx: *Ctx, self: *@This()) void {
                ctx.call(Init, Field(@This(), .state), .{});
                ctx.call(Init, Field(@This(), .cons), .{});
            }

            pub fn tick(comptime ctx: *Ctx, self: *@This()) void {
                ctx.call(Tick, Field(@This(), .state), .{});
                ctx.call(Tick, Field(@This(), .cons), .{});
            }

            pub fn deinit(comptime ctx: *Ctx, self: *@This()) void {
                ctx.call(Deinit, Field(@This(), .state), .{});
                ctx.call(Deinit, Field(@This(), .cons), .{});
            }
        };
    }
}

fn to_type_array(comptime S: anytype) []const type {
    comptime var types :[]const type = &[_]type{};

    inline for (S) |s| {
        // @TODO
    }

    return types;
}